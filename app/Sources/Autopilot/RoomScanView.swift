import ARKit
import SwiftUI
import UIKit
import RoomPlan

/// RoomPlan's scanner, full screen: walk slowly around the room, phone up, until the walls are outlined; Done ends the
/// scan and RoomPlan shows its model; Save keeps the room as the autopilot's map, with what the camera saw (the world
/// map) so the autopilot can find its place in the room again.
struct RoomScanView: View {
    @ObservedObject private var rooms = RoomStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.scanning
    @State private var result: CapturedRoom?
    @State private var worldMap: ARWorldMap?
    @State private var stopRequests = 0

    enum Phase {
        case scanning, processing, done
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoomCaptureContainer(stopRequests: stopRequests) { room, map in
                result = room
                worldMap = map
                phase = .done
            }
            .ignoresSafeArea()
            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    ScanButtonLabel(title: "Cancel", symbol: "xmark", fill: nil)
                }
                switch phase {
                case .scanning:
                    Button {
                        phase = .processing
                        stopRequests += 1
                    } label: {
                        ScanButtonLabel(title: "Done", symbol: "checkmark", fill: GameStyle.blue)
                    }
                case .processing:
                    ScanButtonLabel(title: "Building the model…", symbol: "hourglass", fill: nil)
                case .done:
                    Button {
                        if let result { rooms.save(result, worldMap: worldMap) }
                        dismiss()
                    } label: {
                        ScanButtonLabel(title: "Save the room", symbol: "square.and.arrow.down", fill: GameStyle.green)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .background(Color.black)
    }
}

private struct ScanButtonLabel: View {
    let title: String
    let symbol: String
    let fill: Color?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
            Text(title.uppercased())
                .font(GameStyle.face(14, .heavy))
                .tracking(14 * 0.14)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 18)
        .frame(minHeight: 50)
        .modifier(ScanButtonBackground(fill: fill))
    }
}

private struct ScanButtonBackground: ViewModifier {
    let fill: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let fill {
            content.gamePanel(bar: fill, fill: fill.opacity(0.85))
        } else {
            content.gamePanel(bar: GameStyle.mute)
        }
    }
}

/// RoomPlan's own capture view, which draws the outlines live and then the finished model.
struct RoomCaptureContainer: UIViewControllerRepresentable {
    let stopRequests: Int
    let onResult: (CapturedRoom, ARWorldMap?) -> Void

    func makeUIViewController(context: Context) -> RoomScanController {
        let controller = RoomScanController()
        controller.onResult = onResult
        return controller
    }

    func updateUIViewController(_ controller: RoomScanController, context: Context) {
        controller.onResult = onResult
        if stopRequests != controller.stopsHandled {
            controller.stopsHandled = stopRequests
            controller.stop()
        }
    }
}

final class RoomScanController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    var onResult: ((CapturedRoom, ARWorldMap?) -> Void)?
    var stopsHandled = 0
    private var captureView: RoomCaptureView?
    private var worldMap: ARWorldMap?
    private var stopping = false

    override func viewDidLoad() {
        super.viewDidLoad()
        let capture = RoomCaptureView(frame: view.bounds)
        capture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        capture.delegate = self
        capture.captureSession.delegate = self
        view.addSubview(capture)
        captureView = capture
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        captureView?.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureView?.captureSession.stop()
    }

    /// Ends the scan. First keeps what the camera saw (the world map; the AR session must still run for it), then
    /// RoomPlan processes the scan and presents the model. Three seconds at most for the map.
    func stop() {
        guard let session = captureView?.captureSession, !stopping else { return }
        stopping = true
        var stopped = false
        let finish = { [weak self] (map: ARWorldMap?) in
            guard !stopped else { return }
            stopped = true
            self?.worldMap = map
            session.stop()
        }
        session.arSession.getCurrentWorldMap { map, _ in
            DispatchQueue.main.async { finish(map) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish(nil) }
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if error == nil { onResult?(processedResult, worldMap) }
    }
}
