import Combine
import SwiftUI
import UIKit
import XCTest
@testable import iosApp

/// What the paywall *draws*, measured on a rendered frame: the iPhone SE (375×667) purchase region,
/// the Accessibility sizes, the status-bar scrim's contrast over the hero, and dark mode resolving
/// from the same tokens. Everything here is a pixel or geometry assertion on real SwiftUI output
/// (`APViewProbe`), not a snapshot diff; the device-level flows stay Maestro's job.
@MainActor
final class PaywallScreenLayoutTests: XCTestCase {
    private let se = CGSize(width: 375, height: 667)
    private let phone = CGSize(width: 430, height: 932)
    /// A standard 6.1" notched phone (iPhone 15/16), the second frame the build-21 feedback names.
    private let standard = CGSize(width: 393, height: 852)
    private let scale: CGFloat = 2

    /// The two frames the build-21 feedback names. The probe draws into a real key window, so it
    /// carries the host simulator's insets (59 pt of status bar, 0–34 pt of home indicator): the SE
    /// frame is therefore *stricter* than the phone it is named after, which has a 20 pt status bar
    /// and no home indicator, and the assertions subtract the bottom inset they measure.
    private var purchaseRegionFrames: [(name: String, size: CGSize)] {
        [("iPhone SE", se), ("6.1\" phone", standard)]
    }

    // MARK: - Fixtures

    @MainActor
    private final class Gateway: PurchaseGateway {
        private let subject: CurrentValueSubject<PurchaseSnapshot, Never>
        var snapshot: PurchaseSnapshot { subject.value }
        var snapshots: AnyPublisher<PurchaseSnapshot, Never> { subject.eraseToAnyPublisher() }
        private let nextLoad: PurchaseSnapshot

        init(nextLoad: PurchaseSnapshot) {
            self.nextLoad = nextLoad
            subject = CurrentValueSubject(PurchaseSnapshot(state: .notEntitled, products: []))
        }

        func loadOffering() async -> PurchaseSnapshot {
            subject.send(nextLoad)
            return nextLoad
        }

        func purchase(packageID: String) async -> PurchaseSnapshot { subject.value }
        func restore() async -> PurchaseSnapshot { subject.value }
    }

    private let annual = PurchaseProduct(
        identifier: "annual", packageType: .annual, localizedPrice: "$39.99", period: "year"
    )
    private let monthly = PurchaseProduct(
        identifier: "monthly", packageType: .monthly, localizedPrice: "$5.99", period: "month"
    )
    private var offering: PurchaseSnapshot {
        PurchaseSnapshot(state: .notEntitled, products: [monthly, annual])
    }

    /// A second offering for the "no price above the CTA" measurement: different amounts, the same
    /// card geometry (a saving badge on both cards), so only the printed money can change pixels.
    private var dearOffering: PurchaseSnapshot {
        PurchaseSnapshot(state: .notEntitled, products: [
            PurchaseProduct(identifier: "monthly", packageType: .monthly, localizedPrice: "$9.99", period: "month"),
            PurchaseProduct(identifier: "annual", packageType: .annual, localizedPrice: "$79.99", period: "year"),
        ])
    }

    /// A model that already settled on a real offering, so the captured frame is a final state.
    private func signedInModel(offering: PurchaseSnapshot? = nil) async -> PaywallModel {
        let model = PaywallModel(
            gateway: Gateway(nextLoad: offering ?? self.offering),
            boundary: SessionBoundary(
                tokenStorage: PaywallLayoutTokenStorage(
                    credentials: SessionCredentials(accessToken: "access", refreshToken: "refresh")
                )
            ),
            signInAction: SignInAction(start: {}),
            connectivity: PaywallLayoutConnectivity()
        )
        model.start()
        let deadline = Date().addingTimeInterval(3)
        while model.phase != .ready && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(model.phase, .ready)
        return model
    }

    /// The same offering, no session: the cards still show the store's prices and the CTA is sign-in.
    private func signedOutModel() async -> PaywallModel {
        let model = PaywallModel(
            gateway: Gateway(nextLoad: offering),
            boundary: SessionBoundary(tokenStorage: PaywallLayoutTokenStorage()),
            signInAction: SignInAction(start: {}),
            connectivity: PaywallLayoutConnectivity()
        )
        model.start()
        let deadline = Date().addingTimeInterval(3)
        while model.phase != .signInRequired && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(model.phase, .signInRequired)
        return model
    }

