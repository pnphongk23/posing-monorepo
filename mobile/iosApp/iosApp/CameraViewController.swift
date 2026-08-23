import UIKit
import SwiftUI
import AVFoundation
import MijickCamera

@objc enum AIPoseBridgeFlashMode: Int {
    case off
    case on
    case auto

    init(rawValueString: String) {
        switch rawValueString.lowercased() {
        case "on": self = .on
        case "auto": self = .auto
        default: self = .off
        }
    }

    var mijickMode: CameraFlashMode {
        switch self {
        case .off: return .off
        case .on: return .on
        case .auto: return .auto
        }
    }
}

@objc final class AIPoseCameraBridgeRuntime: NSObject {
    private static let commandName = Notification.Name("AIPoseCameraBridgeCommand")
    private static let eventName = Notification.Name("AIPoseCameraBridgeEvent")

    private static let keyBridgeId = "bridgeId"
    private static let keyCommand = "command"
    private static let keyHostView = "hostView"
    private static let keyFlashMode = "flashMode"
    private static let keyGridVisible = "gridVisible"
    private static let keyZoomFactor = "zoomFactor"

    private static let keyEvent = "event"
    private static let keyPermissionState = "permissionState"
    private static let keyImageData = "imageData"

    private static var isInstalled = false
    private static var commandToken: NSObjectProtocol?
    private static var controllers: [String: CameraViewController] = [:]

    @objc static func install() {
        guard !isInstalled else { return }
        isInstalled = true

        commandToken = NotificationCenter.default.addObserver(
            forName: commandName,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let userInfo = notification.userInfo,
                let bridgeId = userInfo[keyBridgeId] as? String,
                let command = userInfo[keyCommand] as? String
            else {
                return
            }

            switch command {
            case "attach":
                guard let hostView = userInfo[keyHostView] as? UIView else { return }
                attach(bridgeId: bridgeId, hostView: hostView)
            case "detach":
                detach(bridgeId: bridgeId)
            case "start":
                controllers[bridgeId]?.setSessionActive(true)
            case "stop":
                controllers[bridgeId]?.setSessionActive(false)
            case "capture":
                controllers[bridgeId]?.capture()
            case "switch":
                controllers[bridgeId]?.switchCamera()
            case "setFlash":
                let mode = AIPoseBridgeFlashMode(rawValueString: (userInfo[keyFlashMode] as? String) ?? "off")
                controllers[bridgeId]?.setFlashMode(mode)
            case "setGrid":
                let isVisible = (userInfo[keyGridVisible] as? Bool) ?? false
                controllers[bridgeId]?.setGridVisible(isVisible)
            case "setZoom":
                let zoomFactor = (userInfo[keyZoomFactor] as? NSNumber)?.doubleValue ?? 1
                controllers[bridgeId]?.setZoomFactor(CGFloat(zoomFactor))
            case "requestPermission":
                requestPermission(bridgeId: bridgeId)
            default:
                break
            }
        }
    }

    private static func attach(bridgeId: String, hostView: UIView) {
        let controller = controllers[bridgeId] ?? CameraViewController(bridgeId: bridgeId)
        controllers[bridgeId] = controller

        guard let parent = hostView.findParentViewController() else {
            DispatchQueue.main.async {
                attach(bridgeId: bridgeId, hostView: hostView)
            }
            return
        }

        if controller.parent !== parent {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()

            parent.addChild(controller)
            hostView.addSubview(controller.view)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                controller.view.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
                controller.view.topAnchor.constraint(equalTo: hostView.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
            ])
            controller.didMove(toParent: parent)
        } else if controller.view.superview !== hostView {
            controller.view.removeFromSuperview()
            hostView.addSubview(controller.view)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                controller.view.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
                controller.view.topAnchor.constraint(equalTo: hostView.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
            ])
        }
    }

    private static func detach(bridgeId: String) {
        guard let controller = controllers.removeValue(forKey: bridgeId) else { return }
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
    }

    private static func requestPermission(bridgeId: String) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async {
                    postPermissionState(bridgeId: bridgeId)
                }
            }
        default:
            postPermissionState(bridgeId: bridgeId)
        }
    }

    private static func postPermissionState(bridgeId: String) {
        let state: String
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: state = "AUTHORIZED"
        case .denied: state = "DENIED"
        case .restricted: state = "RESTRICTED"
        case .notDetermined: state = "NOT_DETERMINED"
        @unknown default: state = "DENIED"
        }

        NotificationCenter.default.post(
            name: eventName,
            object: nil,
            userInfo: [
                keyBridgeId: bridgeId,
                keyEvent: "permissionState",
                keyPermissionState: state,
            ]
        )
    }

    static func postCapturedImage(bridgeId: String, data: Data) {
        NotificationCenter.default.post(
            name: eventName,
            object: nil,
            userInfo: [
                keyBridgeId: bridgeId,
                keyEvent: "captured",
                keyImageData: data,
            ]
        )
    }
}

private extension UIView {
    func findParentViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let viewController = next as? UIViewController {
                return viewController
            }
            responder = next
        }
        return nil
    }
}

final class CameraViewController: UIViewController {
    private let bridgeId: String
    private let bridgeModel = CameraBridgeModel()
    private var hostingController: UIHostingController<CameraRootView>?

    init(bridgeId: String) {
        self.bridgeId = bridgeId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let rootView = CameraRootView(
            bridgeModel: bridgeModel,
            bridgeId: bridgeId,
            onImageCaptured: { data in
                AIPoseCameraBridgeRuntime.postCapturedImage(bridgeId: self.bridgeId, data: data)
            }
        )

        let host = UIHostingController(rootView: rootView)
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false

        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        hostingController = host
    }

