import SwiftUI
import UIKit

@main
struct RCCarApp: App {
    @StateObject private var ble: BLEManager
    @StateObject private var driver: Driver

    init() {
        UserDefaults.standard.register(defaults: [
            Prefs.steeringLeftKey: true,
            Prefs.keepAliveKey: Prefs.defaultKeepAlive,
            Prefs.writeKey: WritePreference.auto.rawValue,
            Prefs.protocolKey: "auto",
            Prefs.layoutKey: DriveLayout.sticks.rawValue,
        ])
        let ble = BLEManager()
        _ble = StateObject(wrappedValue: ble)
        _driver = StateObject(wrappedValue: Driver(ble: ble))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .stores(ble, driver)
                .preferredColorScheme(.dark)
        }
    }
}

/// Safety around the drive screen: the car stops when the app is no longer in front, and the screen stays on while a
/// car is connected.
struct RootView: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var link: LinkStore
    @EnvironmentObject private var driver: Driver
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        DriveView()
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    ble.resumeFromBackground()
                case .inactive:
                    driver.stop()
                case .background:
                    driver.stop()
                    ble.pauseForBackground()
                @unknown default:
                    driver.stop()
                }
            }
            .onChange(of: link.state) { _, state in
                UIApplication.shared.isIdleTimerDisabled = state == .ready
            }
    }
}

extension View {
    /// Every screen gets the same objects; sheets are given them explicitly.
    func stores(_ ble: BLEManager, _ driver: Driver) -> some View {
        environmentObject(ble)
            .environmentObject(ble.link)
            .environmentObject(ble.scan)
            .environmentObject(ble.log)
            .environmentObject(driver)
    }
}
