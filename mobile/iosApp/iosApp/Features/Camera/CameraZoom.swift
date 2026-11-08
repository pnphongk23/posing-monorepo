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

/// Lens-aware zoom presets. The owner retained 0.5x behavior; a stop the active lens cannot serve is
/// not offered, and requests outside the device range are clamped.
enum CameraZoomPreset: String, CaseIterable, Identifiable, Sendable {
    case half = "0.5x"
    case one = "1x"
    case two = "2x"
    case three = "3x"

    var id: String { rawValue }
    var factor: CGFloat {
        switch self {
        case .half: return 0.5
        case .one: return 1
        case .two: return 2
        case .three: return 3
        }
    }

    /// The handle a flow or a test taps for this lens. Not a retired pill id: the lens row is the zoom
    /// control again, and each lens is its own button.
    var accessibilityIdentifier: String { "camera.zoom.lens.\(rawValue)" }
}

enum CameraZoomPresets {
    static func available(range: ClosedRange<CGFloat>) -> [CameraZoomPreset] {
        let presets = CameraZoomPreset.allCases.filter { range.contains($0.factor) }
        // 1x always exists: it is the lens's native framing even when a device reports a minimum of
        // exactly 1 (every iPhone does).
        return presets.isEmpty ? [.one] : presets
    }

    /// The lens a factor belongs to: the nearest stop the phone offers. It decides which button is
    /// highlighted, so a continuous 1.9× still reads as "the 2× lens is active".
    static func nearest(to factor: CGFloat, in range: ClosedRange<CGFloat>) -> CameraZoomPreset? {
        available(range: range).min { abs($0.factor - factor) < abs($1.factor - factor) }
    }
}

/// What lenses this phone actually has, in **display** zoom space — what the lens buttons and the dial show.
///
/// The distinction that was wrong in build 25: a plain `builtInWideAngleCamera` reports a minimum video zoom of
/// 1.0, so the slider could never offer 0.5× even on a phone whose system camera has it. The ultra-wide stop
/// lives on the *virtual* multi-camera device, where `videoZoomFactor` 1.0 is the ultra-wide and the wide lens
/// is at the first switch-over factor (2.0): `deviceMultiplier` is that mapping.
struct CameraLensProfile: Equatable {
    /// Display-space range: 0.5…5 on a phone with an ultra-wide, 1…5 on one without.
    var range: ClosedRange<CGFloat> = 1...2
    /// Display → lens factor: 2 when `videoZoomFactor` 1.0 *is* the ultra-wide (a virtual device that
    /// includes it), 1 on a plain wide-angle lens.
    var deviceMultiplier: CGFloat = 1

    /// The owner's "does this phone have 0.5×" question, answered from the lens range itself.
    var hasUltraWide: Bool { range.lowerBound <= 0.5 + 0.001 }
    var presets: [CameraZoomPreset] { CameraZoomPresets.available(range: range) }

    /// No capture device (the simulator) or a plain wide-angle lens: 1×…2×, no 0.5 stop offered.
    static let wideOnly = CameraLensProfile()
}

