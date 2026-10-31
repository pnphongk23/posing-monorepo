import SwiftUI

/// The disclosure the user must accept before the first photo leaves the device.
///
/// One constant per string: the sheet, the test that freezes the wording (App Review 5.1.2(i)) and any
/// future translation all read the same value. The copy states the fact — the photo goes to a
/// third-party AI service and the resulting pose is stored privately — and deliberately names no
/// vendor, because the provider is chosen per deployment.
enum AddPoseConsentCopy {
    static let title = "Before you upload"

    static let message = "To extract the pose, your photo is sent to a third-party AI service. The pose created from it is saved privately to your account until you delete your account."

    static let allow = "Allow"
    static let cancel = "Cancel"
}

/// Consent surface for Add pose: a plain sheet with two full-width controls.
///
/// A sheet rather than a `confirmationDialog` because the identifiers have to survive into the
/// accessibility tree for Maestro: alert-style dialogs render as system buttons whose labels carry the
/// wording but whose identifiers are unreliable, while a hosted sheet exposes
/// `addPose.consent.allowButton` / `addPose.consent.cancelButton` directly. Swipe-to-dismiss is the
/// same action as Cancel (`onDismiss` on the presenter calls it), so no gesture can upload anything.
struct AddPoseConsentSheet: View {
    enum Identifiers {
        static let message = "addPose.consent.message"
        static let allowButton = "addPose.consent.allowButton"
        static let cancelButton = "addPose.consent.cancelButton"
    }

    var onAllow: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AP.Space.space16) {
            Text(AddPoseConsentCopy.title)
                .font(AP.Font.title)
                .foregroundStyle(AP.Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(AddPoseConsentCopy.message)
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(Identifiers.message)

            Spacer(minLength: AP.Space.space24)

            VStack(spacing: AP.Space.space12) {
                Button(AddPoseConsentCopy.allow) { onAllow() }
                    .buttonStyle(APPrimaryButtonStyle())
                    .accessibilityIdentifier(Identifiers.allowButton)

                Button(AddPoseConsentCopy.cancel) { onCancel() }
                    .buttonStyle(APSecondaryButtonStyle())
                    .accessibilityIdentifier(Identifiers.cancelButton)
            }
        }
        .padding(.horizontal, AP.Space.space24)
        .padding(.top, AP.Space.space32)
        .padding(.bottom, AP.Space.space24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AP.Color.background.ignoresSafeArea())
    }
}
