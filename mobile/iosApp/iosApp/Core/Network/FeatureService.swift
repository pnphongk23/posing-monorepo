import Foundation

enum Loadable<Value> {
    case idle, loading, loaded(Value), empty, failed(String)
}

protocol PoseServing: Sendable {
    func poses(query: String?) async throws -> [NativePose]
    func pose(id: String) async throws -> NativePose
    /// One page of a pose list. A **requirement**, not just a convenience: a call through
    /// `any PoseServing` dispatches statically to an extension-only method, which would silently
    /// bypass the adapter's paging and always answer "no more pages".
    func posesPage(query: String?, page: Int) async throws -> PosePage
}

/// One page of a pose list plus whether the server has more rows behind it.
///
/// `hasMore` is a separate answer on purpose: a page that happens to hold exactly `limit` rows is
/// not the last page, so the count alone cannot decide it.
struct PosePage: Sendable, Equatable {
    let poses: [NativePose]
    let hasMore: Bool

    static let end = PosePage(poses: [], hasMore: false)
}

extension PoseServing {
    /// Paging default: a service that only knows the first page keeps working unchanged, and any
    /// page beyond it is reported as the end of the list instead of replaying page 1.
    func posesPage(query: String?, page: Int) async throws -> PosePage {
        guard page <= 1 else { return .end }
        return PosePage(poses: try await poses(query: query), hasMore: false)
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
