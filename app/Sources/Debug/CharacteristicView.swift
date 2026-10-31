import SwiftUI
import CoreBluetooth
import CarKit

/// One characteristic: its value, reading, notifications, and raw writes, once or repeated while a finger holds the
/// button (with a frame sent on release, so a test drive always ends with a stop).
struct CharacteristicView: View {
    let serviceUUID: String
    let uuid: String

    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var link: LinkStore
    @State private var text = ""
    @State private var releaseText = ""
    @State private var intervalMs = 100
    @State private var withResponse = false
    @State private var sent = 0
    @State private var holding = false
    @State private var repeater: Timer?
    @State private var message: String?

    private var gatt: GattCharacteristic? {
        link.services.first { $0.uuid == serviceUUID }?.characteristics.first { $0.uuid == uuid }
    }

    private var cb: CBCharacteristic? {
        ble.characteristic(service: serviceUUID, uuid: uuid)
    }

    var body: some View {
        Form {
            if let c = gatt {
                Section("Characteristic") {
                    LabeledContent("Name", value: c.title)
                    Text(c.uuid)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                    LabeledContent("Service", value: serviceUUID)
                    LabeledContent("Properties", value: c.properties.labels.joined(separator: ", "))
                    if !c.descriptors.isEmpty {
                        LabeledContent("Descriptors", value: c.descriptors.joined(separator: ", "))
                    }
                }
                valueSection(c)
                if c.canWrite { writeSection(c) }
            } else {
                Text("This characteristic is gone: the device disconnected.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(gatt?.title ?? uuid)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if text.isEmpty { text = Hex.string(SLProtocol.frame(.neutral)) }
            if let c = gatt { withResponse = !c.properties.contains(.writeWithoutResponse) }
        }
        .onDisappear { stopRepeating() }
    }

    @ViewBuilder
    private func valueSection(_ c: GattCharacteristic) -> some View {
        Section("Value") {
            if let value = c.value {
                let bytes = [UInt8](value)
                Text(bytes.isEmpty ? "(empty)" : Hex.string(bytes))
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                if let ascii = Hex.ascii(bytes) {
                    LabeledContent("Text", value: ascii)
                }
                if uuid.uppercased() == QCARProtocol.status, let status = QCARProtocol.status(bytes) {
                    LabeledContent("Battery", value: "\(status.battery)% (reading \(status.sequence))")
                }
            } else {
                Text("Not read yet")
                    .foregroundStyle(.secondary)
            }
            if c.canRead {
                Button("Read") {
                    if let cb { ble.read(cb) }
                }
            }
            if c.canNotify {
                Toggle("Notifications", isOn: Binding(
                    get: { c.isNotifying },
                    set: { on in if let cb { ble.setNotify(on, for: cb) } }
                ))
            }
        }
    }

    @ViewBuilder
    private func writeSection(_ c: GattCharacteristic) -> some View {
        Section {
            TextField("Bytes in hex", text: $text, axis: .vertical)
                .font(.system(size: 14, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            presets
            if c.properties.contains(.write) && c.properties.contains(.writeWithoutResponse) {
                Toggle("With response", isOn: $withResponse)
            }
            Button("Send once") { send(text, logged: true) }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Write")
        } footer: {
            Text("Spaces, commas and 0x are ignored. Presets fill the frame and its stop.")
        }
        Section {
            Stepper("Every \(intervalMs) ms", value: $intervalMs, in: 10...1000, step: 10)
            TextField("On release, send (hex, optional)", text: $releaseText)
                .font(.system(size: 14, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            HStack {
                Spacer()
                Text(holding ? "Sending… \(sent)" : "Hold to send repeatedly")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.vertical, 18)
            .background(holding ? Theme.accent : Color.gray.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                TouchPad(mode: .hold) { value in
                    if value != 0 { startRepeating() } else { stopRepeating() }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("Hold to repeat")
        } footer: {
            Text("The car drives while the frames say so: lifting your finger stops the stream and sends the release frame.")
        }
    }

    private var presets: some View {
        Menu {
            Section("SL (Bburago Ferrari)") {
                preset("Stop", .sl, .neutral)
                preset("Forward", .sl, DriveCommand(throttle: 1))
                preset("Reverse", .sl, DriveCommand(throttle: -1))
                preset("Left", .sl, DriveCommand(steering: -1))
                preset("Right", .sl, DriveCommand(steering: 1))
                preset("Forward with turbo", .sl, DriveCommand(throttle: 1, turbo: true))
                preset("Lights", .sl, DriveCommand(lights: true))
                preset("360", .sl, DriveCommand(spin: true))
            }
            Section("QCAR (Brandbase, encrypted)") {
                preset("Stop", .qcar, .neutral)
                preset("Forward", .qcar, DriveCommand(throttle: 1))
                preset("Reverse", .qcar, DriveCommand(throttle: -1))
                preset("Left", .qcar, DriveCommand(steering: -1))
                preset("Right", .qcar, DriveCommand(steering: 1))
                preset("Lights", .qcar, DriveCommand(lights: true))
            }
        } label: {
            Label("Presets", systemImage: "list.bullet")
        }
    }

    private func preset(_ title: String, _ proto: CarProtocol, _ command: DriveCommand) -> some View {
        Button(title) {
            text = Hex.string(proto.frame(command))
            releaseText = Hex.string(proto.frame(.neutral))
        }
    }

    // MARK: Sending

    @discardableResult
    private func send(_ hex: String, logged: Bool) -> Bool {
        guard let bytes = Hex.parse(hex) else {
            message = "Not hex: \(hex)"
            return false
        }
        guard let cb else {
            message = "Not connected"
            return false
        }
        let preference: WritePreference = withResponse ? .withResponse : .withoutResponse
        let ok = ble.write(bytes, to: cb, type: ble.writeType(for: cb, preference: preference), logged: logged)
        message = ok ? "Sent \(bytes.count) bytes" : "Not sent (not connected, or the radio is busy)"
        return ok
    }

    private func startRepeating() {
        guard repeater == nil, send(text, logged: true) else { return }
        holding = true
        sent = 1
        let timer = Timer(timeInterval: Double(intervalMs) / 1000, repeats: true) { _ in
            if send(text, logged: false) { sent += 1 }
        }
        RunLoop.main.add(timer, forMode: .common)
        repeater = timer
    }

    private func stopRepeating() {
        guard let timer = repeater else { return }
        timer.invalidate()
        repeater = nil
        holding = false
        let release = releaseText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !release.isEmpty { send(release, logged: true) }
    }
}
