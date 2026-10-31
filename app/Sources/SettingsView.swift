import SwiftUI
import CarKit

struct SettingsView: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var link: LinkStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.steeringLeftKey) private var steeringOnLeft = true
    @AppStorage(Prefs.keepAliveKey) private var keepAliveMs = Prefs.defaultKeepAlive
    @AppStorage(Prefs.writeKey) private var writePreference = WritePreference.auto.rawValue
    @AppStorage(Prefs.protocolKey) private var protocolChoice = "auto"
    @State private var forgotten = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Controls") {
                    Toggle("Steering on the left", isOn: $steeringOnLeft)
                }
                Section {
                    Picker("Protocol", selection: $protocolChoice) {
                        Text("Automatic").tag("auto")
                        ForEach(CarProtocol.allCases) { proto in
                            Text(proto.title).tag(proto.rawValue)
                        }
                    }
                    Picker("Write", selection: $writePreference) {
                        ForEach(WritePreference.allCases) { preference in
                            Text(preference.title).tag(preference.rawValue)
                        }
                    }
                    Picker("Repeat the frame", selection: $keepAliveMs) {
                        Text("Only on change").tag(0)
                        Text("Every 50 ms").tag(50)
                        Text("Every 100 ms").tag(100)
                        Text("Every 200 ms").tag(200)
                        Text("Every 500 ms").tag(500)
                    }
                } header: {
                    Text("Sending")
                } footer: {
                    Text("Automatic picks the protocol from the car's services: SL for Bburago's Ferrari cars (8 plain bytes on FFF1), QCAR for Brandbase's 2020 cars (16 encrypted bytes). The frame is sent again while nothing changes, as some cars stop without a steady stream.")
                }
                Section("Car") {
                    LabeledContent("Remembered", value: forgotten ? "None" : (Prefs.lastCarName ?? "None"))
                    Button("Forget this car", role: .destructive) {
                        Prefs.forgetCar()
                        forgotten = true
                        ble.disconnect()
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: AppInfo.version)
                    Text("Drives Shell's promotional Bluetooth cars (Bburago Ferrari collection, Brandbase 2020 cars) without the Shell app. Packet formats from ariasbruno/rc-commander, jenkings/BLE-RC-Car-ESP32 and scrool's notes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: protocolChoice) { _, _ in
                if link.state == .ready { ble.chooseControl() }
            }
        }
    }
}