    /// Renders at an explicit size, type size and interface style. The style goes on the probe's key
    /// window, because the design tokens are dynamic `UIColor`s and resolve from the trait collection
    /// (a SwiftUI `colorScheme` environment value would not repaint them).
    private func render(
        _ model: PaywallModel,
        size: CGSize,
        type: DynamicTypeSize = .large,
        style: UIUserInterfaceStyle = .light
    ) -> APBitmap {
        let screen = PaywallScreen(model: model)
            .environment(\.dynamicTypeSize, type)
            .environment(\.sizeCategory, type.contentSizeCategory)
        let probe = APViewProbe(screen, size: size, scale: scale)
        let window = UIApplication.shared.windows.first(where: \.isKeyWindow)
        window?.overrideUserInterfaceStyle = style
        let bitmap = probe.render(screen)
        // The probe's window is shared by every view test in the bundle: leaving a pinned style here
        // would repaint the next test's tokens, so the override ends with this capture.
        window?.overrideUserInterfaceStyle = .unspecified
        probe.tearDown()
        return bitmap
    }

    // MARK: - Hero metrics

    func testHeroHeightIsClampedOnSmallAndLargePhones() {
        XCTAssertEqual(
            PaywallHeroMetrics.height(for: 667), 140, accuracy: 0.5,
            "an SE container: what is left once the purchase region has its floor"
        )
        XCTAssertEqual(PaywallHeroMetrics.height(for: 932), 261, accuracy: 0.5, "a 6.7\" container keeps the 28 %")
        XCTAssertEqual(PaywallHeroMetrics.height(for: 480), 118, "never smaller than the 118 pt floor")
        XCTAssertEqual(PaywallHeroMetrics.height(for: 1800), 312, "never taller than the 312 pt ceiling")

        // The invariant the feedback is about: wherever the hero takes its share, everything that has
        // to stay on screen still fits under it.
        for containerHeight in [663.0, 667, 759, 852, 932] {
            XCTAssertLessThanOrEqual(
                PaywallHeroMetrics.height(for: containerHeight) + PaywallHeroMetrics.purchaseRegionFloor,
                containerHeight,
                "at \(containerHeight) pt the hero leaves the purchase region its whole height"
            )
        }
    }

    // MARK: - iPhone SE: purchase region and escape hatch

    func testSEKeepsTheCloseCtaAndLegalRowInsideTheFrame() async {
        let bitmap = render(await signedInModel(), size: se)

        let cta = bitmap.rows(paintedWith: 0xE89CAE)
        XCTAssertFalse(cta.isEmpty, "the pinned CTA must be painted at 375×667")
        let ctaHeight = Double(cta.count) / Double(scale)
        XCTAssertGreaterThanOrEqual(ctaHeight, 44, "the CTA paints at least the 44 pt hit target")
        XCTAssertLessThan(cta.max()!, bitmap.height - 1, "the CTA is inside the viewport, not clipped")

        let legal = bitmap.rows(paintedWith: 0x8C3350).filter { $0 > cta.max()! }
        XCTAssertFalse(legal.isEmpty, "Restore/Terms/Privacy stay on the first screen below the CTA")
        XCTAssertLessThan(legal.max()!, bitmap.height - 1, "the legal row is never pushed off the bottom")
        let legalInk = bitmap.inkExtent(
            inRows: legal.min()!..<(legal.max()! + 1),
            background: UIColor.tokenPixel(APColorTokens.background.light.uiColor)
        )
        XCTAssertGreaterThan(
            legalInk,
            bitmap.width / 2,
            "all three links are painted across the row, not truncated to one label"
        )

        XCTAssertNotNil(
            closeButton(in: bitmap),
            "the 44 pt close is painted in the first frame, top-trailing, with its X"
        )
    }

    func testXXXLargeKeepsTheCtaAndLegalRowInsideTheFrame() async {
        let bitmap = render(await signedInModel(), size: se, type: .xxxLarge)

        let cta = bitmap.rows(paintedWith: 0xE89CAE)
        XCTAssertFalse(cta.isEmpty, "the CTA survives the larger type at 375 pt")
        XCTAssertGreaterThanOrEqual(Double(cta.count) / Double(scale), 44)
        XCTAssertLessThan(cta.max()!, bitmap.height - 1)

        let legal = bitmap.rows(paintedWith: 0x8C3350).filter { $0 > cta.max()! }
        XCTAssertFalse(legal.isEmpty, "the legal row is still pinned below the CTA at .xxxLarge")
        XCTAssertLessThan(legal.max()!, bitmap.height - 1)
        XCTAssertNotNil(closeButton(in: bitmap))
    }

