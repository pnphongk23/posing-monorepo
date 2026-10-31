import Combine
import Foundation
import Network
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
///
/// Direction B chrome: the neutral secondary fill. Google's own logo is supplied at build time, so
/// until it is the row shows the dashed placeholder the board draws.
struct ContinueWithGoogleButton: View {
    let isAuthenticating: Bool
    /// Row label; the paywall's sign-in sheet turns the same row into the retry after a failure.
    var title: String = "Continue with Google"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AP.Space.space12) {
                if isAuthenticating {
                    ProgressView()
                } else {
                    Circle()
                        .strokeBorder(
                            AP.Color.primaryText,
                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                        )
                        .frame(width: 20, height: 20)
                }
                Text(isAuthenticating ? "Opening Google…" : title)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(APSecondaryButtonStyle())
        .disabled(isAuthenticating)
        .accessibilityLabel(isAuthenticating ? "Opening Google" : title)
    }
}

/// Sign in with Apple, drawn with the system button's proportions: 52 pt high, 17 pt label, 16 pt
/// corner radius, one line, the Apple logo beside the wordmark. The action still runs the app's
/// `ASAuthorizationAppleIDProvider` seam (`AppleSignInAction`), which owns the nonce and the API call,
/// so the paywall, the prompt and the Account card share one handoff.
///
/// HIG: black fill with a white wordmark in light mode, white fill with a black wordmark in dark mode.
struct ContinueWithAppleButton: View {
    let isAuthenticating: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: AP.Space.space8) {
                if isAuthenticating {
                    ProgressView().tint(AppleSignInCopy.labelColor(for: colorScheme))
                } else {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 17, weight: .medium))
                }
                Text(isAuthenticating ? AppleSignInCopy.pendingTitle : AppleSignInCopy.title)
                    .font(AP.Font.heading)
                    // System proportions: the wordmark never wraps, it scales down at AX sizes.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(AppleSignInCopy.labelColor(for: colorScheme))
            .frame(maxWidth: .infinity, minHeight: AppleSignInCopy.height)
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                    .fill(AppleSignInCopy.fillColor(for: colorScheme))
            )
            .contentShape(RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous))
        }
        .buttonStyle(.plain)
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
    /// System button geometry (board 11-21 measures it at 358 × 52).
    static let height: CGFloat = 52
    /// HIG: the Apple button is black with a white logo and wordmark in light mode…
    static let fillColor = SwiftUI.Color.black
    static let labelColor = SwiftUI.Color.white

    /// …and white with a black logo and wordmark in dark mode, exactly like `SignInWithAppleButton`.
    static func fillColor(for colorScheme: ColorScheme) -> SwiftUI.Color {
        colorScheme == .dark ? .white : fillColor
    }

    static func labelColor(for colorScheme: ColorScheme) -> SwiftUI.Color {
        colorScheme == .dark ? .black : labelColor
    }

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
    @Published var email = "" {
        didSet { if emailError != nil { emailError = nil } }
    }
    @Published var password = "" {
        didSet { if passwordError != nil { passwordError = nil } }
    }
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorText: String?
    /// Per-field messages (board 11-17): each field states its own problem, in place.
    @Published private(set) var emailError: String?
    @Published private(set) var passwordError: String?
    /// Live connectivity: board 11-20 disables the CTA and says why.
    @Published private(set) var isOffline: Bool

    /// Copy for a submit tap that has nothing to send. Kept for the shared error region so a tap is
    /// always answered; the per-field messages below carry the detail the board draws.
    static let incompleteFormText = "Enter your email address and password."
    static let invalidEmailText = "Enter a valid email address, like name@example.com"
    static let missingPasswordText = "Enter your password"

    /// Both fields carry input. Gates the CTA's *fill*, never its tap: a tap on the muted CTA must
    /// still be answered (`submit()`), because a control that swallows a tap with no feedback is
    /// indistinguishable from a sign-in that failed silently.
    var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var hasFieldErrors: Bool { emailError != nil || passwordError != nil }

    private let client: APIClient
    private let connectivity: ConnectivityReporting

    init(
        client: APIClient = ServiceLocator.makeAPIClient(),
        connectivity: ConnectivityReporting = NetworkConnectivityMonitor.shared
    ) {
        self.client = client
        self.connectivity = connectivity
        self.isOffline = connectivity.isOffline
    }

    /// Starts the connectivity read (the view calls this once it appears).
    func start() {
        connectivity.start()
        isOffline = connectivity.isOffline
    }

    /// The same shape the sign-in endpoint enforces (`z.string().trim().email()`): a local part, an
    /// `@`, and a domain with a dot and a two-letter-or-longer alphabetic suffix. Anything looser
    /// would let the sheet send a request the backend answers with a 400.
    static func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return false }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0]
        let domain = parts[1]
        guard !local.isEmpty, !local.hasPrefix("."), !local.hasSuffix("."), !local.contains("..") else {
            return false
        }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        guard let suffix = labels.last, suffix.count >= 2, suffix.allSatisfy(\.isLetter) else { return false }
        return true
    }

    /// Fills the per-field messages. `true` when the form may be sent.
    @discardableResult
    func validate() -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        emailError = Self.isValidEmail(trimmedEmail) ? nil : Self.invalidEmailText
        // The endpoint accepts any non-empty password (`z.string().min(1)`), so the client rule is
        // presence only: a stricter rule here would refuse credentials the backend accepts.
        passwordError = password.isEmpty ? Self.missingPasswordText : nil
        return emailError == nil && passwordError == nil
    }

    /// Runs the sign-in once per call. `true` only for a real sign-in — the caller then resolves
    /// the interrupted intent, if any.
    ///
    /// Every outcome writes a state the sheet can render, including an incomplete form: a tap with
    /// empty fields sets `incompleteFormText` in the same error region a rejected credential uses
    /// and the per-field messages beside the fields themselves.
    func submit() async -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSubmitting else { return false }
        guard validate() else {
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
/// Live connectivity. The offline states on the paywall (board 11-11) and in email sign-in
/// (board 11-20) are read from the network path, never guessed from an error string.
@MainActor
protocol ConnectivityReporting: AnyObject {
    var isOffline: Bool { get }
    /// Emits the new `isOffline` value whenever the path changes.
    var changes: AnyPublisher<Bool, Never> { get }
    func start()
}

/// One monitor for the app: connectivity is a process-wide fact, and every surface that needs it
/// reads the same source instead of polling.
@MainActor
final class NetworkConnectivityMonitor: ConnectivityReporting {
    static let shared = NetworkConnectivityMonitor()

    /// The path handler runs on the monitor's own queue, so the subject it feeds lives in a
    /// `Sendable` box instead of being captured off the main actor. `CurrentValueSubject` is safe to
    /// send to from any thread; every subscriber hops back to the main actor itself.
    private final class OfflineState: @unchecked Sendable {
        let subject = CurrentValueSubject<Bool, Never>(false)
    }

    private let state = OfflineState()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.aipose.connectivity")
    private var hasStarted = false

    var isOffline: Bool { state.subject.value }
    var changes: AnyPublisher<Bool, Never> { state.subject.eraseToAnyPublisher() }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        monitor.pathUpdateHandler = { [state] path in
            let offline = path.status != .satisfied
            // Publish on the main actor: every reader is a `@MainActor` model whose subscription
            // closure is main-isolated, so a send from the monitor's own queue would trip the
            // executor assertion instead of delivering the new path.
            Task { @MainActor in state.subject.send(offline) }
        }
        monitor.start(queue: queue)
    }
}

