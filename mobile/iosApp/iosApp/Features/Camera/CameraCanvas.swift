import AVFoundation
import Kingfisher
import SwiftUI

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
    /// The photo frame, in the canvas' own coordinate space.
    let frame: CGRect
    /// Leaves the camera from the permission panel's "Not now".
    let onClose: () -> Void

    /// In-flight pinch / twist / drag, folded into `model.guideTransform` when the gesture ends.
    @GestureState private var guideGestureDelta = GuideTransform.Delta.identity

    private var guideFrame: CGRect { CameraViewportFrame.guideRect(in: frame) }

    var body: some View {
        ZStack {
            AP.Color.background

            if isAuthorized {
                CameraPreview(session: model.camera.session)
                    .frame(width: frame.width, height: frame.height)
                    .clipped()
                    .position(x: frame.midX, y: frame.midY)
            }

            // The scrims grade *the photo*: measured against the canvas they would darken the black bars,
            // which are not part of the picture the shutter saves.
            verticalScrims
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // `.nb-camera-pose-reference` — the reference area is a fraction of the framing rect, and the
            // guide's layer is clipped to the rect before it is positioned: pinch / twist / drag can push the
            // line art past its box, and a reference painted outside the photo is a picture the shutter can
            // never take.
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
            }

            if model.isGridVisible {
                CameraFramingGrid()
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }

            // Pinch / twist / drag on the photo places the pose reference; the reference itself stays
            // non-interactive so a thin skeleton is never a hard touch target. The catcher is the framing
            // rect: a drag that starts outside the photo must not move the guide inside it.
            if guide != nil, model.isPoseGuideVisible, isAuthorized {
                Color.clear
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.resetGuideTransform() }
                    .gesture(guidePlacementGesture)
                    .accessibilityHidden(true)
            }

            if !isAuthorized {
                permissionPanel
            }
        }
        .clipped()
    }

    /// `.nb-camera-viewport__top-scrim` (190px) / `__bottom-scrim` (170px).
    private var verticalScrims: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [AP.Color.background.opacity(0.68), AP.Color.background.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 190)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [AP.Color.background.opacity(0), AP.Color.background.opacity(0.54)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 170)
        }
        .allowsHitTesting(false)
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
    private var permissionPanel: some View {
        CameraPermissionPanel(
            permission: model.coordinator.state.permission,
            onAllow: { model.requestPermission() },
            onOpenSettings: openSystemSettings,
            onDismiss: onClose
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AP.Color.scrim)
    }

    private func openSystemSettings() {
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
