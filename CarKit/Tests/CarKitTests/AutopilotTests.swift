import XCTest
@testable import CarKit

/// A camera frame's colour plane, made up: a beige floor with a little noise and the red car, an ellipse 30 by 11
/// chroma pixels (about the SF-25 seen 2.5 m away).
private struct Scene {
    let width = 240
    let height = 180
    var bytes: [UInt8]

    init(car: SIMD2<Double>?, angle: Double = 0, length: Double = 30, breadth: Double = 11, seed: UInt64 = 7) {
        var bytes = [UInt8](repeating: 0, count: 240 * 180 * 2)
        var state = seed
        func noise(_ amplitude: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(2 * amplitude + 1)) - amplitude
        }
        let c = cos(angle), s = sin(angle)
        for y in 0..<180 {
            for x in 0..<240 {
                var cb = 120 + noise(3)
                var cr = 134 + noise(3)
                if let car {
                    let dx = Double(x) - car.x, dy = Double(y) - car.y
                    let u = dx * c + dy * s, v = -dx * s + dy * c
                    if u * u / (length * length / 4) + v * v / (breadth * breadth / 4) <= 1 {
                        cb = 100 + noise(4)
                        cr = 205 + noise(6)
                    }
                }
                bytes[(y * 240 + x) * 2] = UInt8(cb)
                bytes[(y * 240 + x) * 2 + 1] = UInt8(cr)
            }
        }
        self.bytes = bytes
    }

    func with<T>(_ body: (ChromaImage) -> T) -> T {
        bytes.withUnsafeBufferPointer { buffer in
            body(ChromaImage(width: width, height: height, bytesPerRow: width * 2, base: buffer.baseAddress!))
        }
    }
}

final class TrackerTests: XCTestCase {
    func testTheModelTellsTheCarFromTheFloor() {
        let at = SIMD2<Double>(120, 90)
        let lock = Scene(car: at, angle: 0.4).with { BlobTracker.lock($0, at: at, carLength: 30) }
        guard let model = lock?.tracker.model else { return XCTFail("no lock on the car") }
        XCTAssertGreaterThan(model.weights[ColorModel.bin(cb: 100, cr: 205)], 0.8)
        XCTAssertLessThan(model.weights[ColorModel.bin(cb: 120, cr: 134)], 0.1)
    }

    func testAnOffCentreTapStillLocks() {
        let car = SIMD2<Double>(120, 90)
        let lock = Scene(car: car, angle: 0.4).with { BlobTracker.lock($0, at: car + SIMD2(7, 6), carLength: 30) }
        guard let fix = lock?.fix else { return XCTFail("no lock on the car") }
        XCTAssertLessThan(floorLength(fix.center - car), 1.5)
    }

    func testATapOnTheFloorDoesNotLock() {
        let scene = Scene(car: SIMD2(180, 130))
        XCTAssertNil(scene.with { BlobTracker.lock($0, at: SIMD2(60, 60), carLength: 30) })
    }

    func testFollowsTheCarFrameAfterFrame() {
        let start = SIMD2<Double>(60, 90)
        guard let tracker = Scene(car: start, angle: 0.4).with({ BlobTracker.lock($0, at: start, carLength: 30) })?.tracker else {
            return XCTFail("no lock on the car")
        }
        var guess = start + SIMD2(4, -3)
        var truth = start
        for i in 1...30 {
            truth = start + SIMD2(Double(i) * 3, Double(i) * 0.8)
            let fix = Scene(car: truth, angle: 0.4, seed: UInt64(i)).with { tracker.track($0, from: guess, radius: 18) }
            guard let fix else { return XCTFail("lost at frame \(i)") }
            guess = fix.center
        }
        XCTAssertLessThan(floorLength(guess - truth), 1.5)
    }

    func testFindsTheCarsAxis() {
        let at = SIMD2<Double>(120, 90)
        for angle in [0.0, 0.4, 1.2, -0.7, 2.5] {
            let scene = Scene(car: at, angle: angle)
            guard let fix = scene.with({ BlobTracker.lock($0, at: at, carLength: 30) })?.fix else {
                return XCTFail("no lock at \(angle)")
            }
            // a line: the same with + pi
            var d = Angles.difference(fix.axis, angle)
            if d > .pi / 2 { d -= .pi } else if d < -.pi / 2 { d += .pi }
            XCTAssertLessThan(abs(d), 0.08, "axis \(fix.axis) for \(angle)")
            XCTAssertGreaterThan(fix.elongation, 2)
        }
    }

