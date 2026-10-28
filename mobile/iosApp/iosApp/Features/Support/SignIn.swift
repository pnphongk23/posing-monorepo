import SwiftUI

/// Account-scoped entry points that may interrupt the user with the shared sign-in prompt.
/// Copy matrix from the prototype `scripts/sign-in-prompt.js` (`intent=saved|save|try|account`).
enum SignInIntent: String, Equatable, Sendable, CaseIterable {
    case openSaved, savePose, tryPose, openAccount, addPose, openJobs

    var promptCopy: String {
        switch self {
        case .openSaved: return "View your saved poses."
        case .savePose: return "Save this pose."
        case .tryPose: return "Try this pose."
        case .openAccount: return "Manage your account."
        case .addPose: return "Add your own pose."
        case .openJobs: return "See your pose jobs."
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

/// Email/password sign-in error → copy matrix (PLAN §4, DESIGN §5). Contracted codes get frozen
/// copy (one message for unknown email and wrong password — anti-enumeration); everything else
/// falls through to the shared `ErrorCopy` rules.
enum AuthErrorCopy {
    static let invalidCredentials = "Incorrect email or password."
    static let emailNotConfirmed = "Confirm your email address."
    static let rateLimited = "Too many attempts. Try again in a few minutes."

    static func text(for error: Error, fallback: String) -> String {
        if let apiError = error as? PoseAPIError {
            switch apiError.code {
            case "INVALID_CREDENTIALS": return invalidCredentials
            case "EMAIL_NOT_CONFIRMED": return emailNotConfirmed
            case "RATE_LIMITED": return rateLimited
            default: break
            }
        }
        return ErrorCopy.text(for: error) ?? fallback
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

/// Custom control is intentional here so the app's neo-brutalist surfaces remain consistent while
/// the action itself still runs `ASAuthorizationAppleIDProvider` through the injected seam.
///
/// The label colour is passed **into** the style (`NeoButtonStyle(foreground:)`), not applied to the
/// button from outside: `ButtonStyle.makeBody` sets the label's `foregroundStyle` itself, so an
/// outer `.foregroundStyle(...)` can never win. The shipped build applied it outside against a
/// `fill: AIPoseColor.foreground` (near-black) fill, so the black logo + wordmark were painted
/// black-on-black and QA saw an empty box (BUG-261029-02).
struct ContinueWithAppleButton: View {
    let isAuthenticating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AIPoseSpacing.sm) {
                if isAuthenticating { ProgressView().tint(AppleSignInCopy.labelColor) }
                Image(systemName: "apple.logo")
                Text(isAuthenticating ? AppleSignInCopy.pendingTitle : AppleSignInCopy.title)
            }
            // No local `minHeight`/`frame`: the shared style already stretches to full width and pads
            // to a ≥44pt target, so the Apple control keeps the exact height of the Google button
            // beside it (the old inner 44pt minimum made it visibly taller).
            .contentShape(Rectangle())
        }
        .buttonStyle(NeoButtonStyle(fill: AppleSignInCopy.fillColor, foreground: AppleSignInCopy.labelColor))
        .disabled(isAuthenticating)
        .accessibilityLabel(isAuthenticating ? AppleSignInCopy.pendingAccessibilityLabel : AppleSignInCopy.title)
    }
}

/// The Apple control's frozen surface and copy: HIG requires the system wordmark next to the logo,
/// so QA can assert both the identifier and the label verbatim.
enum AppleSignInCopy {
    static let title = "Sign in with Apple"
    static let pendingTitle = "Signing in…"
    static let pendingAccessibilityLabel = "Signing in"
    /// `account.signin.apple` (accessibility identifier convention `<screen>.<element>`).
    static let identifier = "account.signin.apple"
    /// HIG: the Apple button is black with a white logo and wordmark.
    static let fillColor = AIPoseColor.foreground
    static let labelColor = AIPoseColor.surface

    /// True when the glyph/text colour is actually visible against the fill. The shipped bug was
    /// precisely `fill == label`; a test asserts this so the pair cannot silently collapse again.
    static var hasVisibleContrast: Bool { labelColor != fillColor }
}

/// Shared modal sign-in prompt (prototype `screens/sign-in-prompt.html`): one primary
/// `Continue with Google`, one secondary `Not now`, and an inline error region.
struct SignInPromptView: View {
    @ObservedObject var model: SignInPromptModel
    @ObservedObject var appleModel: AppleSignInModel
    /// The presenter's email-attempt state (S4): the prompt is mounted from an `if let intent`
    /// branch, so it can unmount mid-attempt — the attempt's outcome has to outlive it.
    @ObservedObject var emailModel: EmailSignInModel
    let intent: SignInIntent
    let onResolved: (SignInIntent) -> Void
    let onDismiss: () -> Void
    @State private var showsEmailSignIn = false

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
                  ContinueWithGoogleButton(isAuthenticating: model.isAuthenticating || appleModel.isAuthenticating) {
                      Task { await continueWithGoogle() }
                  }
                  ContinueWithAppleButton(isAuthenticating: model.isAuthenticating || appleModel.isAuthenticating) {
                      Task { await continueWithApple() }
                  }
                  .accessibilityIdentifier("signin.apple")
                  if let error = appleModel.error {
                      Text(error)
                          .font(.footnote.weight(.semibold))
                          .foregroundStyle(AIPoseColor.error)
                          .fixedSize(horizontal: false, vertical: true)
                          .accessibilityLabel("Sign-in failed. \(error)")
                  }

                // Email is a peer of Google, never a replacement (DESIGN §3): opening the sheet
                // does not consume the intent — only a real success resolves it.
                Button { showsEmailSignIn = true } label: {
                    Text("Sign in with email")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AIPoseColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                  .disabled(model.isAuthenticating || appleModel.isAuthenticating)
                .accessibilityIdentifier("signin.emailEntry")
                .accessibilityLabel("Sign in with email")

                Button("Not now") { dismiss() }
                    .buttonStyle(NeoButtonStyle(fill: AIPoseColor.surface))
                  .disabled(model.isAuthenticating || appleModel.isAuthenticating)
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
        .emailSignInSheet(model: emailModel, isPresented: $showsEmailSignIn, intentLine: intent.promptCopy) {
            onResolved(intent)
        }
          .onAppear {
              model.clearError()
              appleModel.clearError()
          }
    }

      private func continueWithGoogle() async {
          guard !appleModel.isAuthenticating else { return }
          if await model.continueWithGoogle() {
            onResolved(intent)
        }
    }

      private func continueWithApple() async {
          guard !model.isAuthenticating else { return }
          if await appleModel.signIn() {
            onResolved(intent)
        }
    }

    /// "Not now" and tap-outside cancel without side effects.
    private func dismiss() {
          guard !model.isAuthenticating, !appleModel.isAuthenticating else { return }
        onDismiss()
    }
}

// MARK: - Email sign-in

/// Drives `APIClient.signInWithPassword` for `EmailSignInScreen`. Pure and testable: no navigation,
/// no presentation — the caller decides what success means.
@MainActor
final class EmailSignInModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorText: String?

    /// Copy for a submit tap that has nothing to send. One string for a missing email, a missing
    /// password, or both: the sheet never says which field the server would have rejected.
    static let incompleteFormText = "Enter your email address and password."

    /// Both fields carry input. Gates the CTA's *fill*, never its tap: a tap on the muted CTA must
    /// still be answered (`submit()`), because a control that swallows a tap with no feedback is
    /// indistinguishable from a sign-in that failed silently.
    var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private let client: APIClient

    init(client: APIClient = ServiceLocator.makeAPIClient()) {
        self.client = client
    }

    /// Runs the sign-in once per call. `true` only for a real sign-in — the caller then resolves
    /// the interrupted intent, if any.
    ///
    /// Every outcome writes a state the sheet can render, including an incomplete form: a tap with
    /// empty fields sets `incompleteFormText` in the same error region a rejected credential uses.
    /// Before this, such a tap was a silent no-op that left the sheet exactly as it started — an
    /// empty form with no error — which is the observable outcome the verification lane reported
    /// and could not tell apart from a failed sign-in.
    func submit() async -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSubmitting else { return false }
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorText = Self.incompleteFormText
            return false
        }
        isSubmitting = true
        errorText = nil
        defer { isSubmitting = false }
        do {
            try await client.signInWithPassword(email: trimmedEmail, password: password)
            return true
        } catch {
            errorText = AuthErrorCopy.text(for: error, fallback: "Sign-in could not be completed.")
            return false
        }
    }
}

