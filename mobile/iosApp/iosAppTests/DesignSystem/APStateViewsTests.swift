import SwiftUI
import UIKit
import XCTest
@testable import iosApp

/// Behaviour of the shared state components: glyph + word pairing, status surfaces, press response,
/// Reduce Motion alternatives and Dynamic Type wrapping.
///
/// Assertions about what a component *draws* go through `APViewProbe`, which renders the hosted view
/// and reads its pixels — reading a constant back would only prove the test agrees with itself.
final class APStateViewsTests: XCTestCase {
    // MARK: - Glyph + word, never colour alone

    func testEveryStateToneShipsARealGlyphAndAWord() {
        XCTAssertEqual(APStateTone.allCases.count, 6)
        for tone in APStateTone.allCases {
            XCTAssertNotNil(UIImage(systemName: tone.glyph), "\(tone.rawValue) glyph is not an SF Symbol")
            XCTAssertNotNil(UIImage(systemName: tone.staticGlyph), "\(tone.rawValue) static glyph is not an SF Symbol")
            XCTAssertFalse(tone.word.isEmpty, "\(tone.rawValue) must pair its glyph with a word")
            XCTAssertEqual(tone.word, tone.word.capitalized, "\(tone.rawValue) word is drawn as a label")
        }
        let words = Set(APStateTone.allCases.map(\.word))
        XCTAssertEqual(words.count, APStateTone.allCases.count, "each state needs its own word")
    }

    func testLoadingUsesAStaticArcWhenMotionIsOff() {
        XCTAssertEqual(APStateTone.loading.staticGlyph, "circle.dashed")
        for tone in APStateTone.allCases where tone != .loading {
            XCTAssertEqual(tone.staticGlyph, tone.glyph, "only loading swaps its glyph for a static arc")
        }
    }

    @MainActor func testStatusWordRowDrawsTheWordItIsGiven() {
        // The word is painted, not only carried in a constant: a longer word widens the ink in the row,
        // and a row that dropped its Text would keep only the glyph.
        let probe = APViewProbe(topAligned(APStateWordRow(tone: .offline, word: "Offline")))
        defer { probe.tearDown() }
        let short = probe.capture()
        let long = probe.render(topAligned(APStateWordRow(tone: .offline, word: "Offline offline offline")))

        // The whole frame, so the assertion does not depend on where the row landed.
        let shortInk = short.inkExtent(inRows: 0..<short.height)
        let longInk = long.inkExtent(inRows: 0..<long.height)
        XCTAssertGreaterThan(shortInk, 0, "the word row must paint the glyph and the word")
        XCTAssertGreaterThan(
            longInk, shortInk + 40,
            "a longer word must widen the painted row (short \(shortInk) pt, long \(longInk) pt)"
        )
    }

    @MainActor func testBannerPaintsItsStatusWordAndCopy() {
        let probe = APViewProbe(APStatusBanner(tone: .warning, title: "Storage almost full", message: "Delete a photo."))
        defer { probe.tearDown() }
        let filled = probe.capture()
        let surfaceRows = filled.rows(paintedWith: 0xFED766)
        guard surfaceRows.count > 24, let first = surfaceRows.first, let last = surfaceRows.last else {
            return XCTFail("the banner must paint its warningSurface fill, painted \(surfaceRows.count) rows")
        }

        XCTAssertGreaterThan(
            filled.inkExtent(inRows: first..<min(first + 20, last), background: APPixel(red: 254, green: 215, blue: 102, alpha: 255)),
            0,
            "the status row must paint its glyph and word"
        )

        // Same tone and title, different copy: the pixels below the status row must change, which only
        // holds while the copy is actually drawn.
        let changed = probe.render(APStatusBanner(tone: .warning, title: "Storage almost full", message: "Buy more space."))
        XCTAssertTrue(
            filled.differs(from: changed, inRows: (first + 20)..<last),
            "a different message must change the copy pixels"
        )
    }

    // MARK: - Status surfaces and glyph contrast

    func testStatusBannersUseTheirDocumentedSurfaces() {
        let expectations: [(APStateTone, APColorToken)] = [
            (.error, APColorTokens.errorSurface),
            (.offline, APColorTokens.warningSurface),
            (.warning, APColorTokens.warningSurface),
            (.success, APColorTokens.successSurface)
        ]
        for (tone, token) in expectations {
            for style in [UIUserInterfaceStyle.light, .dark] {
                XCTAssertEqual(
                    resolvedHex(tone.surface, style: style),
                    resolvedHex(token.color, style: style),
                    "\(tone.rawValue) surface should be \(token.name)"
                )
            }
        }
    }

