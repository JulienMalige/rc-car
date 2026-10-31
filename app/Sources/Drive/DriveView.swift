import SwiftUI
import CarKit

/// The main screen. By default the isometric game's floating sticks (steering under the left thumb, gas and reverse under
/// the right), DRS (the turbo), lights and 360 above them, and an F1 TV style read-out; Settings › Layout brings back
/// build 1's big pads.
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
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(link.name ?? "Choose your car")
                        .font(.headline)
                        .lineLimit(1)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
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
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch link.state {
        case .ready: return link.controlUUID == nil ? .orange : .green
        case .connecting, .discovering: return .yellow
        case .failed: return .red
        case .idle: return .gray
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
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                GameToggle(title: "DRS", symbol: "bolt.fill", isOn: driver.command.turbo) {
                    driver.update { $0.turbo.toggle() }
                }
                GameToggle(title: "LIGHTS", symbol: "lightbulb.fill", isOn: driver.command.lights) {
                    driver.update { $0.lights.toggle() }
                }
                GameHold(title: "HOLD 360", symbol: "arrow.triangle.2.circlepath", isOn: driver.command.spin) { on in
                    driver.update { $0.spin = on }
                }
            }
            ZStack(alignment: landscape ? .bottom : .top) {
                TwinSticks(
                    steerOnLeft: steeringOnLeft,
                    onSteer: { v in driver.update { $0.steering = v } },
                    onThrottle: { v in driver.update { $0.throttle = v } }
                )
                VStack(spacing: 6) {
                    statusNote
                    TelemetryHUD(drs: driver.command.turbo)
                    telemetry
                }
                .padding(.vertical, 4)
                .allowsHitTesting(false)
            }
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
                ToggleTile(title: "Turbo", symbol: "bolt.fill", isOn: driver.command.turbo) {
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

    private var telemetry: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                if let battery = link.battery {
                    Label("\(battery)%", systemImage: batterySymbol(battery))
                }
                if let rssi = link.rssi {
                    Label("\(rssi) dBm", systemImage: "antenna.radiowaves.left.and.right")
                }
                if let proto = link.detected, link.state == .ready {
                    Text(proto == .sl ? "SL" : "QCAR")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !link.lastFrame.isEmpty {
                Text(Hex.string(link.lastFrame))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.93, green: 0.11, blue: 0.14)
    static let throttle = Color(red: 0.0, green: 0.86, blue: 0.36)
    static let brake = Color(red: 1.0, green: 0.16, blue: 0.2)
    static let background = LinearGradient(
        colors: [Color(red: 0.07, green: 0.07, blue: 0.09), Color(red: 0.13, green: 0.05, blue: 0.06)],
        startPoint: .top, endPoint: .bottom
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

/// The isometric game's buttons (touchstyle.js): dark, a thin white border, red when on.
struct GameButtonLabel: View {
    let title: String
    let symbol: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .frame(minWidth: 96, minHeight: 44)
        .background(isOn ? Color(red: 0.9, green: 0.25, blue: 0.18).opacity(0.85) : Color(red: 0.04, green: 0.05, blue: 0.08).opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.4), lineWidth: 1))
    }
}

/// On until tapped again (DRS, lights).
struct GameToggle: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GameButtonLabel(title: title, symbol: symbol, isOn: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// On while held (the 360).
struct GameHold: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        GameButtonLabel(title: title, symbol: symbol, isOn: isOn)
            .overlay { TouchPad(mode: .hold) { onChange($0 != 0) } }
    }
}