    func testAccessibilitySizesKeepTheCtaPinnedAndMoveTheLegalRowIntoTheScroll() async {
        for type in [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5] {
            let bitmap = render(await signedInModel(), size: se, type: type)
            let cta = bitmap.rows(paintedWith: 0xE89CAE)
            XCTAssertFalse(cta.isEmpty, "the CTA stays tappable at \(type)")
            XCTAssertLessThan(cta.max()!, bitmap.height - 1, "the CTA is inside the bounds at \(type)")
            XCTAssertFalse(
                PaywallScreen.pinsLegalRow(at: type),
                "at \(type) the legal row moves into the scroll content (reachable, never clipped)"
            )
            XCTAssertNotNil(closeButton(in: bitmap), "the close stays visible at \(type)")
        }
        XCTAssertTrue(PaywallScreen.pinsLegalRow(at: .large))
        XCTAssertTrue(PaywallScreen.pinsLegalRow(at: .xxxLarge))
    }

    // MARK: - Plan cards inside the first screen (build 21)

    /// The reported defect: the Monthly card sat under the dock with its price half hidden. Everything
    /// here is measured on the rendered frame — where the plate is, how wide it paints on its own
    /// first and last rows, and what sits between it and the CTA — so a card that the dock covers
    /// fails on geometry instead of on a snapshot diff.
    func testBothPlanCardsAreFullyVisibleAboveTheDockOnSEAndA61InchPhone() async throws {
        let model = await signedInModel()

        for frame in purchaseRegionFrames {
            let bitmap = render(model, size: frame.size)
            let cards = try cardBands(in: bitmap, frame: frame.name)
            let cta = try ctaBand(in: bitmap, frame: frame.name)

            XCTAssertLessThan(cards.annual.upperBound, cards.monthly.lowerBound, "\(frame.name): Yearly sits above Monthly")
            XCTAssertLessThan(
                cards.monthly.upperBound, cta.lowerBound,
                "\(frame.name): both cards end above the CTA, so neither runs under the dock"
            )

            // A card the dock covers loses its bottom edge: the last painted row would be a straight
            // cut at the dock's edge instead of the card's own rounded corner.
            for (name, band, fill) in [
                ("Yearly", cards.annual, APColorTokens.selectedBackground),
                ("Monthly", cards.monthly, APColorTokens.controlFill),
            ] {
                let middle = plateWidth(in: bitmap, row: band.lowerBound + band.count / 2, fill: fill)
                let topEdge = plateWidth(in: bitmap, row: band.lowerBound + 1, fill: fill)
                let bottomEdge = plateWidth(in: bitmap, row: band.upperBound - 1, fill: fill)
                XCTAssertGreaterThan(points(middle), 300, "\(frame.name), \(name): the card paints a full-width plate")
                XCTAssertLessThan(
                    points(topEdge), points(middle) - 8,
                    "\(frame.name), \(name): the card's top edge is its own rounded corner"
                )
                XCTAssertLessThan(
                    points(bottomEdge), points(middle) - 8,
                    "\(frame.name), \(name): the card's bottom edge is painted, so the dock does not cut it off"
                )
                XCTAssertGreaterThan(
                    points(bottomEdge), points(middle) * 0.8,
                    "\(frame.name), \(name): and the bottom row is the card's edge, not a sliver of it"
                )
            }

            // The trim below the CTA is the legal row plus the dock's own insets — no extra padding.
            let belowTheCta = points(bitmap.height - cta.upperBound - 1) - windowInsets().bottom
            XCTAssertGreaterThanOrEqual(
                belowTheCta, AP.HitTarget.minimum,
                "\(frame.name): the legal row keeps a 44 pt target below the CTA"
            )
            XCTAssertLessThanOrEqual(
                belowTheCta, 60,
                "\(frame.name): no excess padding under the CTA and the legal row (measured \(belowTheCta) pt)"
            )

            // The three 3.1.2 links are painted in that trimmed dock.
            let legal = bitmap.rows(paintedWith: 0x8C3350).filter { $0 > cta.upperBound }
            XCTAssertFalse(legal.isEmpty, "\(frame.name): Restore/Terms/Privacy stay on the first screen")
            XCTAssertLessThan(legal.max()!, bitmap.height - 1, "\(frame.name): the legal row is never pushed off")
        }
    }

