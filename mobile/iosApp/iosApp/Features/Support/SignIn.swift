import SwiftUI

/// Account-scoped entry points that may interrupt the user with the shared sign-in prompt.
/// Copy matrix from the prototype `scripts/sign-in-prompt.js` (`intent=saved|save|try|account`).
enum SignInIntent: String, Equatable, Sendable, CaseIterable {
    case openSaved, savePose, tryPose, openAccount

    var promptCopy: String {
        switch self {
        case .openSaved: return "View your saved poses."
        case .savePose: return "Save this pose."
        case .tryPose: return "Try this pose."
        case .openAccount: return "Manage your account."
        }
    }
}

/// Error → copy mapping. Never invents a message for an error that already describes itself,
/// and never returns the `NSError`-shaped "The operation couldn't be completed…" fallback when
/// the error is silent (callers supply their own context-appropriate default).
enum ErrorCopy {
    static func text(for error: Error) -> String? {
        if let apiError = error as? PoseAPIError { return apiError.message }
        // `URLError` is the common offline/timeout case and its own description is the best copy
        // available ("The request timed out.").
        if let urlError = error as? URLError { return urlError.localizedDescription }
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        // Deliberately no `localizedDescription` fallback: for a plain Swift error that is the
        // narration "The operation couldn't be completed. (… error 1.)", which is worse than the
        // caller's own context-appropriate default.
        return nil
    }
}

/// `sign-in-prompt.html` failed sign-in state (report §3.8): the shared error card with its
/// `Try again` action retrying the handoff. Pure and testable.
enum SignInPromptStateCopy {
    static let failureTitle = "Sign-in failed"
    static let failureMessage = "Try again to continue."
    static let failureActionTitle = "Try again"
}

/// The single "start Google sign-in" seam.
///
/// Every caller (Account screen, paywall, shared prompt) goes through this so they all report
/// the same real launcher outcomes. `OAuthHandoff` persists the session through
/// `SessionBoundary`, so success here always means credentials actually landed.
@MainActor
struct SignInAction {
    typealias Starter = @MainActor () async throws -> Void

    enum Outcome: Equatable {
        case succeeded
        /// The web sheet was dismissed. Not an error: nothing changed, nothing to report.
        case cancelled
        case failed(String)
    }

    private let start: Starter

    init(start: @escaping Starter = { try await OAuthHandoff().start() }) {
        self.start = start
    }

    func run() async -> Outcome {
        do {
            try await start()
            return .succeeded
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(ErrorCopy.text(for: error) ?? "Sign-in could not be completed.")
        }
    }
}

/// Owns one sign-in attempt's in-flight state and truthful error. Which intent is being resumed
/// belongs to the presenter (its `Binding<SignInIntent?>` *is* the single-use store), so a stale
/// intent can never replay on a later screen.
@MainActor
final class SignInPromptModel: ObservableObject {
    @Published private(set) var isAuthenticating = false
    @Published private(set) var error: String?

    private let signInAction: SignInAction

    init(signInAction: SignInAction = SignInAction()) {
        self.signInAction = signInAction
    }

    /// Runs the real handoff. `true` only for a real launcher success.
    func continueWithGoogle() async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        error = nil
        defer { isAuthenticating = false }

        switch await signInAction.run() {
        case .succeeded:
            return true
        case .cancelled:
            return false
        case .failed(let text):
            error = text
            return false
        }
    }

    func clearError() {
        guard error != nil else { return }
        error = nil
    }
}

/// The one "Continue with Google" control. Every surface that can start the handoff shares it, so
/// the spinner, the disabled state and the accessibility label cannot drift apart.
struct ContinueWithGoogleButton: View {
    let isAuthenticating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AIPoseSpacing.sm) {
                if isAuthenticating {
                    ProgressView().tint(AIPoseColor.foreground)
                }
                Text(isAuthenticating ? "Signing in…" : "Continue with Google")
            }
        }
        .buttonStyle(NeoButtonStyle())
        .disabled(isAuthenticating)
        .accessibilityLabel(isAuthenticating ? "Signing in" : "Continue with Google")
    }
}

/// Shared modal sign-in prompt (prototype `screens/sign-in-prompt.html`): one primary
/// `Continue with Google`, one secondary `Not now`, and an inline error region.
struct SignInPromptView: View {
    @ObservedObject var model: SignInPromptModel
    let intent: SignInIntent
    let onResolved: (SignInIntent) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { dismiss() }
            VStack(alignment: .leading, spacing: AIPoseSpacing.md) {
                Text("Sign in").font(.title3.bold())
                Text(intent.promptCopy)
                    .font(.subheadline)
                    .foregroundStyle(AIPoseColor.subtext)
                    .fixedSize(horizontal: false, vertical: true)
                if model.error != nil {
                    // §3.8: the shared error card replaces the old plain error Text. The frozen
                    // copy is fixed; the launcher's specific error text is not displayed (its
                    // truthfulness contract lives on surfaces not covered by this card).
                    FeatureStateView(
                        tone: .error,
                        title: SignInPromptStateCopy.failureTitle,
                        message: SignInPromptStateCopy.failureMessage,
                        actionTitle: SignInPromptStateCopy.failureActionTitle
                    ) {
                        Task { await continueWithGoogle() }
                    }
                    .accessibilityIdentifier("sign-in.retry")
                }
                ContinueWithGoogleButton(isAuthenticating: model.isAuthenticating) {
                    Task { await continueWithGoogle() }
                }

                Button("Not now") { dismiss() }
                    .buttonStyle(NeoButtonStyle(fill: AIPoseColor.surface))
                    .disabled(model.isAuthenticating)
                    .accessibilityLabel("Not now")
            }
            .padding(AIPoseSpacing.xl)
            .background(AIPoseColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AIPoseColor.foreground, lineWidth: 2))
            .shadow(color: AIPoseColor.foreground, radius: 0, x: 4, y: 4)
            .padding(AIPoseSpacing.xl)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { model.clearError() }
    }

    private func continueWithGoogle() async {
        if await model.continueWithGoogle() {
            onResolved(intent)
        }
    }

    /// "Not now" and tap-outside cancel without side effects.
    private func dismiss() {
        guard !model.isAuthenticating else { return }
        onDismiss()
    }
}

/// Presents the shared prompt over any screen. `intent` is set by the gated entry point and
/// cleared as soon as the interaction ends (success, "Not now", or tap-outside).
private struct SignInPromptModifier: ViewModifier {
    @Binding var intent: SignInIntent?
    @StateObject private var model = SignInPromptModel()
    let onResolved: (SignInIntent) -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if let intent {
                SignInPromptView(
                    model: model,
                    intent: intent,
                    onResolved: { resolved in
                        self.intent = nil
                        onResolved(resolved)
                    },
                    onDismiss: { self.intent = nil }
                )
            }
        }
    }
}

extension View {
    /// - Parameter onResolved: called exactly once, only after a real sign-in success, with the
    ///   intent that was interrupted — the point to resume the original action.
    func signInPrompt(
        _ intent: Binding<SignInIntent?>,
        onResolved: @escaping (SignInIntent) -> Void = { _ in }
    ) -> some View {
        modifier(SignInPromptModifier(intent: intent, onResolved: onResolved))
    }
}
