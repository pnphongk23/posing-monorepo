import SwiftUI

enum GalleryStoreBootstrap: Sendable {
    case database(any GalleryStoring)
    case integrationBlocked(String)

    var statusLabel: String {
        switch self {
        case .database:
            return "Gallery: database-backed"
        case .integrationBlocked(let reason):
            return "Gallery blocked: \(reason)"
        }
    }

    var store: any GalleryStoring {
        switch self {
        case .database(let store):
            return store
        case .integrationBlocked(let reason):
            return IntegrationBlockedGalleryStore(reason: reason)
        }
    }

    /// Launch stays cheap: this used to open the database (locator probe + pool + migrations) right
    /// here, inside `didFinishLaunching` on the main thread. Resolving is now deferred to the first
    /// `photos()` call, which is a non-isolated async entry point, so the work happens off the main
    /// thread while the gallery shows its loading state. Measured open+migrate was 3-9ms — small, but
    /// pure launch-path blocking work that has no business being on the critical path.
    static func make() -> GalleryStoreBootstrap {
        .database(DeferredGalleryStore())
    }

    /// The blocking resolution that used to live in `make()`. Never call this from a UI path.
    ///
    /// There used to be a fixture fallback here: an empty database showed six fake photos, and
    /// `delete(id:)` could never remove them because the next read saw an empty primary and handed
    /// the fixtures back. A genuinely empty database now reads as empty, and a database that cannot
    /// be opened reports why instead of hiding behind demo content.
    static func resolveBackend() -> any GalleryStoring {
        do {
            return DatabaseGalleryStore(database: try AppDatabase())
        } catch {
            return IntegrationBlockedGalleryStore(reason: "database: \(error)")
        }
    }
}

/// Resolves the gallery backend once, on first use, off the main thread.
/// The actor also serialises concurrent first calls, so the database is opened exactly once.
actor DeferredGalleryStore: GalleryStoring {
    private let resolveBackend: @Sendable () -> any GalleryStoring
    private var backend: (any GalleryStoring)?

    init(
        resolveBackend: @escaping @Sendable () -> any GalleryStoring = { GalleryStoreBootstrap.resolveBackend() }
    ) {
        self.resolveBackend = resolveBackend
    }

    private func resolvedBackend() -> any GalleryStoring {
        if let backend { return backend }
        let backend = resolveBackend()
        self.backend = backend
        return backend
    }

    func photos() async throws -> [GalleryItem] {
        try await resolvedBackend().photos()
    }

    func delete(id: Int64) async throws {
        try await resolvedBackend().delete(id: id)
    }
}

private struct DatabaseGalleryStore: GalleryStoring {
    let repository: PhotoRepository
    let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
        repository = PhotoRepository(database: database)
    }

    func photos() async throws -> [GalleryItem] {
        try await repository.all().compactMap { record in
            guard let id = record.id else { return nil }
            let fileURL = GalleryMediaPath.fileURL(for: record.imagePath)
              let createdAt = GalleryDateParser.date(from: record.createdAt) ?? .distantPast
            let title = record.poseName.isEmpty ? "Photo" : record.poseName
            return GalleryItem(id: id, fileURL: fileURL, createdAt: createdAt, title: title)
        }
    }

    func delete(id: Int64) async throws {
        try await database.pool.write { db in
            try db.execute(sql: "DELETE FROM Photo WHERE id = ?", arguments: [id])
        }
    }

  }

private struct IntegrationBlockedGalleryStore: GalleryStoring {
    let reason: String

    func photos() async throws -> [GalleryItem] {
        throw GalleryStoreIntegrationError.blocked(reason)
    }

    func delete(id: Int64) async throws {
        throw GalleryStoreIntegrationError.blocked(reason)
    }
}

enum GalleryStoreIntegrationError: LocalizedError {
    case blocked(String)

    var errorDescription: String? {
        switch self {
        case .blocked(let reason):
            return "Gallery integration blocked: \(reason)"
        }
    }
}

struct ContentView: View {
    let isFirebaseConfigured: Bool
    let galleryBootstrap: GalleryStoreBootstrap
    private let poseServices: PoseServiceBundle

    init(isFirebaseConfigured: Bool, galleryBootstrap: GalleryStoreBootstrap) {
        self.isFirebaseConfigured = isFirebaseConfigured
        self.galleryBootstrap = galleryBootstrap
        poseServices = PoseServiceBootstrap.make(baseURL: AppConfig.shared.SERVER_BASE_URL)
    }

    var body: some View {
        AppFeatureRoot(
            poseService: poseServices.service,
            bookmarkService: poseServices.bookmarkService,
            galleryStore: galleryBootstrap.store
        )
    }
}