extension CameraZoomScale {
    /// Display factor → the lens's own `videoZoomFactor`. The one place the two spaces are related, so the
    /// session and the UI cannot disagree about what "0.5×" means.
    static func lensFactor(forDisplay display: CGFloat, in profile: CameraLensProfile) -> CGFloat {
        let factor = display.isFinite ? max(display, 0) : 1
        return factor * (profile.deviceMultiplier > 0 ? profile.deviceMultiplier : 1)
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
    /// `includesUltraWide` is a **device-type** fact, not a switch-over fact: a `builtInDualCamera`
    /// (wide + tele) also reports a switch-over factor of 2, and its 1.0 is the wide lens — mapping it as if it
    /// had an ultra-wide would offer a 0.5× the phone cannot shoot.
    static func profile(
        minimumVideoZoom: CGFloat,
        maximumVideoZoom: CGFloat,
        switchOverFactors: [CGFloat] = [],
        includesUltraWide: Bool
    ) -> CameraLensProfile {
        let switchOver = switchOverFactors.first { $0.isFinite && $0 > 0 }
        let multiplier = includesUltraWide ? (switchOver ?? 2) : 1
        let low = (minimumVideoZoom.isFinite ? minimumVideoZoom : 1) / multiplier
        let high = (maximumVideoZoom.isFinite ? maximumVideoZoom : 2) / multiplier
        return CameraLensProfile(
            range: CameraZoomScale.range(lower: low, upper: high),
            deviceMultiplier: multiplier
        )
    }

    /// A fallback for a process with no capture device at all: no ultra-wide is claimed.
    static let fallback = CameraLensProfile.wideOnly
}


/// The mapping between what the slider shows and what the lens receives, plus the labels and the ticks.
///
/// The camera drives one wide-angle device (`AVCaptureDevice.default(.builtInWideAngleCamera)`), so there is no
/// virtual device to switch between: the displayed factor **is** the lens's `videoZoomFactor`, clamped to the
/// range that lens reports and to the hardware ramp's ceiling. This type is that rule, so a phone whose lens
/// cannot reach 0.5× simply never draws a 0.5 tick, instead of a hard-coded list that lies about the hardware.
enum CameraZoomScale {
    /// The top of the slider and of the hardware ramp. `CameraSessionBox.setZoomOnQueue` clamps the lens to the
    /// same number, so the thumb can never sit where the hardware refuses to follow.
    static let maxFactor: CGFloat = 5
    static let sliderIdentifier = "camera.zoom.slider"

    /// The pill's own ids are retired with the pills; nothing may address them again.
    static let retiredIdentifiers = ["camera.zoom.0.5x", "camera.zoom.1x", "camera.zoom.2x", "camera.zoom.3x"]

    /// The usable range: the lens's own, capped at the ramp's ceiling and never inverted.
    static func range(lower: CGFloat, upper: CGFloat) -> ClosedRange<CGFloat> {
        let low = lower.isFinite ? max(lower, 0.5) : 1
        let high = upper.isFinite ? min(max(upper, low), maxFactor) : max(low, 2)
        return low...high
    }

    static func clamped(_ factor: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        guard factor.isFinite else { return range.lowerBound }
        return min(max(factor, range.lowerBound), range.upperBound)
    }

    /// Display factor → the lens's factor. The identity on this camera; the clamp is what makes a restored or
    /// dragged value safe.
    static func deviceFactor(forDisplay factor: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        clamped(factor, in: range)
    }

    /// The lens's factor → what the slider shows. The inverse of `deviceFactor(forDisplay:in:)`.
    static func displayFactor(forDevice factor: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        clamped(factor, in: range)
    }

    /// The stops the wall of ticks names: only the presets the lens can serve.
    static func ticks(in range: ClosedRange<CGFloat>) -> [CameraZoomPreset] {
        CameraZoomPresets.available(range: range)
    }

    /// Where a factor sits on the track, 0…1, and the way back. Pure, so the thumb's position is a unit test.
    static func fraction(of factor: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (clamped(factor, in: range) - range.lowerBound) / span
    }

    static func factor(atFraction fraction: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let clampedFraction = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        return clamped(range.lowerBound + clampedFraction * (range.upperBound - range.lowerBound), in: range)
    }

    /// The pill above the thumb: "1×", "0.5×", "2.5×".
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

/// The slider's own geometry, pure: where the thumb sits for a zoom value and whether a tick's label would repeat
/// the value shown in that thumb.
struct CameraZoomTrackGeometry: Equatable {
    let width: CGFloat
    let thumbDiameter: CGFloat
    let range: ClosedRange<CGFloat>

    /// Geometry for the dial and its value thumb.
    static let totalHeight: CGFloat = 44
    static let thumbDiameterConstant: CGFloat = 44
    static let thumbVisualHeight: CGFloat = 26
    static let markHeight: CGFloat = 5
    static let labelHeight: CGFloat = 12
    static let markToLabel: CGFloat = 2

    var trackWidth: CGFloat { max(width - thumbDiameter, 1) }

    /// Centre of the thumb for a zoom factor: the track's ends are the range's ends.
    func thumbCenterX(for factor: CGFloat) -> CGFloat {
        thumbDiameter / 2 + trackWidth * CameraZoomScale.fraction(of: factor, in: range)
    }