    /// App Store 3.1.2 asks for the billed amount *and* the period on the card the user can buy, so
    /// both cards state it, and both figures come out of the store packages (two offerings, so no
    /// constant can be the source).
    func testBothPlanCardsCarryTheBilledAmountAndThePeriod() async throws {
        let yearly = PaywallPlanCopy.plan(annual, monthly: monthly, isSelected: true)
        let monthlyCard = PaywallPlanCopy.plan(monthly, monthly: monthly, isSelected: false)
        XCTAssertEqual(yearly.detail, "$3.33 per month, billed $39.99 yearly")
        XCTAssertEqual(monthlyCard.detail, "Billed $5.99 monthly")
        XCTAssertEqual(yearly.price, "$39.99")
        XCTAssertEqual(monthlyCard.price, "$5.99")
        for card in [yearly, monthlyCard] {
            XCTAssertTrue(card.detail.lowercased().contains("billed"), "\(card.title): the card states the billing amount")
            XCTAssertTrue(card.detail.contains(card.price), "\(card.title): the amount is the store's own")
        }
        XCTAssertTrue(yearly.detail.contains("yearly"), "the Yearly card states its period")
        XCTAssertTrue(monthlyCard.detail.contains("monthly"), "the Monthly card states its period")

        // A second offering moves both strings: nothing is typed into the card copy.
        let dongAnnual = PurchaseProduct(
            identifier: "a", packageType: .annual, localizedPrice: "₫999.000", period: "year"
        )
        let dongMonthly = PurchaseProduct(
            identifier: "m", packageType: .monthly, localizedPrice: "₫199.000", period: "month"
        )
        XCTAssertEqual(PaywallPlanCopy.detail(for: dongAnnual), "₫83.250 per month, billed ₫999.000 yearly")
        XCTAssertEqual(PaywallPlanCopy.detail(for: dongMonthly), "Billed ₫199.000 monthly")

        // And each rendered card paints its billing line in the lower part of its plate, so the line
        // is on screen and not the one the dock used to cut.
        let bitmap = render(await signedInModel(), size: se)
        let cards = try cardBands(in: bitmap, frame: "iPhone SE")
        for (name, band, fill) in [
            ("Yearly", cards.annual, APColorTokens.selectedBackground),
            ("Monthly", cards.monthly, APColorTokens.controlFill),
        ] {
            let lowerRows = (band.lowerBound + band.count * 3 / 5)..<(band.upperBound - 2)
            let lines = inkRowBands(in: bitmap, rows: lowerRows, columns: cardInterior(width: se.width), fill: fill)
            let billingLine = try XCTUnwrap(lines.last, "\(name): no billing line is painted under the title")
            XCTAssertGreaterThan(
                points(bitmap.inkExtent(inRows: billingLine, background: UIColor.tokenPixel(fill.light.uiColor))),
                points(Int(60 * scale)),
                "\(name): the billing line is a full line of copy, not a truncated fragment"
            )
        }
    }

    /// The compliance sentence: one auto-renew disclosure, painted in both account states. It is the
    /// same sentence in both, so its pixels have to agree — which is what proves it is the static
    /// disclosure and not a per-state line.
    func testAutoRenewDisclosureIsPaintedInBothAccountStates() async throws {
        let signedIn = render(await signedInModel(), size: se)
        let signedOut = render(await signedOutModel(), size: se)

        var disclosed: [Range<Int>] = []
        for (name, bitmap) in [("signed in", signedIn), ("signed out", signedOut)] {
            let cards = try cardBands(in: bitmap, frame: "iPhone SE, \(name)")
            let cta = try ctaBand(in: bitmap, frame: "iPhone SE, \(name)")
            let between = (cards.monthly.upperBound + 1)..<max(cards.monthly.upperBound + 2, cta.lowerBound - 2)
            // Lines closer than 12 pt are the same paragraph; the dock's own line sits further away.
            let blocks = inkRowBands(
                in: bitmap, rows: between, fill: APColorTokens.background, mergeGap: Int(12 * scale)
            )
            XCTAssertEqual(
                blocks.count, 2,
                "\(name): the scroll ends with the disclosure and the dock starts with its own line"
            )
            let disclosure = try XCTUnwrap(
                blocks.first, "no auto-renew disclosure between the cards and the dock when \(name)"
            )
            let width = bitmap.inkExtent(
                inRows: disclosure,
                background: UIColor.tokenPixel(APColorTokens.background.light.uiColor)
            )
            XCTAssertGreaterThan(
                points(width), 200,
                "\(name): the disclosure is a full sentence near the legal row, not a word"
            )
            XCTAssertGreaterThan(
                points(disclosure.count), 20,
                "\(name): both lines of the sentence are painted, so the dock neither clips nor covers them"
            )
            disclosed.append(disclosure)
        }

        XCTAssertFalse(
            signedIn.differs(from: signedOut, inRows: disclosed[0]),
            "the disclosure is painted identically in both states: same sentence, same place"
        )
    }

