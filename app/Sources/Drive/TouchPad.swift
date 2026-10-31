import SwiftUI
import UIKit

/// A transparent touch surface in UIKit, so each thumb is tracked on its own and a cancelled touch (a system gesture,
/// a call, Control Center) always lets go: -1/0/+1 along an axis, or 1 while held.
struct TouchPad: UIViewRepresentable {
    enum Mode {
        /// left half -1, right half +1
        case horizontal
        /// top half +1, bottom half -1
        case vertical
        /// 1 while touched
        case hold
    }

    let mode: Mode
    let onChange: (Int) -> Void

    func makeUIView(context: Context) -> TouchPadView {
        let view = TouchPadView()
        view.mode = mode
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: TouchPadView, context: Context) {
        view.mode = mode
        view.onChange = onChange
    }

    static func dismantleUIView(_ view: TouchPadView, coordinator: ()) {
        view.release()
    }
}

final class TouchPadView: UIView {
    var mode: TouchPad.Mode = .hold
    var onChange: ((Int) -> Void)?
    /// The share of the pad around its middle that counts as neither side.
    var deadZone: CGFloat = 0.08

    private var touch: UITouch?
    private var value = 0
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touch == nil, let first = touches.first else { return }
        touch = first
        haptics.prepare()
        follow(first)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch, touches.contains(touch) else { return }
        follow(touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch, touches.contains(touch) else { return }
        release()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch, touches.contains(touch) else { return }
        release()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { release() }
    }

    func release() {
        touch = nil
        set(0)
    }

    private func follow(_ touch: UITouch) {
        let p = touch.location(in: self)
        guard bounds.width > 0, bounds.height > 0 else { return }
        switch mode {
        case .hold:
            set(1)
        case .horizontal:
            let x = p.x / bounds.width - 0.5
            set(abs(x) < deadZone ? 0 : (x < 0 ? -1 : 1))
        case .vertical:
            let y = 0.5 - p.y / bounds.height
            set(abs(y) < deadZone ? 0 : (y > 0 ? 1 : -1))
        }
    }

    private func set(_ next: Int) {
        guard next != value else { return }
        value = next
        if next != 0 { haptics.impactOccurred() }
        onChange?(next)
    }
}