    func setSessionActive(_ isActive: Bool) {
        bridgeModel.setPreviewActive(isActive)
    }

    func capture() {
#if targetEnvironment(simulator) && DEBUG
        // Debug simulator fixture only: exercise the ordinary persistence
        // bridge without pretending the simulator has a physical camera.
        let fixtureBase64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAH/AP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAT8Af//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQIBAT8Af//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQMBAT8Af//Z"
        let fixture = Data(base64Encoded: fixtureBase64) ?? Data()
        AIPoseCameraBridgeRuntime.postCapturedImage(bridgeId: bridgeId, data: fixture)
#elseif targetEnvironment(simulator)
        AIPoseCameraBridgeRuntime.postCapturedImage(bridgeId: bridgeId, data: Data())
#else
        bridgeModel.capture()
#endif
    }

    func switchCamera() {
        bridgeModel.switchCamera()
    }

    func setFlashMode(_ mode: AIPoseBridgeFlashMode) {
        bridgeModel.setFlashMode(mode.mijickMode)
    }

    func setGridVisible(_ isVisible: Bool) {
        bridgeModel.setGridVisible(isVisible)
    }

    func setZoomFactor(_ zoomFactor: CGFloat) {
        bridgeModel.setZoomFactor(zoomFactor)
    }
}

@MainActor
private final class CameraBridgeModel: ObservableObject {
    @Published var isPreviewActive = false

    private var captureAction: (() -> Void)?
    private var switchAction: (() -> Void)?
    private var flashAction: ((CameraFlashMode) -> Void)?
    private var gridAction: ((Bool) -> Void)?
    private var zoomAction: ((CGFloat) -> Void)?
    private var pendingFlashMode: CameraFlashMode = .off
    private var pendingGridVisible = false
    private var pendingZoomFactor: CGFloat = 1
    private var isGridReady = false

    func setPreviewActive(_ active: Bool) {
        isPreviewActive = active
    }

    func attachActions(
        capture: @escaping () -> Void,
        switchCamera: @escaping () -> Void,
        setFlashMode: @escaping (CameraFlashMode) -> Void,
        setGridVisible: @escaping (Bool) -> Void,
        setZoomFactor: @escaping (CGFloat) -> Void
    ) {
        captureAction = capture
        switchAction = switchCamera
        flashAction = setFlashMode
        gridAction = setGridVisible
        zoomAction = setZoomFactor
        isGridReady = false
        setFlashMode(pendingFlashMode)
        setZoomFactor(pendingZoomFactor)
    }

    func markGridReady() {
        isGridReady = true
    }

    func applyPendingGridVisibilityIfReady() {
        guard isGridReady else { return }
        gridAction?(pendingGridVisible)
    }
    
    func detachActions() {
        captureAction = nil
        switchAction = nil
        flashAction = nil
        gridAction = nil
        zoomAction = nil
        isGridReady = false
    }

    func setGridVisible(_ isVisible: Bool) {
        pendingGridVisible = isVisible
        guard isGridReady else { return }
        gridAction?(isVisible)
    }

    func setZoomFactor(_ zoomFactor: CGFloat) {
        pendingZoomFactor = zoomFactor
        zoomAction?(zoomFactor)
    }

    func capture() {
        captureAction?()
    }

    func switchCamera() {
        switchAction?()
    }

    func setFlashMode(_ mode: CameraFlashMode) {
        pendingFlashMode = mode
        flashAction?(mode)
    }
}

private struct CameraRootView: View {
        @ObservedObject var bridgeModel: CameraBridgeModel
        let bridgeId: String
        let onImageCaptured: (Data) -> Void
        
        var body: some View {
#if targetEnvironment(simulator)
            Color.black
#else
            // WI-04: the MCamera session is mounted only while the preview is
            // active. Removing it triggers Mijick's onDisappear → cancel(),
            // which stops the AVCaptureSession (start/stop preview are now
            // effective, driven by the Kotlin start/stop bridge commands).
            if bridgeModel.isPreviewActive {
                MCamera()
                    .setAudioAvailability(false)
                    .setCapturedMediaScreen(nil)
                    .setFlashMode(.off)
                    .setCameraScreen {
                        BridgeCameraScreen(
                            cameraManager: $0,
                            namespace: $1,
                            closeMCameraAction: $2,
                            bridgeModel: bridgeModel
                        )
                    }
                    .onImageCaptured { image, _ in
                        if let data = image.jpegData(compressionQuality: 0.92) {
                            onImageCaptured(data)
                        }
                    }
                    .startSession()
            } else {
                Color.black
            }
#endif
        }
    }
    
    private struct BridgeCameraScreen: MCameraScreen {
        @ObservedObject var cameraManager: CameraManager
        let namespace: Namespace.ID
        let closeMCameraAction: () -> ()
        let bridgeModel: CameraBridgeModel
        
        var body: some View {
            createCameraOutputView()
                .ignoresSafeArea()
                .onAppear {
                    bridgeModel.attachActions(
                        capture: { captureOutput() },
                        switchCamera: {
                            Task { @MainActor in
                                try? await setCameraPosition(cameraPosition == .back ? .front : .back)
                            }
                        },
                        setFlashMode: { setFlashMode($0) },
                        setGridVisible: { setGridVisibility($0) },
                        setZoomFactor: { try? setZoomFactor($0) }
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        bridgeModel.markGridReady()
                        bridgeModel.applyPendingGridVisibilityIfReady()
                    }
                }
                .onDisappear {
                    bridgeModel.detachActions()
                }
        }
    }
