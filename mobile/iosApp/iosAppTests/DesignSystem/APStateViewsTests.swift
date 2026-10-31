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

    // MARK: - The one loading look (F4)

    @MainActor func testLoadingStatePaintsTheSharedSeventyTwoPointCircle() {
        let probe = APViewProbe(APLoadingStateView(label: "Loading jobs"), size: CGSize(width: 393, height: 420))
        defer { probe.tearDown() }
        let painted = probe.capture()

        let circleRows = (0..<painted.height).filter { y in
            (0..<painted.width).contains { x in
                guard let pixel = painted.color(x: x, y: y) else { return false }
                return abs(pixel.red - 250) <= 6 && abs(pixel.green - 224) <= 6 && abs(pixel.blue - 231) <= 6
            }
        }
        guard let top = circleRows.first, let bottom = circleRows.last else {
            return XCTFail("the loading state must paint its accent-tint circle")
        }
        XCTAssertEqual(Double(bottom - top + 1), 72, accuracy: 4, "the loading circle is the shared 72 pt")
    }

    // MARK: - The one state look (F4)

    @MainActor func testEveryStatePanelPaintsOneCentredSeventyTwoPointCircle() {
        // F4: one clean, centred icon — a 72 pt accent-tint circle with the glyph in the accent ink —
        // and no second, offset tile behind it. Asserted on painted pixels for both panel styles, so a
        // style that grew its own artwork again fails here instead of shipping.
        XCTAssertEqual(APStateGlyph.diameter, 72, "F4 fixes the state circle at 72 pt")
        XCTAssertLessThan(APStateGlyph.glyphSize, APStateGlyph.diameter / 2, "the glyph sits inside the circle")

        let probe = APViewProbe(emptyPanel(.card), size: CGSize(width: 393, height: 420), scale: 2)
        defer { probe.tearDown() }

        for (index, style) in [APStateCardStyle.card, .plain].enumerated() {
            let painted = index == 0 ? probe.capture() : probe.render(emptyPanel(style))
            assertOneCentredCircle(in: painted, label: "\(style)")
        }
    }

    @MainActor func testTheErrorStateUsesTheSameCircleAsTheEmptyState() {
        // F4 is one illustration for every state, so the error panel cannot grow a different one (the
        // pre-F4 look put a white tile on top of a red tile — the defect the owner called broken).
        let probe = APViewProbe(
            APErrorStateView(title: "Couldn't load jobs", message: "Check your connection.", retry: {}),
            size: CGSize(width: 393, height: 480),
            scale: 2
        )
        defer { probe.tearDown() }
        assertOneCentredCircle(in: probe.capture(), label: "error panel")
    }

    /// `FeatureStateView` is the entry point the feature screens call (Jobs, Add pose, Saved, account,
    /// camera picker). It must paint the same circle for every tone, not the prototype's icon-less
    /// bordered card it used before F4.
    @MainActor func testFeatureStateViewPaintsTheSharedCircleForEveryTone() {
        let probe = APViewProbe(
            featureState(.error, withAction: true),
            size: CGSize(width: 393, height: 560),
            scale: 2
        )
        defer { probe.tearDown() }

        for (index, tone) in FeatureStateTone.allCases.enumerated() {
            let view = featureState(tone, withAction: tone == .error)
            let painted = index == 0 ? probe.capture() : probe.render(view)
            assertOneCentredCircle(in: painted, label: "FeatureStateView .\(tone.rawValue)")
        }
    }

    /// The circle is the one fixed part: at AX3 the copy wraps and the card grows, while the circle
    /// stays 72 pt and the glyph stays centred inside it.
    @MainActor func testFeatureStateViewKeepsTheCircleAtAccessibilitySizesWhileTheCopyWraps() {
        let large = measure(
            featureState(.error, withAction: true).environment(\.dynamicTypeSize, .large),
            width: 320
        )
        let accessibility = measure(
            featureState(.error, withAction: true).environment(\.dynamicTypeSize, .accessibility3),
            width: 320
        )
        XCTAssertGreaterThan(
            accessibility.height, large.height + 60,
            "the card must grow with Dynamic Type instead of clipping its copy (large \(large.height), AX3 \(accessibility.height))"
        )

        let probe = APViewProbe(
            featureState(.error, withAction: true).environment(\.dynamicTypeSize, .accessibility3),
            size: CGSize(width: 320, height: accessibility.height.rounded(.up)),
            scale: 2
        )
        defer { probe.tearDown() }
        assertOneCentredCircle(in: probe.capture(), label: "AX3")
    }

    /// The call API is what the screens and Maestro depend on: the identifiers a state carries are
    /// applied by the screen on this view, and the action identifier has to reach the shared card's
    /// control. SwiftUI's accessibility tree is not materialised for a unit-test host (see
    /// `JobRowAccessibilityTests`), so the pass-through is pinned at source level.
    func testFeatureStateViewThreadsItsActionIdentifierIntoTheSharedCard() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // DesignSystem
                .deletingLastPathComponent() // iosAppTests
                .deletingLastPathComponent() // iosApp (project dir)
                .appendingPathComponent("iosApp/Core/DesignSystem/AIPoseDesignSystem.swift"),
            encoding: .utf8
        )
        guard let body = source.range(of: "struct FeatureStateView: View {") else {
            return XCTFail("FeatureStateView must still exist at this path")
        }
        let view = source[body.lowerBound...]
        XCTAssertTrue(
            view.contains("actionIdentifier: actionIdentifier"),
            "the action identifier must reach the shared card's control (gallery.empty.openCameraButton)"
        )
        XCTAssertTrue(
            view.contains("tone: tone.stateTone"),
            "the feature tone must map onto the shared tone"
        )
        XCTAssertTrue(
            view.contains(".accessibilityElement(children: actionIdentifier == nil ? .combine : .contain)"),
            "a state without an action stays one combined element; one with an action keeps the button addressable"
        )
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
        // The 44 pt claim belongs to the style, not to how many rows survive the rounded corners: the
        // control's minimum height plus the hit-target helper are what make the target big enough.
        XCTAssertGreaterThanOrEqual(APButtonKind.primary.minimumHeight, AP.HitTarget.minimum)
        XCTAssertGreaterThan(buttonRows.count, 24, "the pill is painted over its whole body")
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

    /// The empty panel in either style, so one probe can render both.
    @MainActor
    private func emptyPanel(_ style: APStateCardStyle) -> some View {
        APEmptyStateView(
            title: "No poses yet",
            message: "Poses you save and extract land here.",
            style: style
        )
    }

    @MainActor
    private func featureState(_ tone: FeatureStateTone, withAction: Bool) -> some View {
        var action: (() -> Void)?
        if withAction { action = {} }
        return FeatureStateView(
            tone: tone,
            title: "Couldn't add pose",
            message: "Pose extraction could not be completed. Try again in a moment.",
            actionTitle: withAction ? "Try again" : nil,
            action: action
        )
    }

    /// Asserts the F4 illustration: exactly one accent-tint circle, 72 pt square, with the accent glyph
    /// centred inside it.
    ///
    /// The circle is measured from the largest *connected* patch of tint pixels, not from a bounding
    /// box over every tint-coloured pixel: the accent primary action's anti-aliased edge also blends to
    /// the tint colour, and a stacked or offset second tile would be a second patch of its own. The
    /// glyph punches a hole through the tint without disconnecting the ring around it, which is why the
    /// connected patch still measures the whole circle.
    @MainActor
    private func assertOneCentredCircle(in painted: APBitmap, label: String, file: StaticString = #filePath, line: UInt = #line) {
        let scale: CGFloat = 2
        let patches = tintPatches(0xFAE0E7, in: painted)
        guard let circlePatch = patches.first else {
            return XCTFail("\(label): the state must paint its accent-tint circle", file: file, line: line)
        }
        let circle = CGRect(
            x: CGFloat(circlePatch.minX) / scale,
            y: CGFloat(circlePatch.minY) / scale,
            width: CGFloat(circlePatch.maxX - circlePatch.minX + 1) / scale,
            height: CGFloat(circlePatch.maxY - circlePatch.minY + 1) / scale
        )
        XCTAssertEqual(Double(circle.width), 72, accuracy: 2, "\(label): the circle is 72 pt wide", file: file, line: line)
        XCTAssertEqual(Double(circle.height), 72, accuracy: 2, "\(label): the circle is 72 pt tall", file: file, line: line)

        // One tile: a second tile would be a patch of its own, not the anti-aliasing fringes the accent
        // primary button leaves behind. The circle stays by far the biggest tint patch.
        let second = patches.dropFirst().first?.area ?? 0
        XCTAssertLessThan(
            second, circlePatch.area / 3,
            "\(label): the tint is one circle, not a stack of tiles (\(patches.count) patches, biggest \(circlePatch.area) px, next \(second) px)",
            file: file, line: line
        )

        guard let glyph = paintedBounds(of: 0x8C3350, in: painted, scale: scale) else {
            return XCTFail("\(label): the state must paint its glyph in the accent ink", file: file, line: line)
        }
        XCTAssertTrue(
            circle.contains(glyph),
            "\(label): the glyph sits inside the circle (glyph \(glyph), circle \(circle))", file: file, line: line
        )
        XCTAssertEqual(glyph.midX, circle.midX, accuracy: 2, "\(label): the glyph is centred horizontally", file: file, line: line)
        XCTAssertEqual(glyph.midY, circle.midY, accuracy: 2, "\(label): the glyph is centred vertically", file: file, line: line)
    }

    /// One connected patch of pixels painted with the same colour, in pixel coordinates.
    private struct TintPatch {
        let minX: Int
        let maxX: Int
        let minY: Int
        let maxY: Int
        let area: Int
    }

    /// Connected patches (4-neighbour) of `hex`, biggest first.
    private func tintPatches(_ hex: UInt32, in bitmap: APBitmap) -> [TintPatch] {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        func matches(_ x: Int, _ y: Int) -> Bool {
            guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { return false }
            return abs(pixel.red - target.red) <= 6
                && abs(pixel.green - target.green) <= 6
                && abs(pixel.blue - target.blue) <= 6
        }

        var seen = [Bool](repeating: false, count: bitmap.width * bitmap.height)
        var patches: [TintPatch] = []
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where !seen[y * bitmap.width + x] && matches(x, y) {
                var stack = [(x, y)]
                seen[y * bitmap.width + x] = true
                var patch = TintPatch(minX: x, maxX: x, minY: y, maxY: y, area: 0)
                while let (cx, cy) = stack.popLast() {
                    patch = TintPatch(
                        minX: min(patch.minX, cx), maxX: max(patch.maxX, cx),
                        minY: min(patch.minY, cy), maxY: max(patch.maxY, cy),
                        area: patch.area + 1
                    )
                    for (nx, ny) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)] {
                        guard nx >= 0, nx < bitmap.width, ny >= 0, ny < bitmap.height else { continue }
                        guard !seen[ny * bitmap.width + nx], matches(nx, ny) else { continue }
                        seen[ny * bitmap.width + nx] = true
                        stack.append((nx, ny))
                    }
                }
                patches.append(patch)
            }
        }
        return patches.sorted { $0.area > $1.area }
    }

    /// Bounding box of the pixels painted with `hex`, in points.
    private func paintedBounds(
        of hex: UInt32,
        in bitmap: APBitmap,
        scale: CGFloat,
        tolerance: Int = 6
    ) -> CGRect? {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        var minX = Int.max
        var maxX = Int.min
        var minY = Int.max
        var maxY = Int.min
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { continue }
                guard abs(pixel.red - target.red) <= tolerance,
                      abs(pixel.green - target.green) <= tolerance,
                      abs(pixel.blue - target.blue) <= tolerance else { continue }
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return nil }
        return CGRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
    }

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
