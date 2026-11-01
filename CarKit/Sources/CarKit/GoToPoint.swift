import Foundation

/// Drives the car to a point on the floor with the only controls it has: forward, reverse or nothing; full left, full
/// right or straight. It steers toward the point (backing up first when the point is behind and close), keeps a slow
/// pace by pulsing the throttle against the speed the camera measures, and lets go when it arrives.
public struct GoToPoint {
    public enum Phase: String, Equatable {
        /// No point to go to.
        case idle
        /// Rolling forward a little: the movement shows which way the car points.
        case probing
        case driving
        /// Backing up while turning, the point being behind.
        case reversing
        case arrived
        /// The camera lost the car: wheels stopped until it finds it again.
        case lost
        /// Throttle on and the car not moving (a wall, a chair leg): given up.
        case stuck
    }

    public struct Settings: Equatable {
        /// Metres per second on the way.
        public var cruise = 0.5
        /// Metres per second near the point.
        public var approach = 0.22
        /// Within this distance (m) the pace drops toward `approach`.
        public var slowZone = 0.45
        /// Arrived within this distance (m).
        public var arrive = 0.12
        /// Straight while the point is within this angle (radians) of the heading.
        public var deadband = 8 * Double.pi / 180

        public init() {}
    }

    public var settings: Settings
    public private(set) var target: SIMD2<Double>?
    public private(set) var phase = Phase.idle
    private var steering = 0
    private var phaseStart = 0.0
    private var closest = Double.infinity
    private var stalledSince: Double?

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    public mutating func go(to point: SIMD2<Double>, time: Double) {
        target = point
        closest = .infinity
        steering = 0
        stalledSince = nil
        enter(.driving, time)
    }

    public mutating func halt() {
        target = nil
        steering = 0
        stalledSince = nil
        phase = .idle
    }

    /// One control step, each camera frame. `tracked` false: the camera has lost the car.
    public mutating func step(_ estimate: CarEstimate?, tracked: Bool, time: Double) -> DriveCommand {
        guard let target else { return DriveCommand() }
        guard tracked, let car = estimate else {
            if phase != .lost { enter(.lost, time) }
            stalledSince = nil
            return DriveCommand()
        }
        let toTarget = target - car.position
        let distance = floorLength(toTarget)
        closest = min(closest, distance)
        // there, or just past it
        if distance < settings.arrive || (closest < settings.slowZone * 0.6 && distance > closest + 0.08) {
            finish(.arrived, time)
            return DriveCommand()
        }
        guard let heading = car.heading else {
            if phase != .probing { enter(.probing, time) }
            if time - phaseStart > 1.2 {
                finish(.stuck, time)
                return DriveCommand()
            }
            return DriveCommand(throttle: 1)
        }
        // > 0: the point is on the left
        let error = Angles.difference(atan2(toTarget.y, toTarget.x), heading)

        if phase == .reversing {
            if abs(error) < 70 * Double.pi / 180 || time - phaseStart > 1.5 {
                enter(.driving, time)
            } else {
                return backing(error)
            }
        } else if abs(error) > 115 * Double.pi / 180 && distance < 0.8 {
            enter(.reversing, time)
            return backing(error)
        } else if phase != .driving {
            enter(.driving, time)
        }

        let band = settings.deadband
        switch steering {
        case -1 where error < band / 3: steering = error < -band ? 1 : 0
        case 1 where error > -band / 3: steering = error > band ? -1 : 0
        case 0: steering = error > band ? -1 : (error < -band ? 1 : 0)
        default: break
        }

        var pace = distance > settings.slowZone
            ? settings.cruise
            : max(settings.approach, settings.cruise * distance / settings.slowZone)
        if steering != 0 { pace = max(settings.approach, pace * 0.75) }
        let throttle = car.speed < pace ? 1 : 0

        if throttle != 0 && car.speed < 0.05 {
            if let since = stalledSince {
                if time - since > 1.5 {
                    finish(.stuck, time)
                    return DriveCommand()
                }
            } else {
                stalledSince = time
            }
        } else {
            stalledSince = nil
        }
        return DriveCommand(throttle: throttle, steering: steering)
    }

    /// Reverse with the wheels the other way: the nose swings toward the point.
    private func backing(_ error: Double) -> DriveCommand {
        DriveCommand(throttle: -1, steering: error > 0 ? 1 : -1)
    }

    private mutating func enter(_ next: Phase, _ time: Double) {
        phase = next
        phaseStart = time
    }

    private mutating func finish(_ end: Phase, _ time: Double) {
        target = nil
        steering = 0
        stalledSince = nil
        enter(end, time)
    }
}
