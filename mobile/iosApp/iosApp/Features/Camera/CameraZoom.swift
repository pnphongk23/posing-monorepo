import Foundation
import SwiftUI
import UIKit

/// The zoom stops a stored settings row carries. The slider is continuous, so this enum is the **storage**
/// shape (older rows read as 1x/2x/3x) and the level follows the factor; nothing steps through it any more.
enum CameraZoomLevel: Int, CaseIterable, Equatable {
    case one = 1, two = 2, three = 3

    var factor: CGFloat { CGFloat(rawValue) }
}

extension CameraZoomLevel {
    /// The stored level nearest a lens factor. The enum keeps every pre-existing settings row readable;
    /// the exact factor (which can be 0.5x) lives beside it.
    static func nearest(to factor: CGFloat) -> CameraZoomLevel {
        allCases.min {
            abs(CGFloat($0.rawValue) - factor) < abs(CGFloat($1.rawValue) - factor)
        } ?? .one
    }
}

/// The lenses the camera offers: **1× and 2×** (owner decision, 2026-11-08, replacing the earlier
/// "include 0.5×" decision). 1× is the wide lens's own framing; 2× is the same lens zoomed in, so a phone
/// without a 2× lens still serves it as digital zoom.
enum CameraZoomPreset: String, CaseIterable, Identifiable, Sendable {
    case one = "1x"
    case two = "2x"

    var id: String { rawValue }
    var factor: CGFloat {
        switch self {
        case .one: return 1
        case .two: return 2
        }
    }

    /// The handle a flow or a test taps for this lens.
    var accessibilityIdentifier: String { "camera.zoom.lens.\(rawValue)" }
}

enum CameraZoomPresets {
    /// The row's buttons, in order: every stop the camera offers.
    static let all: [CameraZoomPreset] = CameraZoomPreset.allCases

    /// The lens a factor belongs to: the nearest stop. A continuous 1.4× still reads as "the 1× button is
    /// current", with 1.4× written in it.
    static func nearest(to factor: CGFloat) -> CameraZoomPreset {
        all.min { abs($0.factor - factor) < abs($1.factor - factor) } ?? .one
    }
}

/// The mapping between what the row and the dial show and what the lens receives, plus the labels.
///
/// The camera drives one wide-angle device (`AVCaptureDevice.default(.builtInWideAngleCamera)`), so the displayed
/// factor **is** the lens's `videoZoomFactor`: 1×…2×, clamped. 2× is that lens zoomed in, which every iPhone can
/// do — the owner's "devices without a 2× lens use digital zoom" rule is what this identity means.
enum CameraZoomScale {
    /// The whole range the buttons and the drag span (owner decision, 2026-11-08).
    static let range: ClosedRange<CGFloat> = 1...2
    static let sliderIdentifier = "camera.zoom.slider"

    /// The old pills' ids are retired with them; nothing may address them again.
    static let retiredIdentifiers = ["camera.zoom.0.5x", "camera.zoom.1x", "camera.zoom.2x", "camera.zoom.3x"]

    static func clamped(_ factor: CGFloat) -> CGFloat {
        guard factor.isFinite else { return range.lowerBound }
        return min(max(factor, range.lowerBound), range.upperBound)
    }

    /// Where a factor sits on the line, 0…1, and the way back. Pure, so the thumb's position is a unit test.
    static func fraction(of factor: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (clamped(factor) - range.lowerBound) / span
    }

    static func factor(atFraction fraction: CGFloat) -> CGFloat {
        let clampedFraction = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        return clamped(range.lowerBound + clampedFraction * (range.upperBound - range.lowerBound))
    }

    /// The value in the thumb: "1×", "1.4×".
    static func valueLabel(_ factor: CGFloat) -> String {
        let rounded = (factor * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.001 {
            return "\(Int(rounded.rounded()))×"
        }
        return String(format: "%.1f×", rounded)
    }

    /// What VoiceOver reads: always one decimal, so "1×" cannot be heard as "ten".
    static func accessibilityValue(_ factor: CGFloat) -> String {
        String(format: "%.1f×", (factor * 10).rounded() / 10)
    }
}

/// The dial's own geometry, pure: where the value thumb sits on the line for a factor.
struct CameraZoomTrackGeometry: Equatable {
    let width: CGFloat
    let thumbDiameter: CGFloat
    let range: ClosedRange<CGFloat>

