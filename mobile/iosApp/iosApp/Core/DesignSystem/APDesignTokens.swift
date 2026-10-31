import SwiftUI
import UIKit

/// Semantic design tokens for the approved redesign, direction B ("iOS-native soft").
///
/// Source of truth: `tokens.md` from the DS-261030 design export (artboard `00-design-system`,
/// Version 15). Every value below is transcribed from that board; the tests in
/// `iosAppTests/DesignSystem` re-state the documented hex and contrast pairs so a drifting value
/// fails the build instead of silently re-skinning a screen.
///
/// Rules the tokens encode:
/// - no resting borders: the only outline is the focus ring,
/// - one accent family (pink) and one warm-neutral family; components read semantic tokens, never hex,
/// - every semantic colour has both a light and a dark value,
/// - text is 4.5:1, UI boundaries 3:1, targets are at least 44 × 44 pt.
///
/// Everything here is **additive**. The legacy `AIPoseColor` / `AIPoseSpacing` / `NeoChromeTokens`
/// namespaces keep working untouched so the migration slices can move screens over one at a time.
enum AP {}

extension AP {
    /// 4 pt base, 8 pt rhythm. Token names carry the value so "medium" can never mean 12 in one
    /// file and 16 in another. Off-scale values (13, 12.8, 10) snap to the nearest token.
    enum Space {
        static let space4: CGFloat = 4
        static let space8: CGFloat = 8
        static let space12: CGFloat = 12
        static let space16: CGFloat = 16
        static let space24: CGFloat = 24
        static let space32: CGFloat = 32
        static let space48: CGFloat = 48
    }

    /// Three radii. Circle is a shape, not a token (avatar and camera shutter only).
    enum Radius {
        /// Thumbnails, tags, segments.
        static let radius8: CGFloat = 8
        /// Buttons, chips, fields, cards, rows.
        static let radius16: CGFloat = 16
        /// Sheets, pose dock, large media.
        static let radius24: CGFloat = 24
    }

    /// Every control has a 44 × 44 pt hit area; a smaller glyph gets hit-slop, never a smaller target.
    enum HitTarget {
        static let minimum: CGFloat = 44
    }

    /// Pressed appearance: fill steps one token and the control scales; Reduce Motion keeps the fill
    /// step and drops the scale.
    enum Press {
        static let scale: CGFloat = 0.97
        static let duration: Double = 0.12
    }

    /// Seven type roles on system Dynamic Type text styles. Sizes are never hard-coded: the system
    /// style owns them, so the roles hold from Large through the Accessibility sizes.
    enum Font {
        enum Role: String, CaseIterable {
            case display, title, heading, body, supporting, caption, data

            var textStyle: SwiftUI.Font.TextStyle {
                switch self {
                case .display: return .largeTitle
                case .title: return .title2
                case .heading: return .headline
                case .body: return .body
                case .supporting: return .subheadline
                case .caption: return .footnote
                case .data: return .title3
                }
            }

            var weight: SwiftUI.Font.Weight {
                switch self {
                case .display, .title: return .bold
                case .heading, .data: return .semibold
                case .caption: return .medium
                case .body, .supporting: return .regular
                }
            }

            var font: SwiftUI.Font {
                let base = SwiftUI.Font.system(textStyle, design: .default).weight(weight)
                // Figures line up in timers, counters and "12 poses" style readouts.
                return self == .data ? base.monospacedDigit() : base
            }
        }

        static let display: SwiftUI.Font = Role.display.font
        static let title: SwiftUI.Font = Role.title.font
        static let heading: SwiftUI.Font = Role.heading.font
        static let body: SwiftUI.Font = Role.body.font
        static let supporting: SwiftUI.Font = Role.supporting.font
        static let caption: SwiftUI.Font = Role.caption.font
        static let data: SwiftUI.Font = Role.data.font
    }

