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
    /// The Gallery `+` has no destination of its own: it asks the Poses tab to open Add pose, the same
    /// flow the Poses header `+` runs. Latched rather than delivered straight through, because the
    /// Poses tab (and the `onChange` watching this signal) is rebuilt when the tab changes.
    @State private var addPoseRequest = APAddPoseRequest()
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
            // The paywall can be requested from any paid trigger; the cover owns dismissal, and
            // dismissing it changes nothing, so no access is granted on the way out.
            .paywallCover(isPresented: paywallSheetBinding)
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
                        onResumeHandled: { posesResume.consume() },
                        addPoseRequest: addPoseRequest.signal
                    )
                    // A request taken in the Gallery is delivered once this rebuilt screen is on
                    // screen: raising the signal before the switch would hand it to the new screen as
                    // an initial value, and a value that was never different never fires `onChange`.
                    .modifier(APAddPoseDelivery(request: $addPoseRequest))
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
                        onOpenCamera: { tab = .camera },
                        // The Gallery `+` runs the existing Add-pose flow on the Poses tab.
                        onAddPose: {
                            addPoseRequest.ask()
                            tab = .poses
                        }
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

// MARK: - Add pose asked for from another tab

/// A request to open the Add pose flow, taken in one tab and run by the Poses tab.
///
/// The Poses tab — and with it `PosesScreen`'s `onChange(of: addPoseRequest)` — is rebuilt whenever the
/// selected tab changes, so a signal raised *before* the switch arrives as the new screen's initial
/// value and nothing fires: SwiftUI only reports a change, and a value that was never different is not
/// a change. The request is therefore latched here and the signal is raised on appearance, which is
/// the same consume-once shape `PosesResumeSlot` uses for the camera's return target.
struct APAddPoseRequest: Equatable {
    /// The signal `PosesScreen` watches; every delivery is a new value, so a second request fires again.
    private(set) var signal = 0
    /// A request arrived while the Poses tab was not on screen yet.
    private(set) var isPending = false

    /// The Gallery `+` was tapped.
    mutating func ask() {
        isPending = true
    }

    /// The Poses tab is on screen: hand the pending request over exactly once.
    /// - Returns: `true` when a request was delivered.
    @discardableResult
    mutating func deliver() -> Bool {
        guard isPending else { return false }
        isPending = false
        signal &+= 1
        return true
    }
}

/// Delivers a latched request the moment the receiving tab is on screen.
struct APAddPoseDelivery: ViewModifier {
    @Binding var request: APAddPoseRequest

    func body(content: Content) -> some View {
        content.onAppear { request.deliver() }
    }
}

// MARK: - The Add pose entry's session gate

/// The session gate every Add pose entry runs through: the Poses header `+`, the More menu row, the
/// Gallery header `+` and the Gallery detail's Add pose.
///
/// The Gallery entries hand their request to the Poses tab, which rebuilds `PosesScreen` — and with it
/// the `SessionPresenceModel` — so the request arrives before the session has been read back from
/// storage. Answering at that instant treats a signed-in user as signed out and shows the sign-in
/// prompt. A request that lands before the first read is therefore held, not answered: the prompt
/// only appears once the session is known, and a restored session opens the flow instead.
struct APAddPoseGate {
    enum Step: Equatable {
        /// The session is signed in: open the Add pose flow.
        case open
        /// The session is signed out: ask the user to sign in.
        case askSignIn
        /// The session has not been read yet: hold the request and show nothing.
        case waitForSession
    }

    /// The answer for the session state right now.
    static func step(isResolved: Bool, isSignedIn: Bool) -> Step {
        guard isResolved else { return .waitForSession }
        return isSignedIn ? .open : .askSignIn
    }

    /// `true` while a request waits for the first session read.
    private(set) var isHolding = false

    /// An Add pose entry was used.
    mutating func request(isResolved: Bool, isSignedIn: Bool) -> Step {
        let step = Self.step(isResolved: isResolved, isSignedIn: isSignedIn)
        isHolding = step == .waitForSession
        return step
    }

    /// The session was read: answer the held request now, exactly once.
    mutating func sessionRead(isSignedIn: Bool) -> Step? {
        guard isHolding else { return nil }
        isHolding = false
        return Self.step(isResolved: true, isSignedIn: isSignedIn)
    }
}