    /// The dock used to restate the selected plan and today's charge above the CTA. It is gone: two
    /// offerings whose amounts differ, with the same card geometry, must paint the same pixels above
    /// the CTA — which cannot happen if a "… billed today" line is still drawn there.
    func testTheDockNoLongerRestatesTheSelectedPlanPrice() async throws {
        let cheap = render(await signedInModel(), size: se)
        let dear = render(await signedInModel(offering: dearOffering), size: se)

        let cheapCta = try ctaBand(in: cheap, frame: "iPhone SE, $39.99").lowerBound
        let dearCta = try ctaBand(in: dear, frame: "iPhone SE, $79.99").lowerBound
        XCTAssertEqual(cheapCta, dearCta, "both offerings keep the same card heights and the same dock")

        // The dock's own line: the footer is pinned, so nothing inside the scroll can move it. A
        // "… billed today" line would print a different amount here.
        let dockLine = max(0, cheapCta - Int(30 * scale))..<(cheapCta - 1)
        XCTAssertFalse(
            cheap.differs(from: dear, inRows: dockLine),
            "nothing above the CTA carries a price any more: the amount lives on the cards only"
        )

        let source = try paywallViewSource()
        XCTAssertFalse(source.contains("purchaseSummary"), "the summary line is not rendered from the model")
        XCTAssertFalse(source.contains("billed today"), "and its copy is gone from the view")
    }

    /// The dock's links are one step smaller than the caption they used to use, and keep their targets.
    func testLegalLinksUseTheCompactTypeAtTheirFullTarget() throws {
        let footnote = UIFont.preferredFont(forTextStyle: .footnote).pointSize
        let compact = UIFont.preferredFont(forTextStyle: .caption2).pointSize
        XCTAssertLessThanOrEqual(
            compact / footnote, 0.9,
            "the legal row is ~20 % smaller than a footnote link (\(compact) vs \(footnote) pt)"
        )
        XCTAssertGreaterThanOrEqual(compact, 10, "and still legible")
        let source = try paywallViewSource()
        XCTAssertTrue(source.contains("PaywallLegalType.link"), "the row is drawn with the compact type")
        XCTAssertTrue(
            source.contains("frame(minHeight: AP.HitTarget.minimum)"),
            "every link keeps its 44 pt target"
        )
    }

    // MARK: - Status-bar contrast over the hero

    /// The status bar glyphs are dark over a light background in light mode and white in dark mode, so
    /// each scheme is measured against its own worst case over the brightest hero pixel behind them.
    func testStatusBarScrimMeetsContrastInBothSchemes() async {
        let light = render(await signedInModel(), size: phone, style: .light)
        let lightContrast = contrastOfWorstPixel(in: statusBand(light), against: .black)
        XCTAssertGreaterThanOrEqual(
            lightContrast,
            4.5,
            "dark status glyphs over the cream scrim must clear 4.5:1 (worst pixel: \(lightContrast))"
        )

        let dark = render(await signedInModel(), size: phone, style: .dark)
        let darkContrast = contrastOfWorstPixel(in: statusBand(dark), against: .white)
        XCTAssertGreaterThanOrEqual(
            darkContrast,
            4.5,
            "white status glyphs over the dark scrim must clear 4.5:1 (worst pixel: \(darkContrast))"
        )
    }

    /// The scrim has to be *there*, and it has to follow the scheme: the same photo pixels sit under a
    /// cream wash in light mode and a near-black one in dark mode.
    func testScrimIsAppliedInBothSchemes() async {
        let light = averageLuminance(in: statusBand(render(await signedInModel(), size: phone, style: .light)))
        let dark = averageLuminance(in: statusBand(render(await signedInModel(), size: phone, style: .dark)))
        XCTAssertGreaterThan(light, 0.3, "the light scrim keeps the band light enough for dark glyphs")
        XCTAssertLessThan(dark, 0.2, "the dark scrim keeps the band dark enough for white glyphs")
        XCTAssertGreaterThan(light, dark * 2, "each scheme's scrim resolves from its background token")
    }

    // MARK: - Asset and dark mode

    func testHeroAssetIsBundledAndPainted() async throws {
        let image = try XCTUnwrap(UIImage(named: "paywallHeroC"), "the C hero ships in the asset catalog")
        XCTAssertEqual(image.size.width, 430, accuracy: 1, "the 3x rendition is 1290 px for a 430 pt hero")
        XCTAssertGreaterThan(image.size.height, 0)

        let bitmap = render(await signedInModel(), size: phone)
        let heroBand = band(from: 120 * Int(scale), to: 180 * Int(scale), in: bitmap)
        let background = UIColor.tokenPixel(APColorTokens.background.light.uiColor)
        let painted = heroBand.filter { pixel in
            abs(pixel.red - background.red) > 12
                || abs(pixel.green - background.green) > 12
                || abs(pixel.blue - background.blue) > 12
        }
        XCTAssertGreaterThan(painted.count, heroBand.count / 2, "the hero photo is actually painted")
    }

