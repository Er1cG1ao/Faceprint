// Glance-compatible mirrored preview. Rendering uses Camera's existing frame output;
// views must never attach preview layers to a live capture session.
import SwiftUI
import AppKit

struct CameraPreviewView: NSViewRepresentable {
    let camera: Camera

    func makeNSView(context: Context) -> PreviewHostView { PreviewHostView(camera: camera) }
    func updateNSView(_ nsView: PreviewHostView, context: Context) {}
    static func dismantleNSView(_ nsView: PreviewHostView, coordinator: ()) { nsView.stopDisplaying() }
}

final class PreviewHostView: NSView {
    private let camera: Camera
    private let imageLayer = CALayer()
    private var timer: Timer?
    private var lastFrameID: UInt64?

    init(camera: Camera) {
        self.camera = camera
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopDisplaying()
        guard window != nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.displayLatestFrame()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopDisplaying() { timer?.invalidate(); timer = nil }

    private func displayLatestFrame() {
        let frame = camera.latestFrame()
        guard frame?.id != lastFrameID else { return }
        lastFrameID = frame?.id
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = frame?.image
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        imageLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        CATransaction.commit()
    }
}
