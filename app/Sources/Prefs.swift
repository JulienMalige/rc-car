import Foundation
import CarKit

/// The app's few preferences, in UserDefaults: views bind them with @AppStorage under these keys, the Bluetooth code
/// reads them here.
enum Prefs {
    static let steeringLeftKey = "steeringOnLeft"
    static let keepAliveKey = "keepAliveMs"
    static let writeKey = "writePreference"
    static let protocolKey = "protocol"
    static let lastCarKey = "lastCarID"
    static let lastCarNameKey = "lastCarName"

    static let defaultKeepAlive = 100

    private static var defaults: UserDefaults { .standard }

    /// Milliseconds between two copies of an unchanged frame; 0 sends only changes.
    static var keepAliveMs: Int {
        defaults.object(forKey: keepAliveKey) as? Int ?? defaultKeepAlive
    }

    static var writePreference: WritePreference {
        WritePreference(rawValue: defaults.string(forKey: writeKey) ?? "") ?? .auto
    }

    /// The protocol forced in the settings, nil for automatic.
    static var protocolChoice: CarProtocol? {
        CarProtocol(rawValue: defaults.string(forKey: protocolKey) ?? "")
    }

    static var lastCarID: UUID? {
        defaults.string(forKey: lastCarKey).flatMap(UUID.init(uuidString:))
    }

    static var lastCarName: String? {
        defaults.string(forKey: lastCarNameKey)
    }

    static func remember(car id: UUID, name: String?) {
        defaults.set(id.uuidString, forKey: lastCarKey)
        defaults.set(name, forKey: lastCarNameKey)
    }

    static func forgetCar() {
        defaults.removeObject(forKey: lastCarKey)
        defaults.removeObject(forKey: lastCarNameKey)
    }
}
