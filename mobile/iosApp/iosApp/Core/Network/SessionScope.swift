import Foundation

/// A model that holds Account-derived state.
///
/// The reset is synchronous on purpose (no `await`): every adopted model is reset inside the same
/// main-actor turn that bumped the generation, so no screen can draw Account A's data after another
/// screen has already switched to B. Work that has to be restarted (re-reading a list for the new
/// session) is kicked as a `Task` from inside the reset.
@MainActor
protocol SessionScoped: AnyObject {
    func resetForSessionChange(_ event: SessionEvent)
}

/// Identity of the session a request belongs to.
///
/// Two stamps, because the scope's own counter only moves when it *delivers* an event, and delivery
/// is a main-actor turn behind the boundary mutation. A request that starts in that gap (B signs in,
/// B's first tap a moment later) belongs to the new session, so `boundaryGeneration` is the
/// authoritative half and the scope counter is the cheap half. See `SessionScope.isValid(_:)`.
struct SessionTicket: Equatable, Sendable {
    fileprivate let generation: Int
    /// `nil` for a ticket taken synchronously inside the fan-out: only the cheap check applies there.
    fileprivate let boundaryGeneration: Int?
}

/// One `MainActor` fan-out per `SessionBoundary`.
///
/// Before this, five observers did the same job by hand (`PosesViewModel`, `AccountSessionModel`,
/// `PaywallModel`, `JobsService`, `SessionScopeCoordinator`), each with its own generation trick, and
/// each new model had to solve the leak from scratch. Here there is a single `observeSessions`
/// subscription per boundary: when an event arrives the scope bumps one generation counter and then
/// resets every adopted model synchronously, in that same turn.
///
/// Members are held weakly, so a model that is rebuilt (for example `AppFeatureRoot` constructs
/// `PosesViewModel` inside `body`) costs nothing: throwaway instances are pruned on the next event and
/// never start their own task.
@MainActor
final class SessionScope {
    /// Scopes are process-lifetime, one per boundary instance (`ServiceLocator.sessionBoundary` in the
    /// app, one per test that injects its own). Holding the boundary here is deliberate: it keeps the
    /// map key and the subscription provably in agreement, so an `ObjectIdentifier` can never be
    /// reused by a different boundary.
    private static var scopes: [ObjectIdentifier: SessionScope] = [:]

    static func of(_ boundary: SessionBoundary) -> SessionScope {
        let key = ObjectIdentifier(boundary)
        if let existing = scopes[key] { return existing }
        let scope = SessionScope(boundary: boundary)
        scopes[key] = scope
        return scope
    }

    private struct WeakMember {
        weak var value: (any SessionScoped)?
    }

    private let boundary: SessionBoundary
    private(set) var generation = 0
    /// The boundary generation covered by the last fan-out; `nil` until the subscription's start hook
    /// has run.
    private var deliveredBoundaryGeneration: Int?
    private var members: [WeakMember] = []
    private var task: Task<Void, Never>?

    private init(boundary: SessionBoundary) {
        self.boundary = boundary
    }

    /// Adopts a model and makes sure the single subscription is running. Adopting twice is a no-op.
    func adopt(_ model: some SessionScoped) {
        members.removeAll { $0.value == nil }
        guard !members.contains(where: { $0.value === model }) else { return }
        members.append(WeakMember(value: model))
        guard task == nil else { return }
        // One subscriber for every model behind this boundary. The subscription is not replayed
        // (`SessionBoundary` does not replay: a late model converges by reading the boundary itself).
        task = boundary.observeSessions(
            onStart: { [weak self] in
                await self?.recordDeliveredGeneration()
            },
            onEvent: { [weak self] event in
                await self?.handle(event)
            }
        )
    }

    /// The generation a reset-kicked task should carry. Synchronous, so it can be read inside the
    /// reset itself; a task that also runs work which must survive the gap between a boundary mutation
    /// and its delivery uses `beginRequest()` instead.
    var ticket: SessionTicket {
        SessionTicket(generation: generation, boundaryGeneration: nil)
    }

