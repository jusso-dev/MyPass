import Foundation

/// HTTP client for all MyPass server API endpoints.
///
/// Includes ETag-based caching and request throttling to avoid redundant
/// GET requests when data hasn't changed. ETags are sent via `If-None-Match`
/// and the server returns 304 Not Modified when the client's cached version
/// is still current. Client-side throttling prevents hitting the server at
/// all for repeated identical GETs within a short window.
final class APIClient {
    static let shared = APIClient()

    private let session = URLSession.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// ETag cache: URL string → last known ETag value from server
    private var etags: [String: String] = [:]

    /// Request timestamps for throttling: URL string → last successful request time
    private var lastRequestTimes: [String: Date] = [:]

    /// Minimum interval between identical GET requests (seconds).
    /// Within this window, the client returns `.notModified` without hitting the server.
    /// Set high enough that foreground-resume refreshes don't spam the server.
    private let throttleInterval: TimeInterval = 120

    var baseURL: String {
        KeychainService.shared.serverURL ?? "http://localhost:3000"
    }

    private init() {}

    /// Clear all cached ETags and throttle timestamps.
    /// Called after any mutation (POST/PUT/DELETE) so the next GET goes through.
    private func invalidateGETCaches() {
        lastRequestTimes.removeAll()
    }

    /// Clear throttle timestamps so the next GET goes to the server,
    /// but keep ETags so the server can still return 304 if nothing changed.
    /// Call this when a push notification signals new data may be available.
    func clearThrottles() {
        lastRequestTimes.removeAll()
    }

    // MARK: - Health

    func healthCheck() async throws -> HealthResponse {
        try await get("/health")
    }

    // MARK: - Devices

    func registerDevice(publicKey: String, pushToken: String? = nil) async throws -> RegisterDeviceResponse {
        let body = RegisterDeviceRequest(publicKey: publicKey, pushToken: pushToken, platform: "ios")
        return try await post("/v1/devices", body: body)
    }

    func updatePushToken(deviceId: String, pushToken: String) async throws {
        let body = UpdatePushTokenRequest(pushToken: pushToken, platform: "ios")
        let _: OkResponse = try await put("/v1/devices/\(deviceId)/push", body: body)
    }

    func fetchPublicKey(deviceId: String) async throws -> PublicKeyResponse {
        try await get("/v1/devices/\(deviceId)/public-key")
    }

    // MARK: - Cards

    func createCard(request: CreateCardRequest) async throws -> CreateCardResponse {
        try await post("/v1/cards", body: request)
    }

    func fetchCard(cardId: String, ownerSecret: String) async throws -> FetchCardResponse {
        try await get("/v1/cards/\(cardId)", headers: ["X-Owner-Secret": ownerSecret])
    }

    func fetchCardAsSubscriber(cardId: String, deviceId: String) async throws -> FetchCardResponse {
        try await get("/v1/cards/\(cardId)", headers: ["X-Device-Id": deviceId])
    }

    func updateCard(cardId: String, ownerSecret: String, request: UpdateCardRequest) async throws -> UpdateCardResponse {
        try await put("/v1/cards/\(cardId)", body: request, headers: ["X-Owner-Secret": ownerSecret])
    }

    func deleteCard(cardId: String, ownerSecret: String) async throws {
        let _: OkResponse = try await delete("/v1/cards/\(cardId)", headers: ["X-Owner-Secret": ownerSecret])
    }

    func listCards(deviceId: String) async throws -> CardListResponse {
        try await get("/v1/cards?owner_device_id=\(deviceId)")
    }

    func rotateKey(cardId: String, ownerSecret: String, request: RotateKeyRequest) async throws -> RotateKeyResponse {
        try await post("/v1/cards/\(cardId)/rotate-key", body: request, headers: ["X-Owner-Secret": ownerSecret])
    }

    func rotateOwnerSecret(cardId: String, ownerSecret: String, newOwnerSecret: String) async throws {
        let body = RotateOwnerSecretRequest(newOwnerSecret: newOwnerSecret)
        let _: OkResponse = try await put("/v1/cards/\(cardId)/owner-secret", body: body, headers: ["X-Owner-Secret": ownerSecret])
    }

    // MARK: - Subscriptions

    func createSubscription(cardId: String, ownerSecret: String, request: CreateSubscriptionRequest) async throws -> CreateSubscriptionResponse {
        try await post("/v1/cards/\(cardId)/subscriptions", body: request, headers: ["X-Owner-Secret": ownerSecret])
    }

