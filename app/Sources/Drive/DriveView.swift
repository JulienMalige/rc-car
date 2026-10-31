import SwiftUI
import CarKit

/// The main screen. By default the isometric game's floating sticks (steering under the left thumb, gas and reverse under
/// the right) with, between them, the read-out and the BOOST (the turbo), LIGHTS and 360 tiles in the game's look
/// (Tiles.swift, Julien's pick of 2026-10-31: pedals, then battery and Bluetooth, then the buttons); Settings › Layout brings back build 1's big pads.
struct DriveView: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var link: LinkStore
    @EnvironmentObject private var driver: Driver
    @AppStorage(Prefs.steeringLeftKey) private var steeringOnLeft = true
    @AppStorage(Prefs.layoutKey) private var layout = DriveLayout.sticks.rawValue
    @State private var showPicker = false
    @State private var showDebug = false
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: 12) {
                topBar
                if layout == DriveLayout.pads.rawValue {
                    padsLayout(size: geo.size, landscape: landscape)
                } else {
                    sticksLayout(landscape: landscape)
                }
            }
            .padding(.horizontal, landscape ? 8 : 16)
            .padding(.vertical, 8)
        }
        .background { Theme.background.ignoresSafeArea() }
        .sheet(isPresented: $showPicker) { CarPicker().stores(ble, driver) }
        .sheet(isPresented: $showDebug) { DebugView().stores(ble, driver) }
        .sheet(isPresented: $showSettings) { SettingsView().stores(ble, driver) }
        .task {
            // the first launch starts on the list of cars
            guard Prefs.lastCarID == nil else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            if link.peripheralID == nil { showPicker = true }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                showPicker = true
            } label: {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(GameStyle.red)
                        .frame(width: 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text((link.name ?? "Choose your car").uppercased())
                            .font(GameStyle.face(17, .bold))
                            .tracking(17 * 0.06)
                            .lineLimit(1)
                        Caps(statusText, color: statusColor, size: 9)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 6)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.trailing, 12)
                }
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color.white)
                .gamePanel(bar: GameStyle.red)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            iconButton("wrench.and.screwdriver") { showDebug = true }
            iconButton("gearshape") { showSettings = true }
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(Color.white)
                .gamePanel(bar: .clear)
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch link.state {
        case .ready: return link.controlUUID == nil ? .orange : .green
        case .connecting, .discovering: return .yellow
        case .failed: return .red
        case .idle: return Color.white.opacity(0.5)
        }
    }

    private var statusText: String {
        if let problem = ble.bluetoothState.problem { return problem }
        switch link.state {
        case .connecting where link.name != nil: return "Waiting for the car…"
        case .ready where link.controlUUID == nil: return "Unknown car"
        default: return link.state.label
        }
    }

    // MARK: Floating sticks (the default)

    private func sticksLayout(landscape: Bool) -> some View {
        ZStack(alignment: landscape ? .bottom : .top) {
            TwinSticks(
                steerOnLeft: steeringOnLeft,
                onSteer: { v in driver.update { $0.steering = v } },
                onThrottle: { v in driver.update { $0.throttle = v } }
            )
            VStack(spacing: 6) {
                statusNote
                    .allowsHitTesting(false)
                DriveCluster(command: driver.command, battery: link.battery, rssi: link.rssi, compact: !landscape)
                frameLine
                    .allowsHitTesting(false)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Big pads (build 1's)

    @ViewBuilder
    private func padsLayout(size: CGSize, landscape: Bool) -> some View {
        if landscape {
            HStack(spacing: 18) {
                pad(steering: steeringOnLeft)
                centerPanel
                    .frame(width: min(300, size.width * 0.34))
                pad(steering: !steeringOnLeft)
            }
        } else {
            centerPanel
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                pad(steering: steeringOnLeft)
                pad(steering: !steeringOnLeft)
            }
            .frame(height: min(size.height * 0.45, 360))
        }
    }

    @ViewBuilder
    private func pad(steering: Bool) -> some View {
        if steering {
            SteeringPad(value: driver.command.steering) { v in driver.update { $0.steering = v } }
        } else {
            ThrottlePad(value: driver.command.throttle) { v in driver.update { $0.throttle = v } }
        }
    }

    // MARK: Middle

    private var centerPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ToggleTile(title: "Boost", symbol: "bolt.fill", isOn: driver.command.turbo) {
                    driver.update { $0.turbo.toggle() }
                }
                ToggleTile(title: "Lights", symbol: "lightbulb.fill", isOn: driver.command.lights) {
                    driver.update { $0.lights.toggle() }
                }
            }
            HoldTile(title: "Hold for 360", symbol: "arrow.triangle.2.circlepath", isOn: driver.command.spin) { on in
                driver.update { $0.spin = on }
            }
            telemetry
            statusNote
        }
    }

    @ViewBuilder
    private var statusNote: some View {
        if link.state == .ready && link.controlUUID == nil {
            Text("This car's controls are not known yet. Open the wrench, then share the services report.")
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        } else if link.state == .idle {
            Text("Tap “Choose your car” above. Turn the car on first.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// The car's own numbers (its battery when it reports one, the signal) and the frame being sent.
    private var telemetry: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                BatteryTile(battery: link.battery, width: 104)
                BluetoothTile(rssi: link.rssi, width: 140)
            }
            .foregroundStyle(Color.white)
            frameLine
        }
    }

    /// The bytes going to the car, small, for whoever is debugging.
    @ViewBuilder
    private var frameLine: some View {
        if !link.lastFrame.isEmpty {
            Text(Hex.string(link.lastFrame))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.4))
                .lineLimit(1)
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.93, green: 0.11, blue: 0.14)
    /// The game's charcoal, lighter in the middle.
    static let background = RadialGradient(
        colors: [Color(red: 0.165, green: 0.173, blue: 0.192), Color(red: 0.078, green: 0.082, blue: 0.094),
                 Color(red: 0.047, green: 0.051, blue: 0.059)],
        center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 700
    )
    static let padFill = Color.white.opacity(0.06)
    static let padStroke = Color.white.opacity(0.14)
}