    /// E0 flat · E1 raised (light and dark) · E2 overlay. Only E1 paints; E0 and E2 are explicit
    /// "nothing" so a call site can state its level instead of leaving it implicit.
    enum Elevation: CaseIterable {
        case e0
        case e1
        case e2

        /// `cardStroke` hairline width on E1 surfaces in dark mode.
        static let strokeWidth: CGFloat = 1

        static let lightShadowOpacity: Double = 0.08
        static let darkShadowOpacity: Double = 0.40

        var shadowOpacity: Double {
            switch self {
            case .e0, .e2: return 0
            case .e1: return Self.lightShadowOpacity
            }
        }

        func shadowOpacity(for colorScheme: ColorScheme) -> Double {
            guard self == .e1 else { return 0 }
            return colorScheme == .dark ? Self.darkShadowOpacity : Self.lightShadowOpacity
        }

        /// Dark E1 cards keep their edge through the `cardStroke` hairline; light cards rely on the
        /// shadow and their photo.
        var addsCardStroke: Bool { self == .e1 }
    }
}

/// One semantic colour in one scheme. `hex == nil` means the token paints nothing there (light
/// `cardStroke`), which is why the value is optional instead of a magic clear colour.
struct APColorSpec: Equatable {
    let hex: UInt32?
    let alpha: Double

    init(_ hex: UInt32?, alpha: Double = 1) {
        self.hex = hex
        self.alpha = alpha
    }

    var uiColor: UIColor {
        guard let hex else { return .clear }
        return UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// A semantic colour with its documented light and dark value plus the SwiftUI colour the app draws.
struct APColorToken {
    let name: String
    let light: APColorSpec
    let dark: APColorSpec

    init(_ name: String, light: APColorSpec, dark: APColorSpec) {
        self.name = name
        self.light = light
        self.dark = dark
    }

    func spec(for colorScheme: ColorScheme) -> APColorSpec {
        colorScheme == .dark ? dark : light
    }

    /// The adaptive colour the app draws: one dynamic provider, so SwiftUI and UIKit both resolve it
    /// from the trait collection instead of from two parallel hex constants.
    var dynamicUIColor: UIColor {
        let light = light
        let dark = dark
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark.uiColor : light.uiColor
        }
    }

    var color: SwiftUI.Color { SwiftUI.Color(uiColor: dynamicUIColor) }

    /// Resolves the dynamic colour the way the app will, so tests can compare real output to `hex`.
    func resolvedColor(for style: UIUserInterfaceStyle) -> UIColor {
        dynamicUIColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }
}

/// The 14 core and 11 support tokens from `tokens.md`, kept as data so token integrity is testable.
enum APColorTokens {
    static let background = APColorToken("background", light: APColorSpec(0xFBF6EF), dark: APColorSpec(0x141210))
    static let secondaryBackground = APColorToken("secondaryBackground", light: APColorSpec(0xF4F1E8), dark: APColorSpec(0x1D1A17))
    static let surface = APColorToken("surface", light: APColorSpec(0xFFFFFF), dark: APColorSpec(0x272320))
    static let primaryText = APColorToken("primaryText", light: APColorSpec(0x121212), dark: APColorSpec(0xF7F2EA))
    static let secondaryText = APColorToken("secondaryText", light: APColorSpec(0x5E574C), dark: APColorSpec(0xB5ADA2))
    static let separator = APColorToken("separator", light: APColorSpec(0xDDD5C7), dark: APColorSpec(0x46403A))
    static let accent = APColorToken("accent", light: APColorSpec(0xE89CAE), dark: APColorSpec(0xE89CAE))
    static let onAccent = APColorToken("onAccent", light: APColorSpec(0x121212), dark: APColorSpec(0x121212))
    static let selectedBackground = APColorToken("selectedBackground", light: APColorSpec(0xFAE0E7), dark: APColorSpec(0x4B2B36))
    static let selectedForeground = APColorToken("selectedForeground", light: APColorSpec(0x8C3350), dark: APColorSpec(0xFAE0E7))
    static let success = APColorToken("success", light: APColorSpec(0x1E7A3C), dark: APColorSpec(0xB5E2B9))
    static let warning = APColorToken("warning", light: APColorSpec(0x8A5A00), dark: APColorSpec(0xFED766))
    static let error = APColorToken("error", light: APColorSpec(0xC8302F), dark: APColorSpec(0xFF6B6B))
    static let disabled = APColorToken("disabled", light: APColorSpec(0x8F887C), dark: APColorSpec(0x6F685F))

