import SwiftUI

enum AppTab: Hashable {
    case poses, camera, gallery
}

struct RootNavigation<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content() }
        } else {
            NavigationView { content() }.navigationViewStyle(.stack)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension View {
    /// Marks this view as the source of a zoom transition (iOS 18+). Older systems keep the
    /// standard push / cover animation, and so does a nil namespace.
    @ViewBuilder
    func zoomTransitionSource<ID: Hashable>(id: ID, in namespace: Namespace.ID?, cornerRadius: CGFloat = 0) -> some View {
        if #available(iOS 18.0, *), let namespace {
            self.matchedTransitionSource(id: id, in: namespace) { configuration in
                configuration.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        } else {
            self
        }
    }

    /// Zooms the destination out of (and back into) the source registered with the same id and
    /// namespace, for both open and close (including the interactive swipe back).
    @ViewBuilder
    func zoomTransition<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}
