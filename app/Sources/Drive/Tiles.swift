import SwiftUI
import CarKit

/// The isometric game's look (its index.html, "the race's screens in the menu's look"), chosen by Julien on 2026-10-31
/// for the read-out: Barlow Semi Condensed for words (labels in small grey capitals), Saira ExtraBold Italic for every
/// figure, glossy black panels with square corners, a thin light edge and a coloured bar under each panel.
enum GameStyle {
    static func face(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        let name: String
        if weight == .heavy || weight == .black {
            name = "BarlowSemiCondensed-ExtraBold"
        } else if weight == .bold {
            name = "BarlowSemiCondensed-Bold"
        } else {
            name = "BarlowSemiCondensed-SemiBold"
        }
        return .custom(name, fixedSize: size)
    }

    static func num(_ size: CGFloat) -> Font {
        .custom("Saira-ExtraBoldItalic", fixedSize: size)
    }

    static let blue = Color(red: 0.353, green: 0.663, blue: 0.878) // --a1
    static let red = Color(red: 0.847, green: 0.196, blue: 0.227) // --a2
    static let light = Color(red: 0.914, green: 0.929, blue: 0.949) // --a3
    static let navy = Color(red: 0.173, green: 0.31, blue: 0.561) // --a4
    static let green = Color(red: 0.298, green: 0.718, blue: 0.51) // the throttle's
    static let yellow = Color(red: 0.91, green: 0.773, blue: 0.278)
    static let mute = Color(white: 0.54)
    static let track = Color(red: 0.106, green: 0.114, blue: 0.129)
    static let boost = Color(red: 0.604, green: 0.122, blue: 0.839)
    static let boostDeep = Color(red: 0.416, green: 0.059, blue: 0.6)
    static let gearFill = LinearGradient(colors: [Color(red: 0.31, green: 0.624, blue: 0.847), Color(red: 0.173, green: 0.365, blue: 0.659)],
                                         startPoint: .leading, endPoint: .trailing)
    static let gloss = LinearGradient(stops: [
        .init(color: Color(red: 0.227, green: 0.239, blue: 0.259).opacity(0.94), location: 0),
        .init(color: Color(red: 0.118, green: 0.125, blue: 0.137).opacity(0.95), location: 0.42),
        .init(color: Color(red: 0.063, green: 0.067, blue: 0.075).opacity(0.96), location: 1),
    ], startPoint: .top, endPoint: .bottom)
    static let sheen = LinearGradient(stops: [
        .init(color: .white.opacity(0), location: 0.3),
        .init(color: .white.opacity(0.09), location: 0.45),
        .init(color: .white.opacity(0), location: 0.6),
    ], startPoint: UnitPoint(x: 0.05, y: 0.29), endPoint: UnitPoint(x: 0.95, y: 0.71))
}

/// A label in the game's small grey capitals.
struct Caps: View {
    let text: String
    var color = GameStyle.mute
    var size: CGFloat = 10

    init(_ text: String, color: Color = GameStyle.mute, size: CGFloat = 10) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(GameStyle.face(size))
            .tracking(size * 0.14)
            .foregroundStyle(color)
    }
}

/// The game's panel: glossy black (or the given fill), a thin light edge, square corners, a coloured bar underneath.
struct GamePanel<Fill: ShapeStyle>: ViewModifier {
    let bar: Color
    let fill: Fill
    var glow: Color?

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Rectangle().fill(fill)
                    Rectangle().fill(GameStyle.sheen)
                }
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(bar).frame(height: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2).strokeBorder(Color.black, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .shadow(color: glow ?? Color.black.opacity(0.4), radius: glow == nil ? 7 : 9, y: glow == nil ? 4 : 0)
    }
}

extension View {
    func gamePanel(bar: Color) -> some View {
        modifier(GamePanel(bar: bar, fill: GameStyle.gloss))
    }

    func gamePanel<Fill: ShapeStyle>(bar: Color, fill: Fill, glow: Color? = nil) -> some View {
        modifier(GamePanel(bar: bar, fill: fill, glow: glow))
    }
}

// MARK: The read-out

/// Speed, gear, pedals and the car's own numbers, one glossy tile each (Julien's version 3, 2026-10-31).
struct TelemetryTiles: View {
    @EnvironmentObject private var sim: TelemetrySim
    let battery: Int?
    let rssi: Int?
    /// Narrower pedal bars, for a phone held upright.
    var compact = false

    var body: some View {
        let m = sim.model
        let barWidth: CGFloat = compact ? 84 : 112
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Caps("Speed")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(abs(m.speed).rounded()))")
                        .font(GameStyle.num(34))
                        .monospacedDigit()
                        .frame(minWidth: 64, alignment: .trailing)
                    Caps("km/h")
                }
            }
            .padding(EdgeInsets(top: 6, leading: 12, bottom: 9, trailing: 12))
            .frame(maxHeight: .infinity, alignment: .top)
            .gamePanel(bar: GameStyle.blue)

            VStack(spacing: 0) {
                Caps("Gear", color: GameStyle.light)
                Text(m.gear)
                    .font(GameStyle.num(34))
            }
            .frame(minWidth: 30)
            .padding(EdgeInsets(top: 6, leading: 10, bottom: 9, trailing: 10))
            .frame(maxHeight: .infinity, alignment: .top)
            .gamePanel(bar: GameStyle.navy, fill: GameStyle.gearFill)

            VStack(alignment: .leading, spacing: 4) {
                PedalRow(label: "Thr", value: m.throttle, color: GameStyle.green, width: barWidth)
                PedalRow(label: "Brk", value: m.brake, color: GameStyle.red, width: barWidth)
            }
            .frame(width: barWidth)
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 9, trailing: 12))
            .frame(maxHeight: .infinity, alignment: .top)
            .gamePanel(bar: GameStyle.green)

            LinkTile(battery: battery, rssi: rssi)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Color.white)
    }
}

