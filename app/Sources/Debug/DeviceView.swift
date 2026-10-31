import SwiftUI
import UIKit
import CarKit

/// The connected device: what the app made of it, then every service and characteristic.
struct DeviceView: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var link: LinkStore
    @State private var copied = false

    var body: some View {
        List {
            Section("Device") {
                LabeledContent("Name", value: link.name ?? "—")
                LabeledContent("State", value: link.state.label)
                LabeledContent("Protocol", value: link.detected?.title ?? "None found")
                LabeledContent("Control", value: link.controlUUID ?? "—")
                if let rssi = link.rssi { LabeledContent("Signal", value: "\(rssi) dBm") }
                if let battery = link.battery { LabeledContent("Battery", value: "\(battery)%") }
                if let maxWrite = link.maxWrite { LabeledContent("Largest write", value: "\(maxWrite) bytes") }
                if let error = link.writeError {
                    LabeledContent("Last write error", value: error)
                        .foregroundStyle(.red)
                }
                if let id = link.peripheralID {
                    Text(id.uuidString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Section {
                ShareLink(item: ble.servicesReport()) {
                    Label("Share the services report", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = ble.servicesReport()
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy the services report", systemImage: "doc.on.doc")
                }
                if link.state == .idle, let id = link.peripheralID ?? Prefs.lastCarID {
                    Button("Connect again") { ble.connect(id) }
                } else if link.peripheralID != nil {
                    Button("Disconnect", role: .destructive) { ble.disconnect() }
                }
            }
            if link.services.isEmpty && link.state != .idle {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(link.state.label)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(link.services) { service in
                Section {
                    ForEach(service.characteristics) { c in
                        NavigationLink {
                            CharacteristicView(serviceUUID: c.serviceUUID, uuid: c.uuid)
                        } label: {
                            CharacteristicRow(c: c, isControl: c.uuid.uppercased() == link.controlUUID?.uppercased())
                        }
                    }
                    if service.characteristics.isEmpty {
                        Text("No characteristics")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Service " + service.title)
                }
            }
        }
        .navigationTitle(link.name ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CharacteristicRow: View {
    let c: GattCharacteristic
    let isControl: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(c.title)
                    .font(.subheadline.weight(.semibold))
                if isControl {
                    Text("DRIVES")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.accent, in: Capsule())
                }
                if c.isNotifying {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
            if c.title != c.uuid {
                Text(c.uuid)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(c.properties.labels.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let value = c.value, !value.isEmpty {
                let bytes = [UInt8](value)
                let ascii = Hex.ascii(bytes).map { "  \"" + $0 + "\"" } ?? ""
                Text(Hex.string(bytes) + ascii)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(3)
            }
        }
    }
}
