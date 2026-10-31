/// Brandbase's 2020 Shell Motorsport cars ("QCAR-AABBCC"): 16-byte frames encrypted with AES-128 in ECB mode under a
/// key the firmware shares with every car (scrool's gist e79d6a4cb50c26499746f4fe473b3768). Decrypting the frames that
/// jenkings/BLE-RC-Car-ESP32 and ariasbruno/rc-commander replay gives the clear layout (the gist's table is one byte
/// off from offset 8):
///
///     00 'C' 'T' 'L'  fwd back left right  lightsOff  speed  00 00 00 00 00 00
///
/// speed is 0x50, or 0x64 with turbo; lightsOff is 1 with the lights off. The car wants a frame continuously (the gist
/// says every 10 ms, rc-commander sends one every 200 ms). It notifies its battery on ...9601 about once a minute:
///
///     seq 'V' 'B' 'T'  percent  00 ...
public enum QCARProtocol {
    public static let service = "FFF0"
    public static let control = "D44BC439-ABFD-45A2-B575-925416129600"
    public static let status = "D44BC439-ABFD-45A2-B575-925416129601"

    public static let key: [UInt8] = [
        0x34, 0x52, 0x2A, 0x5B, 0x7A, 0x6E, 0x49, 0x2C, 0x08, 0x09, 0x0A, 0x9D, 0x8D, 0x2A, 0x23, 0xF8,
    ]

    public static func plaintext(_ command: DriveCommand) -> [UInt8] {
        var c = command
        if c.spin {
            // These cars have no spin of their own; rc-commander's 360 is full right lock at full turbo.
            c.throttle = 1
            c.steering = 1
            c.turbo = true
        }
        var p = [UInt8](repeating: 0, count: 16)
        p[1] = 0x43 // C
        p[2] = 0x54 // T
        p[3] = 0x4C // L
        p[4] = c.throttle > 0 ? 1 : 0
        p[5] = c.throttle < 0 ? 1 : 0
        p[6] = c.steering < 0 ? 1 : 0
        p[7] = c.steering > 0 ? 1 : 0
        p[8] = c.lights ? 0 : 1
        p[9] = c.turbo ? 0x64 : 0x50
        return p
    }

    public static func frame(_ command: DriveCommand) -> [UInt8] {
        AES128.encrypt(plaintext(command), key: key) ?? []
    }

    public struct Status: Equatable, Sendable {
        public let sequence: UInt8
        public let battery: Int
    }

    /// A battery notification, or nil when the bytes are not one.
    public static func status(_ bytes: [UInt8]) -> Status? {
        guard bytes.count == 16, let p = AES128.decrypt(bytes, key: key) else { return nil }
        guard p[1] == 0x56, p[2] == 0x42, p[3] == 0x54 else { return nil } // VBT
        return Status(sequence: p[0], battery: Int(p[4]))
    }
}
