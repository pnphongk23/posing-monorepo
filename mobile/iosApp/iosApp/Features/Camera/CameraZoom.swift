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

/// The lenses the row offers: **0.5 · 1× · 2×** (owner decision, 2026-11-08). 0.5× is the ultra-wide and is
/// hidden on a phone that does not have one; 1× is the wide lens's native framing; 2× is a lens stop or, where
/// there is no 2× lens, the wide lens zoomed in. The dial then runs on to 5×.
enum CameraZoomPreset: String, CaseIterable, Identifiable, Sendable {
    case half = "0.5x"
    case one = "1x"
    case two = "2x"

    var id: String { rawValue }
    var factor: CGFloat {
        switch self {
        case .half: return 0.5
        case .one: return 1
        case .two: return 2
        }
    }

    /// The handle a flow or a test taps for this lens.
    var accessibilityIdentifier: String { "camera.zoom.lens.\(rawValue)" }
}

enum CameraZoomPresets {
    /// The buttons the row draws for a range: 1× and 2× always, 0.5× only when the phone really has the
    /// ultra-wide (its range starts at 0.5).
    static func available(range: ClosedRange<CGFloat>) -> [CameraZoomPreset] {
        let presets = CameraZoomPreset.allCases.filter { range.contains($0.factor) }
        return presets.isEmpty ? [.one] : presets
    }

    /// The lens a factor belongs to: the nearest stop the row draws. A continuous 3.2× still reads as
    /// "the 2× button is current", with 3.2× written in it.
    static func nearest(to factor: CGFloat, in range: ClosedRange<CGFloat>) -> CameraZoomPreset {
        available(range: range).min { abs($0.factor - factor) < abs($1.factor - factor) } ?? .one
    }
}

/// What lenses this phone actually has, in **display** zoom space — what the row and the dial show.
///
/// The ultra-wide stop lives on the *virtual* multi-camera device, where `videoZoomFactor` 1.0 **is** the
/// ultra-wide and the wide lens sits at the first switch-over factor (2.0 on every iPhone): `deviceMultiplier`
/// is that mapping. Running the plain wide-angle device instead (build 26) cannot serve 0.5× at all, and mapping
/// a virtual device without it (build 26's fix) would put the UI's 1× at the ultra-wide's framing.
struct CameraLensProfile: Equatable {
    /// Display-space range: 0.5…5 on a phone with an ultra-wide, 1…5 on one without.
    var range: ClosedRange<CGFloat> = 1...CameraZoomScale.maxFactor
    /// Display → lens factor: 2 when `videoZoomFactor` 1.0 is the ultra-wide, 1 on a plain wide-angle lens.
    var deviceMultiplier: CGFloat = 1
    /// The device's own ceiling in `videoZoomFactor` terms, so the UI never asks for a factor the hardware
    /// refuses (`5×` is digital zoom, and even that has a limit).
    var deviceMaximum: CGFloat = 5

    /// The owner's "does this phone have 0.5×" question, answered from the lens range itself.
    var hasUltraWide: Bool { range.lowerBound <= 0.5 + 0.001 }
    /// The buttons the row draws.
    var presets: [CameraZoomPreset] { CameraZoomPresets.available(range: range) }

    /// No capture device (the simulator) or a plain wide-angle lens: 1×…5×, no 0.5 stop.
    static let wideOnly = CameraLensProfile()
}

extension CameraZoomScale {
    /// Display factor → the lens's own `videoZoomFactor`, clamped to the device's ceiling. The one place the two
    /// spaces are related, so the session and the UI cannot disagree about what "1×" means.
    static func lensFactor(forDisplay display: CGFloat, in profile: CameraLensProfile) -> CGFloat {
        let factor = display.isFinite ? max(display, 0) : 1
        let scaled = factor * (profile.deviceMultiplier > 0 ? profile.deviceMultiplier : 1)
        let ceiling = profile.deviceMaximum.isFinite ? max(profile.deviceMaximum, 1) : scaled
        return min(scaled, ceiling)
    }
}