    func testDarkModePaintsTheDarkBackgroundToken() async {
        let light = render(await signedInModel(), size: se, style: .light)
        let dark = render(await signedInModel(), size: se, style: .dark)
        assertColor(
            light.color(x: 4 * Int(scale), y: light.height - 4 * Int(scale)),
            equals: UIColor.tokenPixel(APColorTokens.background.light.uiColor),
            "light mode paints the cream background token to the bottom edge"
        )
        assertColor(
            dark.color(x: 4 * Int(scale), y: dark.height - 4 * Int(scale)),
            equals: UIColor.tokenPixel(APColorTokens.background.dark.uiColor),
            "dark mode paints the dark background token, not the light one"
        )
    }

    // MARK: - Copy and price discipline

    func testNoPriceIsTypedIntoThePaywallView() throws {
        let source = try paywallViewSource()
        for literal in ["39.99", "5.99", "3.33", "Save 44", "44%"] {
            XCTAssertFalse(source.contains(literal), "\(literal) must come from the store, never from the view")
        }
    }

    func testHeadlineAndStepsAreTheHandoffCopy() {
        XCTAssertEqual(PaywallPlanCopy.headlineLines.joined(separator: " "), "Pick a pose. Match it. Shoot.")
        XCTAssertEqual(PaywallPlanCopy.steps.map(\.title), ["Pick a pose", "Match the outline", "Shoot"])
        XCTAssertEqual(
            PaywallPlanCopy.steps.map(\.detail),
            [
                "Browse and save poses for free.",
                "The guide shows on your live camera.",
                "Premium unlocks the shutter with the full pose camera.",
            ]
        )
        XCTAssertEqual(PaywallPlanCopy.steps.filter(\.isPremium).map(\.id), [3], "only the shutter is paid")
        XCTAssertEqual(PaywallPlanCopy.purchaseCTA, "Unlock the pose camera")
        XCTAssertEqual(
            PaywallPlanCopy.autoRenewCaption,
            "Renews automatically until you cancel in Apple ID settings."
        )
    }

    // MARK: - Helpers

    /// Pixels to points, so an assertion reads in the unit it documents.
    private func points(_ pixels: Int) -> Double { Double(pixels) / Double(scale) }

    /// The insets the probe's window carries for the frame it last rendered: the home indicator is
    /// part of the dock's space but not part of its padding.
    private func windowInsets() -> UIEdgeInsets {
        UIApplication.shared.windows.first(where: \.isKeyWindow)?.safeAreaInsets ?? .zero
    }

    /// A plan card, located by the fill token it paints across its width: `selectedBackground` for the
    /// selected Yearly card, `controlFill` for the unselected Monthly one. The step badge paints a
    /// 20 pt dot of `selectedBackground`, so a band has to cover a third of the frame to count.
    private func cardBands(
        in bitmap: APBitmap,
        frame: String
    ) throws -> (annual: Range<Int>, monthly: Range<Int>) {
        let annual = filledBands(in: bitmap, token: APColorTokens.selectedBackground)
        let monthly = filledBands(in: bitmap, token: APColorTokens.controlFill)
        XCTAssertEqual(annual.count, 1, "\(frame): exactly one Yearly card is painted")
        XCTAssertEqual(monthly.count, 1, "\(frame): exactly one Monthly card is painted")
        return (
            try XCTUnwrap(annual.first, "\(frame): no Yearly card (selectedBackground fill) is painted"),
            try XCTUnwrap(monthly.first, "\(frame): no Monthly card (controlFill) is painted")
        )
    }

    /// The columns inside a card's plate, where a corner cannot be mistaken for ink.
    private func cardInterior(width: CGFloat) -> Range<Int> {
        Int(36 * scale)..<Int((width - 36) * scale)
    }

    /// How wide the card's plate paints on one row, from its first to its last painted pixel. The
    /// card's own top and bottom rows are narrower than its middle (a rounded plate), while a card
    /// cut off by the dock ends on a full-width row.
    private func plateWidth(in bitmap: APBitmap, row: Int, fill: APColorToken, tolerance: Int = 4) -> Int {
        let target = UIColor.tokenPixel(fill.light.uiColor)
        var first: Int?
        var last: Int?
        for x in 0..<bitmap.width {
            guard let pixel = bitmap.color(x: x, y: row), pixel.alpha > 200,
                  abs(pixel.red - target.red) <= tolerance,
                  abs(pixel.green - target.green) <= tolerance,
                  abs(pixel.blue - target.blue) <= tolerance
            else { continue }
            first = first ?? x
            last = x
        }
        guard let first, let last else { return 0 }
        return last - first + 1
    }

