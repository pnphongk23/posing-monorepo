import AVFoundation
import Foundation
import Kingfisher
import SwiftUI
import UIKit

/// Where the photo frame sits on the camera stage.
///
/// The preview is always full screen — edge to edge, behind the top buttons and the bottom controls — and the
/// ratio only decides which rect the shutter saves. That rect is never narrower than the screen: 3:4 and 1:1
/// hang from just under the top controls, and 9:16 is taller than the space left, so it starts at the top and
/// runs under the bottom controls. Everything outside it is dimmed, never blacked out.
///
/// Pure, so every number below is a unit test at any phone size instead of something only a screenshot shows.
struct CameraStageFrame: Equatable {
    /// From the safe-area top to a 3:4 / 1:1 frame: the top control row plus the hairline under it.
    static let shortRatioTopInset: CGFloat = 45
    /// A 9:16 frame hangs from the safe-area top itself; the top controls sit on the photo.
    static let tallRatioTopInset: CGFloat = 1
    /// The dim over everything the shutter is leaving out. The owner's default (65 %), not the artboard's.
    static let dimOpacity: Double = 0.65
    /// The frame's edge is a guide, not a border: white at 40 %, one point.
    static let edgeOpacity: Double = 0.4

    let screen: CGSize
    let frame: CGRect

    static func topInset(for ratio: CameraAspectRatio) -> CGFloat {
        ratio == .nineSixteen ? tallRatioTopInset : shortRatioTopInset
    }

    /// The frame for a ratio on a screen, given the safe-area top the chrome is drawn from.
    static func make(ratio: CameraAspectRatio, screen: CGSize, safeTop: CGFloat) -> CameraStageFrame {
        guard screen.width > 0, screen.height > 0 else {
            return CameraStageFrame(screen: screen, frame: .zero)
        }
        // Full width always: the ratio decides the height, and the phone decides the width.
        let height = screen.width / ratio.widthOverHeight
        let wanted = max(0, safeTop) + topInset(for: ratio)
        // A short phone keeps the frame on screen by moving its top up. Its width never gives way, so the
        // picture is never narrower than the screen — only the top moves.
        let top = min(wanted, max(0, screen.height - height))
        return CameraStageFrame(
            screen: screen,
            frame: CGRect(x: 0, y: top, width: screen.width, height: height)
        )
    }

    /// The pose reference's area inside the frame (the prototype's `.nb-camera-pose-reference` fractions).
    var guideFrame: CGRect { CameraViewportFrame.guideRect(in: frame) }
}

/// The stage minus the photo frame: one rect with a hole, so the dim outside the frame is a single translucent
/// layer instead of four strips that could leave a seam.
struct CameraStageFrameMask: Shape {
    let frame: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(frame.intersection(rect))
        return path
    }
}

/// The window's safe-area insets.
///
/// The camera draws edge to edge, so its own `GeometryReader` reports zero insets — the chrome and the photo
/// frame are positioned from the window's numbers instead of from a hard-coded phone.
@MainActor
enum CameraSafeArea {
    struct Insets: Equatable {
        var top: CGFloat = 0
        var bottom: CGFloat = 0
    }

    static func read(from window: UIWindow? = nil) -> Insets {
        let resolved = window ?? keyWindow
        guard let resolved else { return Insets() }
        return Insets(top: resolved.safeAreaInsets.top, bottom: resolved.safeAreaInsets.bottom)
    }

    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
    }
}

/// The live camera canvas: the preview, everything that belongs to *the photo* (the framing edge, the thirds
/// grid and the pose reference, each clipped to it), the pinch/twist/drag layer that places the reference, and
/// the permission panel when there is no camera.
///
/// The frame rect is handed in rather than computed here: it is the same rect the capture crops to, so keeping
/// the maths outside the view is what lets a test assert the framing without a camera.
struct CameraCanvas: View {
    @ObservedObject var model: CameraViewModel
    /// The reference currently up, if any. A value, not a binding: the canvas only draws it, and a pick is
    /// what changes it.
    let guide: NativePose?
    let isAuthorized: Bool
    /// Where the photo frame sits on this screen, and how big the screen is.
    let stage: CameraStageFrame
    /// Leaves the camera from the permission panel's "Not now".
    let onClose: () -> Void
    /// Draws the live preview instead of the camera's own layer. A rendered test injects a flat colour: the
    /// simulator has no camera feed, and "the area outside the frame is dimmed but not opaque" is a claim
    /// about pixels.
    var previewOverride: AnyView? = nil

    /// In-flight pinch / twist / drag, folded into `model.guideTransform` when the gesture ends.
    @GestureState private var guideGestureDelta = GuideTransform.Delta.identity

    private var frame: CGRect { stage.frame }
    private var guideFrame: CGRect { stage.guideFrame }

