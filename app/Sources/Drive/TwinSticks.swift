import SwiftUI
import UIKit

/// The isometric game's floating twin sticks (its game/src/platform/touch.js and native Controls.swift, laid out like
/// ttweb's), made digital for the car: each stick jumps to where its thumb lands, the steering ring in the left 42 % of
/// the area and the gas/reverse slider in the right 42 % (swapped in Settings). Past 35 % of its travel a direction is
/// on, and the stick's edge on that side turns red. A lifted or cancelled touch lets go.
struct TwinSticks: UIViewRepresentable {
    let steerOnLeft: Bool
    let onSteer: (Int) -> Void
    let onThrottle: (Int) -> Void

    func makeUIView(context: Context) -> TwinSticksView {
        let view = TwinSticksView()
        view.steerOnLeft = steerOnLeft
        view.onSteer = onSteer
        view.onThrottle = onThrottle
        return view
    }

    func updateUIView(_ view: TwinSticksView, context: Context) {
        view.steerOnLeft = steerOnLeft
        view.onSteer = onSteer
        view.onThrottle = onThrottle
    }

    static func dismantleUIView(_ view: TwinSticksView, coordinator: ()) {
        view.releaseAll()
    }
}

final class TwinSticksView: UIView {
    var onSteer: ((Int) -> Void)?
    var onThrottle: ((Int) -> Void)?
    var steerOnLeft = true {
        didSet {
            if steerOnLeft != oldValue { releaseAll() }
        }
    }

    private struct Stick {
        let touch: UITouch
        let origin: CGPoint
        var at: CGPoint
    }

    /// The game's measures, in its units (points on an 844 x 390 screen, scaled up to 1.6 on bigger ones).
    private static let zone: CGFloat = 0.42
    private static let threshold: CGFloat = 0.35
    private static let steerTravel: CGFloat = 50
    private static let throttleTravel: CGFloat = 64

    private var steerStick: Stick?
    private var throttleStick: Stick?
    private var steer = 0
    private var throttle = 0
    private var unit: CGFloat = 1

    private let steerRing = UIView()
    private let throttleRing = UIView()
    private let steerKnob = UIView()
    private let throttleKnob = UIView()
    private let steerLabel = UILabel()
    private let throttleLabel = UILabel()
    private let steerMark = CAShapeLayer()
    private let throttleMark = CAShapeLayer()
    private let steerArc = CAShapeLayer()
    private let throttleArc = CAShapeLayer()
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        for ring in [steerRing, throttleRing] {
            ring.layer.borderWidth = 2
            ring.layer.borderColor = UIColor(white: 1, alpha: 0.35).cgColor
            ring.backgroundColor = UIColor(white: 1, alpha: 0.06)
            ring.isUserInteractionEnabled = false
            addSubview(ring)
        }
        for mark in [steerMark, throttleMark] {
            mark.fillColor = nil
            mark.strokeColor = UIColor(white: 1, alpha: 0.28).cgColor
            mark.lineWidth = 1.5
            mark.lineDashPattern = [3, 4]
        }
        for arc in [steerArc, throttleArc] {
            arc.fillColor = nil
            arc.strokeColor = UIColor(red: 0.93, green: 0.11, blue: 0.14, alpha: 1).cgColor
            arc.lineWidth = 5
            arc.lineCap = .round
        }
        steerRing.layer.addSublayer(steerMark)
        steerRing.layer.addSublayer(steerArc)
        throttleRing.layer.addSublayer(throttleMark)
        throttleRing.layer.addSublayer(throttleArc)
        for knob in [steerKnob, throttleKnob] {
            knob.frame = CGRect(x: 0, y: 0, width: 48, height: 48)
            knob.layer.cornerRadius = 24
            knob.backgroundColor = UIColor(white: 1, alpha: 0.45)
            knob.isHidden = true
            knob.isUserInteractionEnabled = false
            addSubview(knob)
        }
        for (label, text) in [(steerLabel, "STEER ◀ ▶"), (throttleLabel, "GAS ▲ / REVERSE ▼")] {
            label.attributedText = NSAttributedString(string: text, attributes: [
                .kern: 1.3,
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor(white: 1, alpha: 0.55),
            ])
            label.sizeToFit()
            label.isUserInteractionEnabled = false
            addSubview(label)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let screen = window?.bounds.size ?? bounds.size
        unit = min(max(min(screen.width / 844, screen.height / 390), 1), 1.6)
        steerRing.bounds = CGRect(x: 0, y: 0, width: 116 * unit, height: 116 * unit)
        steerRing.layer.cornerRadius = 58 * unit
        throttleRing.bounds = CGRect(x: 0, y: 0, width: 52 * unit, height: 180 * unit)
        throttleRing.layer.cornerRadius = 26 * unit
        drawMarks()
        let steerRest = rest(steering: true)
        let throttleRest = rest(steering: false)
        if steerStick == nil { steerRing.center = steerRest }
        if throttleStick == nil { throttleRing.center = throttleRest }
        steerLabel.center = CGPoint(x: steerRest.x, y: steerRest.y + 58 * unit + 16)
        throttleLabel.center = CGPoint(x: throttleRest.x, y: throttleRest.y + 90 * unit + 16)
    }

