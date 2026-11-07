import SwiftUI
import UIKit
import XCTest
@testable import iosApp

/// Token integrity for the DS-261030 direction-B layer.
///
/// Every expected value here is re-transcribed from `tokens.md` (independent of the Swift constants),
/// so a drifting hex, spacing value or contrast pair fails the build instead of silently re-skinning
/// the app. Contrast is computed from the **resolved** `UIColor` for each scheme, so the dynamic
/// light/dark provider is exercised too.
final class APDesignTokensTests: XCTestCase {
    // MARK: - Documented data

    private struct DocumentedColor {
        let name: String
        let light: UInt32?
        let dark: UInt32?
        let lightAlpha: Double
        let darkAlpha: Double

        init(name: String, light: UInt32?, dark: UInt32?, lightAlpha: Double = 1, darkAlpha: Double = 1) {
            self.name = name
            self.light = light
            self.dark = dark
            self.lightAlpha = lightAlpha
            self.darkAlpha = darkAlpha
        }
    }

    /// `tokens.md` § "Colour tokens": 14 core then 11 support plus Poses' neutral selection role.
    private static let documentedColors: [DocumentedColor] = [
        .init(name: "background", light: 0xFBF6EF, dark: 0x141210),
        .init(name: "secondaryBackground", light: 0xF4F1E8, dark: 0x1D1A17),
        .init(name: "surface", light: 0xFFFFFF, dark: 0x272320),
        .init(name: "primaryText", light: 0x121212, dark: 0xF7F2EA),
        .init(name: "secondaryText", light: 0x5E574C, dark: 0xB5ADA2),
        .init(name: "separator", light: 0xDDD5C7, dark: 0x46403A),
        .init(name: "accent", light: 0xE89CAE, dark: 0xE89CAE),
        .init(name: "onAccent", light: 0x121212, dark: 0x121212),
        .init(name: "selectedBackground", light: 0xFAE0E7, dark: 0x4B2B36),
        .init(name: "selectedForeground", light: 0x8C3350, dark: 0xFAE0E7),
        .init(name: "selectedNeutralBackground", light: 0x24211E, dark: 0xE8DFD3),
        .init(name: "success", light: 0x1E7A3C, dark: 0xB5E2B9),
        .init(name: "warning", light: 0x8A5A00, dark: 0xFED766),
        .init(name: "error", light: 0xC8302F, dark: 0xFF6B6B),
        .init(name: "disabled", light: 0x8F887C, dark: 0x6F685F),
        .init(name: "accentText", light: 0x8C3350, dark: 0xF2B6C4),
        .init(name: "accentPressed", light: 0xD47A90, dark: 0xD47A90),
        .init(name: "controlFill", light: 0xECE5D8, dark: 0x35302B),
        .init(name: "controlFillPressed", light: 0xDDD5C7, dark: 0x46403A),
        .init(name: "cardStroke", light: nil, dark: 0x7A7268),
        .init(name: "outline", light: 0x121212, dark: 0xE8DFD3),
        .init(name: "onError", light: 0xFFFFFF, dark: 0x121212),
        .init(name: "successSurface", light: 0xB5E2B9, dark: 0x1F3A28),
        .init(name: "warningSurface", light: 0xFED766, dark: 0x3D3210),
        .init(name: "errorSurface", light: 0xFFF4F5, dark: 0x3A1C1E),
        .init(name: "scrim", light: 0x121212, dark: 0x000000, lightAlpha: 0.48, darkAlpha: 0.64)
    ]

    private struct ContrastPair {
        let foreground: String
        let background: String
        /// Documented ratio, light · dark. `nil` where `tokens.md` documents no ratio.
        let light: Double?
        let dark: Double?
        /// WCAG floors, or `nil` where no floor is claimed for that scheme.
        let lightMinimum: Double?
        let darkMinimum: Double?
        /// Upper bounds for the pairs `tokens.md` explicitly says are too weak to carry meaning.
        let lightMaximum: Double?
        let darkMaximum: Double?

        init(_ foreground: String, on background: String,
             light: Double? = nil, dark: Double? = nil,
             minimum: Double? = nil, lightMax: Double? = nil, darkMax: Double? = nil) {
            self.foreground = foreground
            self.background = background
            self.light = light
            self.dark = dark
            self.lightMinimum = minimum
            self.darkMinimum = minimum
            self.lightMaximum = lightMax
            self.darkMaximum = darkMax
        }

        func documented(for style: UIUserInterfaceStyle) -> Double? {
            style == .dark ? dark : light
        }
    }

