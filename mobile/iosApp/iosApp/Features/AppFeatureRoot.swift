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
                        model: PosesViewModel(service: poseService, bookmarkService: bookmarkService),
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
                    }
                )
            }
        case .gallery:
            RootNavigation {
                tabRoot {
                    GalleryScreen(model: GalleryViewModel(store: galleryStore))
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
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func openCamera(with pose: NativePose) {
        pendingGuide = pose
        cameraGuide.wrappedValue = pose
        tab = .camera
    }
}