    func listReceivedSubscriptions(deviceId: String) async throws -> ReceivedSubscriptionsResponse {
        try await get("/v1/subscriptions/received", headers: ["X-Device-Id": deviceId])
    }

    func listCardSubscribers(cardId: String, ownerSecret: String) async throws -> CardSubscribersResponse {
        try await get("/v1/cards/\(cardId)/subscriptions", headers: ["X-Owner-Secret": ownerSecret])
    }

    func revokeSubscription(subscriptionId: String, ownerSecret: String) async throws {
        let _: OkResponse = try await delete("/v1/subscriptions/\(subscriptionId)", headers: ["X-Owner-Secret": ownerSecret])
    }

    // MARK: - Share Links

    func createShareLink(cardId: String, ownerSecret: String, request: CreateShareLinkRequest) async throws -> CreateShareLinkResponse {
        try await post("/v1/cards/\(cardId)/links", body: request, headers: ["X-Owner-Secret": ownerSecret])
    }

    func listShareLinks(cardId: String, ownerSecret: String) async throws -> ShareLinksResponse {
        try await get("/v1/cards/\(cardId)/links", headers: ["X-Owner-Secret": ownerSecret])
    }

    func redeemShareLink(token: String, deviceId: String) async throws -> RedeemShareLinkResponse {
        try await get("/v1/links/\(token)/card", headers: ["X-Device-Id": deviceId])
    }

    func revokeShareLink(cardId: String, token: String, ownerSecret: String) async throws {
        let _: OkResponse = try await delete("/v1/cards/\(cardId)/links/\(token)", headers: ["X-Owner-Secret": ownerSecret])
    }

    // MARK: - HTTP Helpers

    private func get<T: Decodable>(_ path: String, headers: [String: String] = [:]) async throws -> T {
        let url = URL(string: baseURL + path)!
        let urlString = url.absoluteString

        // Throttle: if we successfully fetched this URL recently, skip the request
        if let lastTime = lastRequestTimes[urlString],
           Date().timeIntervalSince(lastTime) < throttleInterval {
            throw APIError.notModified
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        // Send cached ETag so the server can return 304 if nothing changed
        if let etag = etags[urlString] {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        return try await execute(request)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B, headers: [String: String] = [:]) async throws -> T {
        invalidateGETCaches()
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await execute(request)
    }

    private func put<T: Decodable, B: Encodable>(_ path: String, body: B, headers: [String: String] = [:]) async throws -> T {
        invalidateGETCaches()
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await execute(request)
    }

    private func delete<T: Decodable>(_ path: String, headers: [String: String] = [:]) async throws -> T {
        invalidateGETCaches()
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await execute(request)
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        let urlString = request.url?.absoluteString ?? ""
        let statusCode = httpResponse.statusCode

        // Store ETag from response for future conditional requests
        if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
            etags[urlString] = etag
        }

        // Track successful GET request time for throttling
        if request.httpMethod == "GET" && (200...399).contains(statusCode) {
            lastRequestTimes[urlString] = Date()
        }

        // Server says nothing changed — caller should use cached data
        if statusCode == 304 {
            throw APIError.notModified
        }

        guard (200...299).contains(statusCode) else {
            let message = (try? decoder.decode(ErrorResponse.self, from: data))?.error ?? "Unknown error"

            switch statusCode {
            case 403: throw APIError.forbidden(message)
            case 404: throw APIError.notFound(message)
            case 410: throw APIError.gone(message)
            case 429: throw APIError.rateLimited
            default:  throw APIError.server(statusCode: statusCode, message: message)
            }
        }

        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Error Types

enum APIError: LocalizedError {
    case invalidResponse
    case forbidden(String)
    case notFound(String)
    case gone(String)
    case rateLimited
    case notModified
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .forbidden(let msg):
            return "Access denied: \(msg)"
        case .notFound(let msg):
            return "Not found: \(msg)"
        case .gone(let msg):
            return "No longer available: \(msg)"
        case .rateLimited:
            return "Too many requests. Please try again shortly."
        case .notModified:
            return nil
        case .server(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        }
    }

    var isAccessRevoked: Bool {
        if case .forbidden = self { return true }
        return false
    }

    var isNotFound: Bool {
        if case .notFound = self { return true }
        return false
    }

    var isExpired: Bool {
        if case .gone = self { return true }
        return false
    }

    var isNotModified: Bool {
        if case .notModified = self { return true }
        return false
    }
}