    /// `tokens.md` § "Colour tokens" pairs plus the artboard's two caution notes.
    private static let contrastPairs: [ContrastPair] = [
        .init("primaryText", on: "background", light: 17.4, dark: 16.8, minimum: 4.5),
        .init("primaryText", on: "secondaryBackground", light: 16.6, dark: 15.5, minimum: 4.5),
        .init("primaryText", on: "surface", light: 18.7, dark: 14.0, minimum: 4.5),
        .init("secondaryText", on: "background", light: 6.6, dark: 8.4, minimum: 4.5),
        .init("secondaryText", on: "surface", minimum: 4.5),
        .init("onAccent", on: "accent", light: 8.7, dark: 8.7, minimum: 4.5),
        .init("onAccent", on: "accentPressed", light: 6.2, dark: 6.2, minimum: 4.5),
        .init("selectedForeground", on: "selectedBackground", light: 6.2, dark: 9.9, minimum: 4.5),
        .init("background", on: "selectedNeutralBackground", minimum: 4.5),
        .init("primaryText", on: "controlFill", light: 15.0, dark: 11.7, minimum: 4.5),
        .init("primaryText", on: "controlFillPressed", light: 12.9, dark: 9.2, minimum: 4.5),
        .init("success", on: "background", light: 5.0, dark: 12.9, minimum: 4.5),
        .init("warning", on: "background", light: 5.5, dark: 13.5, minimum: 4.5),
        .init("error", on: "background", light: 5.0, dark: 6.7, minimum: 4.5),
        .init("accentText", on: "background", light: 7.2, dark: 10.9, minimum: 4.5),
        .init("accentText", on: "surface", minimum: 4.5),
        .init("onError", on: "error", light: 5.4, dark: 6.8, minimum: 4.5),
        .init("primaryText", on: "successSurface", light: 13.0, dark: 11.1, minimum: 4.5),
        .init("primaryText", on: "warningSurface", light: 13.5, dark: 11.3, minimum: 4.5),
        .init("primaryText", on: "errorSurface", light: 17.4, dark: 13.8, minimum: 4.5),
        .init("outline", on: "background", light: 17.4, dark: 14.2, minimum: 3.0),
        // Dark card edge: the only thing separating an E1 card from the dark canvas.
        .init("cardStroke", on: "background", dark: 3.95, minimum: 3.9),
        .init("cardStroke", on: "surface", dark: 3.29, minimum: 3.0),
        // Documented as *below* the floor: identification never rests on the pink fill edge, and a
        // light card never relies on its outline.
        .init("accent", on: "background", light: 2.0, dark: 8.7, lightMax: 3.0),
        .init("surface", on: "background", light: 1.1, dark: 1.2, lightMax: 3.0, darkMax: 3.0)
    ]

    // MARK: - Colour integrity

    func testEveryDocumentedColorTokenResolvesToItsLightAndDarkHex() {
        XCTAssertEqual(AP.Color.tokens.count, 26, "14 core + 11 support + neutral selection")
        let byName = Dictionary(uniqueKeysWithValues: AP.Color.tokens.map { ($0.name, $0) })

        for documented in Self.documentedColors {
            guard let token = byName[documented.name] else {
                XCTFail("AP.Color has no token named \(documented.name)")
                continue
            }
            XCTAssertEqual(token.light.hex, documented.light, "\(documented.name) light value")
            XCTAssertEqual(token.dark.hex, documented.dark, "\(documented.name) dark value")

            assertResolved(token, style: .light, matches: documented.light,
                           alpha: documented.lightAlpha, label: "\(documented.name) light")
            assertResolved(token, style: .dark, matches: documented.dark,
                           alpha: documented.darkAlpha, label: "\(documented.name) dark")
        }
    }

    func testScrimKeepsItsDocumentedAlphaPerScheme() {
        guard let scrim = AP.Color.tokens.first(where: { $0.name == "scrim" }) else {
            return XCTFail("missing scrim token")
        }
        XCTAssertEqual(scrim.light.alpha, 0.48, accuracy: 0.001)
        XCTAssertEqual(scrim.dark.alpha, 0.64, accuracy: 0.001)
    }