    func testFindsTheCarAgainAfterLosingIt() {
        let a = SIMD2<Double>(50, 50), b = SIMD2<Double>(180, 130)
        guard let tracker = Scene(car: a).with({ BlobTracker.lock($0, at: a, carLength: 30) })?.tracker else {
            return XCTFail("no lock on the car")
        }
        let moved = Scene(car: b, seed: 3)
        XCTAssertNil(moved.with { tracker.track($0, from: a, radius: 18) })
        guard let found = moved.with({ tracker.search($0, radius: 12) }) else { return XCTFail("not found again") }
        XCTAssertLessThan(floorLength(found.point - b), 6)
        let fix = moved.with { tracker.track($0, from: found.point, radius: 18) }
        XCTAssertLessThan(floorLength((fix?.center ?? .zero) - b), 1.5)
    }
}

final class EstimatorTests: XCTestCase {
    /// 60 sightings a second along `direction` at `speed`, with 4 mm of noise.
    private func run(speed: Double, heading: Double, driven: Int, frames: Int = 40) -> CarEstimate? {
        var estimator = CarEstimator()
        var state: UInt64 = 11
        func noise() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) % 801) / 100_000 - 0.004
        }
        // the car moves along `heading` when driven forward, against it in reverse
        let along = SIMD2(cos(heading), sin(heading)) * Double(driven)
        for i in 0..<frames {
            let t = Double(i) / 60
            let p = SIMD2<Double>(0.3, 1.2) + along * speed * t + SIMD2(noise(), noise())
            estimator.update(position: p, axis: nil, direction: driven, time: 100 + t)
        }
        return estimator.estimate
    }

    func testSpeedAndHeadingGoingForward() {
        let e = run(speed: 0.5, heading: 0.9, driven: 1)
        XCTAssertEqual(e?.speed ?? 0, 0.5, accuracy: 0.05)
        XCTAssertEqual(e?.heading ?? 99, 0.9, accuracy: 0.08)
    }

    func testHeadingInReverseIsTheFront() {
        let e = run(speed: 0.4, heading: -2.0, driven: -1)
        XCTAssertEqual(e?.speed ?? 0, 0.4, accuracy: 0.05)
        XCTAssertEqual(Angles.difference(e?.heading ?? 99, -2.0), 0, accuracy: 0.08)
    }

    func testNoHeadingBeforeItMoves() {
        let e = run(speed: 0, heading: 0, driven: 1)
        XCTAssertNil(e?.heading)
        XCTAssertLessThan(e?.speed ?? 1, 0.1)
    }

    func testTheAxisKeepsTheHeadingWhenStopped() {
        var estimator = CarEstimator()
        for i in 0..<30 {
            estimator.update(position: SIMD2(Double(i) * 0.01, 0), axis: nil, direction: 1, time: Double(i) / 60)
        }
        XCTAssertEqual(estimator.estimate?.heading ?? 99, 0, accuracy: 0.05)
        // stopped, the image says the car's length lies at 0.3 rad (or 0.3 + pi): the heading turns toward 0.3
        for i in 30..<90 {
            estimator.update(position: SIMD2(0.29, 0), axis: 0.3 + .pi, direction: 1, time: Double(i) / 60)
        }
        XCTAssertEqual(estimator.estimate?.heading ?? 99, 0.3, accuracy: 0.05)
    }
}

final class GoToPointTests: XCTestCase {
    private func car(at p: SIMD2<Double> = .zero, heading: Double? = 0, speed: Double = 0) -> CarEstimate {
        CarEstimate(position: p, velocity: SIMD2(cos(heading ?? 0), sin(heading ?? 0)) * speed, heading: heading, time: 10)
    }