    /// Centre of the value thumb, kept inside the track at either extreme.
    func pillCenterX(for factor: CGFloat) -> CGFloat {
        let half = thumbDiameter / 2
        return min(max(thumbCenterX(for: factor), half), max(half, width - half))
    }

    var pillCenterY: CGFloat { Self.thumbVisualHeight / 2 }
    /// The track line and the thumb share one centre line, under the pill.
    var trackLineCenterY: CGFloat { Self.thumbVisualHeight / 2 }
    /// The top of a tick: its mark, then its label, clear of the thumb.
    var ticksTop: CGFloat { 18 }
    var tickCenterY: CGFloat { ticksTop + (Self.markHeight + Self.markToLabel + Self.labelHeight) / 2 }
    /// The minimum stop's label x.
    var minimumLabelX: CGFloat { thumbDiameter / 2 }

    /// Whether a tick's label is readable: it is hidden when the thumb already carries that value.
    func showsLabel(forFactor tick: CGFloat, thumbFactor: CGFloat) -> Bool {
        abs(thumbCenterX(for: tick) - thumbCenterX(for: thumbFactor)) > 14
    }
}

/// The dial's drawing: the track, a tick per reachable lens and the current value in a white thumb.
///
/// It owns **no gesture**. `CameraZoomControl` owns the drag, because the drag starts on the compact lens row
/// and has to keep tracking the same finger once the dial has opened — a child gesture mounted mid-drag would
/// never see it.
struct CameraZoomDial: View {
    let factor: CGFloat
    let range: ClosedRange<CGFloat>
    var isEnabled = true

    private let thumbSize: CGFloat = CameraZoomTrackGeometry.thumbDiameterConstant

    var body: some View {
        GeometryReader { proxy in
            let geometry = CameraZoomTrackGeometry(width: proxy.size.width, thumbDiameter: thumbSize, range: range)
            ZStack(alignment: .topLeading) {
                trackLine(geometry)
                tickMarks(geometry)
                valuePill(geometry)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(height: CameraZoomTrackGeometry.totalHeight)
        .opacity(isEnabled ? 1 : 0.45)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The value in the white thumb: it follows the lens, so the number and handle stay together.
    private func valuePill(_ geometry: CameraZoomTrackGeometry) -> some View {
        Text(CameraZoomScale.valueLabel(factor))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.88))
            .frame(width: thumbSize, height: CameraZoomTrackGeometry.thumbVisualHeight)
            .background(Capsule().fill(Color.white))
            .position(x: geometry.pillCenterX(for: factor), y: geometry.pillCenterY)
    }

    private func trackLine(_ geometry: CameraZoomTrackGeometry) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.4))
            .frame(width: geometry.trackWidth, height: 2)
            .position(x: geometry.width / 2, y: geometry.trackLineCenterY)
    }

    /// A tick per preset the lens serves, with its label under the track. The label under the thumb is dropped:
    /// the value thumb already says that value.
    private func tickMarks(_ geometry: CameraZoomTrackGeometry) -> some View {
        ForEach(CameraZoomScale.ticks(in: range)) { preset in
            VStack(spacing: 2) {
                Rectangle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 1, height: 6)
                if geometry.showsLabel(forFactor: preset.factor, thumbFactor: factor) {
                    Text(CameraZoomScale.valueLabel(preset.factor))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .fixedSize()
                }
            }
            .frame(width: 44)
            .position(x: geometry.thumbCenterX(for: preset.factor), y: geometry.tickCenterY)
        }
    }
}

/// A standalone continuous zoom control: drag continuously or tap for the nearest preset, and VoiceOver gets
/// the same control as one adjustable element. `CameraZoomControl` reuses the dial inside the lens row.
struct CameraZoomSlider: View {
    let factor: CGFloat
    let range: ClosedRange<CGFloat>
    var isEnabled = true
    let onChange: (CGFloat) -> Void

    private let thumbSize: CGFloat = CameraZoomTrackGeometry.thumbDiameterConstant

