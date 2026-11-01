import ARKit
import CarKit
import RoomPlan
import SceneKit
import SwiftUI

/// "Drive to a point", autopilot step 2 (Julien's pick of 2026-11-01, mock-up 2): the camera with the lock ring, the
/// route and the flag drawn on the floor; beside it the scanned room from above, turned the way the camera looks, with
/// the car (a dot for now: "then we will find a 3D model"), its trail and the flag; the speed and the distance the camera
/// measures; STOP. Tap the car once, then a point on the floor or on the map.
struct DriveToPointView: View {
    @EnvironmentObject private var link: LinkStore
    @EnvironmentObject private var driver: Driver
    @EnvironmentObject private var log: LogStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var autopilot = AutopilotSession()
    @ObservedObject private var rooms = RoomStore.shared
    @State private var plan: Plan2D?

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let layout = landscape ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                camera
                panel
                    .frame(width: landscape ? min(310, geo.size.width * 0.36) : nil,
                           height: landscape ? nil : geo.size.height * 0.46)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            plan = rooms.room.map(Plan2D.init)
            autopilot.attach(driver: driver, link: link, log: log)
            autopilot.start()
        }
        .onDisappear {
            autopilot.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { autopilot.halt() }
        }
    }

    // MARK: Camera

    private var camera: some View {
        ZStack(alignment: .top) {
            if ARWorldTrackingConfiguration.isSupported {
                ZStack {
                    ARCameraView(session: autopilot.session)
                    OverlayCanvas(overlay: autopilot.overlay, toGo: autopilot.toGo)
                        .allowsHitTesting(false)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { point in
                            autopilot.tap(at: point)
                        }
                }
                .background {
                    GeometryReader { g in
                        Color.clear
                            .onAppear { autopilot.viewport = g.size }
                            .onChange(of: g.size) { _, size in autopilot.viewport = size }
                    }
                }
                .ignoresSafeArea()
            } else {
                Text("The autopilot needs an iPhone with a LiDAR camera.")
                    .font(GameStyle.face(15))
                    .foregroundStyle(GameStyle.mute)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            hud
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
    }

    private var hud: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                tag
                Spacer(minLength: 8)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Color.white)
                        .gamePanel(bar: .clear)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            chip
        }
    }

    private var tag: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(GameStyle.red)
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text("AUTOPILOT")
                    .font(GameStyle.face(17, .bold))
                    .tracking(17 * 0.06)
                Caps(tagLine, color: tagColor, size: 9)
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .padding(.trailing, 14)
        }
        .fixedSize()
        .foregroundStyle(Color.white)
        .gamePanel(bar: GameStyle.red)
    }

    private var tagLine: String {
        guard link.state == .ready else { return "Car not connected" }
        let name = link.name ?? "the car"
        switch autopilot.status {
        case .starting, .findingRoom, .noFloor, .tapCar, .notCar: return name
        case .lost: return "Lost \(name)"
        default: return "Locked on \(name)"
        }
    }

    private var tagColor: Color {
        guard link.state == .ready else { return .orange }
        switch autopilot.status {
        case .starting, .findingRoom, .noFloor, .tapCar, .notCar: return Color.white.opacity(0.6)
        case .lost: return .orange
        default: return .green
        }
    }

    private var chip: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(chipColor)
                .frame(width: 9, height: 9)
                .shadow(color: chipColor, radius: 5)
            Text(chipText.uppercased())
                .font(GameStyle.face(13, .bold))
                .tracking(13 * 0.12)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.white)
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: 36)
        .background(Capsule().fill(Color(red: 0.04, green: 0.047, blue: 0.063).opacity(0.74)))
        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
        .accessibilityIdentifier("autopilotStatus")
    }

    private var chipText: String {
        switch autopilot.status {
        case .starting: return "Starting the camera"
        case .findingRoom: return "Finding the room: move the phone slowly"
        case .noFloor: return "Point the camera at the floor"
        case .tapCar: return "Tap the car"
        case .notCar: return "No car there: tap right on it"
        case .tapTarget: return "Tap where it should go"
        case .noCar: return "Connect the car first"
        case .probing: return "Finding which way it points"
        case .driving: return "Driving to the flag"
        case .reversing: return "Backing up to turn"
        case .arrived: return "Arrived: tap a new point"
        case .lost: return "Car lost: tap it"
        case .stuck: return "Stuck: tap a new point"
        }
    }

    private var chipColor: Color {
        switch autopilot.status {
        case .probing, .driving, .reversing, .arrived: return GameStyle.green
        case .tapCar, .tapTarget: return GameStyle.blue
        case .notCar, .noCar, .lost, .stuck: return GameStyle.red
        case .starting, .findingRoom, .noFloor: return GameStyle.yellow
        }
    }

    // MARK: Map, read-outs, STOP

    private var panel: some View {
        VStack(spacing: 10) {
            map
            HStack(spacing: 8) {
                ReadoutTile(caption: "Speed", value: autopilot.speed.map { String(format: "%.1f", $0) } ?? "–",
                            unit: "m/s", bar: GameStyle.blue)
                ReadoutTile(caption: "To go", value: autopilot.toGo.map { String(format: "%.1f", $0) } ?? "–",
                            unit: "m", bar: GameStyle.green)
            }
            Button {
                autopilot.halt()
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                    Text("STOP")
                        .font(GameStyle.face(22, .heavy))
                        .tracking(22 * 0.16)
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(LinearGradient(colors: [Color(red: 0.886, green: 0.278, blue: 0.29),
                                                    Color(red: 0.769, green: 0.165, blue: 0.192),
                                                    Color(red: 0.62, green: 0.114, blue: 0.141)],
                                           startPoint: .top, endPoint: .bottom))
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                .shadow(color: GameStyle.red.opacity(0.55), radius: 11)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("autopilotStop")
        }
        .padding(12)
    }

    private var map: some View {
        ZStack(alignment: .topLeading) {
            AutopilotMap(state: autopilot.map, plan: autopilot.roomFound ? plan : nil) { point in
                autopilot.tapMap(at: point)
            }
            Caps("Room")
                .padding(.leading, 10)
                .padding(.top, 8)
                .allowsHitTesting(false)
            if autopilot.usesRoom && !autopilot.roomFound {
                VStack(spacing: 8) {
                    Text("Finding your room. Point the camera at what you scanned, slowly.")
                        .font(GameStyle.face(12))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                    Button {
                        autopilot.skipRoom()
                    } label: {
                        Caps("Drive without the room", color: .white, size: 11)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .gamePanel(bar: GameStyle.mute)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !autopilot.roomFound {
                Text(rooms.room == nil ? "Scan the room (menu, Autopilot) to see it here."
                                       : "Scan the room again to see it here: this scan was saved without what the camera saw.")
                    .font(GameStyle.face(11))
                    .foregroundStyle(GameStyle.mute)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .gamePanel(bar: GameStyle.blue)
    }
}

/// A figure the camera measured, in the game's tile.
private struct ReadoutTile: View {
    let caption: String
    let value: String
    let unit: String
    let bar: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caps(caption)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(GameStyle.num(28))
                Caps(unit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 7, leading: 12, bottom: 9, trailing: 12))
        .foregroundStyle(Color.white)
        .gamePanel(bar: bar)
    }
}

/// The camera image, shown by ARKit's SceneKit view (nothing drawn in 3D: the overlay is SwiftUI's).
private struct ARCameraView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}
}

/// What the autopilot knows, drawn on the camera image: the trail, the route (green, red where it lets go), the flag,
/// the lock ring around the car (yellow while lost) and its heading.
private struct OverlayCanvas: View {
    let overlay: AutopilotSession.Overlay
    let toGo: Double?

    var body: some View {
        Canvas { context, _ in
            let count = max(overlay.trail.count, 1)
            for (i, p) in overlay.trail.enumerated() where i % 2 == 0 {
                let alpha = 0.12 + 0.6 * Double(i) / Double(count)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2.4, y: p.y - 2.4, width: 4.8, height: 4.8)), with: .color(.white.opacity(alpha)))
            }
            context.fill(polygon(overlay.route), with: .color(GameStyle.green.opacity(0.82)))
            context.fill(polygon(overlay.routeEnd), with: .color(GameStyle.red.opacity(0.85)))
            for arrow in overlay.arrows {
                var path = Path()
                path.addLines(arrow)
                context.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 1.6)
            }
            if !overlay.targetRing.isEmpty {
                let ring = polygon(overlay.targetRing)
                context.fill(ring, with: .color(.white.opacity(0.12)))
                context.stroke(ring, with: .color(.white), lineWidth: 2)
            }
            if let base = overlay.flagBase, let top = overlay.flagTop {
                var pole = Path()
                pole.move(to: base)
                pole.addLine(to: top)
                context.stroke(pole, with: .color(.white), lineWidth: 2.2)
                let width = max(overlay.flagWidth, 14)
                let side = width / 4
                let height = width * 0.66
                for a in 0..<4 {
                    for b in 0..<3 {
                        let cell = CGRect(x: top.x + CGFloat(a) * side, y: top.y + CGFloat(b) * height / 3,
                                          width: side + 0.3, height: height / 3 + 0.3)
                        context.fill(Path(cell), with: .color((a + b) % 2 == 0 ? .white : Color(white: 0.07)))
                    }
                }
                if let toGo {
                    let figure = context.resolve(Text(String(format: "%.1f", toGo)).font(GameStyle.num(17)).foregroundColor(.white))
                    let unit = context.resolve(Text("M").font(GameStyle.face(10)).foregroundColor(Color(white: 0.85)))
                    let fs = figure.measure(in: CGSize(width: 200, height: 60))
                    let us = unit.measure(in: CGSize(width: 200, height: 60))
                    let box = CGRect(x: top.x + width + 8, y: top.y - 2, width: 11 + fs.width + 3 + us.width + 8, height: max(fs.height, 20) + 4)
                    context.fill(Path(box), with: .color(Color(red: 0.04, green: 0.047, blue: 0.063).opacity(0.78)))
                    context.fill(Path(CGRect(x: box.minX, y: box.minY, width: 3, height: box.height)), with: .color(.white))
                    context.draw(figure, at: CGPoint(x: box.minX + 11, y: box.midY), anchor: .leading)
                    context.draw(unit, at: CGPoint(x: box.minX + 11 + fs.width + 3, y: box.midY + 2), anchor: .leading)
                }
            }
            if !overlay.ring.isEmpty {
                let ring = polygon(overlay.ring)
                let color = overlay.lost ? GameStyle.yellow : Color.white
                context.fill(ring, with: .color(color.opacity(0.07)))
                context.stroke(ring, with: .color(color), lineWidth: 2)
                for tick in overlay.ticks {
                    var path = Path()
                    path.addLines(tick)
                    context.stroke(path, with: .color(GameStyle.red), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                }
            }
            context.fill(polygon(overlay.chevron), with: .color(.white))
        }
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