    /// Captures the ticket for a new request: the scope counter plus the boundary's authoritative
    /// session stamp, read before the request's first `await`. One actor read, exactly what the
    /// hand-written models did before this mechanism existed.
    ///
    /// The boundary mutates on its own actor, so the fan-out for that mutation follows on this one a
    /// turn later. A request must not start inside that gap: its in-flight claim and its saved-state
    /// read would straddle the change (B's own first tap landed in exactly that gap and was dropped as
    /// stale). So this waits — bounded — for the scope to have delivered everything the boundary
    /// already recorded, instead of adding a second reset path that would double-bump the generation.
    func beginRequest() async -> SessionTicket {
        var attempts = 0
        while attempts < 64 {
            guard let delivered = deliveredBoundaryGeneration else { break }
            let current = await boundary.currentGeneration
            if current == delivered { break }
            attempts += 1
            await Task.yield()
        }
        return SessionTicket(generation: generation, boundaryGeneration: await boundary.currentGeneration)
    }

    /// Cheap synchronous check: no reset has been delivered since the request started. Used by the
    /// reset-kicked tasks, which were captured inside the fan-out and must not be superseded by it.
    func isCurrent(_ ticket: SessionTicket) -> Bool {
        ticket.generation == generation
    }

    /// Authoritative check for a completion.
    ///
    /// The fast path is the synchronous one. When it fails, the scope has caught up with a mutation —
    /// but the request may have *started* after that mutation and before its delivery (the boundary
    /// mutates on its own actor, the fan-out follows a turn later). In that case the boundary stamp
    /// still equals the one captured at the start, so the request belongs to the current session and
    /// its answer is kept. A request that started before the mutation sees a moved boundary stamp and
    /// is dropped, which is the leak this whole mechanism exists to close.
    func isValid(_ ticket: SessionTicket) async -> Bool {
        if isCurrent(ticket) { return true }
        guard let start = ticket.boundaryGeneration else { return false }
        return await boundary.currentGeneration == start
    }

    /// Records the boundary generation this delivery covers, so `beginRequest()` knows whether a
    /// mutation is still waiting for its fan-out.
    private func recordDeliveredGeneration() async {
        deliveredBoundaryGeneration = await boundary.currentGeneration
    }

    /// Stale work dies first (`generation += 1`), then every model resets in the same turn.
    ///
    /// `observeSessions` drives its events one at a time, so an `await` here cannot interleave two
    /// fan-outs: the payload order is the boundary's order.
    private func handle(_ event: SessionEvent) async {
        await recordDeliveredGeneration()
        generation += 1
        members.removeAll { $0.value == nil }
        for member in members {
            member.value?.resetForSessionChange(event)
        }
    }
}

/// Per-request ownership, so a finished request can only release its own claim.
///
/// The bug this exists for: an `InFlight` flag cleared in a `defer` released *whatever* claim was
/// standing, so account A's late answer removed the flag account B had just set for the same key.
struct InFlight<Key: Hashable> {
    private var owners: [Key: UInt64] = [:]
    private var next: UInt64 = 0

    /// Claims `key` for a new request. `nil` means another request already owns it.
    mutating func begin(_ key: Key) -> UInt64? {
        guard owners[key] == nil else { return nil }
        next &+= 1
        owners[key] = next
        return next
    }

    /// Releases `key` only for the request that owns it.
    mutating func end(_ key: Key, _ token: UInt64) {
        if owners[key] == token { owners[key] = nil }
    }

    mutating func removeAll() {
        owners.removeAll()
    }

    func contains(_ key: Key) -> Bool {
        owners[key] != nil
    }

    /// The keys currently in flight, for a view that wants to show them as busy.
    var keys: Set<Key> { Set(owners.keys) }
}
