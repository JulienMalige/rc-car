/// Bburago's Ferrari cars ("SL-SF-24", "SL-499P", ...): one 8-byte frame, in clear, on characteristic FFF1 of
/// service FFF0. Sources: ariasbruno/rc-commander (SLController.ts, its car list) and jenkings/BLE-RC-Car-ESP32
/// (getBBuragoCommand), which agree on the layout:
///
///     01  fwd  back  left  right  lights  turbo  spin
///
/// Each flag is 0 or 1. rc-commander sets turbo only while the car is driven; the ESP32 sets it whenever it is on.
public enum SLProtocol {
    public static let service = "FFF0"
    public static let control = "FFF1"
    /// Seen commented out in the ESP32 code as another Bburago model's pair; tried when FFF1 is missing.
    public static let altService = "6936"
    public static let altControl = "FE01"

    public static func frame(_ c: DriveCommand) -> [UInt8] {
        [
            0x01,
            flag(c.throttle > 0),
            flag(c.throttle < 0),
            flag(c.steering < 0),
            flag(c.steering > 0),
            flag(c.lights),
            flag(c.turbo && c.throttle != 0),
            flag(c.spin),
        ]
    }

    private static func flag(_ on: Bool) -> UInt8 {
        on ? 1 : 0
    }
}
