import XCTest

/// Holding HOLD 360 must turn the spin on (Julien, 2026-10-31: it worked in build 1, not in builds 4 and 5, where the
/// tile sits between the sticks, over their touch layer). The tile's accessibility value counts the spins started.
final class HoldTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testHolding360TurnsTheSpinOn() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        addUIInterruptionMonitor(withDescription: "Bluetooth permission") { alert in
            for title in ["Allow", "OK"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let tile = app.descendants(matching: .any)["hold360"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "the HOLD 360 tile is on screen")
        XCTAssertEqual(tile.value as? String, "0")
        tile.press(forDuration: 0.8)
        XCTAssertEqual(tile.value as? String, "1", "holding the tile turned the spin on")
    }
}
