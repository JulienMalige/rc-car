import ARKit
import CarKit
import simd
import SwiftUI
import UIKit

/// Autopilot step 2, "drive to a point" (Julien's pick of 2026-11-01, mock-up 2). The camera finds the car once it is
/// tapped and follows it frame after frame by its colour (CarKit's BlobTracker); ARKit's floor plane turns where it is in
/// the image into metres on the floor; GoToPoint steers it to a point tapped on the floor or on the map. When the room
/// was scanned with its world map, ARKit first finds the phone's place in it, and the map shows the room.
///
/// Coordinates: CarKit works on the floor counter-clockwise from above, (x, -z) of ARKit's world; the map draws (x, z)
/// as RoomPlan's plan does.
final class AutopilotSession: NSObject, ObservableObject, ARSessionDelegate {
    enum Status: Equatable {
        case starting
        /// Relocalizing into the scanned room.
        case findingRoom
        case noFloor
        case tapCar
        /// The tap did not stand out from the floor.
        case notCar
        case tapTarget
        /// A point to go to, but no car connected.
        case noCar
        case probing
        case driving
        case reversing
        case arrived
        /// The camera lost the car.
        case lost
        case stuck
    }

    /// What the camera view draws over the image, in its own points.
    struct Overlay {
        var ring: [CGPoint] = []
        var ticks: [[CGPoint]] = []
        var chevron: [CGPoint] = []
        var lost = false
        var trail: [CGPoint] = []
        var route: [CGPoint] = []
        var routeEnd: [CGPoint] = []
        var arrows: [[CGPoint]] = []
        var targetRing: [CGPoint] = []
        var flagBase: CGPoint?
        var flagTop: CGPoint?
        var flagWidth: CGFloat = 0
    }

    /// What the map draws, in metres on the floor as RoomPlan's plan has them: (x, z).
    struct MapState {
        var camera: CGPoint?
        /// Where the camera looks, a unit vector.
        var forward = CGPoint(x: 0, y: -1)
        /// The floor the camera sees.
        var view: [CGPoint] = []
        var trail: [CGPoint] = []
        var car: CGPoint?
        var target: CGPoint?
        var route: [CGPoint] = []
    }

    @Published private(set) var status = Status.starting
    @Published private(set) var overlay = Overlay()
    @Published private(set) var map = MapState()
    /// Metres per second, as the camera measures it.
    @Published private(set) var speed: Double?
    /// Metres to the point.
    @Published private(set) var toGo: Double?
    /// Started from the scan's world map: the room can show on the map once found.
    @Published private(set) var usesRoom = false
    @Published private(set) var roomFound = false

    let session = ARSession()
    /// The camera view's size in points, set by the view.
    var viewport = CGSize(width: 1, height: 1)

    /// The SF-25: 13.7 cm long, the middle of its body about 1.5 cm above the floor.
    private let carLength = 0.137
    private let carMiddle: Float = 0.015

    private weak var driver: Driver?
    private weak var link: LinkStore?
    private weak var log: LogStore?
    private var tracker: BlobTracker?
    private var estimator = CarEstimator()
    private var pilot = GoToPoint()
    /// Where the car was last seen, chroma pixels.
    private var lastFix: SIMD2<Double>?
    /// How much of the car showed when it was locked, and how far it was.
    private var refMass = 0.0
    private var refDepth = 1.0
    private var lostSince: Double?
    private var notCarUntil = 0.0
    private var trail: [(t: Double, p: SIMD2<Double>)] = []
    private var floorY: Float?
    private var pendingTap: CGPoint?
    private var pendingTarget: SIMD2<Double>?
    private var lastPublish = 0.0
    private var lastLog = 0.0
    private var frames = 0
    private var direction = 1
    private var running = false
    private var io = UIInterfaceOrientation.landscapeRight

