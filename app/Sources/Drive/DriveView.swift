import SwiftUI
import CarKit

/// The main screen. By default the isometric game's floating sticks (steering under the left thumb, gas and reverse under
/// the right) with, between them, the read-out and the BOOST (the turbo), LIGHTS and 360 tiles in the game's look
/// (Tiles.swift, Julien's pick of 2026-10-31: pedals, then battery and Bluetooth, then the buttons). One layout only
/// (Julien: "no need to multiple layout"); the gear opens the one menu, Bluetooth debug included.
struct DriveView: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var link: LinkStore
    @EnvironmentObject private var driver: Driver
    @AppStorage(Prefs.steeringLeftKey) private var steeringOnLeft = true
    @State private var showPicker = false
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: 12) {
                topBar
                sticksLayout(landscape: landscape)
            }
            .padding(.horizontal, landscape ? 8 : 16)
            .padding(.vertical, 8)
        }
        .background { Theme.background.ignoresSafeArea() }
        .sheet(isPresented: $showPicker) { CarPicker().stores(ble, driver) }
        .sheet(isPresented: $showSettings) { SettingsView().stores(ble, driver) }
        .task {
            // the first launch starts on the list of cars (not under the UI tests)
            guard Prefs.lastCarID == nil, !ProcessInfo.processInfo.arguments.contains("-uitest") else { return }
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
}
