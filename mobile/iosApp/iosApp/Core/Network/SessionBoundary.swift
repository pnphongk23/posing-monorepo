import Foundation

enum SessionEvent: Sendable, Equatable {
    case signInRequired, signedOut, signedIn
}

/// Single owner of the backend session (credentials + generation).
///
/// Ported from the KMP `SessionBoundary`: sign-out is local and repeat-safe (there is
/// no invented backend revocation endpoint), and every credential mutation bumps
/// `currentGeneration` so readers can discard work that crossed a session change.
/// `events()` lets a long-lived projection (e.g. `AccountSessionModel`) observe
/// sign-in / sign-out / 401-clears without polling.
actor SessionBoundary {
    private let tokenStorage: TokenStoring
    private var generation: Int = 0
    private var observers: [Int: AsyncStream<SessionEvent>.Continuation] = [:]
    private var nextObserverID = 0
    private var inFlightRefresh: Task<Bool, Never>?
    private var refreshAttempt = 0

    init(tokenStorage: TokenStoring) {
        self.tokenStorage = tokenStorage
    }

    var currentGeneration: Int { generation }

    /// Read-only session probe for gates that must not trigger a refresh flow.
    func hasStoredSession() -> Bool {
        tokenStorage.loadCredentials() != nil
    }

    func loadAccessToken() -> String? {
        tokenStorage.loadCredentials()?.accessToken
    }

    func loadRefreshToken() -> String? {
        tokenStorage.loadCredentials()?.refreshToken
    }

    /// Live session events. Deliberately not replayed: a late subscriber converges by
    /// reading `hasStoredSession()`/`currentGeneration` (which is what `AccountSessionModel.start()`
    /// does), so a stale replay cannot restart a load that already finished. Nothing is lost to a
    /// late subscriber inside one launch either, because `observeSessions` now registers before it
    /// awaits `onStart` and the stream buffers the newest event meanwhile.
    func events() -> AsyncStream<SessionEvent> {
        let id = nextObserverID
        nextObserverID += 1
        var captured: AsyncStream<SessionEvent>.Continuation!
        let stream = AsyncStream<SessionEvent>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            captured = continuation
        }
        observers[id] = captured
        captured.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    #if DEBUG
    /// Test support: how many live subscribers `events()` currently holds.
    ///
    /// `events()` is deliberately not replayed, so a test that mutates the session before its
    /// projection has subscribed loses the event and can only fail by timing out. This lets a test
    /// wait for the subscription (a real synchronization point) instead of sleeping and hoping.
    /// No production behaviour depends on it.
    func subscriberCountForTests() -> Int { observers.count }
    #endif

    /// Establishes a backend-issued session and invalidates stale reads.
    func saveCredentials(_ credentials: SessionCredentials) {
        tokenStorage.saveCredentials(credentials)
        generation += 1
        emit(.signedIn)
    }

    func clearForUnauthorized() {
        tokenStorage.clearCredentials()
        generation += 1
        emit(.signInRequired)
    }

    /// Clears only the local session. Repeat-safe: a second call on an already signed-out
    /// boundary keeps the same projection and does not bump the generation again.
    func signOut() {
        let hadCredentials = tokenStorage.loadCredentials() != nil
        tokenStorage.clearCredentials()
        guard hadCredentials else { return }
        generation += 1
        emit(.signedOut)
    }

    /// Concurrent callers share one refresh attempt.
    ///
    /// The refresh token rotates server-side (Supabase `grant_type=refresh_token` returns a new
    /// one), so a second concurrent refresh would present a token the first attempt already
    /// consumed: the server rejects it and `clearForUnauthorized()` would then drop a session that
    /// had just refreshed successfully. Serialising on the in-flight task keeps one network
    /// attempt for a burst of 401s.
    func refresh(using refreshSession: @escaping @Sendable (String) async -> SessionCredentials?) async -> Bool {
        if let inFlightRefresh { return await inFlightRefresh.value }

        refreshAttempt += 1
        let attempt = refreshAttempt
        let task = Task { [weak self] in
            guard let self else { return false }
            let refreshed = await self.performRefresh(using: refreshSession)
            await self.finishRefresh(attempt: attempt)
            return refreshed
        }
        inFlightRefresh = task
        return await task.value
    }

    private func performRefresh(using refreshSession: @Sendable (String) async -> SessionCredentials?) async -> Bool {
        let refreshGeneration = generation
        guard let refreshToken = tokenStorage.loadCredentials()?.refreshToken else {
            clearForUnauthorized()
            return false
        }
        guard let updated = await refreshSession(refreshToken) else {
            if generation == refreshGeneration { clearForUnauthorized() }
            return false
        }
        if generation != refreshGeneration { return false }
        // Replacing credentials inside the same session must not invalidate the
        // Account/Saved reads that are retrying the original request.
        tokenStorage.saveCredentials(updated)
        return true
    }

    private func finishRefresh(attempt: Int) {
        // A newer attempt already replaced this one, so leave its task in place.
        guard attempt == refreshAttempt else { return }
        inFlightRefresh = nil
    }

    private func emit(_ event: SessionEvent) {
        for continuation in observers.values {
            continuation.yield(event)
        }
    }

    private func removeObserver(_ id: Int) {
        observers.removeValue(forKey: id)
    }
}

extension SessionBoundary {
    /// Long-lived session observation for app-scope state that follows the Account.
    ///
    /// `onStart` runs once before the first event: launching with an already-stored session emits
    /// nothing, so a projection that only listened for events would never converge. `onEvent` then
    /// runs for every change until the returned task is cancelled.
    ///
    /// The subscription is registered *before* `onStart` is awaited (S4). Registering it after
    /// left a window exactly as long as `onStart` — measured 2.2 ms when `onStart` is empty and
    /// 302 ms when it awaits a read — in which `emit` found no subscriber and the event was lost;
    /// the projection then sat on whatever `onStart` read instead of converging (FEAT-014 FR-005:
    /// a signed-out context must not keep the previous account's rows). Registering first keeps the
    /// ordering contract: events emitted while `onStart` is in flight land in the stream's existing
    /// newest-only buffer and are handled after `onStart` returns, so nothing is dropped and no
    /// replay machinery is added.
    @discardableResult
    nonisolated func observeSessions(
        onStart: @escaping @MainActor () async -> Void = {},
        onEvent: @escaping @MainActor (SessionEvent) async -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            let events = await self.events()
            await onStart()
            for await event in events {
                if Task.isCancelled { return }
                await onEvent(event)
            }
        }
    }
}