/// Lens discovery: which device to run and what the UI may offer for it.
///
/// The virtual multi-camera devices are tried first, because they are the only ones that can serve 0.5×:
/// `builtInTripleCamera` (ultra-wide + wide + tele) then `builtInDualWideCamera` (ultra-wide + wide). A plain
/// `builtInWideAngleCamera` is the last stop, and it never claims an ultra-wide it does not have.
enum CameraLensDiscovery {
    /// The rules, pure: given the device's own numbers, what the UI may offer.
    ///
    /// `includesUltraWide` is a **device-type** fact, not a switch-over fact: a `builtInDualCamera` (wide + tele)
    /// also reports a switch-over factor of 2, and its 1.0 is the wide lens — mapping it as if it had an
    /// ultra-wide would offer a 0.5× the phone cannot shoot.
    static func profile(
        minimumVideoZoom: CGFloat,
        maximumVideoZoom: CGFloat,
        switchOverFactors: [CGFloat] = [],
        includesUltraWide: Bool
    ) -> CameraLensProfile {
        let switchOver = switchOverFactors.first { $0.isFinite && $0 > 0 }
        let multiplier = includesUltraWide ? (switchOver ?? 2) : 1
        let minZoom = minimumVideoZoom.isFinite ? minimumVideoZoom : 1
        let maxZoom = maximumVideoZoom.isFinite ? maximumVideoZoom : CameraZoomScale.maxFactor
        let low = minZoom / multiplier
        let high = maxZoom / multiplier
        return CameraLensProfile(
            range: CameraZoomScale.range(lower: low, upper: high),
            deviceMultiplier: multiplier,
            deviceMaximum: maxZoom
        )
    }

    /// A fallback for a process with no capture device at all: no ultra-wide is claimed.
    static let fallback = CameraLensProfile.wideOnly
}

/// The mapping between what the row and the dial show and what the lens receives, plus the labels.
///
/// The row shows **display** factors; the lens receives `display × deviceMultiplier` (see `CameraLensProfile`).
/// The display range is 0.5…5 where the phone has an ultra-wide and 1…5 where it does not; 5× is digital zoom,
/// so the same range serves a phone with a 2× or a 3× tele lens.
enum CameraZoomScale {
    /// The top of the dial. `CameraSessionBox.setZoomOnQueue` clamps the lens to the device's own ceiling as well,
    /// so the thumb can never sit where the hardware refuses to follow.
    static let maxFactor: CGFloat = 5
    static let sliderIdentifier = "camera.zoom.slider"

    /// The old pills' ids are retired with them; nothing may address them again.
    static let retiredIdentifiers = ["camera.zoom.0.5x", "camera.zoom.1x", "camera.zoom.2x", "camera.zoom.3x"]

    /// The usable range: the lens's own, floored at 0.5× (the ultra-wide) and capped at `maxFactor`, never
    /// inverted.
    static func range(lower: CGFloat, upper: CGFloat) -> ClosedRange<CGFloat> {
        let low = lower.isFinite ? max(lower, 0.5) : 1
        let high = upper.isFinite ? min(max(upper, low), maxFactor) : max(low, maxFactor)
        return low...max(low, high)
    }

    static func clamped(_ factor: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        guard factor.isFinite else { return range.lowerBound }
        return min(max(factor, range.lowerBound), range.upperBound)
    }

    /// Where a factor sits on the line, 0…1, and the way back. Pure, so the thumb's position is a unit test.
    static func fraction(of factor: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (clamped(factor, in: range) - range.lowerBound) / span
    }

    static func factor(atFraction fraction: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let clampedFraction = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        return clamped(range.lowerBound + clampedFraction * (range.upperBound - range.lowerBound), in: range)
    }

    /// The value in the thumb: "1×", "3.2×".
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
        thumbDiameter / 2 + trackWidth * CameraZoomScale.fraction(of: factor, in: range)
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
    var range: ClosedRange<CGFloat> = CameraLensProfile.wideOnly.range
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

    private var row: CameraZoomLensRow { CameraZoomLensRow(presets: CameraZoomPresets.available(range: range)) }
    private var selectedLens: CameraZoomPreset { CameraZoomPresets.nearest(to: factor, in: range) }

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
                    onChange(CameraZoomScale.clamped(factor + 0.5, in: range))
                case .decrement:
                    onChange(CameraZoomScale.clamped(factor - 0.5, in: range))
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
        return CameraZoomScale.factor(atFraction: fraction, in: range)
    }
}
