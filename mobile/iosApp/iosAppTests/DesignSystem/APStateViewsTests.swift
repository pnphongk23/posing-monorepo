import SwiftUI
import UIKit
import XCTest
@testable import iosApp

/// Behaviour of the shared state components: glyph + word pairing, status surfaces, press response,
/// Reduce Motion alternatives and Dynamic Type wrapping.
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

    func testBannerSummaryAlwaysLeadsWithTheStateWord() {
        for tone in APStateTone.allCases {
            let banner = APStatusBanner(tone: tone, title: "Something happened", message: "More detail")
            XCTAssertTrue(
                banner.accessibilitySummary.hasPrefix(tone.word),
                "\(tone.rawValue) banner must announce its word first, got: \(banner.accessibilitySummary)"
            )
            XCTAssertTrue(banner.accessibilitySummary.contains("More detail"))
        }
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

    func testStateCopyStaysOnPrimaryText() {
        // Every banner puts its words on primaryText, which is the pair the tokens document at
        // 11:1–17:1 on each status surface; a tinted label would drop below 4.5:1 in light mode.
        for tone in APStateTone.allCases where tone != .empty && tone != .loading {
            let text = AP.Color.primaryText
            for style in [UIUserInterfaceStyle.light, .dark] {
                guard let ratio = contrastRatio(text, on: tone.surface, style: style) else {
                    return XCTFail("no contrast for \(tone.rawValue)")
                }
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(tone.rawValue) copy contrast in \(style == .dark ? "dark" : "light")")
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

    @MainActor func testErrorStateRetryActionIsReachable() {
        // The retry control exists only when a closure is supplied, and it keeps a 44 pt target.
        var retried = false
        let view = APErrorStateView(title: "Couldn’t load poses", message: "Check your connection.", retry: { retried = true })
        let measured = measure(view.environment(\.dynamicTypeSize, .large), width: 320)
        XCTAssertGreaterThan(measured.height, 44)
        XCTAssertFalse(retried, "retry must not fire on appear")
    }

    // MARK: - Helpers

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

    private func contrastRatio(_ foreground: SwiftUI.Color, on background: SwiftUI.Color, style: UIUserInterfaceStyle) -> Double? {
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
