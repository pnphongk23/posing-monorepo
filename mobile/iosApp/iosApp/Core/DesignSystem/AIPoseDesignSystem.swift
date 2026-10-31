import SwiftUI

enum AIPoseColor {
    static let primary = Color(hex: 0xE89CAE)
    static let primary50 = Color(hex: 0xFDF0F3)
    static let primary100 = Color(hex: 0xFAE0E7)
    static let primary700 = Color(hex: 0xD47A90)
    static let primary900 = Color(hex: 0x8C3350)
    static let background = Color(hex: 0xFBF6EF)
    static let surface = Color.white
    static let surfaceVariant = Color(hex: 0xF4F1E8)
    static let foreground = Color(hex: 0x121212)
    static let subtext = Color(hex: 0x6B7280)
    static let border = Color(hex: 0x000000)
    static let success = Color(hex: 0xB5E2B9)
    static let warning = Color(hex: 0xFED766)
    static let error = Color(hex: 0xEE4848)
    /// `--nb-color-error-surface` (`styles/tokens.css`), the `nb-empty-state--error` container fill.
    static let errorSurface = Color(hex: 0xFFF4F5)
    static let accentBlue = Color(hex: 0x7FBBE6)
    static let accentYellow = Color(hex: 0xFED766)
    static let accentGreen = Color(hex: 0xB5E2B9)
}

enum AIPoseSpacing {
    static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12
    static let lg: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

enum NeoChromeTokens {
    static let borderHairline: CGFloat = 1.0
    static let borderThin: CGFloat = 1.5
    static let borderThick: CGFloat = 2.0
    static let radiusSmall: CGFloat = 6.0
    static let radiusMedium: CGFloat = 10.0
    static let radiusLarge: CGFloat = 14.0
    static let radiusToolbarTab: CGFloat = 20.0
    static let shadowSmall: CGFloat = 1.5
    static let shadowSelected: CGFloat = 2.0
    static let shadowDefault: CGFloat = 3.0
    static let shadowLarge: CGFloat = 5.0
    static let pressedOffset: CGFloat = 3.0
    static let touchMinimum: CGFloat = 44.0
    static let compactSurfaceSide: CGFloat = 32.0
}

/// Reusable Neo-Brutalist surface styling: solid fill, solid single border, and a solid offset shadow shape behind the fill.
/// Avoids SwiftUI `.shadow` on stroke overlays which produces doubled outlines / offset ghost borders.
struct NeoSurfaceModifier<S: Shape>: ViewModifier {
    var shape: S
    var fill: Color = AIPoseColor.surface
    var borderColor: Color = AIPoseColor.foreground
    var borderWidth: CGFloat = NeoChromeTokens.borderThick
    var shadowOffset: CGFloat = NeoChromeTokens.shadowDefault
    var shadowColor: Color = AIPoseColor.foreground

    func body(content: Content) -> some View {
        content
            .clipShape(shape)
            .background(
                ZStack {
                    if shadowOffset > 0 {
                        shape
                            .fill(shadowColor)
                            .offset(x: shadowOffset, y: shadowOffset)
                    }
                    shape
                        .fill(fill)
                }
            )
            .overlay(
                Group {
                    if borderWidth > 0 {
                        shape
                            .stroke(borderColor, lineWidth: borderWidth)
                    }
                }
            )
    }
}

extension View {
    func neoSurface<S: Shape>(
        shape: S,
        fill: Color = AIPoseColor.surface,
        borderColor: Color = AIPoseColor.foreground,
        borderWidth: CGFloat = NeoChromeTokens.borderThick,
        shadowOffset: CGFloat = NeoChromeTokens.shadowDefault,
        shadowColor: Color = AIPoseColor.foreground
    ) -> some View {
        modifier(NeoSurfaceModifier(
            shape: shape,
            fill: fill,
            borderColor: borderColor,
            borderWidth: borderWidth,
            shadowOffset: shadowOffset,
            shadowColor: shadowColor
        ))
    }
}

struct NeoCardModifier: ViewModifier {
    var background = AIPoseColor.surface
    var cornerRadius: CGFloat = NeoChromeTokens.radiusLarge
    var shadowOffset: CGFloat = NeoChromeTokens.shadowDefault

    func body(content: Content) -> some View {
        content
            .padding(AIPoseSpacing.lg)
            .neoSurface(
                shape: RoundedRectangle(cornerRadius: cornerRadius),
                fill: background,
                borderWidth: NeoChromeTokens.borderThick,
                shadowOffset: shadowOffset
            )
    }
}

extension View {
    func neoCard(background: Color = AIPoseColor.surface) -> some View {
        modifier(NeoCardModifier(background: background))
    }
}

struct NeoButtonStyle: ButtonStyle {
    var fill = AIPoseColor.primary
    /// Label colour. `makeBody` owns the label's `foregroundStyle`, so a call site that paints a
    /// dark fill must pass its label colour here: an outer `.foregroundStyle(...)` is overridden by
    /// this one and silently disappears into the fill (BUG-261029-02).
    var foreground = AIPoseColor.foreground
    var cornerRadius: CGFloat = NeoChromeTokens.radiusMedium

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .neoSurface(
                shape: RoundedRectangle(cornerRadius: cornerRadius),
                fill: fill,
                borderWidth: NeoChromeTokens.borderThick,
                shadowOffset: isPressed ? 0 : NeoChromeTokens.shadowDefault
            )
            .offset(
                x: isPressed ? NeoChromeTokens.pressedOffset : 0,
                y: isPressed ? NeoChromeTokens.pressedOffset : 0
            )
    }
}

