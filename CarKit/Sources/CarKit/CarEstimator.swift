import Foundation

/// Angles in radians on the floor, counter-clockwise seen from above.
public enum Angles {
    /// Wrapped to -pi...pi.
    public static func wrap(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 2 * .pi)
        if x > .pi { x -= 2 * .pi } else if x < -.pi { x += 2 * .pi }
        return x
    }

    /// a - b, wrapped: how far to turn from b to reach a (positive: to the left).
    public static func difference(_ a: Double, _ b: Double) -> Double {
        wrap(a - b)
    }
}

/// The length of a floor vector.
@inline(__always) public func floorLength(_ v: SIMD2<Double>) -> Double {
    (v.x * v.x + v.y * v.y).squareRoot()
}

/// Where the car is on the floor, how fast it goes and which way it points.
public struct CarEstimate: Equatable {
    /// Metres on the floor: x to the right, y away from where the session started (counter-clockwise from above).
    public var position: SIMD2<Double>
    /// Metres per second.
    public var velocity: SIMD2<Double>
    /// Radians, nil until the car has moved (or the image has shown which end is the front).
    public var heading: Double?
    /// Seconds (the camera frames' clock).
    public var time: Double

    public var speed: Double { floorLength(velocity) }
}

/// The car's state from where the camera saw it, frame after frame. The speed is the slope of the last 0.2 s of
/// positions; the heading comes from the way the car moves (backwards when it was last driven in reverse) and is kept
/// steady by the direction of its length in the image.
public struct CarEstimator {
    public private(set) var estimate: CarEstimate?
    /// Seconds of positions behind the speed.
    public var window = 0.2
    /// Below this speed (m/s) the motion says nothing about the heading.
    public var movingSpeed = 0.12
    private var samples: [(t: Double, p: SIMD2<Double>)] = []

    public init() {}

    public mutating func reset() {
        estimate = nil
        samples = []
    }

    /// One sighting. `axis`: the car's length on the floor (radians, a line: the same as + pi) when the image showed it
    /// clearly; `direction`: +1 when the car was last driven forward, -1 in reverse.
    public mutating func update(position: SIMD2<Double>, axis: Double?, direction: Int, time: Double) {
        let window = self.window
        if let last = samples.last, time <= last.t { return }
        samples.append((time, position))
        samples.removeAll { time - $0.t > window }

        var velocity = SIMD2<Double>(0, 0)
        if samples.count >= 3, let first = samples.first, time - first.t > 0.05 {
            let n = Double(samples.count)
            let mt = samples.reduce(0) { $0 + $1.t } / n
            let mp = samples.reduce(SIMD2<Double>(0, 0)) { $0 + $1.p } / n
            var stt = 0.0
            var sp = SIMD2<Double>(0, 0)
            for s in samples {
                let dt = s.t - mt
                stt += dt * dt
                sp += (s.p - mp) * dt
            }
            if stt > 0 { velocity = sp / stt }
        }

        var smoothed = position
        if let e = estimate {
            let predicted = e.position + e.velocity * min(time - e.time, 0.2)
            smoothed = predicted + (position - predicted) * 0.6
        }

        var heading = estimate?.heading
        if floorLength(velocity) > movingSpeed {
            var moving = atan2(velocity.y, velocity.x)
            if direction < 0 { moving += .pi }
            if let h = heading {
                heading = h + 0.3 * Angles.difference(moving, h)
            } else {
                heading = moving
            }
        }
        if let h = heading, let axis {
            // the axis is a line: take its end nearer the heading
            var d = Angles.difference(axis, h)
            if d > .pi / 2 { d -= .pi } else if d < -.pi / 2 { d += .pi }
            heading = h + 0.1 * d
        }
        estimate = CarEstimate(position: smoothed, velocity: velocity, heading: heading.map(Angles.wrap), time: time)
    }

    /// Where the car should be at `time`, from its last position and speed (at most 0.2 s ahead).
    public func predicted(at time: Double) -> SIMD2<Double>? {
        guard let e = estimate else { return nil }
        return e.position + e.velocity * max(0, min(time - e.time, 0.2))
    }
}