struct PedalRow: View {
    let label: String
    let value: Double
    let color: Color
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Caps(label)
                Spacer(minLength: 0)
                Text("\(Int((value * 100).rounded()))")
                    .font(GameStyle.face(10, .bold))
                    .monospacedDigit()
            }
            ZStack(alignment: .leading) {
                Capsule().fill(GameStyle.track)
                Capsule().fill(color).frame(width: CGFloat(value) * width)
            }
            .frame(width: width, height: 6)
        }
    }
}

/// The car's battery when it reports one, and the Bluetooth signal; the signal alone otherwise.
struct LinkTile: View {
    let battery: Int?
    let rssi: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let battery {
                Caps("Batt")
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(battery)").font(GameStyle.num(24))
                    Caps("%")
                }
                signal(size: 12)
            } else {
                Caps("Signal")
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(rssi.map { "\($0)" } ?? "--").font(GameStyle.num(24))
                    Caps("dBm")
                }
                SignalBars(rssi: rssi)
            }
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 9, trailing: 12))
        .gamePanel(bar: barColor)
    }

    private func signal(size: CGFloat) -> some View {
        HStack(spacing: 4) {
            SignalBars(rssi: rssi)
            Text(rssi.map { "\($0)" } ?? "--").font(GameStyle.num(size))
        }
    }

    private var barColor: Color {
        guard let battery else { return GameStyle.blue }
        if battery > 40 { return GameStyle.green }
        return battery > 20 ? GameStyle.yellow : GameStyle.red
    }
}

/// Four bars for the Bluetooth signal: -60 dBm and better is four.
struct SignalBars: View {
    let rssi: Int?

    var body: some View {
        let lit = SignalBars.level(rssi)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Rectangle()
                    .fill(i < lit ? GameStyle.light : Color(white: 0.24))
                    .frame(width: 3, height: CGFloat(4 + 3 * i))
            }
        }
        .frame(height: 13, alignment: .bottom)
    }

    static func level(_ rssi: Int?) -> Int {
        guard let rssi else { return 0 }
        if rssi >= -60 { return 4 }
        if rssi >= -70 { return 3 }
        if rssi >= -80 { return 2 }
        return 1
    }
}

// MARK: The controls

/// BOOST, LIGHTS and the held 360 as the read-out's tiles (Julien: "with the buttons down there too").
struct ControlTiles: View {
    @EnvironmentObject private var driver: Driver

    var body: some View {
        HStack(spacing: 6) {
            Button {
                driver.update { $0.turbo.toggle() }
            } label: {
                ControlTileLabel(title: "Boost", symbol: "bolt.fill", isOn: driver.command.turbo,
                                 bar: GameStyle.boostDeep, onFill: GameStyle.boost, symbolColor: GameStyle.boost, glow: true)
            }
            .buttonStyle(.plain)
            .accessibilityValue(driver.command.turbo ? "On" : "Off")
            Button {
                driver.update { $0.lights.toggle() }
            } label: {
                ControlTileLabel(title: "Lights", symbol: "lightbulb.fill", isOn: driver.command.lights,
                                 bar: GameStyle.yellow, onFill: GameStyle.yellow, symbolColor: GameStyle.yellow, darkWhenOn: true)
            }
            .buttonStyle(.plain)
            .accessibilityValue(driver.command.lights ? "On" : "Off")
            ControlTileLabel(title: "Hold 360", symbol: "arrow.triangle.2.circlepath", isOn: driver.command.spin,
                             bar: GameStyle.red, onFill: GameStyle.red, symbolColor: GameStyle.light)
                .overlay { TouchPad(mode: .hold) { value in driver.update { $0.spin = value != 0 } } }
        }
    }
}

struct ControlTileLabel: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let bar: Color
    let onFill: Color
    let symbolColor: Color
    var darkWhenOn = false
    var glow = false

    var body: some View {
        let ink: Color = isOn && darkWhenOn ? .black : .white
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isOn ? ink : symbolColor)
            Text(title.uppercased())
                .font(GameStyle.face(14, .heavy))
                .tracking(14 * 0.14)
                .foregroundStyle(ink)
        }
        .frame(maxWidth: 138, minHeight: 50)
        .frame(minWidth: 112)
        .contentShape(Rectangle())
        .modifier(ControlTileBackground(isOn: isOn, bar: bar, onFill: onFill, glow: glow))
    }
}

private struct ControlTileBackground: ViewModifier {
    let isOn: Bool
    let bar: Color
    let onFill: Color
    let glow: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isOn {
            content.gamePanel(bar: bar, fill: onFill, glow: glow ? onFill.opacity(0.55) : nil)
        } else {
            content.gamePanel(bar: bar)
        }
    }
}
