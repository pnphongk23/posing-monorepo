import AVFoundation
import Foundation
import Kingfisher
import SwiftUI
import UIKit

/// Where the photo frame sits on the camera stage.
///
/// The preview is always full screen — edge to edge, behind the top buttons and the bottom controls — and the
/// ratio decides which rect the shutter saves:
///
/// - **3:4 and 1:1** are full width and **vertically centred** in the band between the top control row and the
///   zoom row (owner feedback, build 25: they used to hang from the top, leaving a large dim area below and an
///   undimmed strip above). Everything outside them is dimmed evenly, never blacked out.
/// - **9:16 is full bleed**: the frame *is* the viewfinder, safe areas included, so nothing is dimmed and the
///   bottom controls float on the photo with no band of their own.
///
/// Pure, so every number below is a unit test at any phone size instead of something only a screenshot shows.
struct CameraStageFrame: Equatable {
    /// From the safe-area top to the band a 3:4 / 1:1 frame is centred in: the top control row plus the
    /// hairline under it.
    static let shortRatioTopInset: CGFloat = 45
    /// One 55% black layer over everything the shutter leaves out (camera changes, line 8).
    static let dimOpacity: Double = 0.55
    /// White corner guides use 90% opacity and a 2pt stroke (camera changes, line 14).
    static let edgeOpacity: Double = 0.9

    let screen: CGSize
    let frame: CGRect
    /// 9:16 covers the whole viewfinder: there is no edge to mark and nothing outside to dim.
    let isFullBleed: Bool

    init(screen: CGSize, frame: CGRect, isFullBleed: Bool = false) {
        self.screen = screen
        self.frame = frame
        self.isFullBleed = isFullBleed
    }

    /// The frame for a ratio on a screen, given the safe-area top the chrome is drawn from and the height of
    /// the control band under the photo (zoom row + rail + home indicator).
    static func make(
        ratio: CameraAspectRatio,
        screen: CGSize,
        safeTop: CGFloat,
        bottomInset: CGFloat = 0
    ) -> CameraStageFrame {
        guard screen.width > 0, screen.height > 0 else {
            return CameraStageFrame(screen: screen, frame: .zero)
        }
        // 9:16 is the viewfinder: edge to edge, under the status bar and over the home indicator.
        if ratio == .nineSixteen {
            return CameraStageFrame(screen: screen, frame: CGRect(origin: .zero, size: screen), isFullBleed: true)
        }
        // Full width always: the ratio decides the height, and the phone decides the width.
        let height = screen.width / ratio.widthOverHeight
        let bandTop = max(0, safeTop) + shortRatioTopInset
        let bandBottom = max(bandTop, screen.height - max(0, bottomInset))
        // Centred in that band, then kept on screen: a short phone moves the frame up instead of shrinking it,
        // so the picture is never narrower than the screen.
        let centred = (bandTop + bandBottom - height) / 2
        let top = min(max(centred, 0), max(0, screen.height - height))
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

/// Four rounded 22pt corner guides inset 16pt from the photo edge; deliberately no continuous border.
struct CameraFrameCorners: Shape {
    static let inset: CGFloat = 16
    static let arm: CGFloat = 22
    static let radius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY
        let arm = Self.arm
        let radius = Self.radius

        path.move(to: CGPoint(x: left + arm, y: top))
        path.addLine(to: CGPoint(x: left + radius, y: top))
        path.addQuadCurve(to: CGPoint(x: left, y: top + radius), control: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: top + arm))

        path.move(to: CGPoint(x: right - arm, y: top))
        path.addLine(to: CGPoint(x: right - radius, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: top + radius), control: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: top + arm))

        path.move(to: CGPoint(x: left, y: bottom - arm))
        path.addLine(to: CGPoint(x: left, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: left + radius, y: bottom), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left + arm, y: bottom))

        path.move(to: CGPoint(x: right, y: bottom - arm))
        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right - arm, y: bottom))
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

                // One layer over everything the shutter is leaving out, sized to the **screen** rather than to
                // whatever the container offers: a full-bleed 9:16 frame leaves nothing to dim, and a safe-area
                // inset container must not leave an undimmed strip at the status bar or the home indicator.
                CameraStageFrameMask(frame: frame)
                    .fill(Color.black.opacity(CameraStageFrame.dimOpacity), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    .frame(width: stage.screen.width, height: stage.screen.height)
                    .accessibilityHidden(true)

                // A full-bleed frame has no edge to mark: its edge is the screen's, so corner guides there
                // would be drawn under the controls or off the display.
                if !stage.isFullBleed {
                    frameEdge
                }

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
        // No clip on the canvas root: the preview and the dim are painted at the screen's size so a safe-area
        // inset container cannot shave an undimmed strip off the status bar or the home indicator.
    }

    @ViewBuilder private var preview: some View {
        if let previewOverride {
            previewOverride
        } else {
            CameraPreview(session: model.camera.session)
        }
    }

    /// The frame is marked by four white corner guides, not a continuous outline.
    private var frameEdge: some View {
        CameraFrameCorners()
            .stroke(Color.white.opacity(CameraStageFrame.edgeOpacity), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: frame.width - CameraFrameCorners.inset * 2, height: frame.height - CameraFrameCorners.inset * 2)
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