    var body: some View {
        ZStack {
            AP.Color.background

            if isAuthorized {
                // The preview is the whole screen: the ratio frames the photo, it never letterboxes the camera.
                preview
                    .frame(width: stage.screen.width, height: stage.screen.height)
                    .clipped()

                // One layer over everything the shutter is leaving out. The preview keeps showing through it,
                // so the user sees what the photo will not include instead of a black bar.
                CameraStageFrameMask(frame: frame)
                    .fill(Color.black.opacity(CameraStageFrame.dimOpacity), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                frameEdge

                if model.isGridVisible {
                    CameraFramingGrid()
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }

                // `.nb-camera-pose-reference` — the reference area is a fraction of the framing rect, and the
                // guide's layer is clipped to the rect before it is positioned: pinch / twist / drag can push
                // the line art past its box, and a reference painted outside the photo is a picture the
                // shutter can never take.
                if let guide, model.isPoseGuideVisible {
                    ZStack {
                        guideOverlay(for: guide)
                            .frame(width: guideFrame.width, height: guideFrame.height)
                            .position(x: guideFrame.midX, y: guideFrame.midY)
                    }
                    .frame(width: frame.width, height: frame.height)
                    // Clip *before* positioning: `.position` makes a view take all the space it is offered, so
                    // a clip after it would cut at the canvas edge and the guide would still reach the bars.
                    .clipped()
                    .position(x: frame.midX, y: frame.midY)
                    // Only the part inside the frame is drawn, so only that part is announced.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Pose guide")
                    .accessibilityValue(guide.id)
                    .accessibilityIdentifier("camera.poseGuide")
                    // The reference is the entry point of its own sheet, so VoiceOver gets the same action.
                    .accessibilityAction(named: "Adjust guide") { model.openGuideAdjust() }
                }

                // Pinch / twist / drag on the photo places the pose reference; the reference itself stays
                // non-interactive so a thin skeleton is never a hard touch target. The catcher is the framing
                // rect: a drag that starts outside the photo must not move the guide inside it.
                if guide != nil, model.isPoseGuideVisible {
                    Color.clear
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.resetGuideTransform() }
                        // One tap on the reference opens the sheet that adjusts it: the guide is the control.
                        .onTapGesture { model.openGuideAdjust() }
                        .gesture(guidePlacementGesture)
                        .accessibilityHidden(true)
                }
            } else {
                permissionPanel
            }
        }
        .clipped()
    }

    @ViewBuilder private var preview: some View {
        if let previewOverride {
            previewOverride
        } else {
            CameraPreview(session: model.camera.session)
        }
    }

    /// The frame's edge: one white hairline at 40 %. Drawn inside the rect, so it never spills on the photo.
    private var frameEdge: some View {
        Rectangle()
            .strokeBorder(Color.white.opacity(CameraStageFrame.edgeOpacity), lineWidth: 1)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var guidePlacementGesture: some Gesture {
        SimultaneousGesture(
            SimultaneousGesture(MagnificationGesture(), RotationGesture()),
            DragGesture()
        )
        .updating($guideGestureDelta) { value, state, _ in
            state = Self.delta(from: value)
        }
        .onEnded { value in
            model.commitGuideGesture(Self.delta(from: value))
        }
    }

    private static func delta(
        from value: SimultaneousGesture<SimultaneousGesture<MagnificationGesture, RotationGesture>, DragGesture>.Value
    ) -> GuideTransform.Delta {
        GuideTransform.Delta(
            scale: value.first?.first ?? 1,
            rotation: value.first?.second ?? .zero,
            translation: value.second?.translation ?? .zero
        )
    }

    @ViewBuilder
    private func guideOverlay(for guide: NativePose) -> some View {
        let placement = model.guideTransform.applying(guideGestureDelta)
        Group {
            if let url = guide.cameraGuideURL {
                KFImage(url)
                    .setProcessor(AppImage.downsample(points: FullScreenImageTarget.drawSize, contentMode: .fit))
                    .placeholder { guideFallback(for: guide) }
                    .onFailureView { guideFallback(for: guide) }
                    .loadDiskFileSynchronously(false)
                    // The extracted pose is line art on a transparent background, so it is drawn as
                    // a template and the Line colour setting becomes its stroke colour.
                    .contentConfigure { image, _ in
                        image.renderingMode(.template).resizable().scaledToFit()
                    }
                    .foregroundColor(model.guideLineColor.color)
            } else {
                guideFallback(for: guide)
            }
        }
        .opacity(model.guideOpacity)
        .scaleEffect(x: model.guideFlipped ? -1 : 1, y: 1)
        .scaleEffect(placement.scale)
        .rotationEffect(placement.rotation)
        .offset(placement.offset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Same stand-in the `AsyncImage` placeholder used before the guide asset loads. The stroke follows the
    /// guide-adjust sheet's Line colour.
    private func guideFallback(for guide: NativePose) -> StickFigureView {
        StickFigureView(kind: .resolve(name: guide.name, category: guide.category, index: 0),
                        lineColor: model.guideLineColor.color)
    }

    /// The camera's permission state on the shared 72 pt panel — one clean accent-tint circle, title, copy
    /// and one action — instead of a camera tile stacked on a yellow square.
    @MainActor private var permissionPanel: some View {
        CameraPermissionPanel(
            permission: model.coordinator.state.permission,
            onAllow: { model.requestPermission() },
            onOpenSettings: openSystemSettings,
            onDismiss: onClose
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AP.Color.scrim)
    }

    @MainActor private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// `.nb-camera-viewport__grid-overlay` — hairline thirds at 30% white.
struct CameraFramingGrid: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                for step in 1...2 {
                    let x = proxy.size.width * CGFloat(step) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))

                    let y = proxy.size.height * CGFloat(step) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.3), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
