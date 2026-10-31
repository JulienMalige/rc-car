import CoreBluetooth
import CarKit

/// One device heard while scanning, its advertisement merged over the packets seen (name and services can come in
/// the scan response rather than the advertisement itself).
struct Advert: Identifiable, Equatable {
    let id: UUID
    var name: String?
    var rssi: Int
    var services: [String] = []
    var manufacturerData: Data?
    var serviceData: [String: Data] = [:]
    var txPower: Int?
    var connectable: Bool?
    var lastSeen: Date

    var title: String { name ?? "Unnamed device" }
    var isCar: Bool { CarCatalog.looksLikeCar(name: name, services: services) }
    var protocolHint: CarProtocol? { CarCatalog.protocolHint(name: name) }

    /// Everything the advertisement says, one line per field, for the debug screen and the reports.
    var details: [String] {
        var lines = ["id \(id.uuidString)", "rssi \(rssi) dBm"]
        if let connectable { lines.append(connectable ? "connectable" : "not connectable") }
        if !services.isEmpty { lines.append("services " + services.joined(separator: ", ")) }
        if let manufacturerData { lines.append("manufacturer " + Hex.string([UInt8](manufacturerData))) }
        for (uuid, data) in serviceData.sorted(by: { $0.key < $1.key }) {
            lines.append("data \(uuid) " + Hex.string([UInt8](data)))
        }
        if let txPower { lines.append("tx power \(txPower) dBm") }
        return lines
    }
}

/// A characteristic as the debug screen shows it, rebuilt from CoreBluetooth's objects after each change.
struct GattCharacteristic: Identifiable, Equatable {
    let id: String
    let serviceUUID: String
    let uuid: String
    let properties: CBCharacteristicProperties
    var value: Data?
    var isNotifying: Bool
    var descriptors: [String]
    var userDescription: String?

    var title: String { CarCatalog.name(ofUUID: uuid) ?? userDescription ?? uuid }
    var canRead: Bool { properties.contains(.read) }
    var canWrite: Bool { properties.contains(.write) || properties.contains(.writeWithoutResponse) }
    var canNotify: Bool { properties.contains(.notify) || properties.contains(.indicate) }
}

struct GattService: Identifiable, Equatable {
    let id: String
    let uuid: String
    let isPrimary: Bool
    var characteristics: [GattCharacteristic]

    var title: String {
        if let name = CarCatalog.name(ofUUID: uuid) { return "\(name) (\(uuid))" }
        return uuid
    }
}

enum LinkState: Equatable {
    case idle
    case connecting
    case discovering
    case ready
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "Not connected"
        case .connecting: return "Connecting…"
        case .discovering: return "Reading the car…"
        case .ready: return "Connected"
        case .failed(let reason): return reason
        }
    }
}

/// How control frames are written; Auto takes "without response" when the car offers it (no round trip per frame).
enum WritePreference: String, CaseIterable, Identifiable {
    case auto
    case withResponse
    case withoutResponse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .withResponse: return "With response"
        case .withoutResponse: return "Without response"
        }
    }
}

extension CBCharacteristicProperties {
    var labels: [String] {
        var out: [String] = []
        if contains(.broadcast) { out.append("broadcast") }
        if contains(.read) { out.append("read") }
        if contains(.writeWithoutResponse) { out.append("write without response") }
        if contains(.write) { out.append("write") }
        if contains(.notify) { out.append("notify") }
        if contains(.indicate) { out.append("indicate") }
        if contains(.authenticatedSignedWrites) { out.append("signed writes") }
        if contains(.extendedProperties) { out.append("extended") }
        if contains(.notifyEncryptionRequired) { out.append("notify (encrypted)") }
        if contains(.indicateEncryptionRequired) { out.append("indicate (encrypted)") }
        return out
    }
}

extension CBManagerState {
    var label: String {
        switch self {
        case .poweredOn: return "On"
        case .poweredOff: return "Off"
        case .unauthorized: return "Not allowed"
        case .unsupported: return "Not supported"
        case .resetting: return "Resetting"
        case .unknown: return "Starting"
        @unknown default: return "Unknown"
        }
    }

    /// What to tell the driver when Bluetooth is not usable, nil when it is.
    var problem: String? {
        switch self {
        case .poweredOn, .unknown, .resetting: return nil
        case .poweredOff: return "Bluetooth is off. Turn it on in Control Center."
        case .unauthorized: return "RC Car may not use Bluetooth. Allow it in Settings › Privacy & Security › Bluetooth."
        case .unsupported: return "This device has no Bluetooth LE."
        @unknown default: return "Bluetooth is unavailable."
        }
    }
}