    static let totalHeight: CGFloat = 44
    static let thumbDiameterConstant: CGFloat = 44
    /// The white value pill: small enough to read as a label, tall enough to stay a 44 pt target with the line
    /// running through its centre.
    static let thumbVisualHeight: CGFloat = 26

    var trackWidth: CGFloat { max(width - thumbDiameter, 1) }

    /// Centre of the thumb for a zoom factor: the track's ends are the range's ends.
    func thumbCenterX(for factor: CGFloat) -> CGFloat {
        thumbDiameter / 2 + trackWidth * CameraZoomScale.fraction(of: factor)
    }

    /// The thumb's centre, kept inside the track at either extreme.
    func pillCenterX(for factor: CGFloat) -> CGFloat {
        let half = thumbDiameter / 2
        return min(max(thumbCenterX(for: factor), half), max(half, width - half))
    }

    var pillCenterY: CGFloat { Self.thumbVisualHeight / 2 }
    /// The hairline and the thumb share one centre line.
    var trackLineCenterY: CGFloat { Self.thumbVisualHeight / 2 }
}

/// The dial's drawing: **one hairline and the value thumb**, nothing else (owner decision, 2026-11-08 — no tick
/// marks, no numbers under the line, no dark capsule). The thumb carries the live factor, so the line needs no
/// labels of its own.
///
/// It owns **no gesture**. `CameraZoomControl` owns the drag, because the drag starts on the compact lens row and
/// has to keep tracking the same finger once the dial has opened — a child gesture mounted mid-drag would never
/// see it.
struct CameraZoomDial: View {
    let factor: CGFloat
    var range: ClosedRange<CGFloat> = CameraZoomScale.range
    var isEnabled = true

    private let thumbSize: CGFloat = CameraZoomTrackGeometry.thumbDiameterConstant

    var body: some View {
        GeometryReader { proxy in
            let geometry = CameraZoomTrackGeometry(width: proxy.size.width, thumbDiameter: thumbSize, range: range)
            ZStack(alignment: .topLeading) {
                trackLine(geometry)
                valueThumb(geometry)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(height: CameraZoomTrackGeometry.totalHeight)
        .opacity(isEnabled ? 1 : 0.45)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One 1 pt line at half white: enough to read as a track on a bright or a dark preview, quiet everywhere
    /// else.
    private func trackLine(_ geometry: CameraZoomTrackGeometry) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.5))
            .frame(width: geometry.trackWidth, height: 1)
            .position(x: geometry.width / 2, y: geometry.trackLineCenterY)
    }

    /// The value in the white pill: it follows the finger, so the number and the handle stay together. A soft
    /// shadow is the only thing behind it — enough to stay readable over a white wall.
    private func valueThumb(_ geometry: CameraZoomTrackGeometry) -> some View {
        Text(CameraZoomScale.valueLabel(factor))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.88))
            .frame(width: thumbSize, height: CameraZoomTrackGeometry.thumbVisualHeight)
            .background(Capsule().fill(Color.white))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .position(x: geometry.pillCenterX(for: factor), y: geometry.pillCenterY)
    }
}

// MARK: - The lens row and the dial it opens

/// Which shape the zoom control is in: the compact lens row, or the dial a drag opens.
enum CameraZoomBarMode: Equatable {
    case lenses
    case dial
}

/// The zoom bar's interaction rules, pure: **tap** a lens to jump to it, **drag** to open the dial, and the dial
/// collapses again about a second after the finger lifts (owner decision for build 25, replacing the always
/// visible 224×44 dial).
struct CameraZoomBarState: Equatable {
    /// A drag shorter than this is a tap on a lens button, not a drag.
    static let dragThreshold: CGFloat = 6
    /// How long the open dial stays up after the finger lifts.
    static let collapseDelaySeconds: Double = 0.9

    private(set) var mode: CameraZoomBarMode

    init(mode: CameraZoomBarMode = .lenses) {
        self.mode = mode
    }

    static func isDrag(_ translation: CGSize) -> Bool {
        guard translation.width.isFinite, translation.height.isFinite else { return false }
        return hypot(translation.width, translation.height) > dragThreshold
    }

    /// A finger moving on the bar opens the dial; once open it stays open for this gesture.
    @discardableResult
    mutating func dragChanged(translation: CGSize) -> CameraZoomBarMode {
        if mode == .lenses, Self.isDrag(translation) { mode = .dial }
        return mode
    }

    /// Whether the finger lifted on a drag, so the dial has to collapse again after the delay.
    mutating func dragEnded(translation: CGSize) -> Bool {
        mode == .dial && Self.isDrag(translation)
    }

