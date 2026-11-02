import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView { let view = PreviewView(); view.layerView.session = session; return view }
    func updateUIView(_ uiView: PreviewView, context: Context) { uiView.layerView.session = session }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var layerView: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override init(frame: CGRect) {
        super.init(frame: frame)
        layerView.videoGravity = .resizeAspectFill
        // The preview is framed to the chosen capture ratio, so the aspect-fill overflow has to stay
        // inside that rect: without this the video would paint over the dark bars beside the frame.
        layerView.masksToBounds = true
    }
    required init?(coder: NSCoder) { nil }
}
