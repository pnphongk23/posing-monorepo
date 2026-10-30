import SwiftUI

/// Pressed appearance for the three control kinds in the artboard 06 state contract.
///
/// Pressed = one fill step plus `scale 0.97`; Reduce Motion keeps the fill step and drops the scale.
/// Disabled controls go flat on `controlFill` with the `disabled` label token, so an inactive control
/// never looks like a pressed one.
enum APButtonKind: CaseIterable {
    /// Primary action: pink fill, ink label (never white).
    case primary
    /// Secondary button: neutral `controlFill`, ink label.
    case secondary
    /// Chip: neutral `controlFill`, supporting type, hugs its label.
    case chip

    var restingFill: SwiftUI.Color {
        switch self {
        case .primary: return AP.Color.accent
        case .secondary, .chip: return AP.Color.controlFill
        }
    }

    var pressedFill: SwiftUI.Color {
        switch self {
        case .primary: return AP.Color.accentPressed
        case .secondary, .chip: return AP.Color.controlFillPressed
        }
    }

    var labelColor: SwiftUI.Color {
        switch self {
        case .primary: return AP.Color.onAccent
        case .secondary, .chip: return AP.Color.primaryText
        }
    }

    var font: SwiftUI.Font {
        switch self {
        case .primary, .secondary: return AP.Font.heading
        case .chip: return AP.Font.supporting
        }
    }

    var cornerRadius: CGFloat { AP.Radius.radius16 }

    var minimumHeight: CGFloat {
        switch self {
        case .primary, .secondary: return 48
        case .chip: return 36
        }
    }

    var expands: Bool { self != .chip }

    func fill(isPressed: Bool, isEnabled: Bool = true) -> SwiftUI.Color {
        guard isEnabled else { return AP.Color.controlFill }
        return isPressed ? pressedFill : restingFill
    }

    func labelColor(isEnabled: Bool) -> SwiftUI.Color {
        isEnabled ? labelColor : AP.Color.disabled
    }

    /// 0.97 while pressed; identity when the press is not active or when Reduce Motion is on.
    func scale(isPressed: Bool, reduceMotion: Bool) -> CGFloat {
        isPressed && !reduceMotion ? AP.Press.scale : 1
    }
}

/// Shared body for the three styles: one place owns type, radius, hit target and the press response.
struct APButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: APButtonKind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(kind.font)
            .foregroundStyle(kind.labelColor(isEnabled: isEnabled))
            .multilineTextAlignment(.center)
            // Labels wrap instead of truncating at the Accessibility sizes.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AP.Space.space16)
            .padding(.vertical, AP.Space.space8)
            .frame(maxWidth: kind.expands ? .infinity : nil, minHeight: kind.minimumHeight)
            .background(
                RoundedRectangle(cornerRadius: kind.cornerRadius, style: .continuous)
                    .fill(kind.fill(isPressed: configuration.isPressed, isEnabled: isEnabled))
            )
            .scaleEffect(kind.scale(isPressed: configuration.isPressed, reduceMotion: reduceMotion))
            .apMinimumHitTarget()
            .animation(
                reduceMotion ? nil : .easeOut(duration: AP.Press.duration),
                value: configuration.isPressed
            )
    }
}

/// Primary action: accent fill → `accentPressed` while pressed.
struct APPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        APButtonStyleBody(configuration: configuration, kind: .primary)
    }
}

/// Secondary button: `controlFill` → `controlFillPressed` while pressed.
struct APSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        APButtonStyleBody(configuration: configuration, kind: .secondary)
    }
}

/// Filter chip: neutral fill, supporting type, hugs its label.
struct APChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        APButtonStyleBody(configuration: configuration, kind: .chip)
    }
}
