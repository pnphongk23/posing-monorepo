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

/// Lens-aware zoom presets (`05-01`/`05-21`: 0.5x / 1x / 2x). A preset the lens cannot serve is not
/// offered at all, and a request outside the device's range is clamped instead of failing silently.
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
}

enum CameraZoomPresets {
    static func available(range: ClosedRange<CGFloat>) -> [CameraZoomPreset] {
        let presets = CameraZoomPreset.allCases.filter { range.contains($0.factor) }
        // 1x always exists: it is the lens's native framing even when a device reports a minimum of
        // exactly 1 (every iPhone does).
        return presets.isEmpty ? [.one] : presets
    }
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

/// The slider's own geometry, pure: where the thumb sits for a zoom value, where the value pill sits, and whether a
/// tick's label would repeat what the pill already says. The board's control is the reference: a light thumb on the
/// track and the accent pill directly above it, kept inside the track at the ends.
struct CameraZoomTrackGeometry: Equatable {
    let width: CGFloat
    let thumbDiameter: CGFloat
    let range: ClosedRange<CGFloat>

    /// The pill's row, the gap under it, the thumb's row, and the ticks with their labels under the track.
    static let pillHeight: CGFloat = 22
    static let pillToTrack: CGFloat = 4
    static let thumbDiameterConstant: CGFloat = 22
    static let markHeight: CGFloat = 6
    static let labelHeight: CGFloat = 11
    static let markToLabel: CGFloat = 2
    static var totalHeight: CGFloat {
        pillHeight + pillToTrack + thumbDiameterConstant + 2 + markHeight + markToLabel + labelHeight
    }

    var trackWidth: CGFloat { max(width - thumbDiameter, 1) }

    /// Centre of the thumb for a zoom factor: the track's ends are the range's ends.
    func thumbCenterX(for factor: CGFloat) -> CGFloat {
        thumbDiameter / 2 + trackWidth * CameraZoomScale.fraction(of: factor, in: range)
    }

    /// Centre of the pill: over the thumb, pushed inside the track at the extremes so it never hangs off.
    func pillCenterX(for factor: CGFloat) -> CGFloat {
        let half = Self.pillHeight / 2 + 8
        return min(max(thumbCenterX(for: factor), half), max(half, width - half))
    }

    var pillCenterY: CGFloat { Self.pillHeight / 2 }
    /// The track line and the thumb share one centre line, under the pill.
    var trackLineCenterY: CGFloat { Self.pillHeight + Self.pillToTrack + thumbDiameter / 2 }
    /// The top of a tick: its mark, then its label, clear of the thumb.
    var ticksTop: CGFloat { trackLineCenterY + thumbDiameter / 2 + 2 }
    var tickCenterY: CGFloat { ticksTop + (Self.markHeight + Self.markToLabel + Self.labelHeight) / 2 }
    /// The minimum stop's label x, to prove the labels survive where the pill does not cover them.
    var minimumLabelX: CGFloat { thumbDiameter / 2 }

    /// Whether a tick's label is readable: it is dropped where the pill already carries that value.
    func showsLabel(forFactor tick: CGFloat, thumbFactor: CGFloat) -> Bool {
        abs(thumbCenterX(for: tick) - thumbCenterX(for: thumbFactor)) > 14
    }
}

/// The continuous zoom control: a light thumb on a thin track, a tick and a label per preset the lens serves, and
/// the zoom value in an accent pill above the thumb that follows it. Drag or tap anywhere on the track; VoiceOver
/// gets the same control as one adjustable element.
struct CameraZoomSlider: View {
    let factor: CGFloat
    let range: ClosedRange<CGFloat>
    var isEnabled = true
    let onChange: (CGFloat) -> Void

    private let thumbSize: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let geometry = CameraZoomTrackGeometry(width: proxy.size.width, thumbDiameter: thumbSize, range: range)
            ZStack(alignment: .topLeading) {
                valuePill(geometry)
                trackLine(geometry)
                tickMarks(geometry)
                thumb(geometry)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        let fraction = (value.location.x - thumbSize / 2) / geometry.trackWidth
                        onChange(CameraZoomScale.factor(atFraction: fraction, in: range))
                    }
            )
        }
        .frame(height: CameraZoomTrackGeometry.totalHeight)
        .opacity(isEnabled ? 1 : 0.45)
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

    /// The value, in the accent pill over the thumb (the board's pink "1×"): it follows the thumb, so the number
    /// and the handle are never read from two different places.
    private func valuePill(_ geometry: CameraZoomTrackGeometry) -> some View {
        Text(CameraZoomScale.valueLabel(factor))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AP.Color.onAccent)
            .padding(.horizontal, AP.Space.space8)
            .frame(minHeight: CameraZoomTrackGeometry.pillHeight)
            .background(Capsule().fill(AP.Color.accent))
            .fixedSize()
            .position(x: geometry.pillCenterX(for: factor), y: CameraZoomTrackGeometry.pillHeight / 2)
            .accessibilityHidden(true)
    }

    private func trackLine(_ geometry: CameraZoomTrackGeometry) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.4))
            .frame(width: geometry.trackWidth, height: 2)
            .position(x: geometry.width / 2, y: geometry.trackLineCenterY)
            .allowsHitTesting(false)
    }

    private func thumb(_ geometry: CameraZoomTrackGeometry) -> some View {
        Circle()
            .fill(AP.Color.primaryText)
            .frame(width: thumbSize, height: thumbSize)
            .position(x: geometry.thumbCenterX(for: factor), y: geometry.trackLineCenterY)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .allowsHitTesting(false)
    }

    /// A tick per preset the lens serves, with its label under the track. The label under the thumb is dropped:
    /// the pill above already says that value.
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
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
