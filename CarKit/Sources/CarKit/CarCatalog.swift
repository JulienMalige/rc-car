import Foundation

/// How a car is recognised: by its advertised name first, then by the characteristics it turns out to have.
public enum CarCatalog {
    /// The protocol a name suggests, before connecting.
    public static func protocolHint(name: String?) -> CarProtocol? {
        guard let name = name?.uppercased() else { return nil }
        if name.hasPrefix("QCAR") { return .qcar }
        if name.hasPrefix("SL-") || name.hasPrefix("SL ") { return .sl }
        return nil
    }

    /// Whether an advertisement is worth listing among the cars.
    public static func looksLikeCar(name: String?, services: [String]) -> Bool {
        if protocolHint(name: name) != nil { return true }
        let upper = services.map { $0.uppercased() }
        if upper.contains(SLProtocol.service) || upper.contains(SLProtocol.altService) { return true }
        guard let name = name?.uppercased() else { return false }
        return ["SHELL", "FERRARI", "BBURAGO", "SF-2", "SF2"].contains { name.contains($0) }
    }

    /// The protocol a connected car speaks, from its characteristics (UUID strings as CoreBluetooth prints them).
    /// Returns the protocol and the characteristic to write to.
    public static func detect(characteristics: [String], name: String?) -> (CarProtocol, String)? {
        let upper = Set(characteristics.map { $0.uppercased() })
        if upper.contains(QCARProtocol.control) { return (.qcar, QCARProtocol.control) }
        if upper.contains(SLProtocol.control) { return (.sl, SLProtocol.control) }
        if upper.contains(SLProtocol.altControl) { return (.sl, SLProtocol.altControl) }
        return nil
    }

    /// The characteristic a protocol writes to, when it is forced in the settings.
    public static func control(for proto: CarProtocol, characteristics: [String]) -> String? {
        let upper = Set(characteristics.map { $0.uppercased() })
        switch proto {
        case .qcar:
            return upper.contains(QCARProtocol.control) ? QCARProtocol.control : nil
        case .sl:
            if upper.contains(SLProtocol.control) { return SLProtocol.control }
            return upper.contains(SLProtocol.altControl) ? SLProtocol.altControl : nil
        }
    }

    /// Names for the UUIDs these cars show, for the debug screen.
    public static func name(ofUUID uuid: String) -> String? {
        switch uuid.uppercased() {
        case "FFF0": return "Car control service"
        case "FFF1": return "SL control"
        case "6936": return "Bburago service (alt)"
        case "FE01": return "Bburago control (alt)"
        case QCARProtocol.control: return "QCAR control"
        case QCARProtocol.status: return "QCAR battery"
        case "D44BC439-ABFD-45A2-B575-92541612960A", "D44BC439-ABFD-45A2-B575-92541612960B": return "QCAR (unknown)"
        case "FD00": return "QCAR service FD00"
        case "1800": return "Generic Access"
        case "1801": return "Generic Attribute"
        case "180A": return "Device Information"
        case "180F": return "Battery"
        case "2A19": return "Battery Level"
        case "2A00": return "Device Name"
        case "2A01": return "Appearance"
        case "2A04": return "Connection Parameters"
        case "2A05": return "Service Changed"
        case "2A24": return "Model Number"
        case "2A25": return "Serial Number"
        case "2A26": return "Firmware Revision"
        case "2A27": return "Hardware Revision"
        case "2A28": return "Software Revision"
        case "2A29": return "Manufacturer Name"
        case "2A50": return "PnP ID"
        default: return nil
        }
    }
}