/// The scanned room from above, turned so that the camera looks up the map (left and right as on the camera), with
/// what the camera sees (blue), the trail, the route, the flag and the car (a red dot). Without the room, the camera's
/// floor and a 50 cm grid. A tap sends the car there.
private struct AutopilotMap: View {
    let state: AutopilotSession.MapState
    let plan: Plan2D?
    let onTap: (CGPoint) -> Void

    var body: some View {
        GeometryReader { geo in
            let fit = MapFit(points: content, forward: state.forward, size: geo.size)
            Canvas { context, _ in
                guard let fit else { return }
                if let plan {
                    plan.drawShapes(in: &context, labels: false, lineScale: 0.5, at: fit.view)
                } else {
                    drawGrid(in: &context, fit: fit)
                }
                if state.view.count > 2 {
                    var view = Path()
                    view.addLines(state.view.map(fit.view))
                    view.closeSubpath()
                    context.fill(view, with: .color(GameStyle.blue.opacity(0.15)))
                    context.stroke(view, with: .color(GameStyle.blue.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
                if let camera = state.camera {
                    let c = fit.view(camera)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(GameStyle.blue))
                }
                if state.trail.count > 1 {
                    var trail = Path()
                    trail.addLines(state.trail.map(fit.view))
                    context.stroke(trail, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [1, 3]))
                }
                if state.route.count > 1 {
                    var route = Path()
                    route.addLines(state.route.map(fit.view))
                    context.stroke(route, with: .color(GameStyle.green), lineWidth: 2.6)
                }
                if let target = state.target {
                    let t = fit.view(target)
                    context.stroke(Path(ellipseIn: CGRect(x: t.x - 3.5, y: t.y - 3.5, width: 7, height: 7)), with: .color(.white), lineWidth: 1.2)
                    var pole = Path()
                    pole.move(to: t)
                    pole.addLine(to: CGPoint(x: t.x, y: t.y - 14))
                    context.stroke(pole, with: .color(.white), lineWidth: 1.4)
                    for a in 0..<4 {
                        for b in 0..<3 {
                            let cell = CGRect(x: t.x + CGFloat(a) * 3, y: t.y - 14 + CGFloat(b) * 3, width: 3, height: 3)
                            context.fill(Path(cell), with: .color((a + b) % 2 == 0 ? .white : Color(white: 0.07)))
                        }
                    }
                }
                if let car = state.car {
                    let c = fit.view(car)
                    let dot = Path(ellipseIn: CGRect(x: c.x - 5.5, y: c.y - 5.5, width: 11, height: 11))
                    context.fill(dot, with: .color(GameStyle.red))
                    context.stroke(dot, with: .color(.white), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                if let fit { onTap(fit.world(point)) }
            }
        }
    }

    /// What the map fits in its frame: the room if there is one, else the camera's floor and what is on it.
    private var content: [CGPoint] {
        var points = state.view
        if let camera = state.camera { points.append(camera) }
        if let plan {
            points += plan.points
        } else {
            points += state.trail
            if let car = state.car { points.append(car) }
            if let target = state.target { points.append(target) }
        }
        return points
    }

    private func drawGrid(in context: inout GraphicsContext, fit: MapFit) {
        let points = content
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return }
        let step: CGFloat = 0.5
        var x = (minX / step).rounded(.down) * step
        while x <= maxX {
            var line = Path()
            line.move(to: fit.view(CGPoint(x: x, y: minY)))
            line.addLine(to: fit.view(CGPoint(x: x, y: maxY)))
            context.stroke(line, with: .color(.white.opacity(0.08)), lineWidth: 1)
            x += step
        }
        var y = (minY / step).rounded(.down) * step
        while y <= maxY {
            var line = Path()
            line.move(to: fit.view(CGPoint(x: minX, y: y)))
            line.addLine(to: fit.view(CGPoint(x: maxX, y: y)))
            context.stroke(line, with: .color(.white.opacity(0.08)), lineWidth: 1)
            y += step
        }
    }
}

/// Floor metres (x, z) to the map's points and back: turned so that `forward` points up, scaled and centred to fit.
private struct MapFit {
    let angle: CGFloat
    let scale: CGFloat
    let center: CGPoint
    let middle: CGPoint

    init?(points: [CGPoint], forward: CGPoint, size: CGSize, margin: CGFloat = 18) {
        guard !points.isEmpty, size.width > 2 * margin, size.height > 2 * margin else { return nil }
        let angle = -.pi / 2 - atan2(forward.y, forward.x)
        let turned = points.map { MapFit.rotate($0, angle) }
        let xs = turned.map(\.x), ys = turned.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        self.angle = angle
        scale = min((size.width - 2 * margin) / max(maxX - minX, 0.5), (size.height - 2 * margin) / max(maxY - minY, 0.5))
        center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        middle = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    func view(_ p: CGPoint) -> CGPoint {
        let r = MapFit.rotate(p, angle)
        return CGPoint(x: middle.x + (r.x - center.x) * scale, y: middle.y + (r.y - center.y) * scale)
    }

    func world(_ v: CGPoint) -> CGPoint {
        let r = CGPoint(x: (v.x - middle.x) / scale + center.x, y: (v.y - middle.y) / scale + center.y)
        return MapFit.rotate(r, -angle)
    }

    static func rotate(_ p: CGPoint, _ a: CGFloat) -> CGPoint {
        CGPoint(x: p.x * cos(a) - p.y * sin(a), y: p.x * sin(a) + p.y * cos(a))
    }
}
