import XCTest
@testable import CarKit

final class SLProtocolTests: XCTestCase {
    private func hex(_ c: DriveCommand) -> String { Hex.string(SLProtocol.frame(c)) }

    func testFrames() {
        XCTAssertEqual(hex(.neutral), "01 00 00 00 00 00 00 00")
        XCTAssertEqual(hex(DriveCommand(throttle: 1)), "01 01 00 00 00 00 00 00")
        XCTAssertEqual(hex(DriveCommand(throttle: -1)), "01 00 01 00 00 00 00 00")
        XCTAssertEqual(hex(DriveCommand(steering: -1)), "01 00 00 01 00 00 00 00")
        XCTAssertEqual(hex(DriveCommand(steering: 1)), "01 00 00 00 01 00 00 00")
        XCTAssertEqual(hex(DriveCommand(lights: true)), "01 00 00 00 00 01 00 00")
        XCTAssertEqual(hex(DriveCommand(spin: true)), "01 00 00 00 00 00 00 01")
        XCTAssertEqual(hex(DriveCommand(throttle: 1, steering: 1, turbo: true, lights: true)), "01 01 00 00 01 01 01 00")
    }

    func testTurboOnlyWhileDriven() {
        // as rc-commander sends it: the turbo flag rides on a throttle, never alone
        XCTAssertEqual(hex(DriveCommand(turbo: true)), "01 00 00 00 00 00 00 00")
        XCTAssertEqual(hex(DriveCommand(throttle: -1, turbo: true)), "01 00 01 00 00 00 01 00")
    }

    func testCommandClampsToOneStep() {
        XCTAssertEqual(DriveCommand(throttle: 5, steering: -7), DriveCommand(throttle: 1, steering: -1))
        XCTAssertEqual(DriveCommand(throttle: 1, steering: 1, turbo: true, lights: true, spin: true).stopped,
                       DriveCommand(turbo: true, lights: true))
    }
}

final class CatalogTests: XCTestCase {
    func testHints() {
        XCTAssertEqual(CarCatalog.protocolHint(name: "SL-SF-24"), .sl)
        XCTAssertEqual(CarCatalog.protocolHint(name: "QCAR-3217D4"), .qcar)
        XCTAssertNil(CarCatalog.protocolHint(name: "AirPods"))
        XCTAssertTrue(CarCatalog.looksLikeCar(name: nil, services: ["FFF0"]))
        XCTAssertTrue(CarCatalog.looksLikeCar(name: "SL-SF-25", services: []))
        XCTAssertFalse(CarCatalog.looksLikeCar(name: "Julien's AirPods", services: ["180F"]))
    }

    func testDetectionPrefersTheCharacteristics() {
        let qcar = CarCatalog.detect(characteristics: ["2A00", QCARProtocol.control, QCARProtocol.status], name: "SL-X")
        XCTAssertEqual(qcar?.0, .qcar)
        XCTAssertEqual(CarCatalog.detect(characteristics: ["2A00", "fff1"], name: nil)?.1, "FFF1")
        XCTAssertEqual(CarCatalog.detect(characteristics: ["FE01"], name: nil)?.0, .sl)
        XCTAssertNil(CarCatalog.detect(characteristics: ["2A00", "2A19"], name: "SL-SF-25"))
        XCTAssertEqual(CarCatalog.control(for: .sl, characteristics: ["FFF1", QCARProtocol.control]), "FFF1")
        XCTAssertNil(CarCatalog.control(for: .qcar, characteristics: ["FFF1"]))
    }
}

final class HexTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(Hex.parse("01 02 ff"), [1, 2, 255])
        XCTAssertEqual(Hex.parse("0102FF"), [1, 2, 255])
        XCTAssertEqual(Hex.parse("0x01, 0x02"), [1, 2])
        XCTAssertEqual(Hex.parse("01:0a"), [1, 10])
        XCTAssertNil(Hex.parse("012"))
        XCTAssertNil(Hex.parse("zz"))
        XCTAssertNil(Hex.parse("  "))
    }

    func testFormat() {
        XCTAssertEqual(Hex.string([0, 15, 16, 255]), "00 0f 10 ff")
        XCTAssertEqual(Hex.ascii(Array("SL-SF-25".utf8) + [0]), "SL-SF-25")
        XCTAssertNil(Hex.ascii([0x01, 0x02]))
    }
}
