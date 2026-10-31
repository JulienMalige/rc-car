import SwiftUI
import RoomPlan
import simd

/// The scanned room from above, in the app's line style (as the icon and TV Scores' court): the walls in thick white,
/// doors in blue, windows in light blue, openings dashed, furniture as outlined boxes with their names, and the room's
/// size in metres.
struct RoomPlanView: View {
    let room: CapturedRoom

    var body: some View {
        let plan = Plan2D(room)
        VStack(spacing: 10) {
            Canvas { context, size in
                plan.draw(in: &context, size: size)
            }
            .background(Theme.background)
            HStack(spacing: 6) {
                PlanFigure(label: "Width", value: plan.bounds.width)
                PlanFigure(label: "Depth", value: plan.bounds.height)
                PlanCount(label: "Walls", count: plan.walls.count)
                PlanCount(label: "Objects", count: plan.boxes.count)
            }
            .foregroundStyle(Color.white)
            .padding(.bottom, 8)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Room plan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlanFigure: View {
    let label: String
    let value: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caps(label)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.1f", Double(value))).font(GameStyle.num(22))
                Caps("m")
            }
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 9, trailing: 12))
        .gamePanel(bar: GameStyle.blue)
    }
}

private struct PlanCount: View {
    let label: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caps(label)
            Text("\(count)").font(GameStyle.num(22))
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 9, trailing: 12))
        .gamePanel(bar: GameStyle.light)
    }
}

/// The room flattened onto the floor, in metres: x across, z (RoomPlan's depth) down the screen.
struct Plan2D {
    struct Segment {
        var a: CGPoint
        var b: CGPoint
    }

    struct Box {
        var corners: [CGPoint]
        var center: CGPoint
        var label: String
    }

    var walls: [Segment]
    var doors: [Segment]
    var windows: [Segment]
    var openings: [Segment]
    var boxes: [Box]
    var bounds: CGRect

    init(_ room: CapturedRoom) {
        walls = room.walls.map(Plan2D.segment)
        doors = room.doors.map(Plan2D.segment)
        windows = room.windows.map(Plan2D.segment)
        openings = room.openings.map(Plan2D.segment)
        boxes = room.objects.map(Plan2D.box)
        var points: [CGPoint] = []
        for s in walls + doors + windows + openings { points += [s.a, s.b] }
        for b in boxes { points += b.corners }
        if let first = points.first {
            var rect = CGRect(origin: first, size: .zero)
            for p in points.dropFirst() { rect = rect.union(CGRect(origin: p, size: .zero)) }
            bounds = rect
        } else {
            bounds = .zero
        }
    }

    private static func flat(_ v: SIMD4<Float>) -> SIMD2<Float> {
        let f = SIMD2<Float>(v.x, v.z)
        let length = simd_length(f)
        return length > 0 ? f / length : SIMD2<Float>(1, 0)
    }

    private static func point(_ v: SIMD2<Float>) -> CGPoint {
        CGPoint(x: CGFloat(v.x), y: CGFloat(v.y))
    }

    /// A wall, door, window or opening: a segment as wide as the surface, along its own x axis.
    static func segment(_ surface: CapturedRoom.Surface) -> Segment {
        let t = surface.transform
        let center = SIMD2<Float>(t.columns.3.x, t.columns.3.z)
        let half = flat(t.columns.0) * (surface.dimensions.x / 2)
        return Segment(a: point(center - half), b: point(center + half))
    }

    /// A piece of furniture: its footprint, width along its x axis, depth along its z axis.
    static func box(_ object: CapturedRoom.Object) -> Box {
        let t = object.transform
        let center = SIMD2<Float>(t.columns.3.x, t.columns.3.z)
        let right = flat(t.columns.0) * (object.dimensions.x / 2)
        let forward = flat(t.columns.2) * (object.dimensions.z / 2)
        let corners: [SIMD2<Float>] = [center - right - forward, center + right - forward, center + right + forward, center - right + forward]
        return Box(corners: corners.map(point), center: point(center), label: String(describing: object.category))
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        guard bounds.width > 0 || bounds.height > 0 else {
            context.draw(Text("Nothing was found in this scan.").foregroundColor(.gray), at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }
        let margin: CGFloat = 28
        let scale = min((size.width - 2 * margin) / max(bounds.width, 0.5), (size.height - 2 * margin) / max(bounds.height, 0.5))
        let ox = (size.width - bounds.width * scale) / 2 - bounds.minX * scale
        let oy = (size.height - bounds.height * scale) / 2 - bounds.minY * scale
        func at(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * scale + ox, y: p.y * scale + oy)
        }
        func line(_ s: Segment) -> Path {
            var path = Path()
            path.move(to: at(s.a))
            path.addLine(to: at(s.b))
            return path
        }

        for box in boxes {
            var path = Path()
            path.addLines(box.corners.map(at))
            path.closeSubpath()
            context.fill(path, with: .color(Color.white.opacity(0.08)))
            context.stroke(path, with: .color(Color.white.opacity(0.5)), lineWidth: 1.5)
            context.draw(Text(box.label.uppercased()).font(GameStyle.face(9)).foregroundColor(GameStyle.mute), at: at(box.center))
        }
        for wall in walls {
            context.stroke(line(wall), with: .color(.white), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        for opening in openings {
            context.stroke(line(opening), with: .color(Color(white: 0.16)), style: StrokeStyle(lineWidth: 7))
            context.stroke(line(opening), with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
        }
        for window in windows {
            context.stroke(line(window), with: .color(Color(red: 0.6, green: 0.85, blue: 1)), style: StrokeStyle(lineWidth: 3))
        }
        for door in doors {
            context.stroke(line(door), with: .color(GameStyle.blue), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }
    }
}
