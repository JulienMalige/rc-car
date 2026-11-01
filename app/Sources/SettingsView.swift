import ARKit
import SwiftUI
import CarKit
import RoomPlan

/// The app's one menu (Julien, 2026-10-31: "two option menu ... maybe do subsection in the menu"): the autopilot (the
/// room scan, driving to a point), the Bluetooth debug pages and the log, the car, the controls, how frames are sent.
struct SettingsView: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var link: LinkStore
    @EnvironmentObject private var driver: Driver
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.steeringLeftKey) private var steeringOnLeft = true
    @AppStorage(Prefs.keepAliveKey) private var keepAliveMs = Prefs.defaultKeepAlive
    @AppStorage(Prefs.writeKey) private var writePreference = WritePreference.auto.rawValue
    @AppStorage(Prefs.protocolKey) private var protocolChoice = "auto"
    @AppStorage(Prefs.autopilotPaceKey) private var autopilotPace = Prefs.defaultAutopilotPace
    @State private var forgotten = false
    @State private var cover: Cover?
    @ObservedObject private var rooms = RoomStore.shared

    /// The two full-screen pages, one modifier for both.
    enum Cover: String, Identifiable {
        case scan, drive
        var id: String { rawValue }
    }

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
                Section {
                    Button {
                        cover = .drive
                    } label: {
                        Label("Drive to a point", systemImage: "flag.checkered")
                    }
                    .disabled(!ARWorldTrackingConfiguration.isSupported)
                    Picker("Pace", selection: $autopilotPace) {
                        Text("Slow, 0.3 m/s").tag(0.3)
                        Text("Medium, 0.5 m/s").tag(0.5)
                        Text("Fast, 0.8 m/s").tag(0.8)
                    }
                    Button {
                        cover = .scan
                    } label: {
                        Label(rooms.room == nil ? "Scan the room" : "Scan the room again", systemImage: "viewfinder")
                    }
                    .disabled(!RoomCaptureSession.isSupported)
                    if let room = rooms.room {
                        NavigationLink {
                            RoomPlanView(room: room)
                        } label: {
                            Label("Room plan", systemImage: "square.split.bottomrightquarter")
                        }
                    }
                    if let problem = rooms.problem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Autopilot")
                } footer: {
                    Text(RoomCaptureSession.isSupported
                         ? "Drive to a point: prop the phone up so it sees the floor, tap the car, then tap where it should go, on the floor or on the map. The pace is the speed the camera keeps it at. Scanning the room (walk slowly around it, phone up, until the walls are outlined, then Done) puts the room on the map."
                         : "The autopilot needs a LiDAR iPhone.")
                }
                Section {
                    NavigationLink {
                        DebugView()
                    } label: {
                        Label("Devices nearby", systemImage: "dot.radiowaves.left.and.right")
                    }
                    if link.peripheralID != nil {
                        NavigationLink {
                            DeviceView()
                        } label: {
                            Label("Services of \(link.name ?? "the car")", systemImage: "list.bullet.indent")
                        }
                    }
                    NavigationLink {
                        LogView()
                    } label: {
                        Label("Log", systemImage: "list.bullet.rectangle")
                    }
                } header: {
                    Text("Bluetooth")
                } footer: {
                    Text("Every device in range, the car's services and values, raw writes, and everything sent and received.")
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
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(item: $cover) { page in
                switch page {
                case .scan: RoomScanView()
                case .drive: DriveToPointView().stores(ble, driver)
                }
            }
            .onChange(of: protocolChoice) { _, _ in
                if link.state == .ready { ble.chooseControl() }
            }
        }
    }
}