    mutating func collapse() { mode = .lenses }
}

/// The bar's live state, one object per control.
///
/// The mode and the collapse timer live on a **reference type** on purpose: a `Task` scheduled from a gesture
/// captured a copy of the view's `@State`, and after the drag ended its `collapse()` wrote to a copy the screen was
/// no longer drawing from — the dial stayed open forever (reproduced on the iPhone 16 simulator, build 25 lane).
/// Writing to the object the view observes cannot drift like that.
@MainActor
final class CameraZoomBarModel: ObservableObject {
    @Published private(set) var state: CameraZoomBarState
    private var collapseTask: Task<Void, Never>?

    init(mode: CameraZoomBarMode = .lenses) {
        state = CameraZoomBarState(mode: mode)
    }

    var mode: CameraZoomBarMode { state.mode }

    /// A finger moved on the bar: opens the dial once the movement passes the tap threshold.
    @discardableResult
    func dragChanged(translation: CGSize) -> CameraZoomBarMode {
        state.dragChanged(translation: translation)
    }

    /// The finger lifted: a drag on an open dial schedules the collapse, a tap does not.
    func dragEnded(translation: CGSize) {
        guard state.dragEnded(translation: translation) else { return }
        scheduleCollapse()
    }

    /// A tap on an open dial snaps the value; the dial then gets the same ~1 s before it closes.
    func tappedOnOpenDial() {
        scheduleCollapse()
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(CameraZoomBarState.collapseDelaySeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            state.collapse()
        }
    }

    deinit { collapseTask?.cancel() }
}

/// The compact lens row's geometry, pure: where each button sits and which lens a tap at an x selects.
struct CameraZoomLensRow: Equatable {
    /// One lens button: a 44 pt touch target holding a small capsule label, as in the system camera.
    static let buttonWidth: CGFloat = 46
    static let height: CGFloat = 44
    static let visualHeight: CGFloat = 34
    static let horizontalInset: CGFloat = 3

    let presets: [CameraZoomPreset]

    var width: CGFloat { CGFloat(presets.count) * Self.buttonWidth + Self.horizontalInset * 2 }

    func centerX(index: Int) -> CGFloat {
        Self.horizontalInset + CGFloat(index) * Self.buttonWidth + Self.buttonWidth / 2
    }

    /// The lens a tap at `x` selects. A tap in the gap between two buttons belongs to the nearer one, so no
    /// part of the row is a dead zone.
    func preset(atX x: CGFloat) -> CameraZoomPreset? {
        guard !presets.isEmpty else { return nil }
        let rawIndex = ((x - Self.horizontalInset) / Self.buttonWidth).rounded(.down)
        let index = Int(min(max(rawIndex, 0), CGFloat(presets.count - 1)))
        return presets[index]
    }

    /// What a button shows: the selected one carries the **live** value ("1.9×"), the others their own stop.
    func label(for preset: CameraZoomPreset, factor: CGFloat, isSelected: Bool) -> String {
        isSelected ? CameraZoomScale.valueLabel(factor) : CameraZoomScale.valueLabel(preset.factor)
    }
}

/// The zoom control: compact **1× / 2×** buttons, the current one highlighted and carrying the live value
/// ("1.4×"). Tap a lens to jump to it; **drag** to expand the same row into the minimal dial, which collapses
/// about a second after the finger lifts (owner decisions, 2026-11-08).
struct CameraZoomControl: View {
    let factor: CGFloat
    let range: ClosedRange<CGFloat>
    var isEnabled = true
    let onChange: (CGFloat) -> Void

    @StateObject private var bar: CameraZoomBarModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `initialMode` exists so a rendered test (and a SwiftUI preview) can show the open dial: the mode is
    /// otherwise reached by a drag, which a snapshot cannot perform.
    init(
        factor: CGFloat,
        range: ClosedRange<CGFloat>,
        isEnabled: Bool = true,
        initialMode: CameraZoomBarMode = .lenses,
        onChange: @escaping (CGFloat) -> Void
    ) {
        self.factor = factor
        self.range = range
        self.isEnabled = isEnabled
        self.onChange = onChange
        _bar = StateObject(wrappedValue: CameraZoomBarModel(mode: initialMode))
    }