    func attach(driver: Driver, link: LinkStore, log: LogStore) {
        self.driver = driver
        self.link = link
        self.log = log
    }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported, !running else { return }
        running = true
        session.delegate = self
        pilot.settings.cruise = Prefs.autopilotPace
        run(withRoom: RoomStore.shared.hasWorldMap)
    }

    func stop() {
        guard running else { return }
        running = false
        halt()
        session.pause()
        log?.add(.info, "Autopilot: camera off")
    }

    /// STOP: no point to go to any more, wheels stopped; the car stays locked.
    func halt() {
        pilot.halt()
        driver?.stop()
    }

    /// Without the scan's world map: when the room cannot be found from here, or not worth waiting for.
    func skipRoom() {
        guard usesRoom else { return }
        run(withRoom: false)
    }

    /// A tap on the camera view: the car when none is locked (or it was lost), else the point to go to.
    func tap(at point: CGPoint) {
        pendingTap = point
    }

    /// A tap on the map, (x, z) metres.
    func tapMap(at point: CGPoint) {
        pendingTarget = SIMD2(Double(point.x), -Double(point.y))
    }

    private func run(withRoom: Bool) {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        let worldMap = withRoom ? RoomStore.shared.loadWorldMap() : nil
        config.initialWorldMap = worldMap
        usesRoom = worldMap != nil
        roomFound = false
        floorY = nil
        forgetPosition()
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        log?.add(.info, usesRoom ? "Autopilot: camera on, looking for the scanned room" : "Autopilot: camera on")
    }

    /// The world's coordinates changed (a new run, the room found): what was known in metres is gone; the car's colours
    /// and its place in the image stay.
    private func forgetPosition() {
        estimator.reset()
        trail = []
        lostSince = nil
        pilot.halt()
        driver?.stop()
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running else { return }
        frames += 1
        let time = frame.timestamp
        io = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation ?? .landscapeRight
        updateFloor(frame)
        if let tap = pendingTap {
            pendingTap = nil
            handleTap(tap, frame)
        }
        if let target = pendingTarget {
            pendingTarget = nil
            go(to: target, time: time)
        }
        follow(frame)
        drive(time)
        refreshStatus(time)
        if time - lastPublish >= 1.0 / 30 {
            lastPublish = time
            publish(frame)
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        guard case .normal = camera.trackingState, usesRoom, !roomFound else { return }
        roomFound = true
        forgetPosition()
        log?.add(.info, "Autopilot: found the scanned room")
    }

    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        true
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        log?.add(.error, "Autopilot: the camera stopped: \(error.localizedDescription)")
        halt()
    }

    func sessionWasInterrupted(_ session: ARSession) {
        halt()
    }

    // MARK: Floor and geometry

    /// The floor's height: ARKit's planes classified as floor (the lowest), else the lowest horizontal plane at least
    /// 20 cm under the phone.
    private func updateFloor(_ frame: ARFrame) {
        let cameraY = frame.camera.transform.columns.3.y
        var best: Float?
        var classified = false
        for case let plane as ARPlaneAnchor in frame.anchors where plane.alignment == .horizontal {
            let y = plane.transform.columns.3.y
            guard y < cameraY - 0.2 else { continue }
            var isFloor = false
            if case .floor = plane.classification { isFloor = true }
            if isFloor && !classified {
                classified = true
                best = y
            } else if isFloor == classified {
                best = min(best ?? y, y)
            }
        }
        if let best { floorY = best }
    }

    private func floorPoint(_ w: SIMD3<Float>) -> SIMD2<Double> {
        SIMD2(Double(w.x), -Double(w.z))
    }

    private func world(_ f: SIMD2<Double>, height: Float) -> SIMD3<Float> {
        SIMD3(Float(f.x), height, Float(-f.y))
    }

    private func plan(_ f: SIMD2<Double>) -> CGPoint {
        CGPoint(x: f.x, y: -f.y)
    }

    /// A world point in the camera's frame (metres; the camera looks along -z).
    private func cameraSpace(_ w: SIMD3<Float>, _ frame: ARFrame) -> SIMD3<Float> {
        let p = simd_mul(simd_inverse(frame.camera.transform), SIMD4<Float>(w.x, w.y, w.z, 1))
        return SIMD3(p.x, p.y, p.z)
    }

    /// Where a world point is in the captured image, in pixels (landscape, as the sensor gives it); nil behind.
    private func pixel(_ w: SIMD3<Float>, _ frame: ARFrame) -> SIMD2<Double>? {
        let c = cameraSpace(w, frame)
        guard c.z < -0.05 else { return nil }
        let k = frame.camera.intrinsics
        let depth = -c.z
        return SIMD2(Double(k[2][0] + k[0][0] * c.x / depth), Double(k[2][1] - k[1][1] * c.y / depth))
    }

    /// The world direction of the ray through an image pixel.
    private func ray(_ p: SIMD2<Double>, _ frame: ARFrame) -> SIMD3<Float> {
        let k = frame.camera.intrinsics
        let d = SIMD4<Float>((Float(p.x) - k[2][0]) / k[0][0], -(Float(p.y) - k[2][1]) / k[1][1], -1, 0)
        let w = simd_mul(frame.camera.transform, d)
        return SIMD3(w.x, w.y, w.z)
    }

    /// Where the ray through an image pixel meets the level `height`; nil above the horizon.
    private func ground(_ p: SIMD2<Double>, _ frame: ARFrame, height: Float) -> SIMD3<Float>? {
        let dir = ray(p, frame)
        let t = frame.camera.transform
        let origin = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        guard dir.y < -1e-4 else { return nil }
        let s = (height - origin.y) / dir.y
        guard s > 0 else { return nil }
        return origin + dir * s
    }

    /// The image pixel under a point of the camera view.
    private func pixel(view p: CGPoint, _ frame: ARFrame) -> SIMD2<Double> {
        let toView = frame.displayTransform(for: io, viewportSize: viewport)
        let n = CGPoint(x: p.x / viewport.width, y: p.y / viewport.height).applying(toView.inverted())
        let size = frame.camera.imageResolution
        return SIMD2(Double(n.x * size.width), Double(n.y * size.height))
    }

    /// Where a world point shows in the camera view, in points; nil behind the camera.
    private func viewPoint(_ w: SIMD3<Float>, _ frame: ARFrame) -> CGPoint? {
        guard cameraSpace(w, frame).z < -0.05 else { return nil }
        return frame.camera.projectPoint(w, orientation: io, viewportSize: viewport)
    }

    /// How long the car looks at `depth` metres, in chroma pixels (half the image's).
    private func carPixels(depth: Double, _ frame: ARFrame) -> Double {
        Double(frame.camera.intrinsics[0][0]) * carLength / max(depth, 0.1) / 2
    }

    private func withChroma(_ frame: ARFrame, _ body: (ChromaImage) -> Void) {
        let buffer = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(buffer) >= 2 else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { return }
        body(ChromaImage(width: CVPixelBufferGetWidthOfPlane(buffer, 1), height: CVPixelBufferGetHeightOfPlane(buffer, 1),
                         bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(buffer, 1),
                         base: UnsafePointer(base.assumingMemoryBound(to: UInt8.self))))
    }

    // MARK: Taps, tracking, driving

    private var waitingForRoom: Bool { usesRoom && !roomFound }

    private func handleTap(_ point: CGPoint, _ frame: ARFrame) {
        guard !waitingForRoom, let floorY else { return }
        let px = pixel(view: point, frame)
        let following = tracker != nil && lostSince == nil
        if following, let car = estimator.estimate,
           let onScreen = viewPoint(world(car.position, height: floorY + carMiddle), frame),
           hypot(onScreen.x - point.x, onScreen.y - point.y) > 44 {
            if let hit = ground(px, frame, height: floorY) { go(to: floorPoint(hit), time: frame.timestamp) }
            return
        }
        lock(at: px, frame)
    }

    private func lock(at px: SIMD2<Double>, _ frame: ARFrame) {
        guard let floorY, let hit = ground(px, frame, height: floorY + carMiddle) else { return }
        let depth = Double(-cameraSpace(hit, frame).z)
        let length = carPixels(depth: depth, frame)
        var locked: (tracker: BlobTracker, fix: BlobFix)?
        withChroma(frame) { image in
            locked = BlobTracker.lock(image, at: px / 2, carLength: length)
        }
        guard let locked else {
            notCarUntil = frame.timestamp + 3
            log?.add(.info, String(format: "Autopilot: no car there (%.2f m away, %.0f px long expected)", depth, length))
            return
        }
        tracker = locked.tracker
        lastFix = locked.fix.center
        refMass = locked.fix.mass
        refDepth = depth
        notCarUntil = 0
        forgetPosition()
        log?.add(.info, String(format: "Autopilot: locked on the car %.2f m away, %.0f px long", depth, length))
    }

    private func go(to point: SIMD2<Double>, time: Double) {
        guard tracker != nil, !waitingForRoom else { return }
        pilot.settings.cruise = Prefs.autopilotPace
        pilot.go(to: point, time: time)
        let away = estimator.estimate.map { floorLength(point - $0.position) } ?? -1
        log?.add(.info, String(format: "Autopilot: go to (%.2f, %.2f), %.2f m away", point.x, point.y, away))
    }

    /// Finds the car in this frame: from where it should be (its last position and speed), else, every third frame,
    /// anywhere near (or, after 2 s, anywhere in the image).
    private func follow(_ frame: ARFrame) {
        guard let tracker, let floorY else { return }
        let time = frame.timestamp
        let height = floorY + carMiddle
        var start = lastFix
        var depth = refDepth
        if let p = estimator.predicted(at: time) {
            let w = world(p, height: height)
            if let px = pixel(w, frame) { start = px / 2 }
            depth = Double(-cameraSpace(w, frame).z)
        }
        guard let from = start, depth > 0.1 else { return }
        let length = carPixels(depth: depth, frame)
        let expected = refMass * (refDepth / depth) * (refDepth / depth)
        let lostFor = lostSince.map { time - $0 } ?? 0
        let lookAround = frames % 3 == 0
        var fix: BlobFix?
        withChroma(frame) { image in
            if let f = tracker.track(image, from: from, radius: 0.6 * length), f.mass > 0.25 * expected {
                fix = f
            } else if lookAround,
                      let spot = tracker.search(image, around: from, reach: lostFor < 2 ? 6 * length : nil, radius: 0.5 * length),
                      spot.mass > 0.35 * expected,
                      let f = tracker.track(image, from: spot.point, radius: 0.6 * length), f.mass > 0.25 * expected {
                fix = f
            }
        }
        guard let fix else {
            if lostSince == nil {
                lostSince = time
                log?.add(.info, "Autopilot: lost sight of the car")
            }
            return
        }
        if let since = lostSince, time - since > 0.15 { log?.add(.info, "Autopilot: found the car again") }
        lostSince = nil
        lastFix = fix.center
        guard let hit = ground(fix.center * 2, frame, height: height) else { return }
        var axis: Double?
        if fix.elongation > 1.5 {
            let d = SIMD2(cos(fix.axis), sin(fix.axis)) * (0.4 * length)
            if let a = ground((fix.center - d) * 2, frame, height: height), let b = ground((fix.center + d) * 2, frame, height: height) {
                let fa = floorPoint(a), fb = floorPoint(b)
                axis = atan2(fb.y - fa.y, fb.x - fa.x)
            }
        }
        estimator.update(position: floorPoint(hit), axis: axis, direction: direction, time: time)
        if let p = estimator.estimate?.position {
            trail.append((time, p))
            trail.removeAll { time - $0.t > 2.5 }
        }
    }

    private func drive(_ time: Double) {
        guard pilot.target != nil else { return }
        guard link?.state == .ready else {
            driver?.stop()
            return
        }
        let tracked = tracker != nil && (lostSince.map { time - $0 < 0.15 } ?? true)
        let command = pilot.step(estimator.estimate, tracked: tracked, time: time)
        if command.throttle != 0 { direction = command.throttle }
        driver?.update {
            $0.throttle = command.throttle
            $0.steering = command.steering
            $0.spin = false
            $0.turbo = false
        }
        switch pilot.phase {
        case .arrived, .stuck:
            log?.add(.info, "Autopilot: \(pilot.phase.rawValue)")
        default:
            break
        }
        if time - lastLog >= 0.2, let e = estimator.estimate {
            lastLog = time
            let heading = e.heading.map { String(format: "%.0f", $0 * 180 / .pi) } ?? "?"
            let away = pilot.target.map { floorLength($0 - e.position) } ?? 0
            log?.add(.info, String(format: "Autopilot: at %.2f %.2f, %.2f m/s, heading %@, %.2f m to go, %@, throttle %ld steering %ld",
                                   e.position.x, e.position.y, e.speed, heading, away, pilot.phase.rawValue,
                                   command.throttle, command.steering))
        }
    }

    private func refreshStatus(_ time: Double) {
        let next: Status
        if waitingForRoom {
            next = .findingRoom
        } else if floorY == nil {
            next = .noFloor
        } else if tracker == nil {
            next = time < notCarUntil ? .notCar : .tapCar
        } else if pilot.target != nil {
            if link?.state != .ready {
                next = .noCar
            } else {
                switch pilot.phase {
                case .probing: next = .probing
                case .reversing: next = .reversing
                case .lost: next = .lost
                default: next = .driving
                }
            }
        } else if let since = lostSince, time - since > 0.3 {
            next = .lost
        } else if time < notCarUntil {
            next = .notCar
        } else {
            switch pilot.phase {
            case .arrived: next = .arrived
            case .stuck: next = .stuck
            default: next = .tapTarget
            }
        }
        if next != status { status = next }
    }

    // MARK: What the views draw

    private func publish(_ frame: ARFrame) {
        let tracked = tracker != nil && lostSince == nil
        let estimate = tracked ? estimator.estimate : nil
        let newSpeed = estimate.map { $0.speed }
        if newSpeed != speed { speed = newSpeed }
        let newToGo: Double? = pilot.target.flatMap { target in estimator.estimate.map { floorLength(target - $0.position) } }
        if newToGo != toGo { toGo = newToGo }
        overlay = makeOverlay(frame)
        map = makeMap(frame)
    }

    private func circle(_ c: SIMD2<Double>, _ r: Double, _ n: Int = 40) -> [SIMD2<Double>] {
        (0..<n).map { i in
            let a = Double(i) / Double(n) * 2 * .pi
            return c + SIMD2(cos(a), sin(a)) * r
        }
    }

    /// From the car's nose to the point, leaving along its heading: a curve as the car will roughly drive it.
    private func route(from car: CarEstimate, to target: SIMD2<Double>) -> [SIMD2<Double>] {
        guard let h = car.heading else { return [car.position, target] }
        let f = SIMD2(cos(h), sin(h))
        let start = car.position + f * 0.085
        let control = start + f * (0.45 * floorLength(target - start))
        return (0...30).map { i in
            let t = Double(i) / 30, u = 1 - t
            return start * (u * u) + control * (2 * u * t) + target * (t * t)
        }
    }

    private func makeOverlay(_ frame: ARFrame) -> Overlay {
        var o = Overlay()
        guard let floorY else { return o }
        func v(_ f: SIMD2<Double>, _ h: Float = 0) -> CGPoint? {
            viewPoint(world(f, height: floorY + h), frame)
        }
        if let car = estimator.estimate, tracker != nil {
            let c = car.position
            o.lost = lostSince != nil
            o.ring = circle(c, 0.115).compactMap { v($0) }
            o.ticks = (0..<4).compactMap { k -> [CGPoint]? in
                let a = Double(k) * .pi / 2 + .pi / 4
                let u = SIMD2(cos(a), sin(a))
                guard let p = v(c + u * 0.115), let q = v(c + u * 0.155) else { return nil }
                return [p, q]
            }
            if let h = car.heading, !o.lost {
                let f = SIMD2(cos(h), sin(h)), l = SIMD2(-sin(h), cos(h))
                o.chevron = [c + f * 0.15 + l * 0.03, c + f * 0.185, c + f * 0.15 - l * 0.03, c + f * 0.163].compactMap { v($0) }
            }
            o.trail = trail.compactMap { v($0.p) }
            if let target = pilot.target {
                let path = route(from: car, to: target)
                var lengths = [0.0]
                for i in 1..<path.count { lengths.append(lengths[i - 1] + floorLength(path[i] - path[i - 1])) }
                let total = lengths.last ?? 0
                o.route = ribbon(path, lengths, 0, total - 0.24, v)
                o.routeEnd = ribbon(path, lengths, max(0, total - 0.26), total, v)
                var d = 0.12
                while d < total - 0.1 {
                    if let i = lengths.firstIndex(where: { $0 >= d }) {
                        let a = path[max(i - 1, 0)], b = path[min(i + 1, path.count - 1)]
                        let n = floorLength(b - a)
                        if n > 0 {
                            let u = (b - a) / n, side = SIMD2(-u.y, u.x)
                            let p = path[i]
                            let arrow = [p - u * 0.01 + side * 0.016, p + u * 0.006, p - u * 0.01 - side * 0.016].compactMap { v($0) }
                            if arrow.count == 3 { o.arrows.append(arrow) }
                        }
                    }
                    d += 0.14
                }
            }
        }
        if let target = pilot.target {
            o.targetRing = circle(target, 0.1).compactMap { v($0) }
            o.flagBase = v(target)
            o.flagTop = v(target, 0.24)
            let right = frame.camera.transform.columns.0
            let side = SIMD3<Float>(right.x, 0, right.z)
            let sideLength = simd_length(side)
            if let top = o.flagTop, sideLength > 0.1,
               let edge = viewPoint(world(target, height: floorY + 0.24) + side / sideLength * 0.1, frame) {
                o.flagWidth = hypot(edge.x - top.x, edge.y - top.y)
            }
        }
        return o
    }

    /// A band 5.6 cm wide along `path` between two distances, as the camera sees it.
    private func ribbon(_ path: [SIMD2<Double>], _ lengths: [Double], _ from: Double, _ to: Double,
                        _ v: (SIMD2<Double>, Float) -> CGPoint?) -> [CGPoint] {
        guard to > from else { return [] }
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in path.indices where lengths[i] >= from && lengths[i] <= to {
            let a = path[max(i - 1, 0)], b = path[min(i + 1, path.count - 1)]
            let n = floorLength(b - a)
            guard n > 0 else { continue }
            let side = SIMD2(-(b - a).y, (b - a).x) / n * 0.028
            guard let l = v(path[i] + side, 0), let r = v(path[i] - side, 0) else { continue }
            left.append(l)
            right.append(r)
        }
        return left.count > 1 ? left + right.reversed() : []
    }

    private func makeMap(_ frame: ARFrame) -> MapState {
        var m = MapState()
        let t = frame.camera.transform
        let camera = SIMD2<Double>(Double(t.columns.3.x), Double(t.columns.3.z))
        m.camera = CGPoint(x: camera.x, y: camera.y)
        let forward = SIMD2<Double>(Double(-t.columns.2.x), Double(-t.columns.2.z))
        let fl = floorLength(forward)
        if fl > 0.1 { m.forward = CGPoint(x: forward.x / fl, y: forward.y / fl) }
        if let floorY {
            let corners = [CGPoint(x: 0, y: viewport.height), CGPoint(x: viewport.width, y: viewport.height),
                           CGPoint(x: viewport.width, y: 0), CGPoint(x: 0, y: 0)]
            m.view = corners.map { corner in
                let px = pixel(view: corner, frame)
                let reach = 4.0
                if let hit = ground(px, frame, height: floorY) {
                    let d = SIMD2<Double>(Double(hit.x), Double(hit.z)) - camera
                    let n = floorLength(d)
                    let p = n > reach ? camera + d / n * reach : camera + d
                    return CGPoint(x: p.x, y: p.y)
                }
                // above the horizon: as far as `reach` that way
                let r = ray(px, frame)
                var d = SIMD2<Double>(Double(r.x), Double(r.z))
                let n = floorLength(d)
                d = n > 1e-6 ? d / n : SIMD2(forward.x, forward.y) / max(fl, 1e-6)
                let p = camera + d * reach
                return CGPoint(x: p.x, y: p.y)
            }
        }
        if tracker != nil {
            m.trail = trail.map { plan($0.p) }
            m.car = estimator.estimate.map { plan($0.position) }
            if let target = pilot.target, let car = estimator.estimate {
                m.route = route(from: car, to: target).map(plan)
            }
        }
        m.target = pilot.target.map(plan)
        return m
    }
}
