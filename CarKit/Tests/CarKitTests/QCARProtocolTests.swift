import XCTest
@testable import CarKit

/// The frames other projects replay to real QCAR cars (jenkings/BLE-RC-Car-ESP32, ariasbruno/rc-commander
/// constants/commands.ts): our encoder must produce them byte for byte.
final class QCARProtocolTests: XCTestCase {
    private func hex(_ c: DriveCommand) -> String { Hex.string(QCARProtocol.frame(c), separator: "") }

    func testKnownFrames() {
        let known: [(DriveCommand, String)] = [
            (DriveCommand(), "025e695a48ff2a438ca680f83e04e45d"),
            (DriveCommand(throttle: 1), "29609c664852cff1b0f0cbb98014bd2c"),
            (DriveCommand(throttle: -1), "03209909ba9da1c8b986163c6d484655"),
            (DriveCommand(steering: -1), "51382112135cccdb46cf8921b705499a"),
            (DriveCommand(steering: 1), "1b5769cdf13e8ab627080ff3cefc3bc0"),
            (DriveCommand(turbo: true), "d994b371c3be2a9a9d0488a1044b7f67"),
            (DriveCommand(throttle: 1, turbo: true), "e65567da8e6c560d09d3733a7f47ff06"),
            (DriveCommand(throttle: -1, turbo: true), "cec2ff1d7acc163cd13b7e6153ad5c45"),
            (DriveCommand(throttle: 1, steering: -1), "9928e590dfe821485f414fbb633d5c4e"),
            (DriveCommand(throttle: 1, steering: 1), "0f2ce56662d4fd9d32a44f102bf20aa7"),
            (DriveCommand(throttle: -1, steering: -1), "98ce981d58d115afe11960bf4613925c"),
            (DriveCommand(throttle: -1, steering: 1), "f2520fba3144fb11468fe080c6c2c23c"),
            (DriveCommand(throttle: 1, steering: -1, turbo: true), "592381c943a417ca1bc3b59400e0fc12"),
            (DriveCommand(throttle: 1, steering: 1, turbo: true), "fb976fba04af87022226ec50ae82f8c4"),
            (DriveCommand(throttle: -1, steering: -1, turbo: true), "d54ad55857d327745f141dd00d671595"),
            (DriveCommand(throttle: -1, steering: 1, turbo: true), "80dfb2165f3260f1d9837750f43a43da"),
            (DriveCommand(lights: true), "39b53b9bb7a0e0d65254f9ea845ddeee"),
            // rc-commander's 360 is its forward-right-turbo frame
            (DriveCommand(spin: true), "fb976fba04af87022226ec50ae82f8c4"),
        ]
        for (command, frame) in known {
            XCTAssertEqual(hex(command), frame, "\(command)")
        }
    }

    func testPlaintextLayout() {
        let p = QCARProtocol.plaintext(DriveCommand(throttle: 1, steering: 1, turbo: true, lights: true))
        XCTAssertEqual(Hex.string(p, separator: ""), "0043544c010000010064000000000000")
    }

    func testBatteryNotification() {
        // 07 'VBT' 0x55 encrypted with the car key (openssl enc -aes-128-ecb -nopad)
        let status = QCARProtocol.status(Hex.parse("378aca8eacb543bedec0d0b4be4e213b")!)
        XCTAssertEqual(status, QCARProtocol.Status(sequence: 7, battery: 85))
        XCTAssertNil(QCARProtocol.status(QCARProtocol.frame(.neutral)), "a control frame is not a battery reading")
        XCTAssertNil(QCARProtocol.status([1, 2, 3]))
    }

    func testAESReferenceVector() {
        // FIPS-197 appendix C.1
        let key = Hex.parse("000102030405060708090a0b0c0d0e0f")!
        let plain = Hex.parse("00112233445566778899aabbccddeeff")!
        let cipher = AES128.encrypt(plain, key: key)!
        XCTAssertEqual(Hex.string(cipher, separator: ""), "69c4e0d86a7b0430d8cdb78070b4c55a")
        XCTAssertEqual(AES128.decrypt(cipher, key: key), plain)
        XCTAssertNil(AES128.encrypt([1, 2, 3], key: key))
    }
}
