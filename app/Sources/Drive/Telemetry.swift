import SwiftUI
import QuartzCore
import CarKit

/// Steps the pretend telemetry (CarKit's SpeedModel) 30 times a second from the driver's command. Only the read-out
/// observes it, so the rest of the screen does not redraw at that rate.
final class TelemetrySim: ObservableObject {
    @Published private(set) var model = SpeedModel()
    private weak var driver: Driver?
    private var timer: Timer?
    private var last = CACurrentMediaTime()

    init(driver: Driver) {
        self.driver = driver
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = now - last
        last = now
        guard let driver else { return }
        var next = model
        next.step(driver.command, dt: dt)
        if next != model { model = next }
    }
}