    private var row: CameraZoomLensRow { CameraZoomLensRow(presets: CameraZoomPresets.all) }
    private var selectedLens: CameraZoomPreset { CameraZoomPresets.nearest(to: factor) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // The mode swaps **inside** this ZStack, and the drag is attached to the ZStack itself, which never
            // changes: attaching it to the swapping content cancelled the gesture mid-drag (the dial then never
            // heard its release and stayed open forever — found on the simulator, iPhone 16 lane). The inactive
            // presentation is not mounted at all, so a screen reader cannot reach a control nobody can touch.
            ZStack(alignment: .leading) {
                switch bar.mode {
                case .lenses:
                    lensRow
                        .background(CameraGlassBackground(shape: .capsule))
                        .frame(height: CameraZoomLensRow.visualHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                case .dial:
                    dial(width: width)
                        .transition(.opacity)
                }
            }
            .frame(width: width, height: CameraZoomLensRow.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(zoomGesture(width: width), including: isEnabled ? .all : .none)
        }
        .frame(height: CameraZoomLensRow.height)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: bar.mode)
        .accessibilityElement(children: .contain)
    }

    /// The dial: the drawing plus the one adjustable element VoiceOver gets while it is up.
    private func dial(width: CGFloat) -> some View {
        CameraZoomDial(factor: factor, range: range, isEnabled: isEnabled)
            .frame(width: width)
            .accessibilityElement()
            .accessibilityLabel("Zoom")
            .accessibilityValue(CameraZoomScale.accessibilityValue(factor))
            .accessibilityAdjustableAction { direction in
                guard isEnabled else { return }
                switch direction {
                case .increment:
                    onChange(CameraZoomScale.clamped(factor + 0.1))
                case .decrement:
                    onChange(CameraZoomScale.clamped(factor - 0.1))
                @unknown default:
                    break
                }
            }
            .accessibilityIdentifier(CameraZoomScale.sliderIdentifier)
    }

    /// The buttons are plain views, not `Button`s: the whole row shares one gesture, so a tap and a drag can
    /// never both fire for the same touch. VoiceOver gets each lens as a button through its own action.
    private var lensRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(row.presets.enumerated()), id: \.element) { index, preset in
                let isSelected = preset == selectedLens
                Text(row.label(for: preset, factor: factor, isSelected: isSelected))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.88) : Color.white)
                    .frame(width: CameraZoomLensRow.buttonWidth - 8, height: 28)
                    .background {
                        if isSelected { Capsule().fill(Color.white) }
                    }
                    .frame(width: CameraZoomLensRow.buttonWidth, height: CameraZoomLensRow.visualHeight)
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityLabel(isSelected ? "Zoom .\(CameraZoomScale.accessibilityValue(factor))" : "Zoom \(preset.rawValue)")
                    .accessibilityAction { onChange(preset.factor) }
                    .accessibilityIdentifier(preset.accessibilityIdentifier)
                    .id(index)
            }
        }
        .padding(.horizontal, CameraZoomLensRow.horizontalInset)
    }

    private func zoomGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled else { return }
                guard bar.dragChanged(translation: value.translation) == .dial else { return }
                onChange(factor(atX: value.location.x, width: width))
            }
            .onEnded { value in
                guard isEnabled else { return }
                let wasDrag = CameraZoomBarState.isDrag(value.translation)
                // A drag that ends while the dial is open schedules the collapse (it also covers the very first
                // drag, which opens the dial and lifts in the same gesture).
                bar.dragEnded(translation: value.translation)
                switch bar.mode {
                case .lenses:
                    // A tap: jump to the lens under the finger. To the right of the compact row there is no button
                    // (the row hugs its content, the Poses chip owns the rest), so nothing happens there.
                    if value.location.x <= row.width, let preset = row.preset(atX: value.location.x) {
                        onChange(preset.factor)
                    }
                case .dial:
                    guard !wasDrag else { return }
                    // A tap on an open dial jumps to the factor under the finger and gets the same ~1 s to close.
                    onChange(factor(atX: value.location.x, width: width))
                    bar.tappedOnOpenDial()
                }
            }
    }

    /// Where a point on the dial sits, in display zoom: the same mapping the thumb uses.
    private func factor(atX x: CGFloat, width: CGFloat) -> CGFloat {
        let geometry = CameraZoomTrackGeometry(
            width: width,
            thumbDiameter: CameraZoomTrackGeometry.thumbDiameterConstant,
            range: range
        )
        let fraction = (x - CameraZoomTrackGeometry.thumbDiameterConstant / 2) / geometry.trackWidth
        return CameraZoomScale.factor(atFraction: fraction)
    }
}
