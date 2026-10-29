import Foundation

struct PoseDraft: Codable, Sendable, Equatable {
    let name: String
    let tags: [String]
    let description: String?

    init(name: String, tags: [String], description: String? = nil) {
        self.name = name
        self.tags = tags
        self.description = description
    }
}

struct ExtractionJobListItem: Codable, Sendable, Identifiable, Equatable {
    var id: String { jobId }
    let jobId: String
    let status: String
    let poseDraft: PoseDraft?
    let poseId: String?
    let thumbnailUrl: String?
    let errorCode: String?
    let errorMessage: String?
    let createdAt: String
    let updatedAt: String
}

struct ExtractionJobListMeta: Codable, Sendable, Equatable {
    let nextCursor: String?
}

struct ExtractionJobListResponse: Codable, Sendable, Equatable {
    let success: Bool
    let data: [ExtractionJobListItem]
    let meta: ExtractionJobListMeta?
}

struct GuidePose: Codable, Sendable, Identifiable, Equatable {
    var id: String { poseId }
    let poseId: String
    let ownerAccountId: String?
    let name: String
    let description: String?
    let tags: [String]
    let difficulty: String?
    let bodyParts: [String]?
    let status: String
    let originalUrl: String?
    let skeletonUrl: String
    let thumbnailUrl: String
    let currentJobId: String?
    let createdAt: String?
    let updatedAt: String?
}

struct GuidePoseDetailResponse: Codable, Sendable, Equatable {
    let data: GuidePose
}

struct ExtractPoseData: Codable, Sendable, Equatable {
    let imageBase64: String?
    let mimeType: String?
    let processingTimeMs: Int64?

    init(imageBase64: String? = nil, mimeType: String? = nil, processingTimeMs: Int64? = nil) {
        self.imageBase64 = imageBase64
        self.mimeType = mimeType
        self.processingTimeMs = processingTimeMs
    }
}

struct PoseExtractionJob: Codable, Sendable, Equatable {
    let jobId: String
    let status: String
}

struct PoseExtractionMeta: Codable, Sendable, Equatable {
    let pollUrl: String?
}

struct PoseExtractionStartResponse: Codable, Sendable, Equatable {
    let success: Bool
    let data: PoseExtractionJob
    let meta: PoseExtractionMeta?
}

struct ApiErrorResponse: Codable, Sendable, Equatable {
    let code: String?
    let message: String?
}

struct ApiErrorEnvelope: Codable, Sendable, Equatable {
    let error: ApiErrorResponse?
}

struct PoseExtractionJobData: Codable, Sendable, Equatable {
    let jobId: String
    let status: String
    let poseId: String?
    let result: ExtractPoseData?
    let error: ApiErrorResponse?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case jobId, status, poseId, result, error, updatedAt
    }

    init(
        jobId: String,
        status: String,
        poseId: String? = nil,
        result: ExtractPoseData? = nil,
        error: ApiErrorResponse? = nil,
        updatedAt: String? = nil
    ) {
        self.jobId = jobId
        self.status = status
        self.poseId = poseId
        self.result = result
        self.error = error
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try c.decode(String.self, forKey: .jobId)
        status = try c.decode(String.self, forKey: .status)
        poseId = try c.decodeIfPresent(String.self, forKey: .poseId)
        result = try c.decodeIfPresent(ExtractPoseData.self, forKey: .result)
        error = try c.decodeIfPresent(ApiErrorResponse.self, forKey: .error)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct PoseExtractionJobStatus: Codable, Sendable, Equatable {
    let success: Bool?
    let data: PoseExtractionJobData

    init(data: PoseExtractionJobData, success: Bool? = nil) {
        self.data = data
        self.success = success
    }
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

/// POST /api/auth/email/signin (PLAN §4): token pair plus the signed-in account, the same shape
/// `/api/auth/refresh` returns plus `account`.
struct EmailSignInRequest: Codable, Sendable {
    let email: String
    let password: String
}

struct EmailSignInResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let account: AccountSummary
}

struct AppleSignInRequest: Codable, Sendable {
    let identityToken: String
    let nonce: String
    let fullName: String?
}

struct AppleSignInResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let account: AccountSummary
}

/// The optional `DELETE /api/account` body. Only sent for an account that signs in with Apple, and
/// only after the server asked for it with `409 APPLE_REAUTH_REQUIRED`.
struct AppleAccountDeletionRequest: Codable, Sendable {
    let appleAuthorizationCode: String
}