/// Left and right halves; slide from one to the other without lifting.
struct SteeringPad: View {
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.padFill)
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.padStroke))
            HStack(spacing: 0) {
                PadZone(symbol: "arrowtriangle.left.fill", active: value < 0)
                Rectangle().fill(Theme.padStroke).frame(width: 1).padding(.vertical, 24)
                PadZone(symbol: "arrowtriangle.right.fill", active: value > 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            TouchPad(mode: .horizontal, onChange: onChange)
        }
        .accessibilityElement()
        .accessibilityLabel("Steering")
    }
}

/// Forward on the top half, reverse on the bottom.
struct ThrottlePad: View {
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.padFill)
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.padStroke))
            VStack(spacing: 0) {
                PadZone(symbol: "arrowtriangle.up.fill", active: value > 0, caption: "Forward")
                Rectangle().fill(Theme.padStroke).frame(height: 1).padding(.horizontal, 24)
                PadZone(symbol: "arrowtriangle.down.fill", active: value < 0, caption: "Reverse")
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            TouchPad(mode: .vertical, onChange: onChange)
        }
        .accessibilityElement()
        .accessibilityLabel("Throttle")
    }
}

struct PadZone: View {
    let symbol: String
    let active: Bool
    var caption: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .bold))
            if let caption {
                Text(caption.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
            }
        }
        .foregroundStyle(active ? Theme.accent : Color.white.opacity(0.45))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(active ? Theme.accent.opacity(0.18) : Color.clear)
        .animation(.easeOut(duration: 0.08), value: active)
    }
}

/// A switch that stays on (turbo, lights).
struct ToggleTile: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(isOn ? Color.black : Color.white)
            .background(isOn ? Color.yellow : Theme.padFill, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.padStroke))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// On only while held (the 360).
struct HoldTile: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.85))
        .background(isOn ? Theme.accent : Theme.padFill, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.padStroke))
        .overlay { TouchPad(mode: .hold) { onChange($0 != 0) } }
    }
}