    /// Where a stick waits, low in its corner as in the game.
    private func rest(steering: Bool) -> CGPoint {
        let onLeft = steering == steerOnLeft
        let inset = (steering ? 70 : 38) * unit
        let x = onLeft ? bounds.minX + inset : bounds.maxX - inset
        let half = (steering ? 58 : 90) * unit
        let y = max(bounds.minY + half, bounds.maxY - (steering ? 90 : 118) * unit)
        return CGPoint(x: x, y: y)
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard bounds.width > 0 else { return }
        for touch in touches {
            let p = touch.location(in: self)
            let fx = (p.x - bounds.minX) / bounds.width
            let onLeft: Bool
            if fx < Self.zone {
                onLeft = true
            } else if fx > 1 - Self.zone {
                onLeft = false
            } else {
                continue
            }
            if onLeft == steerOnLeft {
                guard steerStick == nil else { continue }
                steerStick = Stick(touch: touch, origin: p, at: p)
                steerRing.center = p
                steerKnob.center = p
                steerKnob.isHidden = false
            } else {
                guard throttleStick == nil else { continue }
                throttleStick = Stick(touch: touch, origin: p, at: p)
                throttleRing.center = p
                throttleKnob.center = p
                throttleKnob.isHidden = false
            }
        }
        haptics.prepare()
        follow()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if steerStick?.touch === touch { steerStick?.at = touch.location(in: self) }
            if throttleStick?.touch === touch { throttleStick?.at = touch.location(in: self) }
        }
        follow()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lift(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lift(touches)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { releaseAll() }
    }

    func releaseAll() {
        steerStick = nil
        throttleStick = nil
        steerKnob.isHidden = true
        throttleKnob.isHidden = true
        setNeedsLayout()
        follow()
    }

    private func lift(_ touches: Set<UITouch>) {
        for touch in touches {
            if steerStick?.touch === touch {
                steerStick = nil
                steerKnob.isHidden = true
            }
            if throttleStick?.touch === touch {
                throttleStick = nil
                throttleKnob.isHidden = true
            }
        }
        setNeedsLayout()
        follow()
    }

    /// The knobs follow the thumbs, within their travel; the directions past the threshold go to the driver.
    private func follow() {
        var nextSteer = 0
        var nextThrottle = 0
        if let s = steerStick {
            let travel = Self.steerTravel * unit
            var dx = (s.at.x - s.origin.x) / travel
            var dy = (s.at.y - s.origin.y) / travel
            let m = hypot(dx, dy)
            if m > 1 {
                dx /= m
                dy /= m
            }
            steerKnob.center = CGPoint(x: s.origin.x + dx * travel, y: s.origin.y + dy * travel)
            if abs(dx) >= Self.threshold { nextSteer = dx < 0 ? -1 : 1 }
        }
        if let t = throttleStick {
            let travel = Self.throttleTravel * unit
            let dy = max(-1, min(1, (t.at.y - t.origin.y) / travel))
            throttleKnob.center = CGPoint(x: t.origin.x, y: t.origin.y + dy * travel)
            if abs(dy) >= Self.threshold { nextThrottle = dy < 0 ? 1 : -1 }
        }
        var changed = false
        if nextSteer != steer {
            steer = nextSteer
            changed = true
            if steer != 0 { haptics.impactOccurred() }
            onSteer?(steer)
        }
        if nextThrottle != throttle {
            throttle = nextThrottle
            changed = true
            if throttle != 0 { haptics.impactOccurred() }
            onThrottle?(throttle)
        }
        if changed { drawArcs() }
    }

    // MARK: Drawing

    /// The dashed threshold: a circle inside the ring, two ticks across the slider.
    private func drawMarks() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let sb = steerRing.bounds
        let r = Self.threshold * Self.steerTravel * unit
        steerMark.path = UIBezierPath(ovalIn: CGRect(x: sb.midX - r, y: sb.midY - r, width: 2 * r, height: 2 * r)).cgPath
        let tb = throttleRing.bounds
        let d = Self.threshold * Self.throttleTravel * unit
        let ticks = UIBezierPath()
        for y in [tb.midY - d, tb.midY + d] {
            ticks.move(to: CGPoint(x: tb.minX + 12, y: y))
            ticks.addLine(to: CGPoint(x: tb.maxX - 12, y: y))
        }
        throttleMark.path = ticks.cgPath
        CATransaction.commit()
        drawArcs()
    }

    /// Red on the side that is on: the ring's left or right edge, a cap over or under the slider.
    private func drawArcs() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let sb = steerRing.bounds
        if steer == 0 {
            steerArc.path = nil
        } else {
            let mid: CGFloat = steer < 0 ? .pi : 0
            steerArc.path = UIBezierPath(arcCenter: CGPoint(x: sb.midX, y: sb.midY), radius: sb.width / 2 - 6,
                                         startAngle: mid - 0.6, endAngle: mid + 0.6, clockwise: true).cgPath
        }
        let tb = throttleRing.bounds
        if throttle == 0 {
            throttleArc.path = nil
        } else {
            let up = throttle > 0
            let center = CGPoint(x: tb.midX, y: up ? tb.minY + tb.width / 2 : tb.maxY - tb.width / 2)
            let start: CGFloat = up ? .pi + 0.5 : 0.5
            let end: CGFloat = up ? 2 * .pi - 0.5 : .pi - 0.5
            throttleArc.path = UIBezierPath(arcCenter: center, radius: tb.width / 2 + 7,
                                            startAngle: start, endAngle: end, clockwise: true).cgPath
        }
        CATransaction.commit()
    }
}