/// Email + password sign-in surface (DESIGN-signin.md §3–7). Presented as a `.sheet` from the
/// shared prompt, the Account signed-out card and the paywall — never from the 9-line overlay.
struct EmailSignInScreen: View {
    /// The interrupted intent, one line of subtext under the header (DESIGN §3).
    let intentLine: String
    /// Called exactly once, only after a real sign-in success.
    let onResolved: () -> Void

    /// Owned by the presenter, never by this view. A sheet's content view is re-created whenever
    /// its host re-renders; a model created here (`@StateObject`) is discarded with it, taking the
    /// typed email, the error text and the attempt's outcome along. That is how a sign-in that did
    /// not succeed could be observed as a pristine, error-free form. The presenter owns it so the
    /// outcome outlives the view that reports it (PLAN §4, DESIGN §5).
    @ObservedObject private var model: EmailSignInModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPasswordShown = false
    @State private var isGoogleAuthenticating = false
    @State private var googleError: String?
    @State private var submitTask: Task<Void, Never>?

    /// Keyboard focus chain: the email field's `.next` return key must actually advance to the
    /// password field (SwiftUI does not do this by itself). This also gives the largest text
    /// sizes a tap-independent path into the password field, where a coordinate tap can miss a
    /// field that just scrolled under the keyboard.
    private enum FocusField { case email, password }
    @FocusState private var focusedField: FocusField?
    private let googleAction = SignInAction()