/// One actionable message on a support surface: the boards' error card instead of a plain footnote
/// line, with the action that fixes it where one exists.
struct SupportNotice: Equatable {
    enum Action: Equatable {
        case retryLoad
        case retryRestore
        case retryGoogle
    }

    let title: String
    let message: String
    let action: Action?

    var actionTitle: String? { action == nil ? nil : "Try again" }
}

/// Board 11-11/11-20: a one-line status banner in the state's own surface, glyph plus words.
struct SupportInlineBanner: View {
    let tone: APStateTone
    let message: String

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
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.vertical, AP.Space.space12)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(tone.surface)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

/// The boards' error card (11-08/11-09/11-15/11-19): title, truthful body and the action that fixes
/// it. One component for the paywall and for email sign-in.
struct SupportNoticeCard: View {
    let notice: SupportNotice
    var action: (SupportNotice.Action) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: AP.Space.space12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AP.Color.error)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AP.Space.space8) {
                Text(notice.title)
                    .font(AP.Font.heading)
                    .foregroundStyle(AP.Color.error)
                    .fixedSize(horizontal: false, vertical: true)
                Text(notice.message)
                    .font(AP.Font.supporting)
                    .foregroundStyle(AP.Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle = notice.actionTitle, let noticeAction = notice.action {
                    Button(actionTitle) { action(noticeAction) }
                        .buttonStyle(.plain)
                        .font(AP.Font.supporting.weight(.semibold))
                        .foregroundStyle(AP.Color.accentText)
                        .frame(minHeight: AP.HitTarget.minimum)
                        .accessibilityLabel(actionTitle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AP.Space.space16)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.errorSurface)
        )
        .accessibilityElement(children: .contain)
    }
}