/// Tones of the shared state panels (`docs/prototype/scripts/empty-state.js` +
/// `styles/components/empty-state.css`), mapped onto the direction-B `APStateTone` the shared panel
/// draws.
enum FeatureStateTone: String, CaseIterable {
    case empty, error, loading, offline, success, warning

    /// The shared tone this card paints, so a feature surface and a catalogue panel show the same
    /// state colour whichever component the screen reaches for (`AP.Color.*` tokens only).
    var stateTone: APStateTone {
        switch self {
        case .empty: return .empty
        case .error: return .error
        case .loading: return .loading
        case .offline: return .offline
        case .success: return .success
        case .warning: return .warning
        }
    }

    /// Container fill, read from the shared tone so the two mappings cannot drift apart.
    var surface: Color { stateTone.surface }

    /// `empty-state.js` `ROLE_BY_STATE`: only `error` is `role="alert"`; every other tone is
    /// `role="status"`. `LIVE_BY_STATE` matches: `error` is `aria-live="assertive"`, rest `polite`.
    var isAssertive: Bool { self == .error }

    /// `.nb-empty-state--loading` tints the copy and keeps the title dark.
    var copyColor: Color { self == .loading ? AP.Color.secondaryText : AP.Color.primaryText }
}

/// Shared empty / loading / offline / recoverable-error / success / warning surface.
///
/// Owner feedback F4 replaced this card's prototype geometry (`empty-state.css`: a 1.5pt bordered,
/// 10pt-radius, leading-aligned block with **no icon**) with the one state look: a centred 72 pt
/// accent-tint circle with the glyph in the accent ink, then the title, the copy and at most one
/// action. No stacked or offset tiles, no red tile for errors. F4 is the newer owner decision and
/// overrides the artboard.
///
/// The panel itself is `APStateCard`, so there is exactly one implementation of a state panel in the
/// app; this type keeps the call sites' API, their accessibility identifiers and its live-region
/// behaviour. Loading states that already draw the skeleton (`APLoadingStateView`) keep it.
///
/// Accessibility mirrors `scripts/empty-state.js`: combined children (`aria-atomic`), `alert` +
/// assertive announcement for `.error`, `status` + polite announcement for every other tone.
struct FeatureStateView: View {
    var tone: FeatureStateTone = .empty
    let title: String
    let message: String
    var actionTitle: String? = nil
    /// E2E handle for the action control (`gallery.empty.openCameraButton`). Passing one also stops the
    /// card from merging its children into a single element, so the button is individually addressable;
    /// cards without a handle keep the combined element they always had.
    var actionIdentifier: String? = nil
    var action: (() -> Void)? = nil
    /// How the panel is mounted: the raised `surface` card most feature states sit in, or the
    /// borderless centred panel a screen paints directly on its own background (Jobs, permission
    /// boards). Both draw the same F4 circle; only the chrome around it changes.
    var style: APStateCardStyle = .card

    @State private var didAnnounce = false

    /// `empty-state.css`: `margin-bottom: var(--nb-space-sm)` → 8pt.
    private static let contentGap: CGFloat = 8

    var body: some View {
        APStateCard(
            tone: tone.stateTone,
            glyphOverride: nil,
            showsWord: false,
            title: title,
            message: message,
            actionTitle: actionTitle,
            actionKind: .secondary,
            action: action,
            style: style,
            expandsVertically: false,
            actionIdentifier: actionIdentifier
        )
        // `margin-bottom: var(--nb-space-sm)`: stacked states keep the prototype's spacing.
        .padding(.bottom, Self.contentGap)
        .accessibilityElement(children: actionIdentifier == nil ? .combine : .contain)
        .onAppear(perform: announceIfNeeded)
    }

    /// iOS has no declarative live-region role; a `UIAccessibility` announcement is the native
    /// equivalent. `.error` announces at high priority (assertive); every other tone queues politely.
    private func announceIfNeeded() {
        guard !didAnnounce else { return }
        didAnnounce = true
        let text = [title, message].filter { !$0.isEmpty }.joined(separator: ". ")
        guard !text.isEmpty else { return }
        var attributes: [NSAttributedString.Key: Any] = [:]
        if #available(iOS 17.0, *) {
            attributes[.accessibilitySpeechAnnouncementPriority] = tone.isAssertive
                ? UIAccessibilityPriority.high
                : UIAccessibilityPriority.default
        } else {
            // `aria-live`: assertive interrupts current speech, polite queues behind it.
            attributes[.accessibilitySpeechQueueAnnouncement] = NSNumber(value: !tone.isAssertive)
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: NSAttributedString(string: text, attributes: attributes)
        )
    }
}

extension Loadable {
    /// Single source of truth for the shared-card tone a `Loadable`-driven surface renders, or `nil`
    /// when the surface has content to draw instead of a card.
    ///
    /// Screens must read their card tone from here rather than restating it, because several of the
    /// states this maps (notably the Saved signed-in states) cannot be driven in the unauthenticated
    /// parity rig — these mappings are the substitute evidence for the missing screenshot verdicts.
    var stateTone: FeatureStateTone? {
        switch self {
        case .idle, .loading: return .loading
        case .empty: return .empty
        case .failed: return .error
        case .loaded: return nil
        }
    }
}