    init(
        model: EmailSignInModel,
        intentLine: String,
        onResolved: @escaping () -> Void = {}
    ) {
        self.intentLine = intentLine
        self.onResolved = onResolved
        _model = ObservedObject(wrappedValue: model)
    }

    /// A failed Google attempt inside the sheet is a state change like any other: routed through
    /// the same error region. `model.errorText` and `googleError` never overlap — only one flow
    /// runs at a time.
    private var activeError: String? { model.errorText ?? googleError }

    var body: some View {
        VStack(spacing: 0) {
            NeoSubscreenHeader(title: "Sign in with email", backLabel: "Back", onBack: cancel)
            ScrollView {
                VStack(alignment: .leading, spacing: AIPoseSpacing.md) {
                    Text(intentLine)
                        .font(.subheadline)
                        .foregroundStyle(AIPoseColor.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                    emailField
                    passwordField
                    errorRegion
                }
                .padding(.horizontal, AIPoseSpacing.lg)
                .padding(.top, AIPoseSpacing.sm)
                .padding(.bottom, AIPoseSpacing.lg)
            }
            dock
        }
        .background(AIPoseColor.background)
        .interactiveDismissDisabled(model.isSubmitting)
        // No `onDisappear` cancellation (S4): a content-view teardown is not a user cancel, and
        // cancelling the in-flight attempt there abandoned a real sign-in request with no error to
        // show for it. The explicit header Back (`cancel()`) is the only path that cancels.
    }

    // MARK: fields — the app's text-input chrome, minus the offset shadow (DESIGN §4)

    private var emailField: some View {
        TextField("Email address", text: $model.email)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focusedField, equals: .email)
            .onSubmit { focusedField = .password }
            .font(.body)
            .foregroundStyle(AIPoseColor.foreground)
            .frame(minHeight: 44)
            .padding(.horizontal, AIPoseSpacing.md)
            .background(AIPoseColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AIPoseColor.foreground, lineWidth: 2))
            .disabled(model.isSubmitting)
            .accessibilityIdentifier("signin.email")
    }

    private var passwordField: some View {
        HStack(spacing: 0) {
            Group {
                if isPasswordShown {
                    TextField("Password", text: $model.password)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        // The id must sit on the FIELD element (F1): on the wrapping `Group` it
                        // does not propagate to the field (verified in the live hierarchy).
                        .accessibilityIdentifier("signin.password")
                } else {
                    SecureField("Password", text: $model.password)
                        .textContentType(.password)
                        .accessibilityIdentifier("signin.password")
                }
            }
            // Re-identity on every Show/Hide swap: SwiftUI otherwise keeps the old field alive
            // and a re-hidden SecureField can render blank while the binding still holds the
            // value (F3). A fresh field view re-reads the binding, so the dots come back.
            .id(isPasswordShown)
            .submitLabel(.done)
            .focused($focusedField, equals: .password)
            .onSubmit { submitTask = Task { await submit() } }
            .font(.body)
            .foregroundStyle(AIPoseColor.foreground)
            .frame(minHeight: 44)

            Button {
                isPasswordShown.toggle()
            } label: {
                Text(isPasswordShown ? "Hide" : "Show")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AIPoseColor.foreground)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isSubmitting)
            .accessibilityIdentifier("signin.showPassword")
            .accessibilityLabel(isPasswordShown ? "Hide password" : "Show password")
            .accessibilityValue(isPasswordShown ? "shown" : "hidden")
        }
        .padding(.leading, AIPoseSpacing.md)
        .background(AIPoseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AIPoseColor.foreground, lineWidth: 2))
        .disabled(model.isSubmitting)
    }

    @ViewBuilder
    private var errorRegion: some View {
        if let activeError {
            FeatureStateView(tone: .error, title: SignInPromptStateCopy.failureTitle, message: activeError)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("signin.error")
                .transition(reduceMotion ? .identity : .opacity)
        }
    }

    /// The single primary action plus the Google peer option, docked above the safe area
    /// (paywall dock precedent, DESIGN §5 "long content").
    ///
    /// `fixedSize` on the dock (G1): at accessibility text sizes the sheet cannot give this VStack
    /// its ideal height, and a compressed child (the CTA reported 97pt for ~200pt of content in the
    /// AX tree) overflows its frame and paints over its neighbours. Refusing compression here
    /// pushes the squeeze onto the ScrollView instead, which scrolls; the secondary keeps a real
    /// `md` separation so the CTA's 4pt offset shadow can never touch its glyphs.
    private var dock: some View {
        VStack(spacing: AIPoseSpacing.md) {
            Button {
                submitTask = Task { await submit() }
            } label: {
                HStack(spacing: AIPoseSpacing.sm) {
                    if model.isSubmitting { ProgressView().tint(AIPoseColor.foreground) }
                    Text(model.isSubmitting ? "Signing in…" : "Sign in")
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                }
            }
            // Call-site disabled affordance (F2): `NeoButtonStyle` never reads `isEnabled`, so a
            // `.disabled` CTA still paints the full primary fill and shadow. An empty form keeps
            // its fill token but mutes to the neutral surface, matching DESIGN §5 "initial".
            // During the in-flight request the fill stays primary — the spinner + "Signing in…"
            // label own the loading read (DESIGN §5 "loading"), not a disabled look.
            .buttonStyle(NeoButtonStyle(fill: model.canSubmit ? AIPoseColor.primary : AIPoseColor.surfaceVariant))
            .opacity(model.canSubmit ? 1 : 0.8)
            .frame(minHeight: 44)
            // An incomplete form mutates the fill (§5 "initial") but never swallows the tap: the
            // model answers it with `incompleteFormText` so "nothing happened" is not a state this
            // sheet can be left in (S4).
            .disabled(model.isSubmitting)
            .accessibilityIdentifier("signin.submit")
            .accessibilityLabel(model.isSubmitting ? "Signing in" : "Sign in")

            Button {
                Task { await continueWithGoogle() }
            } label: {
                Text("Use Google instead")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AIPoseColor.foreground)
                    // Wrap, never clip, at accessibility text sizes (F5).
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isGoogleAuthenticating)
            .accessibilityIdentifier("signin.google")
            .accessibilityLabel(isGoogleAuthenticating ? "Signing in" : "Use Google instead")
        }
        .padding(AIPoseSpacing.lg)
        .background(AIPoseColor.background)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .top) {
            Rectangle().fill(AIPoseColor.foreground.opacity(0.15)).frame(height: 1)
        }
    }

    private func submit() async {
        let succeeded = await model.submit()
        guard succeeded, !Task.isCancelled else { return }
        onResolved()
        dismiss()
    }

    /// Header Back cancels the in-flight request (DESIGN §3). Swipe-down while submitting is
    /// blocked by `interactiveDismissDisabled`, so Back is the only cancel path there.
    private func cancel() {
        submitTask?.cancel()
        dismiss()
    }

    private func continueWithGoogle() async {
        guard !isGoogleAuthenticating else { return }
        isGoogleAuthenticating = true
        defer { isGoogleAuthenticating = false }
        switch await googleAction.run() {
        case .succeeded:
            onResolved()
            dismiss()
        case .cancelled:
            break
        case .failed(let text):
            googleError = text
        }
    }
}

