import Foundation

// MARK: - Where the camera was opened from (BUG-261029-05)

/// Why the camera tab is up, so closing it can put the user back where they came from.
///
/// The camera is a **tab**: opening it swaps the whole Poses branch of `AppFeatureRoot`, which tears
/// down that tab's `NavigationStack`. Closing therefore used to land everyone on the catalogue
/// (Home), even when the user had just pressed "Use this pose" on a pose detail. The app root records
/// the entry point and replays it on close, so a pose-detail entry is re-pushed and every other entry
/// (the dock, the gallery's empty state) still goes Home.
enum CameraEntry: Equatable {
    /// Opened with no pose chosen — the dock, the gallery.
    case home
    /// "Use this pose" from a pose detail, which back has to return to.
    case poseDetail(NativePose)

    /// The detail the camera was opened from, `nil` for an entry that returns Home.
    var returnPose: NativePose? {
        if case .poseDetail(let pose) = self { return pose }
        return nil
    }
}

/// The one-shot "come back here" slot the Poses tab reads when its stack is rebuilt.
///
/// Closing the camera rebuilds the Poses branch from its root, so the pushed detail is gone. The slot
/// carries that detail across the rebuild exactly once: `PosesScreen` consumes it as soon as its root
/// appears, so going Home and later re-entering the tab from the dock does not silently re-open the
/// pose.
struct PosesResumeSlot: Equatable {
    /// The pose whose detail the Poses root still has to push, `nil` once consumed.
    private(set) var poseToRestore: NativePose?

    /// Closing the camera records where back has to land: the detail for a `.poseDetail` entry, and
    /// nothing at all for `.home` (which also clears a target left over from an earlier visit).
    mutating func cameraClosed(after entry: CameraEntry) {
        poseToRestore = entry.returnPose
    }

    /// The Poses root took the target (it is pushing it, or decided there is nothing to push).
    mutating func consume() {
        poseToRestore = nil
    }
}

// MARK: - The pose the camera remembers (BUG-261029-04)

/// The last pose the user took into the camera, in the smallest shape that can still draw a guide
/// with **no network**: the id (capture metadata), the name and category (the stick-figure fallback
/// is chosen from those) and the extracted line-art URL (Kingfisher's disk cache answers offline; a
/// miss falls back to the stick figure, never to an error).
///
/// Deliberately not a whole `NativePose` row: instructions, the source photo and the Saved flag are
/// detail-screen concerns and would make the reference heavier for nothing. Decoding is defensive for
/// the same reason `CameraSettings` is — a hand-edited or half-written row must degrade to "nothing
/// remembered" instead of taking the camera screen down.
struct CameraLastPose: Equatable, Sendable {
    var poseId: String
    var name: String
    var category: String
    var guideURL: String?

    init(poseId: String, name: String, category: String, guideURL: String? = nil) {
        self.poseId = poseId
        self.name = name
        self.category = category
        self.guideURL = guideURL
    }

    init(pose: NativePose) {
        self.init(
            poseId: pose.id,
            name: pose.name,
            category: pose.category,
            // `imageURL` is the source photo and is never the camera reference, so only the extracted
            // line art is remembered (`NativePose.cameraGuideURL`).
            guideURL: pose.cameraGuideURL?.absoluteString
        )
    }

    /// The guide the camera can draw, or `nil` when this reference resolves to nothing.
    ///
    /// An empty id or name means there is nothing to name a capture with and nothing to pick a
    /// fallback figure from, so the row is treated as unresolvable and the camera opens exactly as it
    /// does on a first launch — no pose, no error.
    var pose: NativePose? {
        let id = poseId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !trimmedName.isEmpty else { return nil }
        return NativePose(
            id: id,
            name: trimmedName,
            category: category,
            imageURL: nil,
            instructions: [],
            isSaved: false,
            guideURL: Self.url(guideURL)
        )
    }

    private static func url(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }
}

extension CameraLastPose: Codable {
    enum CodingKeys: String, CodingKey {
        case poseId, name, category, guideURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        poseId = (try? container.decodeIfPresent(String.self, forKey: .poseId)) ?? nil ?? ""
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil ?? ""
        category = (try? container.decodeIfPresent(String.self, forKey: .category)) ?? nil ?? ""
        guideURL = (try? container.decodeIfPresent(String.self, forKey: .guideURL)) ?? nil
    }

    /// `nil` when the payload is not a JSON object this type understands. Sorted keys keep the stored
    /// bytes stable for the repository test that pins them.
    static func decode(_ json: String?) -> CameraLastPose? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CameraLastPose.self, from: data)
    }

    func encodedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

/// The camera's opening rule, in one place.
///
/// An explicitly chosen pose always wins: the remembered one is only a fallback for an entry point
/// that chose nothing. `nil` means "open exactly as before the feature existed" — no pose, no error.
enum CameraGuidePolicy {
    static func openingGuide(explicit: NativePose?, remembered: CameraLastPose?) -> NativePose? {
        if let explicit { return explicit }
        return remembered?.pose
    }
}

// MARK: - Store

/// Reads and writes the remembered pose. Async because the row sits behind the same GRDB database the
/// camera settings use; throwing because a broken row has to degrade to "nothing remembered", never
/// to an error on the camera screen.
protocol CameraLastPoseStore: Sendable {
    func load() async throws -> CameraLastPose?
    /// `nil` clears the reference (session change, or "nothing was used yet").
    func save(_ pose: CameraLastPose?) async throws
}

