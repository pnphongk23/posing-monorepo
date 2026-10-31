// Owner feedback F2: one back button everywhere — 44 pt hit target, rounded square, radius 16. Only
// the fill changes over imagery (surface instead of controlFill) so it stays legible on a photo.

import SwiftUI

enum APBackButtonStyle {
    /// On a plain page: the neutral `controlFill` control.
    case control
    /// Over imagery (the pose detail hero): `surface` plus E1, so it separates from the photo.
    case overlay

    var fill: SwiftUI.Color {
        switch self {
        case .control: return AP.Color.controlFill
        case .overlay: return AP.Color.surface
        }
    }
}

struct APBackButton: View {
    var style: APBackButtonStyle = .control
    var accessibilityLabel: String = "Back"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AP.Color.primaryText)
                .frame(width: AP.HitTarget.minimum, height: AP.HitTarget.minimum)
                .background(
                    RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                        .fill(style.fill)
                )
                .apElevation(style == .overlay ? .e1 : .e0, cornerRadius: AP.Radius.radius16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
