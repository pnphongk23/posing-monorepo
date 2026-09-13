import AVFoundation
import SwiftUI
import UIKit

/// Native UIKit host for embedding the SwiftUI camera screen without KMP/Mijick bridges.
final class CameraViewController: UIViewController {
    private var hostingController: UIHostingController<AnyView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let screen = AnyView(NavigationView { CameraScreen() })
        let host = UIHostingController(rootView: screen)
        host.view.backgroundColor = .clear
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
        // Lifecycle is owned by SwiftUI CameraScreen; keep API for legacy callers.
        if !isActive {
            NotificationCenter.default.post(name: .cameraHostShouldPause, object: nil)
        }
    }
}

extension Notification.Name {
    static let cameraHostShouldPause = Notification.Name("CameraHostShouldPause")
}
