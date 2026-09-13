import Foundation

/// Runtime API base URL holder. Startup resolution writes here before any API call.
final class AppConfig: @unchecked Sendable {
    static let shared = AppConfig()

    private let lock = NSLock()
    private var _serverBaseURL = "https://pose-extract-server-production.up.railway.app"

    var SERVER_BASE_URL: String {
        lock.lock()
        defer { lock.unlock() }
        return _serverBaseURL
    }

    func applyEndpoint(_ url: String) {
        lock.lock()
        _serverBaseURL = url
        lock.unlock()
    }
}
