import SwiftUI
import XCTest
@testable import iosApp

/// Rendered regressions for the S1 surfaces: dock geometry and the card's E1 shadow. Both are pixel
/// assertions on a hosted view, so a layout or modifier-order mistake fails here instead of shipping.
final class APCatalogViewTests: XCTestCase {
    private let canvas: UInt32 = 0xF4F1E8 // secondaryBackground
    private let surface: UInt32 = 0xFFFFFF
    private let selectedFill: UInt32 = 0x24211E

    private func pose() -> NativePose {
        NativePose(
            id: "dock-pose",
            name: "Window light",
            category: "Standing",
            imageURL: nil,
            instructions: [],
            isSaved: false
        )
    }

    // MARK: - Dock geometry

    @MainActor func testDockTabsSitInSymmetricSlotsAroundTheShutter() {
        let probe = APViewProbe(dockCanvas(active: .poses), size: CGSize(width: 393, height: 140))
        defer { probe.tearDown() }
        let poses = probe.capture()

        guard let pillRow = widestRun(of: surface, in: poses),
              let posesPill = run(of: selectedFill, inRow: pillRow.row, of: poses) else {
            return XCTFail("dock pill or selected fill not painted")
        }

        // Compact: the selected fill hugs the icon + label instead of filling its whole half.
        XCTAssertGreaterThan(posesPill.width, 44, "the selected pill must still hold a 44 pt target")
        XCTAssertLessThan(
            posesPill.width, 110,
            "the selected fill must hug its content, painted \(posesPill.width) pt of a \(pillRow.width) pt pill"
        )

        // Symmetric slots: the Poses pill centres in the space the shutter leaves on its left.
        let slot = (pillRow.width - 2 * NeoDockTabBar.pillInset - NeoDockTabBar.shutterSlot) / 2
        let expectedCentre = CGFloat(pillRow.minX) + NeoDockTabBar.pillInset + slot / 2
        XCTAssertEqual(
            posesPill.midX, expectedCentre, accuracy: 2,
            "Poses pill centre \(posesPill.midX) should sit at \(expectedCentre) inside the pill"
        )

        // Mirror: with Gallery selected its pill lands at the mirrored position, so neither tab is
        // pulled towards the shutter.
        let mirrored = probe.render(dockCanvas(active: .gallery))
        guard let mirroredRow = widestRun(of: surface, in: mirrored),
              let galleryPill = run(of: selectedFill, inRow: mirroredRow.row, of: mirrored) else {
            return XCTFail("gallery selected fill not painted")
        }
        XCTAssertEqual(mirroredRow.midX, pillRow.midX, accuracy: 1, "the pill must not move between states")
        XCTAssertEqual(
            galleryPill.midX,
            mirroredRow.midX + (mirroredRow.midX - posesPill.midX),
            accuracy: 2,
            "Gallery pill \(galleryPill.midX) must mirror the Poses pill around the shutter"
        )
    }

    @MainActor private func dockCanvas(active: AppTab) -> some View {
        ZStack(alignment: .bottom) {
            Color(hex: UInt(canvas))
            NeoDockTabBar(selection: .constant(active), activeTab: active)
        }
        .frame(width: 393, height: 140)
    }

    // MARK: - Card elevation

    @MainActor func testPoseCardKeepsItsE1ShadowOutsideTheZoomClip() {
        let probe = APViewProbe(cardCanvas(), size: CGSize(width: 280, height: 520))
        defer { probe.tearDown() }
        let painted = probe.capture()

        guard let cardRow = widestRun(of: surface, in: painted) else {
            return XCTFail("the card surface was not painted")
        }
        // The card's bottom edge is the last row that still paints a card-wide surface run; a single
        // column would stop at the artwork instead.
        var cardBottom = cardRow.row
        for y in (cardRow.row + 1)..<painted.height {
            guard let row = run(of: surface, inRow: y, of: painted), row.width > cardRow.width * 0.8 else { break }
            cardBottom = y
        }
        XCTAssertGreaterThan(cardBottom, cardRow.row, "the card must paint a body under its top row")

        let lower = cardBottom + 2
        let upper = min(cardBottom + 14, painted.height)
        var shadowPixels = 0
        for y in lower..<max(lower, upper) {
            for x in max(0, Int(cardRow.minX) - 8)..<min(Int(cardRow.maxX) + 8, painted.width) {
                guard let pixel = painted.color(x: x, y: y), pixel.alpha > 200 else { continue }
                // Shadow means *darker than the canvas*: 8% black over #F4F1E8 lands near (224, 222, 213).
                if pixel.red < 238 && pixel.green < 235 && pixel.blue < 227 {
                    shadowPixels += 1
                }
            }
        }
        XCTAssertGreaterThan(
            shadowPixels, 0,
            "the card's E1 shadow must paint below the card body, not be clipped away by the zoom source"
        )
    }

    @MainActor private func cardCanvas() -> some View {
        ZStack {
            Color(hex: UInt(canvas))
            CardHost(pose: pose())
                .padding(AP.Space.space32)
        }
        .frame(width: 280, height: 520)
    }

    // MARK: - Helpers

    private struct Run {
        let row: Int
        let minX: Int
        let maxX: Int
        var width: CGFloat { CGFloat(maxX - minX + 1) }
        var midX: CGFloat { CGFloat(minX + maxX) / 2 }
    }

    /// The widest horizontal run of `hex` that is a *shape*, not the window background: a run that
    /// spans (nearly) the whole capture is the hosting view's own background and is skipped.
    private func widestRun(of hex: UInt32, in bitmap: APBitmap, tolerance: Int = 6) -> Run? {
        var best: Run?
        for y in 0..<bitmap.height {
            guard let run = run(of: hex, inRow: y, of: bitmap, tolerance: tolerance) else { continue }
            guard run.width < CGFloat(bitmap.width) - 4 else { continue }
            if best == nil || run.width > best!.width {
                best = run
            }
        }
        return best
    }

    private func run(of hex: UInt32, inRow y: Int, of bitmap: APBitmap, tolerance: Int = 6) -> Run? {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        var minX: Int?
        var maxX: Int?
        for x in 0..<bitmap.width {
            guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { continue }
            let matches = abs(pixel.red - target.red) <= tolerance
                && abs(pixel.green - target.green) <= tolerance
                && abs(pixel.blue - target.blue) <= tolerance
            guard matches else { continue }
            minX = min(minX ?? x, x)
            maxX = max(maxX ?? x, x)
        }
        guard let minX, let maxX, maxX > minX else { return nil }
        return Run(row: y, minX: minX, maxX: maxX)
    }
}

/// Hosts the card with a real `Namespace`, so the zoom-transition source (and its clip) is active.
private struct CardHost: View {
    let pose: NativePose
    @Namespace private var namespace

    var body: some View {
        APPoseCard(pose: pose, aspectRatio: 1, zoomNamespace: namespace)
    }
}
