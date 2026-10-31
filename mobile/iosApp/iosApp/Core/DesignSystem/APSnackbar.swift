// Owner feedback F5: a snackbar sits at the BOTTOM of the screen, directly above the bottom bar, the
// dock or a pinned CTA — never mid-screen. One component, one placement helper.

import SwiftUI

struct APSnackbar: View {
    var tone: APStateTone = .error
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: AP.Space.space12) {
            Image(systemName: tone.glyph)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tone.glyphColor)
                .accessibilityHidden(true)
            Text(message)
                .font(AP.Font.supporting)
                .foregroundStyle(AP.Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(AP.Font.supporting.weight(.semibold))
                    .foregroundStyle(AP.Color.accentText)
                    .apMinimumHitTarget()
            }
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.vertical, AP.Space.space12)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.surface)
        )
        .apElevation(.e1, cornerRadius: AP.Radius.radius16)
        .accessibilityElement(children: action == nil ? .combine : .contain)
        .accessibilityLabel(message)
        .onTapGesture { onDismiss?() }
    }
}

extension View {
    /// Pins a snackbar to the bottom, above whatever bottom chrome the surface has: a `.safeAreaInset`
    /// rides above the dock and above a pinned CTA, and it never covers content.
    @ViewBuilder
    func apSnackbar(
        _ message: String?,
        tone: APStateTone = .error,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if let message, !message.isEmpty {
                APSnackbar(
                    tone: tone,
                    message: message,
                    actionTitle: actionTitle,
                    action: action,
                    onDismiss: onDismiss
                )
                .padding(.horizontal, AP.Space.space16)
                .padding(.bottom, AP.Space.space12)
            }
        }
    }
}
