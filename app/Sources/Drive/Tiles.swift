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

/// Only what is real (Julien, 2026-10-31: "there is no gear and there is no speed"), his layout C: the car's battery
/// and the Bluetooth signal on top; under them one PEDALS box, the brake (red) and the throttle (green) as vertical bars
/// as on the 2026 F1 TV graphic, beside the BOOST, LIGHTS and HOLD 360 tiles stacked.
struct DriveCluster: View {
    let command: DriveCommand
    let battery: Int?
    let rssi: Int?

    private static let buttonHeight: CGFloat = 58

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                BatteryTile(battery: battery, width: 118)
                BluetoothTile(rssi: rssi, width: 156)
            }
            .allowsHitTesting(false)
            HStack(alignment: .top, spacing: 6) {
                PedalsTile(throttle: command.throttle > 0, brake: command.throttle < 0)
                    .frame(width: 118, height: Self.buttonHeight * 3 + 12)
                    .allowsHitTesting(false)
                ControlTiles(column: true)
                    .frame(width: 156)
                    .environment(\.controlTileHeight, Self.buttonHeight)
            }
        }
        .foregroundStyle(Color.white)
    }
}

/// The brake and the throttle as they are being sent (up is throttle; down brakes, then reverses): eight segments
/// each, all lit while the command is on, as the cars are all or nothing.
struct PedalsTile: View {
    let throttle: Bool
    let brake: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Caps("Pedals")
            HStack {
                Segments(on: brake, color: GameStyle.red)
                Spacer(minLength: 0)
                Segments(on: throttle, color: GameStyle.green)
            }
            .frame(maxHeight: .infinity)
            HStack {
                Caps("Brk", color: GameStyle.red)
                Spacer(minLength: 0)
                Caps("Thr", color: GameStyle.green)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 14, bottom: 11, trailing: 14))
        .gamePanel(bar: .clear)
        .overlay(alignment: .bottom) {
            HStack(spacing: 0) {
                Rectangle().fill(GameStyle.red)
                Rectangle().fill(GameStyle.green)
            }
            .frame(height: 3)
            .padding(.horizontal, 1)
            .padding(.bottom, 1)
        }
    }
}

struct Segments: View {
    let on: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<8, id: \.self) { _ in
                Rectangle()
                    .fill(on ? color : Color(red: 0.137, green: 0.149, blue: 0.169))
                    .shadow(color: on ? color.opacity(0.8) : .clear, radius: 3)
            }
        }
        .frame(width: 30)
        .animation(.easeOut(duration: 0.1), value: on)
    }
}

/// The car's own battery, when it reports one (Battery service 180F, or the QCAR cars' notifications).
struct BatteryTile: View {
    let battery: Int?
    let width: CGFloat
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caps("Battery")
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(battery.map { "\($0)" } ?? "--")
                    .font(GameStyle.num(compact ? 20 : 24))
                if battery != nil { Caps("%") }
            }
        }
        .padding(EdgeInsets(top: 6, leading: compact ? 10 : 12, bottom: 9, trailing: compact ? 6 : 12))
        .frame(width: width, height: 58, alignment: .topLeading)
        .gamePanel(bar: barColor)
    }

    private var barColor: Color {
        guard let battery else { return GameStyle.mute }
        if battery > 40 { return GameStyle.green }
        return battery > 20 ? GameStyle.yellow : GameStyle.red
    }
}

/// The signal of the Bluetooth link to the car, read every two seconds.
struct BluetoothTile: View {
    let rssi: Int?
    let width: CGFloat
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caps("Bluetooth")
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                SignalBars(rssi: rssi)
                Text(rssi.map { "\($0)" } ?? "--")
                    .font(GameStyle.num(compact ? 18 : 24))
                if !compact { Caps("dBm") }
            }
        }
        .padding(EdgeInsets(top: 6, leading: compact ? 10 : 12, bottom: 9, trailing: compact ? 6 : 12))
        .frame(width: width, height: 58, alignment: .topLeading)
        .gamePanel(bar: GameStyle.blue)
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

/// BOOST, LIGHTS and the held 360 as the read-out's tiles (Julien: "with the buttons down there too", then stacked).
struct ControlTiles: View {
    @EnvironmentObject private var driver: Driver
    /// Stacked beside the pedals (layout C), or in a row.
    var column = false

    var body: some View {
        let layout = column ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
        layout {
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

private struct ControlTileHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 50
}

extension EnvironmentValues {
    /// The control tiles' height: taller when stacked.
    var controlTileHeight: CGFloat {
        get { self[ControlTileHeightKey.self] }
        set { self[ControlTileHeightKey.self] = newValue }
    }
}

struct ControlTileLabel: View {
    @Environment(\.controlTileHeight) private var height
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
        .frame(maxWidth: 156, minHeight: height)
        .frame(minWidth: 140)
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
