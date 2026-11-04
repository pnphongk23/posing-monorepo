import Foundation
import SwiftUI

/// Prototype scale-factor stops (`nb-camera-zoom-slider`, values 0…2 → 1x…3x).
enum CameraZoomLevel: Int, CaseIterable, Equatable {
    case one = 1, two = 2, three = 3

    var label: String { "\(rawValue)x" }
    var factor: CGFloat { CGFloat(rawValue) }

    func next() -> CameraZoomLevel {
        let all = CameraZoomLevel.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
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

    var id: String { rawValue }
    var factor: CGFloat {
        switch self {
        case .half: return 0.5
        case .one: return 1
        case .two: return 2
        }
    }
    var accessibilityIdentifier: String { "camera.zoom.\(rawValue)" }
}

enum CameraZoomPresets {
    static func available(range: ClosedRange<CGFloat>) -> [CameraZoomPreset] {
        let presets = CameraZoomPreset.allCases.filter { range.contains($0.factor) }
        // 1x always exists: it is the lens's native framing even when a device reports a minimum of
        // exactly 1 (every iPhone does).
        return presets.isEmpty ? [.one] : presets
    }

    static func clamp(_ factor: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        guard factor.isFinite else { return 1 }
        return min(max(factor, range.lowerBound), range.upperBound)
    }

    /// The preset closest to a factor, so a clamped or restored value still lights up a choice.
    static func nearest(to factor: CGFloat, range: ClosedRange<CGFloat>) -> CameraZoomPreset? {
        available(range: range).min { abs($0.factor - factor) < abs($1.factor - factor) }
    }
}