extension View {
    /// Shared presenter seam: hosts `EmailSignInScreen` in a large sheet (DESIGN §3). Success is
    /// reported to `onResolved` by the screen itself; dismissing without success leaves the
    /// originating gate untouched.
    ///
    /// - Parameter model: the presenter's attempt state, so the sheet is a projection of it rather
    ///   than its owner (S4). Keep it in the presenter's `@StateObject`, not in the sheet content.
    func emailSignInSheet(
        model: EmailSignInModel,
        isPresented: Binding<Bool>,
        intentLine: String,
        onResolved: @escaping () -> Void = {}
    ) -> some View {
        sheet(isPresented: isPresented) {
            if #available(iOS 16.0, *) {
                EmailSignInScreen(model: model, intentLine: intentLine, onResolved: onResolved)
                    .presentationDetents([.large])
            } else {
                EmailSignInScreen(model: model, intentLine: intentLine, onResolved: onResolved)
            }
        }
    }
}

/// Presents the shared prompt over any screen. `intent` is set by the gated entry point and
/// cleared as soon as the interaction ends (success, "Not now", or tap-outside).
private struct SignInPromptModifier: ViewModifier {
    @Binding var intent: SignInIntent?
    @StateObject private var model = SignInPromptModel()
      @StateObject private var appleModel = AppleSignInModel()
    /// Owned here, above the `if let intent` branch, so a mid-attempt unmount of the prompt cannot
    /// discard the email attempt's typed input, error or in-flight request (S4).
    @StateObject private var emailModel = EmailSignInModel()
    let onResolved: (SignInIntent) -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if let intent {
                  SignInPromptView(
                      model: model,
                      appleModel: appleModel,
                      emailModel: emailModel,
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
