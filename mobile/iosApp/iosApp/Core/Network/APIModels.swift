import Foundation

struct ExtractPoseData: Codable, Sendable {
    let imageBase64: String
    let mimeType: String
    let processingTimeMs: Int64
}

struct PoseExtractionJob: Codable, Sendable {
    let jobId: String
    let status: String
}

struct PoseExtractionMeta: Codable, Sendable {
    let pollUrl: String?
}

struct PoseExtractionStartResponse: Codable, Sendable {
    let success: Bool
    let data: PoseExtractionJob
    let meta: PoseExtractionMeta?
}

struct ApiErrorResponse: Codable, Sendable {
    let code: String?
    let message: String?
}

struct ApiErrorEnvelope: Codable, Sendable {
    let error: ApiErrorResponse?
}

struct PoseExtractionJobData: Codable, Sendable {
    let jobId: String
    let status: String
    let result: ExtractPoseData?
    let error: ApiErrorResponse?
}

struct PoseExtractionJobStatus: Codable, Sendable {
    let success: Bool
    let data: PoseExtractionJobData
}

struct CommunityPose: Codable, Sendable, Identifiable {
    var id: String { poseId }
    let poseId: String
    let name: String
    let skeletonUrl: String
    let thumbnailUrl: String
    let difficulty: String?
    let tags: [String]
    let description: String?
    let bodyParts: [String]
    let status: String
    let uploadedAt: String?
    let downloadCount: Int?

    enum CodingKeys: String, CodingKey {
        case poseId, id, name, skeletonUrl, imagePath, thumbnailUrl, thumbnailPath
        case difficulty, tags, description, bodyParts, status, uploadedAt, downloadCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        poseId = try c.decodeIfPresent(String.self, forKey: .poseId)
            ?? c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        skeletonUrl = try c.decodeIfPresent(String.self, forKey: .skeletonUrl)
            ?? c.decodeIfPresent(String.self, forKey: .imagePath) ?? ""
        thumbnailUrl = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
            ?? c.decodeIfPresent(String.self, forKey: .thumbnailPath) ?? ""
        difficulty = try c.decodeIfPresent(String.self, forKey: .difficulty)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        description = try c.decodeIfPresent(String.self, forKey: .description)
        bodyParts = try c.decodeIfPresent([String].self, forKey: .bodyParts) ?? []
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "published"
        uploadedAt = try c.decodeIfPresent(String.self, forKey: .uploadedAt)
        downloadCount = try c.decodeIfPresent(Int.self, forKey: .downloadCount)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(poseId, forKey: .poseId)
        try c.encode(name, forKey: .name)
        try c.encode(skeletonUrl, forKey: .skeletonUrl)
        try c.encode(thumbnailUrl, forKey: .thumbnailUrl)
        try c.encodeIfPresent(difficulty, forKey: .difficulty)
        try c.encode(tags, forKey: .tags)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(bodyParts, forKey: .bodyParts)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(uploadedAt, forKey: .uploadedAt)
        try c.encodeIfPresent(downloadCount, forKey: .downloadCount)
    }
}

struct PaginationInfo: Codable, Sendable {
    let page: Int
    let limit: Int
    let total: Int
}

struct PaginatedResult<T: Codable & Sendable>: Codable, Sendable where T: Sendable {
    let data: [T]
    let pagination: PaginationInfo
}

struct AccountSummary: Codable, Sendable, Equatable {
    let id: String
    let displayName: String
    let createdAt: String?
}

struct AccountSummaryResponse: Codable, Sendable {
    let data: AccountSummary
}

struct CommunityPoseDetailResponse: Codable, Sendable {
    let data: CommunityPose
}

struct RefreshRequest: Codable, Sendable {
    let refreshToken: String
}

struct RefreshResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
}

struct SessionExchangeRequest: Codable, Sendable {
    let code: String
}

struct SessionExchangeResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
}
