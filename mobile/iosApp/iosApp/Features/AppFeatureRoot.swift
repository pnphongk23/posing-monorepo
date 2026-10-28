import SwiftUI

struct AppFeatureRoot: View {
    let poseService: any PoseServing
    var bookmarkService: (any PoseBookmarkServing)?
    var galleryStore: any GalleryStoring
    var cameraGuide: Binding<NativePose?>
    @State private var tab: AppTab = .poses
    @State private var pendingGuide: NativePose?
    /// Set by `PosesScreen` while its in-place Search overlay is up. Search is not a tab, so the
    /// dock must render with no active pill (`reference/search-blank.png`), unlike the Poses list.
    @State private var isSearchPresented = false
    /// FEAT-011: the capture gate's live inputs. One instance for the app, so the camera and any
    /// other entry point read the same entitlement (and the same session-scoped reset).
    @StateObject private var premiumGate = PremiumGateModel()
    /// One presenter for the paywall: the camera asks for it, the root shows it. No event bus.
    @State private var isPaywallPresented = false

    init(
        poseService: any PoseServing,
        bookmarkService: (any PoseBookmarkServing)? = nil,
        galleryStore: any GalleryStoring,
        cameraGuide: Binding<NativePose?> = .constant(nil)
    ) {
        self.poseService = poseService
        self.bookmarkService = bookmarkService
        self.galleryStore = galleryStore
        self.cameraGuide = cameraGuide
    }

    var body: some View {
        screenContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AIPoseColor.background.ignoresSafeArea())
            .onAppear { premiumGate.start() }
            // The paywall can be requested from any paid trigger; the sheet owns dismissal, and
            // dismissing it changes nothing, so no access is granted on the way out.
            .sheet(isPresented: $isPaywallPresented) {
                PaywallScreen()
            }
            .onChange(of: tab) { newTab in
                if newTab != .camera { pendingGuide = nil }
                if newTab != .poses { isSearchPresented = false }
            }
    }

    /// Kept out of `body` on purpose: `Group { switch … }` makes the compiler fall back to
    /// SwiftUI's `TableColumnBuilder` overload of `Group.init` and the file stops type-checking.
    @ViewBuilder
    private var screenContent: some View {
        switch tab {
        case .poses:
            RootNavigation {
                tabRoot {
                    PosesScreen(
                        // The Account can change under this screen (Settings → Account, delete
                        // account), so the model follows the session boundary and drops the previous
                        // Account's saved state instead of showing it to the next one.
                        model: PosesViewModel(
                            service: poseService,
                            bookmarkService: bookmarkService,
                            boundary: ServiceLocator.sessionBoundary
                        ),
                        onTryPose: openCamera(with:),
                        onSearchVisibilityChange: { isSearchPresented = $0 }
                    )
                }
            }
        case .camera:
            RootNavigation {
                CameraScreen(
                    guide: Binding(
                        get: { pendingGuide ?? cameraGuide.wrappedValue },
                        set: { newGuide in
                            pendingGuide = newGuide
                            cameraGuide.wrappedValue = newGuide
                        }
                    ),
                    poseService: poseService,
                    onClose: {
                        tab = .poses
                    },
                    onOpenGallery: {
                        tab = .gallery
                    },
                    // The shutter's paid-action gate (`PremiumGate`): the decision itself lives in
                    // `CameraViewModel.capture()`, ahead of camera readiness. `signIn` is the gate's
                    // answer to "must this user also sign in to buy?" (M2); the paywall derives the
                    // visible sign-in state from the session boundary itself, which is why the sheet
                    // does not need it.
                    premiumGate: premiumGate,
                    onPremiumRequired: { _ in isPaywallPresented = true }
                )
            }
        case .gallery:
            RootNavigation {
                tabRoot {
                    GalleryScreen(
                        model: GalleryViewModel(store: galleryStore),
                        // `gallery.html` all-empty `Open Camera` — the gallery's only entry point to
                        // capture. Wired here because the destination is app-level tab routing;
                        // `GalleryScreen` only owns the action site.
                        onOpenCamera: { tab = .camera }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func tabRoot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .bottom) {
            content()
            NeoDockTabBar(selection: $tab, activeTab: isSearchPresented ? nil : tab)
        }
        // The dock floats at `bottom: 16pt + safe area` in the prototype, i.e. anchored to the
        // screen — not to the keyboard. Without this, the whole stack shrinks for the keyboard and
        // the dock ends up floating in the middle of the results grid while the user types.
        .ignoresSafeArea([.container, .keyboard], edges: .bottom)
    }

    private func openCamera(with pose: NativePose) {
        pendingGuide = pose
        cameraGuide.wrappedValue = pose
        tab = .camera
    }
}