    var body: some View {
        GeometryReader { proxy in
            let geometry = CameraZoomTrackGeometry(width: proxy.size.width, thumbDiameter: thumbSize, range: range)
            CameraZoomDial(factor: factor, range: range, isEnabled: isEnabled)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isEnabled else { return }
                            onChange(CameraZoomScale.factor(atFraction: tappedFraction(value.location.x, geometry), in: range))
                        }
                        .onEnded { value in
                            guard isEnabled,
                                  abs(value.translation.width) < 5,
                                  abs(value.translation.height) < 5
                            else { return }
                            let tapped = CameraZoomScale.factor(atFraction: tappedFraction(value.location.x, geometry), in: range)
                            if let nearestStop = CameraZoomPresets.nearest(to: tapped, in: range) {
                                onChange(nearestStop.factor)
                            }
                        }
                )
        }
        .frame(height: CameraZoomTrackGeometry.totalHeight)
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

    private func tappedFraction(_ x: CGFloat, _ geometry: CameraZoomTrackGeometry) -> CGFloat {
        (x - thumbSize / 2) / geometry.trackWidth
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

/// The zoom control: compact lens buttons by default (0.5 / 1× / 2× / 3× depending on the phone), the current
/// one highlighted and carrying the live value. Tap a lens to jump to it; **drag** to expand the same row into
/// the dial, which collapses about a second after the finger lifts.
struct CameraZoomControl: View {
    let factor: CGFloat
    let range: ClosedRange<CGFloat>
    var isEnabled = true
    let onChange: (CGFloat) -> Void

    @State private var bar: CameraZoomBarState
    @State private var pendingCollapse: Task<Void, Never>?
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
        _bar = State(initialValue: CameraZoomBarState(mode: initialMode))
    }

    private var presets: [CameraZoomPreset] { CameraZoomPresets.available(range: range) }
    private var row: CameraZoomLensRow { CameraZoomLensRow(presets: presets) }
    private var selectedLens: CameraZoomPreset? { CameraZoomPresets.nearest(to: factor, in: range) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Both presentations stay mounted and only one is shown: swapping the content out would replace the
            // view the drag is attached to, which cancels the gesture mid-drag (the dial then never hears its
            // release and stays open forever — found on the simulator, iPhone 16 lane).
            ZStack(alignment: .leading) {
                lensRow
                    .background(CameraGlassBackground(shape: .capsule))
                    .frame(height: CameraZoomLensRow.visualHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(bar.mode == .lenses ? 1 : 0)
                    .accessibilityHidden(bar.mode != .lenses)

                dial(width: width)
                    .opacity(bar.mode == .dial ? 1 : 0)
                    .accessibilityHidden(bar.mode != .dial)
            }
            .frame(width: width, height: CameraZoomLensRow.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(zoomGesture(width: width), including: isEnabled ? .all : .none)
        }
        .frame(height: CameraZoomLensRow.height)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: bar.mode)
        .accessibilityElement(children: .contain)
        .onDisappear { pendingCollapse?.cancel() }
    }

    /// The dial: the drawing plus the one adjustable element VoiceOver gets while it is up.
    private func dial(width: CGFloat) -> some View {
        CameraZoomDial(factor: factor, range: range, isEnabled: isEnabled)
            .frame(width: width)
            .background(CameraGlassBackground(shape: .capsule))
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
                pendingCollapse?.cancel()
                guard bar.dragChanged(translation: value.translation) == .dial else { return }
                onChange(factor(atX: value.location.x, width: width))
            }
            .onEnded { value in
                guard isEnabled else { return }
                if bar.dragEnded(translation: value.translation) {
                    scheduleCollapse()
                    return
                }
                switch bar.mode {
                case .lenses:
                    // A tap: jump to the lens under the finger. To the right of the compact row there is no
                    // button (the row hugs its content, the Poses chip owns the rest), so nothing happens there.
                    if value.location.x <= row.width, let preset = row.preset(atX: value.location.x) {
                        onChange(preset.factor)
                    }
                case .dial:
                    // A tap on an open dial snaps to the nearest lens and starts the collapse timer.
                    if let preset = CameraZoomPresets.nearest(to: factor(atX: value.location.x, width: width), in: range) {
                        onChange(preset.factor)
                    }
                    scheduleCollapse()
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

    private func scheduleCollapse() {
        pendingCollapse?.cancel()
        pendingCollapse = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(CameraZoomBarState.collapseDelaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            bar.collapse()
        }
    }
}
