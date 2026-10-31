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

/// The read-out, after F1 TV's onboard telemetry: speed, gear, shift lights, the throttle (green) and brake (red) bars,
/// the DRS tag (the turbo) and a g-force dot. All simulated: the toy reports nothing.
struct TelemetryHUD: View {
    @EnvironmentObject private var sim: TelemetrySim
    let drs: Bool

    var body: some View {
        let m = sim.model
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: -3) {
                Text("\(Int(abs(m.speed).rounded()))")
                    .font(.system(size: 34, weight: .heavy).italic().monospacedDigit())
                Text("KM/H")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .frame(width: 76, alignment: .trailing)
            Text(m.gear)
                .font(.system(size: 26, weight: .heavy).italic())
                .frame(width: 38, height: 44)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 6) {
                ShiftLights(revs: m.revs)
                PedalBar(label: "THR", value: m.throttle, color: Theme.throttle)
                PedalBar(label: "BRK", value: m.brake, color: Theme.brake)
            }
            VStack(spacing: 5) {
                Text("DRS")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(drs ? Color.black : Color.white.opacity(0.45))
                    .background(drs ? Theme.throttle : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
                GForce(long: m.gLong, lat: m.gLat, total: m.gTotal)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .foregroundStyle(Color.white)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.accent)
                .frame(width: 3)
                .padding(.vertical, 10)
        }
    }
}

/// Fifteen lights across the top, green, red then purple, as on an F1 steering wheel.
struct ShiftLights: View {
    let revs: Double

    var body: some View {
        let lit = Int((revs * 15).rounded())
        HStack(spacing: 2) {
            ForEach(0..<15, id: \.self) { i in
                Capsule()
                    .fill(i < lit ? color(i) : Color.white.opacity(0.12))
                    .frame(width: 7, height: 4)
            }
        }
    }

    private func color(_ i: Int) -> Color {
        if i < 5 { return Theme.throttle }
        if i < 10 { return Theme.brake }
        return Color(red: 0.62, green: 0.38, blue: 1)
    }
}

struct PedalBar: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 20, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(color).frame(width: CGFloat(value) * 103)
            }
            .frame(width: 103, height: 7)
        }
    }
}

/// The forces on the driver: braking pushes the dot up, a left turn pushes it right; the outer ring is 5 g.
struct GForce: View {
    let long: Double
    let lat: Double
    let total: Double

    var body: some View {
        let r: CGFloat = 18
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.3), lineWidth: 1)
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 1).padding(r / 2)
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 7, height: 7)
                    .offset(x: CGFloat(lat / 5) * r, y: CGFloat(-long / 5) * r)
            }
            .frame(width: r * 2, height: r * 2)
            Text(String(format: "%.1f G", total))
                .font(.system(size: 8, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }
}
