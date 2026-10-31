/// What the driver asks of the car at one moment. The cars are digital: full throttle or none, full lock or straight.
public struct DriveCommand: Equatable, Sendable {
    /// +1 forward, -1 reverse, 0 rolling.
    public var throttle: Int
    /// -1 left, +1 right, 0 straight.
    public var steering: Int
    public var turbo: Bool
    public var lights: Bool
    /// The SL cars' "360": the car spins on the spot while it is set.
    public var spin: Bool

    public init(throttle: Int = 0, steering: Int = 0, turbo: Bool = false, lights: Bool = false, spin: Bool = false) {
        self.throttle = throttle.signum()
        self.steering = steering.signum()
        self.turbo = turbo
        self.lights = lights
        self.spin = spin
    }

    public static let neutral = DriveCommand()

    /// The same command with the wheels stopped: what is sent when the app loses the driver (released, backgrounded).
    public var stopped: DriveCommand {
        DriveCommand(turbo: turbo, lights: lights)
    }
}

/// The two families of Shell promotional cars that people have decoded.
public enum CarProtocol: String, CaseIterable, Identifiable, Sendable {
    /// Bburago's Ferrari collection (2023 onwards: SF-23, SF-24, 499P, 296 GT3...), named "SL-<model>": 8 plain bytes.
    case sl
    /// Brandbase's 2020 Shell Motorsport cars, named "QCAR-<mac>": 16 bytes, AES-128 encrypted.
    case qcar

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sl: return "SL (Bburago Ferrari)"
        case .qcar: return "QCAR (Brandbase 2020)"
        }
    }

    /// The bytes written to the car's control characteristic for a command.
    public func frame(_ command: DriveCommand) -> [UInt8] {
        switch self {
        case .sl: return SLProtocol.frame(command)
        case .qcar: return QCARProtocol.frame(command)
        }
    }
}
