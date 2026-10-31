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
    /// One presenter for the paywall: the camera asks for it, the root shows it. No event bus. The
    /// state is a small pure model (`PaywallPresentation`), so "one sheet, dismissed once" is tested
    /// without a sheet.
    @State private var paywall = PaywallPresentation()
    /// BUG-261029-04: the pose the camera falls back to when the entry point chose none. Session-scoped,
    /// so an Account switch drops the previous Account's reference instead of opening the next
    /// Account's camera on someone else's pose.
    @StateObject private var lastPose = CameraLastPoseModel()
    /// BUG-261029-05: where the camera was opened from, so its Close control can land back on the pose
    /// detail instead of the catalogue.
    @State private var cameraEntry: CameraEntry = .home
    /// The detail the Poses tab has to re-push the moment its stack is rebuilt (one-shot).
    @State private var posesResume = PosesResumeSlot()
    /// F7: the appearance preference lives in Settings now; the root is the one place that applies it.
    @ObservedObject private var appearance = APAppearanceStore.shared

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
            .sheet(isPresented: paywallSheetBinding) {
                PaywallScreen()
            }
            // A purchase or a restore that lands while the sheet is open closes it exactly once. The
            // press that opened it is never re-fired: the user is back on the camera, nothing more.
            .onChange(of: premiumGate.entitlement) { _ in settlePaywall() }
            .onChange(of: premiumGate.isSignedIn) { _ in settlePaywall() }
            .preferredColorScheme(appearance.appearance.colorScheme)
            .onChange(of: tab) { newTab in
                if newTab != .camera {
                    pendingGuide = nil
                    // Leaving the camera by any route other than its Close control (the gallery
                    // thumbnail, the dock) drops the return target: only Close replays it, and it has
                    // already recorded it before switching tabs.
                    cameraEntry = .home
                }
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
                        onSearchVisibilityChange: { isSearchPresented = $0 },
                        resumePose: posesResume.targetToRestore,
                        onResumeHandled: { posesResume.consume() }
                    )
                }
            }
        case .camera:
            RootNavigation {
                CameraScreen(
                    guide: Binding(
                        // An explicitly chosen pose always wins; the remembered one is only the
                        // fallback for an entry point that chose nothing (BUG-261029-04).
                        get: {
                            CameraGuidePolicy.openingGuide(
                                explicit: pendingGuide ?? cameraGuide.wrappedValue,
                                remembered: lastPose.remembered
                            )
                        },
                        set: { newGuide in
                            pendingGuide = newGuide
                            cameraGuide.wrappedValue = newGuide
                            // A pose chosen inside the camera is a pose the user used, so it becomes
                            // the one the dock entry opens with next time.
                            // The picker only lists catalogue poses, so a pick is never private.
                            if let newGuide { lastPose.remember(newGuide, isPrivate: false) }
                        }
                    ),
                    poseService: poseService,
                    onClose: closeCamera,
                    onOpenGallery: {
                        tab = .gallery
                    },
                    // The shutter's paid-action gate (`PremiumGate`): the decision itself lives in
                    // `CameraViewModel.capture()`, ahead of camera readiness. `signIn` is the gate's
                    // answer to "must this user also sign in to buy?" (M2); the paywall derives the
                    // visible sign-in state from the session boundary itself, which is why the sheet
                    // does not need it.
                    premiumGate: premiumGate,
                    onPremiumRequired: { _ in paywall.send(.shutterRequested) }
                )
                // Reads the remembered pose while the screen comes up, and revalidates it on every
                // Home entry (deleted / unsaved since it was used): a dock entry opened before the
                // first read still ends up drawing the guide, or none on a first launch.
                .task {
                    await lastPose.cameraOpened(
                        explicitPoseChosen: (pendingGuide ?? cameraGuide.wrappedValue) != nil
                    )
                }
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
            // Design B: the Search workspace is a full screen of its own, so the dock steps out of
            // the way while it is up (`03-search-idle` has no dock). Every other tab keeps it.
            if !isSearchPresented {
                NeoDockTabBar(selection: $tab, activeTab: tab)
                    .transition(.opacity)
            }
        }
        // The dock floats at `bottom: 16pt + safe area`, anchored to the screen — not to the
        // keyboard, or it ends up floating in the middle of the results grid while the user types.
        // Search is the exception: it hides the dock and its state panels must stay above the
        // keyboard (`03-search-no-results`), so the keyboard inset is honoured there.
        .ignoresSafeArea(isSearchPresented ? [.container] : [.container, .keyboard], edges: .bottom)
    }

    /// "Use this pose" from a pose detail: the explicit pose wins over the remembered one, it becomes
    /// the remembered one, and closing the camera has to land back on that same detail — in the same
    /// lane, so a private (Jobs / Add pose) detail is restored as private.
    private func openCamera(with request: CameraPoseRequest) {
        pendingGuide = request.pose
        cameraGuide.wrappedValue = request.pose
        lastPose.remember(request.pose, isPrivate: request.isPrivate)
        cameraEntry = .poseDetail(request)
        tab = .camera
    }

    /// The camera's Close control. The entry point decides the destination: a pose-detail entry is
    /// re-pushed on the Poses stack, a Home entry shows the catalogue (BUG-261029-05).
    private func closeCamera() {
        posesResume.cameraClosed(after: cameraEntry)
        cameraEntry = .home
        pendingGuide = nil
        tab = .poses
    }

    private var paywallSheetBinding: Binding<Bool> {
        Binding(
            get: { paywall.isPresented },
            // SwiftUI writes `false` when the user dismisses (swipe or the paywall's own close).
            set: { presented in if !presented { paywall.send(.userDismissed) } }
        )
    }

    private func settlePaywall() {
        paywall.send(.gateSettled(
            entitlement: premiumGate.entitlement,
            signedIn: premiumGate.isSignedIn
        ))
    }
}