/// Email + password sign-in surface. Presented as a `.sheet` from the shared prompt, the Account
/// signed-out card and the paywall.
///
/// Board page 11 (11-16 … 11-20): an F1 header, one labelled field per row with its own inline
/// message, a server error card above the fields, an offline banner, and the CTA pinned at the
/// bottom. There is no password-reset link: the app has no reset path (owner decision), so drawing
/// one would be a dead control.
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
    @State private var submitTask: Task<Void, Never>?

    /// Keyboard focus chain: the email field's `.next` return key must actually advance to the
    /// password field (SwiftUI does not do this by itself). This also gives the largest text
    /// sizes a tap-independent path into the password field, where a coordinate tap can miss a
    /// field that just scrolled under the keyboard.
    private enum FocusField { case email, password }
    @FocusState private var focusedField: FocusField?

    init(
        model: EmailSignInModel,
        intentLine: String,
        onResolved: @escaping () -> Void = {}
    ) {
        self.intentLine = intentLine
        self.onResolved = onResolved
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            APPageHeader(title: "Sign in with email", backLabel: "Back", onBack: cancel)
            ScrollView {
                VStack(alignment: .leading, spacing: AP.Space.space16) {
                    Text(intentLine)
                        .font(AP.Font.supporting)
                        .foregroundStyle(AP.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.isOffline {
                        SupportInlineBanner(tone: .offline, message: "You're offline. Connect to sign in.")
                            .accessibilityIdentifier("signin.offline")
                    }
                    serverErrorCard
                    emailField
                    passwordField
                }
                .padding(.horizontal, AP.Space.space16)
                .padding(.top, AP.Space.space8)
                .padding(.bottom, AP.Space.space24)
            }
            dock
        }
        .background(AP.Color.background)
        .onAppear { model.start() }
        .interactiveDismissDisabled(model.isSubmitting)
        // No `onDisappear` cancellation (S4): a content-view teardown is not a user cancel, and
        // cancelling the in-flight attempt there abandoned a real sign-in request with no error to
        // show for it. The explicit header Back (`cancel()`) is the only path that cancels.
    }

    // MARK: fields

    private var emailField: some View {
        VStack(alignment: .leading, spacing: AP.Space.space8) {
            fieldLabel("Email")
            HStack(spacing: AP.Space.space8) {
                Image(systemName: "envelope")
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.secondaryText)
                    .accessibilityHidden(true)
                TextField("name@example.com", text: $model.email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                    .accessibilityIdentifier("signin.email")
                if model.emailError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AP.Color.error)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, AP.Space.space16)
            .frame(minHeight: 52)
            .background(fieldBackground(hasError: model.emailError != nil, isFocused: focusedField == .email))
            .disabled(model.isSubmitting)
            if let emailError = model.emailError {
                fieldError(emailError, identifier: "signin.email.error")
            }
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: AP.Space.space8) {
            fieldLabel("Password")
            HStack(spacing: AP.Space.space8) {
                Image(systemName: "key")
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.secondaryText)
                    .accessibilityHidden(true)
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
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)

                if model.passwordError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AP.Color.error)
                        .accessibilityHidden(true)
                }

                Button {
                    isPasswordShown.toggle()
                } label: {
                    Image(systemName: isPasswordShown ? "eye.slash" : "eye")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AP.Color.primaryText)
                        .frame(minWidth: AP.HitTarget.minimum, minHeight: AP.HitTarget.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isSubmitting)
                .accessibilityIdentifier("signin.showPassword")
                .accessibilityLabel(isPasswordShown ? "Hide password" : "Show password")
                .accessibilityValue(isPasswordShown ? "shown" : "hidden")
            }
            .padding(.leading, AP.Space.space16)
            .frame(minHeight: 52)
            .background(fieldBackground(hasError: model.passwordError != nil, isFocused: focusedField == .password))
            .disabled(model.isSubmitting)
            if let passwordError = model.passwordError {
                fieldError(passwordError, identifier: "signin.password.error")
            }
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(AP.Font.supporting.weight(.semibold))
            .foregroundStyle(AP.Color.primaryText)
    }

    /// Focus tints the field, an invalid field goes to the error surface: the two reads the board
    /// distinguishes (11-16 focused, 11-17 invalid) without a resting border.
    private func fieldBackground(hasError: Bool, isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
            .fill(hasError ? AP.Color.errorSurface : (isFocused ? AP.Color.selectedBackground : AP.Color.controlFill))
    }

    private func fieldError(_ message: String, identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AP.Space.space8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AP.Color.error)
                .accessibilityHidden(true)
            Text(message)
                .font(AP.Font.caption.weight(.semibold))
                .foregroundStyle(AP.Color.error)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier(identifier)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    /// Board 11-19: a rejected sign-in is a titled card above the fields. The per-field messages own
    /// the empty-form case, so the card never repeats them.
    @ViewBuilder
    private var serverErrorCard: some View {
        if let error = model.errorText, !model.hasFieldErrors {
            SupportNoticeCard(
                notice: SupportNotice(title: "Couldn't sign in", message: error, action: nil)
            )
            .accessibilityIdentifier("signin.error")
            .transition(reduceMotion ? .identity : .opacity)
        }
    }

    /// The single primary action, docked above the safe area (DESIGN §5 "long content").
    ///
    /// `fixedSize` on the dock (G1): at accessibility text sizes the sheet cannot give this VStack
    /// its ideal height, and a compressed child overflows its frame and paints over its neighbours.
    /// Refusing compression here pushes the squeeze onto the ScrollView instead, which scrolls.
    private var dock: some View {
        VStack(spacing: AP.Space.space12) {
            Button {
                submitTask = Task { await submit() }
            } label: {
                HStack(spacing: AP.Space.space8) {
                    if model.isSubmitting { ProgressView().tint(AP.Color.onAccent) }
                    Text(model.isSubmitting ? "Signing in…" : "Sign in")
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                }
            }
            .buttonStyle(APPrimaryButtonStyle(minimumHeight: 48))
            // An incomplete form keeps the CTA tappable: the tap is answered with the field messages
            // (S4). Only the in-flight request and a known-offline device disable it.
            .disabled(model.isSubmitting || model.isOffline)
            .accessibilityIdentifier("signin.submit")
            .accessibilityLabel(model.isSubmitting ? "Signing in" : "Sign in")
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.vertical, AP.Space.space12)
        .background(AP.Color.background)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .top) {
            Rectangle().fill(AP.Color.separator).frame(height: 1)
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
