/// A pretend telemetry for the toy, which reports nothing: speed, gear, revs, pedals and g-forces worked out from the
/// commands alone, at the scale of a real F1 car (Julien, 2026-10-31: "just a simulation", for an F1 TV style
/// read-out). The numbers are made to look right, not to be right: the toy's motor is all or nothing.
public struct SpeedModel: Sendable, Equatable {
    /// km/h at full scale; negative in reverse.
    public private(set) var speed: Double = 0
    /// The pedals, 0 to 1: the green and red bars. They take a tenth of a second to travel, as feet do.
    public private(set) var throttle: Double = 0
    public private(set) var brake: Double = 0
    /// The forces the driver feels, in g: + when braking (the dot goes up), - when speeding up; + when turning left
    /// (pushed to the right).
    public private(set) var gLong: Double = 0
    public private(set) var gLat: Double = 0
    /// Where the revs are in the current gear, 0 to 1: the shift lights.
    public private(set) var revs: Double = 0

    public static let topSpeed = 240.0
    public static let turboTopSpeed = 300.0
    public static let reverseTopSpeed = 30.0
    /// Seconds to 63 % of the top speed.
    static let lag = 1.5
    static let brakeDecel = 260.0 // km/h per second
    static let reverseAccel = 60.0
    static let kmhPerSecondPerG = 35.30394 // 9.80665 m/s²
    /// The gs shown are half the simulated ones: F1-like values (about 2 g speeding up, 3.7 braking).
    static let gScale = 0.5
    /// Upper speed of gears 1 to 7; 8th up to the turbo top speed.
    static let shifts: [Double] = [70, 100, 130, 160, 190, 220, 255]

    private var reversing = false

    public init() {}

    public mutating func step(_ c: DriveCommand, dt: Double) {
        guard dt > 0 else { return }
        let t = min(dt, 0.1)
        let before = speed
        let top = c.turbo ? Self.turboTopSpeed : Self.topSpeed
        var wantThrottle = 0.0
        var wantBrake = 0.0
        if c.spin {
            // the 360 turns the car on the spot: the speed falls as when braking
            speed = Self.approach(speed, 0, Self.brakeDecel * t)
            reversing = false
        } else if c.throttle > 0 {
            reversing = false
            if speed < -0.5 {
                wantBrake = 1
                speed = min(0, speed + Self.brakeDecel * t)
            } else if speed > top {
                speed = max(top, speed - Self.coast(speed) * t) // turbo let go
                wantThrottle = 1
            } else {
                wantThrottle = 1
                speed += (top - speed) / Self.lag * t
            }
        } else if c.throttle < 0 {
            if speed > 0.5 {
                wantBrake = 1
                speed = max(0, speed - Self.brakeDecel * t)
            } else {
                reversing = true
                wantThrottle = 1
                speed = max(-Self.reverseTopSpeed, speed - Self.reverseAccel * t)
            }
        } else {
            reversing = false
            speed = Self.approach(speed, 0, Self.coast(speed) * t)
        }
        throttle = Self.approach(throttle, wantThrottle, t / 0.12)
        brake = Self.approach(brake, wantBrake, t / 0.08)

        let accel = (abs(speed) - abs(before)) / t // km/h per second, + speeding up
        let long = -accel / Self.kmhPerSecondPerG * Self.gScale
        let pace = min(1, abs(speed) / 200)
        var lat = Double(-c.steering) * 4 * pace * pace.squareRoot()
        if c.spin { lat = 2.5 }
        let smooth = min(1, t / 0.15)
        gLong += (Self.clamp(long, 5) - gLong) * smooth
        gLat += (Self.clamp(lat, 5) - gLat) * smooth
        revs = Self.revs(speed)
    }

    /// N, R or 1 to 8.
    public var gear: String {
        if speed < -0.5 || reversing { return "R" }
        if speed < 0.5 && throttle < 0.5 { return "N" }
        return String(Self.shifts.filter { speed >= $0 }.count + 1)
    }

    /// The g-force's size, for the read-out under the dot.
    public var gTotal: Double {
        (gLong * gLong + gLat * gLat).squareRoot()
    }

    private static func revs(_ speed: Double) -> Double {
        let v = abs(speed)
        let bounds = [0.0] + shifts + [turboTopSpeed]
        guard let upper = bounds.firstIndex(where: { v < $0 }), upper > 0 else { return v > 0 ? 1 : 0 }
        let low = bounds[upper - 1], high = bounds[upper]
        let inGear = (v - low) / (high - low)
        // revs drop to about half after an upshift (first gear starts from idle)
        return upper == 1 ? inGear : 0.5 + 0.5 * inGear
    }

    /// Lifting off: the drag at speed, then the toy's quick stop.
    private static func coast(_ speed: Double) -> Double {
        60 + 0.4 * abs(speed)
    }

    private static func approach(_ value: Double, _ target: Double, _ step: Double) -> Double {
        value < target ? min(target, value + step) : max(target, value - step)
    }

    private static func clamp(_ value: Double, _ limit: Double) -> Double {
        max(-limit, min(limit, value))
    }
}
