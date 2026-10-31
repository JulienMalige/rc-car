import XCTest
@testable import CarKit

final class SpeedModelTests: XCTestCase {
    private func run(_ model: inout SpeedModel, _ command: DriveCommand, seconds: Double) {
        for _ in 0..<Int(seconds * 60) { model.step(command, dt: 1.0 / 60) }
    }

    func testFullThrottleReachesTopSpeedInSeventhOrEighth() {
        var m = SpeedModel()
        XCTAssertEqual(m.gear, "N")
        run(&m, DriveCommand(throttle: 1), seconds: 1)
        XCTAssertGreaterThan(m.speed, 100)
        XCTAssertLessThan(m.gLong, -1, "speeding up pushes the driver back")
        XCTAssertEqual(m.throttle, 1, accuracy: 0.001)
        run(&m, DriveCommand(throttle: 1), seconds: 12)
        XCTAssertEqual(m.speed, SpeedModel.topSpeed, accuracy: 1)
        XCTAssertEqual(m.gear, "7")
        run(&m, DriveCommand(throttle: 1, turbo: true), seconds: 12)
        XCTAssertEqual(m.speed, SpeedModel.turboTopSpeed, accuracy: 1)
        XCTAssertEqual(m.gear, "8")
    }

    func testLiftingOffStopsTheCarWithoutReversing() {
        var m = SpeedModel()
        run(&m, DriveCommand(throttle: 1), seconds: 5)
        var last = m.speed
        for _ in 0..<(6 * 60) {
            m.step(.neutral, dt: 1.0 / 60)
            XCTAssertLessThanOrEqual(m.speed, last)
            last = m.speed
        }
        XCTAssertEqual(m.speed, 0)
        XCTAssertEqual(m.gear, "N")
        XCTAssertEqual(m.throttle, 0)
    }

    func testPullingBackBrakesThenReverses() {
        var m = SpeedModel()
        run(&m, DriveCommand(throttle: 1), seconds: 3)
        XCTAssertGreaterThan(m.speed, 150)
        run(&m, DriveCommand(throttle: -1), seconds: 0.3)
        XCTAssertEqual(m.brake, 1, accuracy: 0.001)
        XCTAssertGreaterThan(m.gLong, 2, "braking throws the driver forward")
        run(&m, DriveCommand(throttle: -1), seconds: 2)
        XCTAssertLessThan(m.speed, 0)
        XCTAssertEqual(m.gear, "R")
        XCTAssertGreaterThanOrEqual(m.speed, -SpeedModel.reverseTopSpeed)
        run(&m, DriveCommand(throttle: -1), seconds: 3)
        XCTAssertEqual(m.speed, -SpeedModel.reverseTopSpeed, accuracy: 0.01)
    }

    func testCorneringPushesTheDriverOutwards() {
        var m = SpeedModel()
        run(&m, DriveCommand(throttle: 1), seconds: 6)
        run(&m, DriveCommand(throttle: 1, steering: -1), seconds: 1)
        XCTAssertGreaterThan(m.gLat, 2, "a left turn pushes to the right")
        run(&m, DriveCommand(throttle: 1, steering: 1), seconds: 1)
        XCTAssertLessThan(m.gLat, -2)
        XCTAssertLessThanOrEqual(m.gTotal, 5 * 2.0.squareRoot())
    }

    func testRevsRiseInEachGear() {
        var m = SpeedModel()
        var previousGear = m.gear
        var previousRevs = 0.0
        for _ in 0..<(8 * 60) {
            m.step(DriveCommand(throttle: 1, turbo: true), dt: 1.0 / 60)
            if m.gear == previousGear {
                XCTAssertGreaterThanOrEqual(m.revs + 1e-9, previousRevs)
            }
            XCTAssertTrue((0...1).contains(m.revs))
            previousGear = m.gear
            previousRevs = m.revs
        }
    }
}
