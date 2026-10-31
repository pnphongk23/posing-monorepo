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

    /// Only the enabled primary action is raised (E1). A disabled control goes flat, so it never
    /// reads as tappable; secondary buttons and chips are E0 by design.
    func usesElevation(isEnabled: Bool) -> Bool {
        self == .primary && isEnabled
    }
}

/// Shared body for the three styles: one place owns type, radius, hit target and the press response.
struct APButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: APButtonKind
    /// Overrides the kind's minimum height, so a caller can make the *painted* control taller instead
    /// of wrapping it in transparent space.
    var minimumHeight: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if kind.usesElevation(isEnabled: isEnabled) {
                control.apElevation(.e1, cornerRadius: kind.cornerRadius)
            } else {
                control
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: AP.Press.duration),
            value: configuration.isPressed
        )
    }

    private var control: some View {
        configuration.label
            .font(kind.font)
            .foregroundStyle(kind.labelColor(isEnabled: isEnabled))
            .multilineTextAlignment(.center)
            // Labels wrap instead of truncating at the Accessibility sizes.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AP.Space.space16)
            .padding(.vertical, AP.Space.space8)
            .frame(maxWidth: kind.expands ? .infinity : nil, minHeight: minimumHeight ?? kind.minimumHeight)
            .background(
                RoundedRectangle(cornerRadius: kind.cornerRadius, style: .continuous)
                    .fill(kind.fill(isPressed: configuration.isPressed, isEnabled: isEnabled))
            )
            .scaleEffect(kind.scale(isPressed: configuration.isPressed, reduceMotion: reduceMotion))
            .apMinimumHitTarget()
    }
}

/// Primary action: accent fill → `accentPressed` while pressed.
struct APPrimaryButtonStyle: ButtonStyle {
    /// Painted height of the control; `nil` keeps the kind's own minimum.
    var minimumHeight: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        APButtonStyleBody(configuration: configuration, kind: .primary, minimumHeight: minimumHeight)
    }
}

/// Secondary button: `controlFill` → `controlFillPressed` while pressed.
struct APSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        APButtonStyleBody(configuration: configuration, kind: .secondary)
    }
}

/// Picks a style from an `APButtonKind`, so a caller can state the kind once (state panels do).
struct APButtonStyleForKind: ButtonStyle {
    let kind: APButtonKind

    func makeBody(configuration: Configuration) -> some View {
        APButtonStyleBody(configuration: configuration, kind: kind)
    }
}

/// Filter chip: neutral fill, supporting type, hugs its label.
struct APChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        APButtonStyleBody(configuration: configuration, kind: .chip)
    }
}
