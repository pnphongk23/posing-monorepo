import Foundation

struct PoseAPIService: Sendable {
    let client: APIClient

    func startPoseExtraction(imageBytes: Data, fileName: String, draft: PoseDraft? = nil) async throws -> PoseExtractionStartResponse {
        var fields: [(String, String)] = []
        if let draft {
            fields.append(("name", draft.name))
            for tag in draft.tags {
                fields.append(("tags", tag))
            }
            if let description = draft.description {
                fields.append(("description", description))
            }
        }
        let mimeType = mimeTypeFromFileName(fileName)
        let body = multipartBody(
            fields: fields,
            fileField: "image",
            fileName: fileName,
            mimeType: mimeType,
            fileData: imageBytes
        )
        let (data, _) = try await client.request(
            path: "/api/extract-pose",
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(multipartBoundary)",
            acceptedStatus: [202]
        )
        return try client.decode(PoseExtractionStartResponse.self, from: data)
    }

    func getPoseExtractionJob(jobId: String) async throws -> PoseExtractionJobStatus {
        let (data, _) = try await client.request(path: "/api/extract-jobs/\(jobId)")
        return try client.decode(PoseExtractionJobStatus.self, from: data)
    }

    func listMyExtractJobs(
        state: String? = nil,
        cursor: String? = nil,
        limit: Int = 20
    ) async throws -> ExtractionJobListResponse {
        var query = [
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let state { query.append(URLQueryItem(name: "state", value: state)) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let (data, _) = try await client.request(path: "/api/me/extract-jobs", query: query)
        return try client.decode(ExtractionJobListResponse.self, from: data)
    }

    func retryExtractJob(id: String) async throws -> PoseExtractionStartResponse {
        let (data, _) = try await client.request(
            path: "/api/me/extract-jobs/\(id)/retry",
            method: "POST",
            acceptedStatus: [202]
        )
        return try client.decode(PoseExtractionStartResponse.self, from: data)
    }

    func hideExtractJob(id: String) async throws {
        _ = try await client.request(
            path: "/api/me/extract-jobs/\(id)",
            method: "DELETE",
            acceptedStatus: [204]
        )
    }

    func getGuide(id: String) async throws -> GuidePose {
        let (data, _) = try await client.request(path: "/api/guides/\(id)")
        return try client.decode(GuidePoseDetailResponse.self, from: data).data
    }

    func getCommunityPoses(
        page: Int = 1,
        limit: Int = 20,
        difficulty: String? = nil,
        tag: String? = nil,
        q: String? = nil
    ) async throws -> PaginatedResult<CommunityPose> {
        var query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let difficulty { query.append(URLQueryItem(name: "difficulty", value: difficulty)) }
        if let tag { query.append(URLQueryItem(name: "tag", value: tag)) }
        if let q { query.append(URLQueryItem(name: "q", value: q)) }
        let (data, _) = try await client.request(path: "/api/community/poses", query: query)
        return try client.decode(PaginatedResult<CommunityPose>.self, from: data)
    }

    func getCurrentAccount() async throws -> AccountSummary {
        let (data, _) = try await client.request(path: "/api/account/me")
        return try client.decode(AccountSummaryResponse.self, from: data).data
    }

    func deleteAccount() async throws {
        try await client.deleteAccount()
    }

    func getSavedPoses(page: Int = 1, limit: Int = 20) async throws -> PaginatedResult<CommunityPose> {
        precondition(page >= 1)
        precondition((1...100).contains(limit))
        let query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let (data, _) = try await client.request(path: "/api/me/saved", query: query)
        return try client.decode(PaginatedResult<CommunityPose>.self, from: data)
    }

    func savePose(poseId: String) async throws -> CommunityPose {
        let (data, _) = try await client.request(path: "/api/me/saved/\(poseId)", method: "PUT", acceptedStatus: [200])
        return try client.decode(CommunityPoseDetailResponse.self, from: data).data
    }

    func unsavePose(poseId: String) async throws {
        _ = try await client.request(path: "/api/me/saved/\(poseId)", method: "DELETE", acceptedStatus: [204])
    }

    func downloadImageBytes(url: String) async throws -> Data {
        let resolved = if url.hasPrefix("http://") || url.hasPrefix("https://") {
            url
        } else {
            "\(client.baseURL)/\(url.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        }
        guard let target = URL(string: resolved) else { throw APIClientError.invalidURL }
        var request = URLRequest(url: target)
        if let token = await client.boundary.loadAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PoseAPIError(code: String(status), message: "Failed to download image: \(status)")
        }
        return data
    }

    private func mimeTypeFromFileName(_ fileName: String) -> String {
        let lower = fileName.lowercased()
        if lower.hasSuffix(".png") { return "image/png" }
        if lower.hasSuffix(".webp") { return "image/webp" }
        if lower.hasSuffix(".gif") { return "image/gif" }
        return "image/jpeg"
    }

    private let multipartBoundary = "AIPoseBoundary"

    private func multipartBody(
        fields: [(String, String)],
        fileField: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.append("--\(multipartBoundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        body.append("--\(multipartBoundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(multipartBoundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
