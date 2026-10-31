import AVFoundation
import SwiftUI
import UIKit

struct OnboardingScreen: View {
    let onComplete: () -> Void
    @State private var page = 0
    private let pages = [
        ("sparkles", "Pose with confidence", "Simple guides help you frame every shot."),
        ("camera", "Line it up", "Adjust, flip, and fade a guide over the camera."),
        ("lock.shield", "Your photos, your space", "Keep your gallery close and under your control."),
    ]

    var body: some View {
        VStack(spacing: AIPoseSpacing.xl) {
            Spacer()
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: AIPoseSpacing.lg) {
                        Image(systemName: pages[index].0)
                            .font(.system(size: 72))
                            .foregroundStyle(AIPoseColor.primary)
                        Text(pages[index].1).font(.largeTitle.bold())
                        Text(pages[index].2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AIPoseColor.subtext)
                    }
                    .padding()
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 360)
            Button(page == pages.count - 1 ? "Get started" : "Continue") {
                if page == pages.count - 1 { onComplete() } else { withAnimation { page += 1 } }
            }
            .buttonStyle(NeoButtonStyle())
            .padding(.horizontal, AIPoseSpacing.xl)
            Button("Skip") { onComplete() }.font(.footnote).foregroundStyle(AIPoseColor.subtext)
        }
        .padding(.bottom, AIPoseSpacing.xl)
        .background(AIPoseColor.background)
    }
}
