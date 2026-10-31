// Owner feedback F1: one page header for every pushed screen — the back control and the page title
// on ONE row, the title vertically centred immediately to its right. Not a large title under the
// button. Tab roots (Poses, Gallery), the camera and the pose detail hero keep their own headers.

import SwiftUI

struct APPageHeader: View {
    let title: String
    var backLabel: String = "Back"
    var backStyle: APBackButtonStyle = .control
    /// Route-specific back identifier (kept from the screen's previous header).
    var backIdentifier: String = ""
    /// Route-specific title identifier and machine-readable value, where a screen carries one.
    var titleIdentifier: String = ""
    var titleValue: String?
    var onBack: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: AP.Space.space12) {
            if let onBack {
                APBackButton(style: backStyle, accessibilityLabel: backLabel, action: onBack)
                    .apIdentifier(backIdentifier.isEmpty ? nil : backIdentifier)
            }
            Text(title)
                .font(AP.Font.title)
                .foregroundStyle(AP.Color.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .apIdentifier(titleIdentifier.isEmpty ? nil : titleIdentifier)
                .accessibilityValue(titleValue ?? "")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space8)
        .padding(.bottom, AP.Space.space12)
    }
}