    /// The pinned CTA, located by its accent fill: the anchor the cards have to stay above.
    private func ctaBand(in bitmap: APBitmap, frame: String) throws -> Range<Int> {
        let rows = bitmap.rows(paintedWith: 0xE89CAE)
        guard let first = rows.min(), let last = rows.max() else {
            XCTFail("\(frame): no CTA is painted")
            return 0..<0
        }
        XCTAssertGreaterThanOrEqual(
            points(last - first + 1), AP.HitTarget.minimum, "\(frame): the CTA keeps its 48 pt height"
        )
        return first..<(last + 1)
    }

    /// Contiguous rows where a fill token paints at least `minimumWidthRatio` of the frame's width.
    private func filledBands(
        in bitmap: APBitmap,
        token: APColorToken,
        minimumWidthRatio: Double = 0.35,
        tolerance: Int = 4
    ) -> [Range<Int>] {
        let target = UIColor.tokenPixel(token.light.uiColor)
        let minimumPixels = Int(Double(bitmap.width) * minimumWidthRatio)
        var bands: [Range<Int>] = []
        var start: Int?
        for y in 0..<bitmap.height {
            var painted = 0
            for x in 0..<bitmap.width {
                guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { continue }
                if abs(pixel.red - target.red) <= tolerance,
                   abs(pixel.green - target.green) <= tolerance,
                   abs(pixel.blue - target.blue) <= tolerance {
                    painted += 1
                }
            }
            if painted >= minimumPixels {
                start = start ?? y
            } else if let open = start {
                bands.append(open..<y)
                start = nil
            }
        }
        if let open = start { bands.append(open..<bitmap.height) }
        return bands
    }

    /// Row bands inside `rows`, over `columns`, that paint anything but `fill`: one band per painted
    /// line, so a line of copy that lost its row (clipped, or replaced by nothing) cannot hide inside
    /// another one. `mergeGap` joins bands separated by less than that many pixels, which is how a
    /// two-line sentence becomes one block and two separate elements stay two.
    private func inkRowBands(
        in bitmap: APBitmap,
        rows: Range<Int>,
        columns: Range<Int>? = nil,
        fill: APColorToken,
        mergeGap: Int = 0
    ) -> [Range<Int>] {
        let target = UIColor.tokenPixel(fill.light.uiColor)
        let scanned = max(columns?.lowerBound ?? 0, 0)..<min(columns?.upperBound ?? bitmap.width, bitmap.width)
        var bands: [Range<Int>] = []
        var start: Int?
        for y in rows where y >= 0 && y < bitmap.height {
            var inked = false
            for x in scanned {
                guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { continue }
                if abs(pixel.red - target.red) > 12
                    || abs(pixel.green - target.green) > 12
                    || abs(pixel.blue - target.blue) > 12 {
                    inked = true
                    break
                }
            }
            if inked {
                start = start ?? y
            } else if let open = start {
                bands.append(open..<y)
                start = nil
            }
        }
        if let open = start { bands.append(open..<bitmap.height) }

        guard mergeGap > 0 else { return bands }
        var merged: [Range<Int>] = []
        for band in bands {
            if let last = merged.last, band.lowerBound - last.upperBound <= mergeGap {
                merged[merged.count - 1] = last.lowerBound..<band.upperBound
            } else {
                merged.append(band)
            }
        }
        return merged
    }

    private enum Reference {
        case black
        case white
    }

    /// The written status-bar band: its glyphs sit in the top ~59 pt, sampled here from 6 pt to 52 pt
    /// and stopping before the close control's column so its white circle cannot be read as backdrop.
    private func statusBand(_ bitmap: APBitmap) -> [APPixel] {
        band(
            from: 6 * Int(scale),
            to: 52 * Int(scale),
            in: bitmap,
            maxColumn: bitmap.width - 110 * Int(scale)
        )
    }

    private func band(
        from startRow: Int,
        to endRow: Int,
        in bitmap: APBitmap,
        maxColumn: Int? = nil
    ) -> [APPixel] {
        var pixels: [APPixel] = []
        let lastColumn = maxColumn ?? bitmap.width
        for y in startRow..<min(endRow, bitmap.height) {
            for x in 0..<min(lastColumn, bitmap.width) {
                if let pixel = bitmap.color(x: x, y: y) { pixels.append(pixel) }
            }
        }
        return pixels
    }

    private func averageLuminance(in pixels: [APPixel]) -> Double {
        guard !pixels.isEmpty else { return 0 }
        return pixels.reduce(0) { $0 + luminance($1) } / Double(pixels.count)
    }