    static let accentText = APColorToken("accentText", light: APColorSpec(0x8C3350), dark: APColorSpec(0xF2B6C4))
    static let accentPressed = APColorToken("accentPressed", light: APColorSpec(0xD47A90), dark: APColorSpec(0xD47A90))
    static let controlFill = APColorToken("controlFill", light: APColorSpec(0xECE5D8), dark: APColorSpec(0x35302B))
    static let controlFillPressed = APColorToken("controlFillPressed", light: APColorSpec(0xDDD5C7), dark: APColorSpec(0x46403A))
    /// Dark only: light cards have no stroke, so the light value is explicitly "nothing".
    static let cardStroke = APColorToken("cardStroke", light: APColorSpec(nil), dark: APColorSpec(0x7A7268))
    static let outline = APColorToken("outline", light: APColorSpec(0x121212), dark: APColorSpec(0xE8DFD3))
    static let onError = APColorToken("onError", light: APColorSpec(0xFFFFFF), dark: APColorSpec(0x121212))
    static let successSurface = APColorToken("successSurface", light: APColorSpec(0xB5E2B9), dark: APColorSpec(0x1F3A28))
    static let warningSurface = APColorToken("warningSurface", light: APColorSpec(0xFED766), dark: APColorSpec(0x3D3210))
    static let errorSurface = APColorToken("errorSurface", light: APColorSpec(0xFFF4F5), dark: APColorSpec(0x3A1C1E))
    static let scrim = APColorToken("scrim", light: APColorSpec(0x121212, alpha: 0.48), dark: APColorSpec(0x000000, alpha: 0.64))

    /// Doc order, core then support: 25 tokens total (14 + 11).
    static let all: [APColorToken] = [
        background, secondaryBackground, surface, primaryText, secondaryText, separator,
        accent, onAccent, selectedBackground, selectedForeground, success, warning, error, disabled,
        accentText, accentPressed, controlFill, controlFillPressed, cardStroke, outline, onError,
        successSurface, warningSurface, errorSurface, scrim
    ]
}

extension AP {
    /// Semantic colour roles. Screens read these, never a hex literal.
    enum Color {
        /// The 25 documented tokens, for token-integrity tests.
        static let tokens: [APColorToken] = APColorTokens.all

        static let background: SwiftUI.Color = APColorTokens.background.color
        static let secondaryBackground: SwiftUI.Color = APColorTokens.secondaryBackground.color
        static let surface: SwiftUI.Color = APColorTokens.surface.color
        static let primaryText: SwiftUI.Color = APColorTokens.primaryText.color
        static let secondaryText: SwiftUI.Color = APColorTokens.secondaryText.color
        static let separator: SwiftUI.Color = APColorTokens.separator.color
        static let accent: SwiftUI.Color = APColorTokens.accent.color
        static let onAccent: SwiftUI.Color = APColorTokens.onAccent.color
        static let selectedBackground: SwiftUI.Color = APColorTokens.selectedBackground.color
        static let selectedForeground: SwiftUI.Color = APColorTokens.selectedForeground.color
        static let success: SwiftUI.Color = APColorTokens.success.color
        static let warning: SwiftUI.Color = APColorTokens.warning.color
        static let error: SwiftUI.Color = APColorTokens.error.color
        static let disabled: SwiftUI.Color = APColorTokens.disabled.color

