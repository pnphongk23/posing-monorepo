import Foundation

enum Loadable<Value> {
    case idle, loading, loaded(Value), empty, failed(String)
}

/// The collection a pose read is for, named by the request instead of by a slot on the service.
///
/// It is the filter the screen is showing (`PoseLibraryFilter`: All poses / My poses / Community). The
/// route belongs to the request so two screens cannot reroute each other through shared service state —
/// a signed-out Search used to write `.all` into the adapter's slot, which made the camera picker read
/// the account route too.
typealias PoseFilter = PoseLibraryFilter

protocol PoseServing: Sendable {
    func poses(query: String?) async throws -> [NativePose]
    func pose(id: String) async throws -> NativePose
    /// Rows `offset ..< offset+limit` of a pose list. A **requirement**, not just a convenience: a
    /// call through `any PoseServing` dispatches statically to an extension-only method, which would
    /// silently bypass the adapter's paging and always answer "no more rows".
    ///
    /// Offset, not page number: the server pages with `OFFSET`, and a row the user removes (an
    /// unsave in the Saved list) shifts every later row one position up. A page counter cannot
    /// express "the list moved", so the caller owns the cursor and this call is a pure window read.
    func posesPage(query: String?, offset: Int, limit: Int) async throws -> PosePage
    /// The same window, read from the collection `filter` names.
    ///
    /// This is the signature routed services implement: the route comes from this argument (and the
    /// session), never from state another screen may have set. `PoseAPIServiceAdapter` overrides it, so
    /// a call through `any PoseServing` reaches it; the default below only keeps single-collection
    /// services (previews, test doubles) working unchanged.
    func posesPage(query: String?, filter: PoseFilter, offset: Int, limit: Int) async throws -> PosePage
}

/// One window of a pose list plus whether the server has more rows behind it.
///
/// `hasMore` is a separate answer on purpose: a window that happens to hold exactly `limit` rows is
/// not the last window, so the count alone cannot decide it.
struct PosePage: Sendable, Equatable {
    let poses: [NativePose]
    let hasMore: Bool
    /// How many rows of the server's list this answer advanced past. It is **not** `poses.count`:
    /// a local name filter can hide every row a window returned, and a merged `.all` first window
    /// spans two collections. The next offset and `hasMore` are both computed from it.
    let consumed: Int

    static let end = PosePage(poses: [], hasMore: false, consumed: 0)
}

extension PoseServing {
    /// Paging default: a service that only knows the first window keeps working unchanged, and any
    /// offset beyond it is reported as the end of the list instead of replaying the same rows.
    func posesPage(query: String?, offset: Int, limit: Int) async throws -> PosePage {
        guard offset <= 0 else { return .end }
        let poses = try await poses(query: query)
        return PosePage(poses: poses, hasMore: false, consumed: poses.count)
    }

    /// A service with one collection ignores the filter and answers its one list.
    func posesPage(query: String?, filter: PoseFilter, offset: Int, limit: Int) async throws -> PosePage {
        try await posesPage(query: query, offset: offset, limit: limit)
    }
}

struct NativePose: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var category: String
    /// Card / hero image: the source photo.
    var imageURL: URL?
    var instructions: [String]
    var isSaved: Bool
    /// Extracted line art drawn as the camera guide. `nil` falls back to the stick figure.
    var guideURL: URL? = nil
}

struct PreviewPoseService: PoseServing {
    func poses(query: String?) async throws -> [NativePose] {
        let all = [NativePose(id: "standing-1", name: "Soft Standing", category: "Standing", imageURL: nil,
                              instructions: ["Relax your shoulders", "Turn slightly toward the light"], isSaved: false)]
        guard let query, !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    func pose(id: String) async throws -> NativePose {
        let all = try await poses(query: nil)
        if let match = all.first(where: { $0.id == id }) {
            return match
        }
        return all[0]
    }
}