    func testSemanticRolesResolveToTheirDocumentedHexInBothSchemes() {
        // A role wired to the wrong token still resolves to a *valid* colour, so pin each role to the
        // documented hex through the SwiftUI colour the screens actually read.
        let roles: [(String, SwiftUI.Color)] = [
            ("background", AP.Color.background),
            ("secondaryBackground", AP.Color.secondaryBackground),
            ("surface", AP.Color.surface),
            ("primaryText", AP.Color.primaryText),
            ("secondaryText", AP.Color.secondaryText),
            ("separator", AP.Color.separator),
            ("accent", AP.Color.accent),
            ("onAccent", AP.Color.onAccent),
            ("selectedBackground", AP.Color.selectedBackground),
            ("selectedForeground", AP.Color.selectedForeground),
            ("selectedNeutralBackground", AP.Color.selectedNeutralBackground),
            ("success", AP.Color.success),
            ("warning", AP.Color.warning),
            ("error", AP.Color.error),
            ("disabled", AP.Color.disabled),
            ("accentText", AP.Color.accentText),
            ("accentPressed", AP.Color.accentPressed),
            ("controlFill", AP.Color.controlFill),
            ("controlFillPressed", AP.Color.controlFillPressed),
            ("cardStroke", AP.Color.cardStroke),
            ("outline", AP.Color.outline),
            ("onError", AP.Color.onError),
            ("successSurface", AP.Color.successSurface),
            ("warningSurface", AP.Color.warningSurface),
            ("errorSurface", AP.Color.errorSurface),
            ("scrim", AP.Color.scrim)
        ]
        let documented = Dictionary(uniqueKeysWithValues: Self.documentedColors.map { ($0.name, $0) })
        XCTAssertEqual(roles.count, 26)

        for (name, role) in roles {
            guard let expected = documented[name] else {
                XCTFail("no documented value for \(name)")
                continue
            }
            assertResolved(role, style: .light, matches: expected.light,
                           alpha: expected.lightAlpha, label: "AP.Color.\(name) light")
            assertResolved(role, style: .dark, matches: expected.dark,
                           alpha: expected.darkAlpha, label: "AP.Color.\(name) dark")
        }
    }

    // MARK: - Contrast

    func testDocumentedTextAndSurfacePairsMeetWCAGInBothSchemes() {
        for pair in Self.contrastPairs {
            for scheme in [UIUserInterfaceStyle.light, .dark] {
                let isDark = scheme == .dark
                let documented = pair.documented(for: scheme)
                let floor = (isDark ? pair.darkMinimum : pair.lightMinimum) ?? 0
                let ceiling = (isDark ? pair.darkMaximum : pair.lightMaximum) ?? .greatestFiniteMagnitude
                guard let ratio = contrastRatio(pair.foreground, on: pair.background, style: scheme) else {
                    // Light cardStroke paints nothing, so there is no edge to measure there — and
                    // tokens.md documents no light value for it either.
                    XCTAssertNil(documented, "\(pair.foreground) → \(pair.background) has no \(isDark ? "dark" : "light") colour")
                    continue
                }
                let label = "\(pair.foreground) on \(pair.background) (\(isDark ? "dark" : "light"))"

                XCTAssertGreaterThanOrEqual(ratio, floor, "\(label) = \(formatted(ratio)), below the \(floor):1 floor")
                XCTAssertLessThanOrEqual(ratio, ceiling, "\(label) = \(formatted(ratio)), expected at most \(formatted(ceiling)):1")
                if let documented {
                    XCTAssertEqual(
                        ratio, documented, accuracy: 0.06,
                        "\(label) = \(formatted(ratio)); tokens.md documents \(formatted(documented))"
                    )
                }
            }
        }
    }

    // MARK: - Spacing and radius

