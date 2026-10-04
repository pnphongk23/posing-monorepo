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
    var cornerRadius: CGFloat = NeoChromeTokens.radiusMedium

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        configuration.label
            .font(.headline)
            .foregroundStyle(AIPoseColor.foreground)
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

/// Tones of the shared prototype state component `nb-empty-state`
/// (`docs/prototype/scripts/empty-state.js` + `styles/components/empty-state.css`).
enum FeatureStateTone: String, CaseIterable {
    case empty, error, loading, offline, success, warning

    /// Container fill. `empty`/`loading` keep the white surface; `error` uses
    /// `--nb-color-error-surface`; `offline` and `warning` share `--nb-color-warning-surface`;
    /// `success` uses `--nb-color-success-surface`.
    /// Note: `empty-state.css` maps the container fill by tone, so the old plain-white
    /// `.nb-empty-state` base rule is overridden for the four coloured tones.
    var surface: Color {
        switch self {
        case .empty, .loading: return AIPoseColor.surface
        case .error: return AIPoseColor.errorSurface
        case .offline, .warning: return AIPoseColor.warning
        case .success: return AIPoseColor.success
        }
    }

    /// `empty-state.js` `ROLE_BY_STATE`: only `error` is `role="alert"`; every other tone is
    /// `role="status"`. `LIVE_BY_STATE` matches: `error` is `aria-live="assertive"`, rest `polite`.
    var isAssertive: Bool { self == .error }

    /// `.nb-empty-state--loading` tints the copy `--nb-color-gray` and keeps the title dark.
    var copyColor: Color { self == .loading ? AIPoseColor.subtext : AIPoseColor.foreground }
}

/// Shared empty / loading / offline / recoverable-error / success / warning surface.
///
/// Geometry and colour come from `docs/prototype/styles/components/empty-state.css` mapped against
/// `docs/prototype/styles/tokens.css` **by value, not by name** (token names do not match the Swift
/// `AIPoseSpacing` enum): white surface, `--nb-border-thin` = 1.5pt black border,
/// `--nb-radius-medium` = 10pt corner, `--nb-space-md` = 16pt padding, `--nb-space-sm` = 8pt gap
/// and bottom margin, leading-aligned full-width card, **no shadow**, **no icon**, and **no
/// centring** — a screen that needs a centred state centres this card in its own call site.
///
/// `scripts/empty-state.js` `render()` builds the element with `replaceChildren()` and then appends
/// at most a preserved `[data-empty-state-visual]`, a `<strong>` title, a `<p>` copy and the action;
/// `empty-state.css` has no icon rule, no centring and no full-height rule. Native must therefore
/// paint no glyph here: only `gallery-detail-v2.html` supplies a `data-empty-state-visual`, and that
/// screen keeps its own geometry-preserving placeholder (`GalleryLocalImage.onFailureView`) instead
/// of this component. Painting an icon is a parity defect — absence is part of the contract.
///
/// Accessibility mirrors `scripts/empty-state.js`: combined children (`aria-atomic`), `alert` +
/// assertive announcement for `.error`, `status` + polite announcement for every other tone.
struct FeatureStateView: View {
    var tone: FeatureStateTone = .empty
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @State private var didAnnounce = false

    /// `empty-state.css`: `border-radius: var(--nb-radius-medium)` → 10pt (tokens.css).
    private static let cornerRadius: CGFloat = NeoChromeTokens.radiusMedium
    /// `empty-state.css`: `border: var(--nb-border-thin)` → `--nb-border-width-thin` = 1.5pt.
    private static let borderWidth: CGFloat = NeoChromeTokens.borderThin
    /// `empty-state.css`: `padding: var(--nb-space-md)` → 16pt (tokens.css, not `AIPoseSpacing.md`).
    private static let contentPadding: CGFloat = 16
    /// `empty-state.css`: `gap` / `margin-bottom: var(--nb-space-sm)` → 8pt.
    private static let contentGap: CGFloat = 8
    /// `empty-state.css`: `.nb-empty-state__copy { max-width: 42ch }`. Measured in the prototype at the
    /// 14pt body size, `42ch` resolves to 370.37px, so 370pt is the faithful equivalent. It never
    /// binds on a 390pt screen (the card's inner width is ~326pt), which is exactly the prototype's
    /// behaviour; a smaller guess would silently re-wrap the copy.
    private static let copyMaxWidth: CGFloat = 370

    var body: some View {
        VStack(alignment: .leading, spacing: Self.contentGap) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AIPoseColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(tone.copyColor)
                // `--nb-type-body-leading` 1.55 on the 14pt body size ≈ 21.7pt line box.
                .lineSpacing(5)
                .frame(maxWidth: Self.copyMaxWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                // `NeoButtonStyle` is shared app-wide and carries no horizontal padding, so the
                  // state card's action uses inline horizontal padding to match `.nb-btn`
                  // (`components/button.css`), whose control padding is 16pt on each side.
                // is `padding: var(--nb-space-compact) var(--nb-space-md)` — 12pt vertical, 16pt
                // horizontal — so the inline padding belongs here at the call site, not in the style.
                Button(action: action) {
                    Text(actionTitle)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(NeoButtonStyle(fill: AIPoseColor.surface))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.top, 2)
            }
        }
        .padding(Self.contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .neoSurface(
            shape: RoundedRectangle(cornerRadius: Self.cornerRadius),
            fill: tone.surface,
            borderWidth: Self.borderWidth,
            shadowOffset: 0
        )
        // `margin-bottom: var(--nb-space-sm)`.
        .padding(.bottom, Self.contentGap)
        .accessibilityElement(children: .combine)
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
