import SwiftUI

/// Root application state managing device registration, push, and deep links.
@MainActor
@Observable
final class AppState {
    var isRegistered = false
    var deviceId: String?
    var isLoading = true
    var error: String?
    var serverURL: String

    /// Deep link that should be handled after app is ready.
    var pendingDeepLink: DeepLink?

    private let api = APIClient.shared
    private let crypto = CryptoService.shared
    private let keychain = KeychainService.shared
    private let push = PushNotificationService.shared
    private let recovery = RecoveryService.shared

    init() {
        self.serverURL = keychain.serverURL ?? "http://localhost:3000"
        self.deviceId = keychain.deviceId
        self.isRegistered = keychain.deviceId != nil
    }

    /// Initialize the app: fetch remote config, then register device with server if needed.
    func initialize() async {
        isLoading = true
        error = nil

        serverURL = keychain.serverURL ?? "http://localhost:3000"

        do {
            let publicKey = try crypto.devicePublicKeyBase64()

            if let existingDeviceId = keychain.deviceId {
                deviceId = existingDeviceId
                isRegistered = true
            } else {
                let response = try await api.registerDevice(publicKey: publicKey)
                keychain.deviceId = response.deviceId
                deviceId = response.deviceId
                isRegistered = true
            }

            // Register for push notifications after device is set up
            push.registerForPushNotifications()

            // Ensure recovery key exists and update recovery blob
            _ = recovery.getOrCreateRecoveryKey()
            recovery.updateRecoveryBlob()
        } catch {
            // If already registered, proceed offline with cached data
            if keychain.deviceId != nil {
                deviceId = keychain.deviceId
                isRegistered = true
            } else {
                self.error = error.localizedDescription
            }
        }

        isLoading = false
    }

    /// Called when the app returns to foreground.
    func didBecomeActive() async {
        guard isRegistered else { return }
        // Refresh will be handled by individual views listening for notifications
        // Post a general refresh notification
        NotificationCenter.default.post(name: .myPassShouldRefresh, object: nil)
    }

    func updateServerURL(_ url: String) {
        serverURL = url
        keychain.serverURL = url
    }

    func resetDevice() {
        keychain.deviceId = nil
        deviceId = nil
        isRegistered = false
        CacheService.shared.clearAll()
    }

    /// Handle an incoming deep link URL (mypass://links/TOKEN#KEY).
    func handleDeepLink(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        pendingDeepLink = link
    }
}

// MARK: - Deep Link

enum DeepLink: Equatable {
    case redeemShareLink(token: String, keyFragment: String?)

    init?(url: URL) {
        guard url.scheme == "mypass" else { return nil }

        // mypass://links/TOKEN#KEY
        if url.host == "links", let token = url.pathComponents.dropFirst().first {
            let fragment = url.fragment
            self = .redeemShareLink(token: String(token), keyFragment: fragment)
        } else {
            return nil
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let myPassShouldRefresh = Notification.Name("MyPass.shouldRefresh")
}