    func testSpacingTokensMatchTheDocumentedScale() {
        XCTAssertEqual(AP.Space.space4, 4)
        XCTAssertEqual(AP.Space.space8, 8)
        XCTAssertEqual(AP.Space.space12, 12)
        XCTAssertEqual(AP.Space.space16, 16)
        XCTAssertEqual(AP.Space.space24, 24)
        XCTAssertEqual(AP.Space.space32, 32)
        XCTAssertEqual(AP.Space.space48, 48)

        let scale = [AP.Space.space4, AP.Space.space8, AP.Space.space12, AP.Space.space16,
                     AP.Space.space24, AP.Space.space32, AP.Space.space48]
        XCTAssertEqual(scale, scale.sorted(), "spacing must be an ascending 4 pt scale")
        XCTAssertTrue(scale.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 }, "4 pt base")
    }

    func testRadiusTokensMatchTheDocumentedScale() {
        XCTAssertEqual(AP.Radius.radius8, 8)
        XCTAssertEqual(AP.Radius.radius16, 16)
        XCTAssertEqual(AP.Radius.radius24, 24)
    }

    func testFocusRingGeometryIsA2PointStrokeAfterA2PointGap() {
        XCTAssertEqual(APFocusRing.width, 2, "the ring itself is 2 pt")
        XCTAssertEqual(APFocusRing.offset, 2, "the ring's inner edge sits 2 pt outside the control")
        XCTAssertEqual(APFocusRing.centerlineOutset, 3, "a centred 2 pt stroke straddles offset + width/2")
        XCTAssertEqual(APFocusRing.band(fromControlEdge: 100), 102...104)
        XCTAssertEqual(APFocusRing.band(fromControlEdge: 0), 2...4)
    }

    @MainActor func testFocusRingPaintsTwoPointsOutsideTheControlWithATwoPointGap() {
        // Rendered proof of the documented geometry, captured at 2× so a half-point layout phase cannot
        // turn a band into a one-pixel lie. Everything below is in capture pixels inside the row that
        // crosses the control's right edge.
        let probe = probeWithFocusRing(isFocused: true)
        defer { probe.tearDown() }
        let painted = probe.capture()
        guard let band = ringBand(inRow: 120, of: painted) else {
            return XCTFail("no ring painted on the control's mid line")
        }

        XCTAssertEqual(band.ringPixels, 4, "the stroke is 2 pt = 4 px at 2×")
        XCTAssertGreaterThanOrEqual(band.gapPixels, 3, "the ring keeps a 2 pt = 4 px gap from the control")
        XCTAssertLessThanOrEqual(band.gapPixels, 5, "the gap is 2 pt, not more")

        let unfocused = probeWithFocusRing(isFocused: false)
        defer { unfocused.tearDown() }
        XCTAssertNil(
            ringBand(inRow: 120, of: unfocused.capture()),
            "no focus, no ring: the outline is never a resting border"
        )
    }

    @MainActor func testFocusRingDoesNotChangeTheControlLayout() {
        let plain = measure(Color.white.frame(width: 80, height: 80), width: 200)
        let ringed = measure(Color.white.frame(width: 80, height: 80).apFocusRing(isFocused: true), width: 200)
        XCTAssertEqual(plain, ringed, "the ring paints outside the bounds and takes no layout space")
    }

    // MARK: - Hit target

    @MainActor func testMinimumHitTargetHelperYieldsAtLeast44Points() {
        XCTAssertEqual(AP.HitTarget.minimum, 44)

        let tiny = Text("x").font(AP.Font.caption).apMinimumHitTarget()
        let measured = measure(tiny, width: 200)
        XCTAssertGreaterThanOrEqual(measured.width, 44, "hit area must be at least 44 pt wide")
        XCTAssertGreaterThanOrEqual(measured.height, 44, "hit area must be at least 44 pt tall")

        let custom = Text("x").apMinimumHitTarget(56)
        let customMeasured = measure(custom, width: 200)
        XCTAssertGreaterThanOrEqual(customMeasured.height, 56)
    }

    // MARK: - Typography

    func testTypographyRolesMapToTheSevenDocumentedTextStyles() {
        XCTAssertEqual(AP.Font.Role.allCases.count, 7)
        XCTAssertEqual(AP.Font.Role.display.textStyle, .largeTitle)
        XCTAssertEqual(AP.Font.Role.title.textStyle, .title2)
        XCTAssertEqual(AP.Font.Role.heading.textStyle, .headline)
        XCTAssertEqual(AP.Font.Role.body.textStyle, .body)
        XCTAssertEqual(AP.Font.Role.supporting.textStyle, .subheadline)
        XCTAssertEqual(AP.Font.Role.caption.textStyle, .footnote)
        XCTAssertEqual(AP.Font.Role.data.textStyle, .title3)
    }

    @MainActor func testTypeRolesGrowWithDynamicType() {
        let large = AP.Font.Role.allCases.map { height(of: $0, at: .large) }
        let accessibility = AP.Font.Role.allCases.map { height(of: $0, at: .accessibility3) }
        for (role, pair) in zip(AP.Font.Role.allCases, zip(large, accessibility)) {
            XCTAssertGreaterThan(
                pair.1, pair.0 * 1.3,
                "\(role.rawValue) must scale with Dynamic Type (large \(pair.0) → AX3 \(pair.1))"
            )
        }
        // display is the largest role at the default size, caption the smallest.
        XCTAssertGreaterThan(large[0], large[1])
        XCTAssertGreaterThan(large[1], large[5])
    }

    // MARK: - Helpers

    @MainActor
    private func height(of role: AP.Font.Role, at size: DynamicTypeSize) -> CGFloat {
        measure(Text("Pose").font(role.font).environment(\.dynamicTypeSize, size), width: 400).height
    }

    /// An 80 × 80 white control centred on the secondaryBackground canvas, so its edge is detectable.
    @MainActor
    private func probeWithFocusRing(isFocused: Bool) -> APViewProbe {
        let view = ZStack {
            Color(hex: 0xF4F1E8)
            Color.white
                .frame(width: 80, height: 80)
                .apFocusRing(isFocused: isFocused, cornerRadius: AP.Radius.radius8)
        }
        .frame(width: 120, height: 120)
        return APViewProbe(view, size: CGSize(width: 120, height: 120), scale: 2)
    }

    /// The ring as the renderer painted it on one row: how many pixels are canvas between the control's
    /// edge and the ring, and how many pixels the ring itself covers.
    private struct RenderedRing {
        let gapPixels: Int
        let ringPixels: Int
    }

    private func ringBand(inRow y: Int, of bitmap: APBitmap) -> RenderedRing? {
        var gap: Int?
        var ring: Int?
        var x = bitmap.width / 2
        // Skip the control, which is pure white.
        while x < bitmap.width, (bitmap.color(x: x, y: y)?.red ?? 0) >= 250 { x += 1 }
        // Then the gap, until the ring starts.
        while x < bitmap.width, (bitmap.color(x: x, y: y)?.red ?? 0) > 120 {
            gap = (gap ?? 0) + 1
            x += 1
        }
        // Then the ring itself.
        while x < bitmap.width, (bitmap.color(x: x, y: y)?.red ?? 255) < 120 {
            ring = (ring ?? 0) + 1
            x += 1
        }
        guard let gap, let ring else { return nil }
        return RenderedRing(gapPixels: gap, ringPixels: ring)
    }

    @MainActor
    func measure<V: View>(_ view: V, width: CGFloat) -> CGSize {
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 0)
        host.view.layoutIfNeeded()
        return host.view.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    private func assertResolved(_ token: APColorToken, style: UIUserInterfaceStyle,
                                matches hex: UInt32?, alpha expectedAlpha: Double, label: String) {
        assertResolved(token.color, resolvedWith: style, matches: hex, alpha: expectedAlpha, label: label)
    }

    private func assertResolved(_ color: SwiftUI.Color, style: UIUserInterfaceStyle,
                                matches hex: UInt32?, alpha expectedAlpha: Double, label: String) {
        assertResolved(color, resolvedWith: style, matches: hex, alpha: expectedAlpha, label: label)
    }

    private func assertResolved(_ color: SwiftUI.Color, resolvedWith style: UIUserInterfaceStyle,
                                matches hex: UInt32?, alpha expectedAlpha: Double, label: String) {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        guard let hex else {
            XCTAssertEqual(resolved.cgColor.alpha, 0, "\(label) should paint nothing")
            return
        }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha), "\(label) is not RGB")
        XCTAssertEqual(round(red * 255), CGFloat((hex >> 16) & 0xFF), "\(label) red")
        XCTAssertEqual(round(green * 255), CGFloat((hex >> 8) & 0xFF), "\(label) green")
        XCTAssertEqual(round(blue * 255), CGFloat(hex & 0xFF), "\(label) blue")
        XCTAssertEqual(alpha, expectedAlpha, accuracy: 0.005, "\(label) alpha")
    }

    /// WCAG 2.1 relative luminance and contrast ratio from the *resolved* dynamic colours.
    private func contrastRatio(_ foreground: String, on background: String, style: UIUserInterfaceStyle) -> Double? {
        guard let fg = luminance(of: foreground, style: style),
              let bg = luminance(of: background, style: style) else { return nil }
        let lighter = max(fg, bg)
        let darker = min(fg, bg)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(of name: String, style: UIUserInterfaceStyle) -> Double? {
        guard let token = AP.Color.tokens.first(where: { $0.name == name }) else {
            XCTFail("unknown token \(name)")
            return nil
        }
        let scheme: ColorScheme = style == .dark ? .dark : .light
        guard token.spec(for: scheme).hex != nil else { return nil }
        let color = token.resolvedColor(for: style)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        func channel(_ value: CGFloat) -> Double {
            let linear = Double(value)
            return linear <= 0.03928 ? linear / 12.92 : pow((linear + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