    private func first(to target: SIMD2<Double>, from estimate: CarEstimate, tracked: Bool = true) -> (DriveCommand, GoToPoint.Phase) {
        var pilot = GoToPoint()
        pilot.go(to: target, time: 10)
        let command = pilot.step(estimate, tracked: tracked, time: 10)
        return (command, pilot.phase)
    }

    func testSteersTowardThePoint() {
        // heading 0 is along +x; +y is on the car's left (counter-clockwise from above)
        XCTAssertEqual(first(to: SIMD2(1, 0.5), from: car()).0, DriveCommand(throttle: 1, steering: -1))
        XCTAssertEqual(first(to: SIMD2(1, -0.5), from: car()).0, DriveCommand(throttle: 1, steering: 1))
        XCTAssertEqual(first(to: SIMD2(1, 0.05), from: car()).0, DriveCommand(throttle: 1, steering: 0))
    }

    func testBacksUpWhenThePointIsBehind() {
        // behind on the left: reverse with the wheels to the right, so the nose swings left
        let (command, phase) = first(to: SIMD2(-0.3, 0.2), from: car())
        XCTAssertEqual(command, DriveCommand(throttle: -1, steering: 1))
        XCTAssertEqual(phase, .reversing)
        XCTAssertEqual(first(to: SIMD2(-0.3, -0.2), from: car()).0, DriveCommand(throttle: -1, steering: -1))
    }

    func testKeepsThePace() {
        // already faster than the cruise: the throttle lets go
        XCTAssertEqual(first(to: SIMD2(2, 0), from: car(speed: 0.7)).0, DriveCommand(throttle: 0, steering: 0))
        // near the point the pace drops: 0.35 m/s is too fast 0.2 m away
        XCTAssertEqual(first(to: SIMD2(0.2, 0), from: car(speed: 0.35)).0.throttle, 0)
    }

    func testStopsThere() {
        let (command, phase) = first(to: SIMD2(0.08, 0.02), from: car(speed: 0.2))
        XCTAssertEqual(command, DriveCommand())
        XCTAssertEqual(phase, .arrived)
    }

    func testRollsForwardToLearnTheHeading() {
        let (command, phase) = first(to: SIMD2(1, 1), from: car(heading: nil))
        XCTAssertEqual(command, DriveCommand(throttle: 1, steering: 0))
        XCTAssertEqual(phase, .probing)
    }

    func testStopsWhenTheCameraLosesTheCar() {
        var pilot = GoToPoint()
        pilot.go(to: SIMD2(1, 0), time: 10)
        XCTAssertEqual(pilot.step(car(), tracked: false, time: 10), DriveCommand())
        XCTAssertEqual(pilot.phase, .lost)
        // found again: on its way
        XCTAssertEqual(pilot.step(car(), tracked: true, time: 10.1).throttle, 1)
        XCTAssertNotNil(pilot.target)
    }

    func testGivesUpWhenStuck() {
        var pilot = GoToPoint()
        pilot.go(to: SIMD2(1, 0), time: 10)
        var t = 10.0
        while t < 12 {
            _ = pilot.step(car(), tracked: true, time: t)
            t += 1.0 / 60
        }
        XCTAssertEqual(pilot.phase, .stuck)
        XCTAssertNil(pilot.target)
    }

    func testDrivesASimulatedCarThere() {
        // a car that goes 0.5 m/s with the throttle on, turns on a 0.3 m radius at full lock, and stops at once
        var pilot = GoToPoint()
        var position = SIMD2<Double>(0, 0), heading = 0.0
        let target = SIMD2<Double>(0.9, 0.7)
        pilot.go(to: target, time: 0)
        var estimator = CarEstimator()
        var direction = 1
        var t = 0.0
        while t < 10, pilot.target != nil {
            estimator.update(position: position, axis: nil, direction: direction, time: t)
            let c = pilot.step(estimator.estimate, tracked: true, time: t)
            if c.throttle != 0 { direction = c.throttle }
            let v = 0.5 * Double(c.throttle)
            heading += -Double(c.steering) * v / 0.3 / 60
            position += SIMD2(cos(heading), sin(heading)) * v / 60
            t += 1.0 / 60
        }
        XCTAssertEqual(pilot.phase, .arrived)
        XCTAssertLessThan(floorLength(position - target), 0.2)
    }
}
