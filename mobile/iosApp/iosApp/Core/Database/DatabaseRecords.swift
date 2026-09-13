import Foundation
import GRDB

struct PhotoRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    static let databaseTableName = "Photo"

    var id: Int64?
    var imagePath: String
    var poseId: String?
    var poseName: String
    var createdAt: String
    var isFavorite: Int64
}

struct PoseRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    static let databaseTableName = "Pose"

    var poseId: String
    var ownerAccountId: String
    var name: String
    var description: String?
    var tags: String
    var difficulty: String?
    var bodyParts: String
    var status: String
    var originalPath: String
    var skeletonPath: String
    var thumbnailPath: String
    var currentJobId: String?
    var createdAt: String
    var updatedAt: String
}

struct CameraSnapshotRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    static let databaseTableName = "CameraSnapshot"

    var id: Int64 = 1
    var schemaVersion: Int64
    var settingsJSON: String
    var poseJSON: String?

    enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case settingsJSON = "settings_json"
        case poseJSON = "pose_json"
    }
}
