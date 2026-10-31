import XCTest

/// Holding HOLD 360 must keep the spin on for as long as the finger stays (Julien, 2026-10-31: it worked in build 1, not
/// in builds 4 and 5, where the tile sits between the sticks). The tile's accessibility value is "<spins started> <ms the
/// last one lasted>". A first version only counted the start, and passed: the spin did start.
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
        XCTAssertEqual(tile.value as? String, "0 0")
        tile.press(forDuration: 1.0)
        let parts = (tile.value as? String ?? "").split(separator: " ").compactMap { Int($0) }
        XCTAssertEqual(parts.first, 1, "holding the tile started one spin, not several")
        XCTAssertGreaterThan(parts.last ?? 0, 700, "the spin lasted as long as the finger held the tile (1 s)")
    }
}