    /// The worst (least contrasty) pixel in the band decides whether the glyphs are legible.
    private func contrastOfWorstPixel(in pixels: [APPixel], against reference: Reference) -> Double {
        let worst = pixels.map(luminance).min(by: { contrast($0, reference) < contrast($1, reference) })
        return contrast(worst ?? 0, reference)
    }

    private func contrast(_ background: Double, _ reference: Reference) -> Double {
        switch reference {
        case .white: return 1.05 / (background + 0.05)
        case .black: return (background + 0.05) / 0.05
        }
    }

    private func luminance(_ pixel: APPixel) -> Double {
        func channel(_ value: Int) -> Double {
            let srgb = Double(value) / 255
            return srgb <= 0.04045 ? srgb / 12.92 : pow((srgb + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(pixel.red) + 0.7152 * channel(pixel.green) + 0.0722 * channel(pixel.blue)
    }

    /// The close control: a `surface`-filled 44 pt rounded square in the top-trailing corner with the
    /// ink X inside it. Returns its painted bounds when it is on screen.
    private func closeButton(in bitmap: APBitmap) -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>)? {
        let surface = UIColor.tokenPixel(APColorTokens.surface.light.uiColor)
        var minRow = bitmap.height, maxRow = -1, minColumn = bitmap.width, maxColumn = -1
        for y in 0..<min(90 * Int(scale), bitmap.height) {
            for x in max(0, bitmap.width - 100 * Int(scale))..<bitmap.width {
                guard let pixel = bitmap.color(x: x, y: y) else { continue }
                guard abs(pixel.red - surface.red) <= 3,
                      abs(pixel.green - surface.green) <= 3,
                      abs(pixel.blue - surface.blue) <= 3 else { continue }
                minRow = min(minRow, y)
                maxRow = max(maxRow, y)
                minColumn = min(minColumn, x)
                maxColumn = max(maxColumn, x)
            }
        }
        guard maxRow > minRow else { return nil }
        let side = Double(max(maxRow - minRow, maxColumn - minColumn) + 1) / Double(scale)
        XCTAssertGreaterThanOrEqual(side, 43, "the close control paints a 44 pt target")
        var hasX = false
        for y in minRow...maxRow where !hasX {
            for x in minColumn...maxColumn {
                guard let pixel = bitmap.color(x: x, y: y) else { continue }
                if luminance(pixel) < 0.06 { hasX = true; break }
            }
        }
        XCTAssertTrue(hasX, "the X glyph is painted inside the close control")
        return (minRow...maxRow, minColumn...maxColumn)
    }

    private func assertColor(_ pixel: APPixel?, equals expected: APPixel, _ message: String) {
        guard let pixel else {
            XCTFail(message)
            return
        }
        XCTAssertEqual(pixel.red, expected.red, accuracy: 3, message)
        XCTAssertEqual(pixel.green, expected.green, accuracy: 3, message)
        XCTAssertEqual(pixel.blue, expected.blue, accuracy: 3, message)
    }

    private func paywallViewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Features
            .deletingLastPathComponent() // iosAppTests
            .deletingLastPathComponent() // mobile/iosApp
            .appendingPathComponent("iosApp/Features/Support/PaywallScreen.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - Test doubles

@MainActor
final class PaywallLayoutConnectivity: ConnectivityReporting {
    private let subject = CurrentValueSubject<Bool, Never>(false)
    var isOffline: Bool { subject.value }
    var changes: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }
    func start() {}
}

final class PaywallLayoutTokenStorage: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: SessionCredentials?

    init(credentials: SessionCredentials? = nil) {
        self.credentials = credentials
    }

    func saveCredentials(_ credentials: SessionCredentials) {
        lock.lock()
        self.credentials = credentials
        lock.unlock()
    }

    func loadCredentials() -> SessionCredentials? {
        lock.lock()
        defer { lock.unlock() }
        return credentials
    }

    func clearCredentials() {
        lock.lock()
        credentials = nil
        lock.unlock()
    }
}

extension UIColor {
    /// The rendered pixel a resolved dynamic colour paints, so a test compares real output to the
    /// documented token instead of to a second hex constant.
    static func tokenPixel(_ color: UIColor) -> APPixel {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return APPixel(
            red: Int((red * 255).rounded()),
            green: Int((green * 255).rounded()),
            blue: Int((blue * 255).rounded()),
            alpha: Int((alpha * 255).rounded())
        )
    }
}

extension DynamicTypeSize {
    /// The `ContentSizeCategory` the probe also sets, so both Dynamic Type entry points agree in the
    /// rendered frame.
    var contentSizeCategory: ContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}