    func testStateGlyphsClearThreeToOneAgainstTheirSurfaceInBothSchemes() {
        for tone in APStateTone.allCases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                guard let ratio = contrastRatio(tone.glyphColor, on: tone.surface, style: style) else {
                    return XCTFail("\(tone.rawValue) glyph colour is not opaque RGB")
                }
                XCTAssertGreaterThanOrEqual(
                    ratio, 3.0,
                    "\(tone.rawValue) glyph on its surface is \(ratio):1 in \(style == .dark ? "dark" : "light"), need 3:1"
                )
            }
        }
    }

    // MARK: - Pressed tokens and Reduce Motion

    func testPressedFillsStepToOneTokenWithoutChangingTheLabel() {
        XCTAssertEqual(resolvedHex(APButtonKind.primary.fill(isPressed: false)), resolvedHex(AP.Color.accent))
        XCTAssertEqual(resolvedHex(APButtonKind.primary.fill(isPressed: true)), resolvedHex(AP.Color.accentPressed))
        XCTAssertEqual(resolvedHex(APButtonKind.primary.labelColor), resolvedHex(AP.Color.onAccent))
        XCTAssertNotEqual(
            resolvedHex(APButtonKind.primary.fill(isPressed: true)),
            resolvedHex(APButtonKind.primary.fill(isPressed: false)),
            "pressing must visibly change the fill"
        )

        for kind in [APButtonKind.secondary, .chip] {
            XCTAssertEqual(resolvedHex(kind.fill(isPressed: false)), resolvedHex(AP.Color.controlFill))
            XCTAssertEqual(resolvedHex(kind.fill(isPressed: true)), resolvedHex(AP.Color.controlFillPressed))
            XCTAssertEqual(resolvedHex(kind.labelColor(isEnabled: true)), resolvedHex(AP.Color.primaryText))
        }
    }

    func testDisabledControlsGoFlatAndUseTheDisabledLabel() {
        for kind in APButtonKind.allCases {
            XCTAssertEqual(
                resolvedHex(kind.fill(isPressed: true, isEnabled: false)),
                resolvedHex(AP.Color.controlFill),
                "\(kind) disabled fill must be flat controlFill even while pressed"
            )
            XCTAssertEqual(resolvedHex(kind.labelColor(isEnabled: false)), resolvedHex(AP.Color.disabled))
        }
    }

    func testReduceMotionKeepsTheFillStepAndDropsTheScale() {
        XCTAssertEqual(APButtonKind.primary.scale(isPressed: true, reduceMotion: false), 0.97, accuracy: 0.0001)
        XCTAssertEqual(APButtonKind.primary.scale(isPressed: true, reduceMotion: true), 1)
        XCTAssertEqual(APButtonKind.chip.scale(isPressed: false, reduceMotion: false), 1)
        // The fill step survives Reduce Motion: it is the non-motion press cue.
        XCTAssertEqual(
            resolvedHex(APButtonKind.secondary.fill(isPressed: true)),
            resolvedHex(AP.Color.controlFillPressed)
        )
    }

    func testLoadingSkeletonIsStaticUnderReduceMotion() {
        XCTAssertEqual(APSkeleton.opacity(isPulsing: true, reduceMotion: true), APSkeleton.restingOpacity)
        XCTAssertEqual(APSkeleton.opacity(isPulsing: false, reduceMotion: false), APSkeleton.restingOpacity)
        XCTAssertEqual(APSkeleton.opacity(isPulsing: true, reduceMotion: false), APSkeleton.pulsingOpacity)
        XCTAssertLessThan(APSkeleton.pulsingOpacity, APSkeleton.restingOpacity)
        XCTAssertEqual(resolvedHex(AP.Color.controlFill), resolvedHex(APColorTokens.controlFill.color))
    }

    // MARK: - Dynamic Type

    @MainActor func testEmptyStateWrapsInsteadOfTruncatingAtAccessibilitySizes() {
        let view = APEmptyStateView(
            title: "No poses match those filters",
            message: "Try a different category, or clear the filters to see every pose in the library.",
            actionTitle: "Clear filters",
            action: {}
        )
        let large = measure(view.environment(\.dynamicTypeSize, .large), width: 320)
        let accessibility = measure(view.environment(\.dynamicTypeSize, .accessibility5), width: 320)

        XCTAssertGreaterThanOrEqual(
            accessibility.height, large.height * 1.4,
            "card must grow with Dynamic Type instead of clipping its copy (large \(large.height), AX5 \(accessibility.height))"
        )
        XCTAssertGreaterThan(accessibility.width, 0)
    }

    // MARK: - Retry control

    @MainActor func testRetryControlIsPaintedOnlyWhenAnActionIsSupplied() {
        // The retry button is part of the rendered card, not of the model: it is painted only when a
        // retry closure is passed, it keeps a 44 pt hit area, and it paints its label.
        // Tall enough for the whole card: a clipped card would make the button's height a lie.
        let probe = APViewProbe(APErrorStateView(
            title: "Couldn't load poses",
            message: "Check your connection.",
            retry: {}
        ), size: CGSize(width: 320, height: 460))
        defer { probe.tearDown() }
        let painted = probe.capture()
        // The error panel's recovery is the primary action, per `02-poses-home-error`.
        let buttonRows = painted.rows(paintedWith: 0xE89CAE)

        XCTAssertFalse(buttonRows.isEmpty, "the retry control must paint its accent pill")
        XCTAssertGreaterThanOrEqual(
            buttonRows.count, 44,
            "the retry control must keep a 44 pt hit area, painted \(buttonRows.count) pt"
        )
        if let top = buttonRows.first, let bottom = buttonRows.last {
            XCTAssertGreaterThan(
                painted.inkExtent(inRows: top..<(bottom + 1), background: APPixel(red: 232, green: 156, blue: 174, alpha: 255)),
                0,
                "the retry control must paint its label"
            )
        }

        let withoutRetry = probe.render(APErrorStateView(title: "Couldn't load poses", message: "Check your connection."))
        XCTAssertEqual(withoutRetry.width, 320)
        XCTAssertTrue(
            withoutRetry.rows(paintedWith: 0xE89CAE).isEmpty,
            "no retry closure, no retry control"
        )
    }

    // MARK: - Elevation

    @MainActor func testPrimaryActionIsTheOnlyRaisedButtonAndOnlyWhileEnabled() {
        XCTAssertTrue(APButtonKind.primary.usesElevation(isEnabled: true))
        XCTAssertFalse(APButtonKind.primary.usesElevation(isEnabled: false), "a disabled primary goes flat")
        XCTAssertFalse(APButtonKind.secondary.usesElevation(isEnabled: true))
        XCTAssertFalse(APButtonKind.chip.usesElevation(isEnabled: true))

        // Rendered proof: E1 paints a shadow under the enabled primary fill, and none when disabled.
        let probe = APViewProbe(primaryButton(enabled: true), size: CGSize(width: 320, height: 200))
        defer { probe.tearDown() }
        let enabled = probe.capture()
        let disabled = probe.render(primaryButton(enabled: false))

        let enabledFill = enabled.rows(paintedWith: 0xE89CAE)
        let disabledFill = disabled.rows(paintedWith: 0xECE5D8)
        XCTAssertFalse(enabledFill.isEmpty, "the enabled primary action must paint its accent fill")
        XCTAssertFalse(disabledFill.isEmpty, "the disabled primary action must paint the flat controlFill")

        XCTAssertGreaterThan(
            enabled.inkExtent(inRows: shadowBand(below: enabledFill)),
            0,
            "enabled primary must carry the E1 shadow below its fill"
        )
        XCTAssertEqual(
            disabled.inkExtent(inRows: shadowBand(below: disabledFill)),
            0,
            "disabled primary stays flat: no shadow below its fill"
        )
    }

    // MARK: - Helpers

    /// Pins the content to the top-left so "row 0..40" is where the component is drawn.
    @MainActor
    private func topAligned<V: View>(_ view: V) -> some View {
        VStack(alignment: .leading) {
            view
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @MainActor
    private func primaryButton(enabled: Bool) -> some View {
        ZStack {
            Color.white
            Button("Continue") {}
                .buttonStyle(APPrimaryButtonStyle())
                .disabled(!enabled)
                .padding(.horizontal, AP.Space.space48)
        }
        .frame(width: 320, height: 200)
    }

    /// Rows just outside the control's bottom edge, where the E1 shadow lands.
    private func shadowBand(below fillRows: [Int]) -> Range<Int> {
        guard let bottom = fillRows.max() else { return 0..<0 }
        return (bottom + 2)..<(bottom + 14)
    }

    @MainActor
    private func measure<V: View>(_ view: V, width: CGFloat) -> CGSize {
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 0)
        host.view.layoutIfNeeded()
        return host.view.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    private func resolvedHex(_ color: SwiftUI.Color, style: UIUserInterfaceStyle = .light) -> UInt32? {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        guard resolved.cgColor.alpha > 0 else { return nil }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return UInt32(round(red * 255)) << 16 | UInt32(round(green * 255)) << 8 | UInt32(round(blue * 255))
    }

    private func contrastRatio(_ foreground: SwiftUI.Color, on background: SwiftUI.Color,
                               style: UIUserInterfaceStyle) -> Double? {
        guard let fg = luminance(foreground, style: style), let bg = luminance(background, style: style) else { return nil }
        return (max(fg, bg) + 0.05) / (min(fg, bg) + 0.05)
    }

    private func luminance(_ color: SwiftUI.Color, style: UIUserInterfaceStyle) -> Double? {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        func channel(_ value: CGFloat) -> Double {
            let linear = Double(value)
            return linear <= 0.03928 ? linear / 12.92 : pow((linear + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}
