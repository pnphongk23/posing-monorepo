// Owner feedback F5: a snackbar sits at the BOTTOM of the screen, directly above the bottom bar, the
// dock or a pinned CTA — never mid-screen. One component, one placement helper.

import SwiftUI

/// The accessibility ids a snackbar can expose to a UI test: one for the bar, one for its action.
///
/// The bar's copy is code-owned and carries a name ("Removed <pose>"), so a flow that reads it by
/// text has to know the name *and* catch it inside the four-second window. The Saved removal bar is
/// the only one a flow has to address without reading that copy, so its ids are named where the
/// flows name them — and the action's id is the action's, never the bar's.
struct APSnackbarIdentifiers: Equatable {
    /// The bar itself.
    var bar: String
    /// The bar's action control, when it has one.
    var action: String?

    /// `saved.snackbar` / `saved.snackbar.undo`: the Saved surface's removal and its Undo offer.
    static let saved = APSnackbarIdentifiers(bar: "saved.snackbar", action: "saved.snackbar.undo")
}

struct APSnackbar: View {
    /// How long a snackbar stays before it dismisses itself (F5: it never parks on screen).
    static let autoDismissDelay: TimeInterval = 4

    var tone: APStateTone = .error
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?
    /// Ids for the flows that have to find this bar; `nil` keeps a label-only bar, which is what the
    /// surfaces without a flow of their own still use.
    var identifiers: APSnackbarIdentifiers?
    /// Overridable so a test does not have to wait four seconds.
    var autoDismissAfter: TimeInterval = APSnackbar.autoDismissDelay

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
                    .apIdentifier(identifiers?.action)
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
        .apIdentifier(identifiers?.bar)
        .onTapGesture { onDismiss?() }
        // Announced once, then dismissed: the task id is the message, so a new snackbar restarts the
        // clock and a disappearing one cancels it.
        .task(id: message) {
            UIAccessibility.post(notification: .announcement, argument: message)
            guard autoDismissAfter > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(autoDismissAfter * 1_000_000_000))
            guard !Task.isCancelled else { return }
            onDismiss?()
        }
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
        onDismiss: (() -> Void)? = nil,
        identifiers: APSnackbarIdentifiers? = nil
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if let message, !message.isEmpty {
                APSnackbar(
                    tone: tone,
                    message: message,
                    actionTitle: actionTitle,
                    action: action,
                    onDismiss: onDismiss,
                    identifiers: identifiers
                )
                .padding(.horizontal, AP.Space.space16)
                .padding(.bottom, AP.Space.space12)
            }
        }
    }
}