        static let accentText: SwiftUI.Color = APColorTokens.accentText.color
        static let accentPressed: SwiftUI.Color = APColorTokens.accentPressed.color
        static let controlFill: SwiftUI.Color = APColorTokens.controlFill.color
        static let controlFillPressed: SwiftUI.Color = APColorTokens.controlFillPressed.color
        static let cardStroke: SwiftUI.Color = APColorTokens.cardStroke.color
        static let outline: SwiftUI.Color = APColorTokens.outline.color
        static let onError: SwiftUI.Color = APColorTokens.onError.color
        static let successSurface: SwiftUI.Color = APColorTokens.successSurface.color
        static let warningSurface: SwiftUI.Color = APColorTokens.warningSurface.color
        static let errorSurface: SwiftUI.Color = APColorTokens.errorSurface.color
        static let scrim: SwiftUI.Color = APColorTokens.scrim.color
    }
}

/// E1: `0 1 2` + `0 4 12`, black at 8% light / 40% dark, plus the `cardStroke` hairline in dark.
/// SwiftUI's `radius:` is roughly half a CSS blur radius, so `0 1 2` is `radius 1` and `0 4 12` is
/// `radius 6`; the two layers are chained because SwiftUI has no multi-shadow primitive.
struct APElevationModifier<S: InsettableShape>: ViewModifier {
    var level: AP.Elevation
    var shape: S

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let opacity = level.shadowOpacity(for: colorScheme)
        return content
            .shadow(color: .black.opacity(opacity), radius: 1, x: 0, y: 1)
            .shadow(color: .black.opacity(opacity), radius: 6, x: 0, y: 4)
            .overlay {
                if level.addsCardStroke, colorScheme == .dark {
                    shape.strokeBorder(AP.Color.cardStroke, lineWidth: AP.Elevation.strokeWidth)
                }
            }
    }
}

/// Focus ring only: 2 pt stroke, 2 pt outside the control, for keyboard and Switch Control focus.
/// Never a resting border.
enum APFocusRing {
    static let width: CGFloat = 2
    /// The gap between the control edge and the ring's inner edge.
    static let offset: CGFloat = 2

    /// How far past the control edge the stroke's *centre line* has to sit: the ring keeps an
    /// `offset` gap, and a centred stroke of `width` straddles that line by half its thickness.
    static var centerlineOutset: CGFloat { offset + width / 2 }

    /// The ring's band measured from a control edge: with the documented 2 pt gap and 2 pt stroke a
    /// control ending at 100 paints its ring over `102...104`, exactly as artboard 00 draws it.
    static func band(fromControlEdge edge: CGFloat) -> ClosedRange<CGFloat> {
        (edge + offset)...(edge + offset + width)
    }
}

/// The ring is drawn **outside** the shape: the overlay grows by `centerlineOutset` and the stroke is
/// centred on that expanded edge, so its 2 pt land on `offset...(offset + width)` — a real 2 pt gap
/// between the control and the ring instead of a ring hugging the control edge.
struct APFocusRingModifier<S: InsettableShape>: ViewModifier {
    var isFocused: Bool
    var shape: S

    func body(content: Content) -> some View {
        content.overlay(
            shape
                .inset(by: -APFocusRing.centerlineOutset)
                .stroke(AP.Color.outline, lineWidth: APFocusRing.width)
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(false)
        )
    }
}

extension View {
    func apElevation(_ level: AP.Elevation = .e1, cornerRadius: CGFloat = AP.Radius.radius16) -> some View {
        modifier(APElevationModifier(
            level: level,
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ))
    }

    func apFocusRing(isFocused: Bool, cornerRadius: CGFloat = AP.Radius.radius8) -> some View {
        modifier(APFocusRingModifier(
            isFocused: isFocused,
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ))
    }

    /// Pads a small glyph up to a 44 × 44 pt hit area without moving it visually.
    func apMinimumHitTarget(_ side: CGFloat = AP.HitTarget.minimum) -> some View {
        frame(minWidth: side, minHeight: side)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Applies an accessibility identifier only when the caller supplied one.
    @ViewBuilder
    func apIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