/// GRDB implementation over `CameraSnapshot.pose_json`.
///
/// That column is the one the schema already reserves for a pose and that nothing else writes
/// (`CameraSettings` owns `settings_json` only, D8; a settings write carries `pose_json` over). Reusing
/// it keeps the remembered pose out of the settings revision protocol — a pose is not a setting, so it
/// must not bump that revision or be replayed by a settings write — and needs no schema change.
struct GRDBCameraLastPoseStore: CameraLastPoseStore {
    let database: AppDatabase

    func load() async throws -> CameraLastPose? {
        guard let record = try await CameraSnapshotRepository(database: database).snapshot() else {
            return nil
        }
        return CameraLastPose.decode(record.poseJSON)
    }

    func save(_ pose: CameraLastPose?) async throws {
        try await CameraSnapshotRepository(database: database).savePose(
            CameraSnapshotPoseWrite(
                poseJSON: try pose?.encodedJSON(),
                schemaVersion: Int64(CameraSettings.currentVersion),
                // Only used when the write has to create the singleton row, i.e. a pose remembered
                // before the camera ever stored a setting: the settings start at their defaults.
                defaultSettingsJSON: try CameraSettings().encodedJSON()
            )
        )
    }
}

/// In-memory fallback: used by tests, and when the database cannot be opened (a corrupt or unreadable
/// container must not take the remembered pose with it).
actor InMemoryCameraLastPoseStore: CameraLastPoseStore {
    private var stored: CameraLastPose?
    private(set) var saves: [CameraLastPose?] = []

    init(seed: CameraLastPose? = nil) {
        stored = seed
    }

    func load() async throws -> CameraLastPose? { stored }

    func save(_ pose: CameraLastPose?) async throws {
        saves.append(pose)
        stored = pose
    }
}

/// Opens the database the first time the remembered pose is actually needed, off the main thread,
/// exactly like `DeferredCameraSettingsStore` does for the settings. `CameraLastPoseModel` is built
/// from `AppFeatureRoot` on the main thread, so no database work may happen in its init.
actor DeferredCameraLastPoseStore: CameraLastPoseStore {
    private var resolved: (any CameraLastPoseStore)?

    private func backend() -> any CameraLastPoseStore {
        if let resolved { return resolved }
        let backend: any CameraLastPoseStore
        if let database = try? AppDatabase() {
            backend = GRDBCameraLastPoseStore(database: database)
        } else {
            backend = InMemoryCameraLastPoseStore()
        }
        resolved = backend
        return backend
    }

    func load() async throws -> CameraLastPose? {
        try await backend().load()
    }

    func save(_ pose: CameraLastPose?) async throws {
        try await backend().save(pose)
    }
}

// MARK: - Model

/// Owns the camera's remembered pose and the session rule that keeps it honest.
///
/// Reads and writes are best effort: a database that cannot answer degrades to "nothing remembered"
/// and the camera opens exactly as it did before this feature. Nothing here gates a capture — the M02
/// `PremiumGate` still runs first in `CameraViewModel.capture()`, whichever way the guide was chosen.
@MainActor
final class CameraLastPoseModel: ObservableObject, SessionScoped {
    /// The stored reference, published so a camera screen that opened before the row was read picks
    /// the guide up as soon as the load lands (or shows no guide at all when there is nothing).
    @Published private(set) var remembered: CameraLastPose?

    private let store: any CameraLastPoseStore
    private let scope: SessionScope
    /// Bumped by a session change. A load that was in flight when the Account moved must not paint
    /// the previous Account's pose over the reset.
    private var generation = 0
    private var didLoad = false
    private var writeTask: Task<Void, Never>?

    init(
        store: any CameraLastPoseStore = DeferredCameraLastPoseStore(),
        boundary: SessionBoundary = ServiceLocator.sessionBoundary
    ) {
        self.store = store
        self.scope = SessionScope.of(boundary)
        scope.adopt(self)
    }

    /// The camera opened. Reads the stored reference once per process (and once more after a session
    /// change, which clears it); a failed read is simply "nothing remembered".
    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        let generation = self.generation
        let loaded = (try? await store.load()) ?? nil
        guard generation == self.generation else { return }
        // A pose the user already took in this process is fresher than the row this read returned: the
        // first camera open of a run writes the pose and reads the row in the same turn, and the read
        // loses that race. Without this guard the guide then vanished on the *next* camera open.
        guard remembered == nil else { return }
        remembered = loaded
    }

    /// The user took this pose into the camera — the detail's CTA, or the camera's own pose picker —
    /// so it is the pose the next dock entry opens with.
    func remember(_ pose: NativePose) {
        let reference = CameraLastPose(pose: pose)
        // Only write when the value actually moved: the camera's binding funnels the pose it is
        // already drawing back through here.
        guard reference != remembered else { return }
        remembered = reference
        save(reference)
    }

    /// Sign-out or an account switch: the next Account must not open the camera on the previous
    /// Account's pose, and the row it came from is dropped too, so a relaunch cannot bring it back.
    ///
    /// The reset is synchronous (the `SessionScoped` contract), so no screen can draw the old pose
    /// after another one has switched. The stored reference is not account-keyed because the local
    /// credentials carry no Account id — the same reason the pose catalogue clears on the event.
    func resetForSessionChange(_ event: SessionEvent) {
        generation &+= 1
        remembered = nil
        // The row is being cleared, so there is nothing to read back: a later camera open must not
        // resurrect it even if the clear below cannot reach the disk.
        didLoad = true
        writeTask?.cancel()
        save(nil)
    }

    private func save(_ reference: CameraLastPose?) {
        writeTask?.cancel()
        let store = store
        writeTask = Task { try? await store.save(reference) }
    }
}
