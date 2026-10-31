import CoreBluetooth
import CarKit

/// Turns the controls into frames for the car: a changed command leaves at once, an unchanged one is sent again every
/// keep-alive interval (some cars stop without a steady stream), and a write never queues behind another.
final class Driver: ObservableObject {
    @Published private(set) var command = DriveCommand()
    /// How many times the 360 has been started: the UI test reads it on the HOLD 360 tile.
    @Published private(set) var spinStarts = 0

    private let ble: BLEManager
    private var timer: Timer?
    private var lastFrame: [UInt8]?
    private var lastSentAt = Date.distantPast
    private var awaitingAck = false
    private var ackDeadline = Date.distantPast

    init(ble: BLEManager) {
        self.ble = ble
        ble.onWriteReady = { [weak self] in
            self?.awaitingAck = false
            self?.pump()
        }
        ble.onReady = { [weak self] in
            self?.lastFrame = nil
            self?.awaitingAck = false
            self?.pump()
        }
        ble.onDisconnect = { [weak self] in
            self?.lastFrame = nil
            self?.awaitingAck = false
        }
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in self?.pump() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func update(_ change: (inout DriveCommand) -> Void) {
        var next = command
        change(&next)
        guard next != command else { return }
        if next.spin && !command.spin { spinStarts += 1 }
        command = next
        pump()
    }

    /// Wheels stopped, turbo and lights kept: when the driver lets go or the app leaves the screen.
    func stop() {
        update { $0 = $0.stopped }
    }

    private func pump() {
        let link = ble.link
        guard link.state == .ready, let proto = link.detected, let uuid = link.controlUUID,
              let characteristic = ble.characteristic(uuid) else { return }
        let frame = proto.frame(command)
        let now = Date()
        let changed = frame != lastFrame
        let keepAlive = Prefs.keepAliveMs
        let due = keepAlive > 0 && now.timeIntervalSince(lastSentAt) * 1000 >= Double(keepAlive)
        guard changed || due else { return }
        if awaitingAck && now < ackDeadline { return } // the acknowledgement calls pump again
        let type = ble.writeType(for: characteristic, preference: Prefs.writePreference)
        guard ble.write(frame, to: characteristic, type: type, logged: changed) else { return }
        if changed { link.lastFrame = frame }
        lastFrame = frame
        lastSentAt = now
        if type == .withResponse {
            awaitingAck = true
            ackDeadline = now.addingTimeInterval(0.5)
        }
    }
}
