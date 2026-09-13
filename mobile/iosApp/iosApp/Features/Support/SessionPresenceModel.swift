import Foundation

/// Session presence for account-scoped entry points.
///
/// `isSignedIn` is `true` only while the single `SessionBoundary` seam holds credentials, and it
/// flips to `false` as soon as the boundary clears them (sign-out, or a 401 refresh failure), so
/// protected content unmounts instead of rendering the previous Account's data as current
/// (FEAT-013/FEAT-014: never show stale protected state after a context change).
@MainActor
final class SessionPresenceModel: ObservableObject {
    @Published private(set) var isSignedIn = false
    /// `false` until the first storage read, so callers can avoid flashing the signed-out state.
    @Published private(set) var isResolved = false

    private let boundary: SessionBoundary
    private var task: Task<Void, Never>?

    init(boundary: SessionBoundary = ServiceLocator.sessionBoundary) {
        self.boundary = boundary
    }

    deinit {
        task?.cancel()
    }

    func start() {
        guard task == nil else { return }
        // Converge once up front, then re-read storage on every change rather than interpreting
        // the event: the boundary is the only authority for whether a session exists.
        task = boundary.observeSessions(
            onStart: { [weak self] in
                guard let self else { return }
                await self.refresh()
            },
            onEvent: { [weak self] _ in
                guard let self else { return }
                await self.refresh()
            }
        )
    }

    private func refresh() async {
        isSignedIn = await boundary.hasStoredSession()
        isResolved = true
    }
}
