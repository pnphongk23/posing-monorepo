import Foundation

enum Loadable<Value> {
    case idle, loading, loaded(Value), empty, failed(String)
}

protocol PoseServing: Sendable {
    func poses(query: String?) async throws -> [NativePose]
    func pose(id: String) async throws -> NativePose
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
