import Foundation
import UserNotifications
import UIKit

/// Manages push notification registration, permission, and APNs token handling.
///
/// The server is sent the raw APNs device token (hex-encoded). It is the server's
/// responsibility to deliver pushes via APNs or a relay of its choice.
@MainActor
final class PushNotificationService: NSObject {
    static let shared = PushNotificationService()

    private let api = APIClient.shared
    private let keychain = KeychainService.shared

    static let cardUpdatedNotification = Notification.Name("MyPass.cardUpdated")
    static let newShareNotification = Notification.Name("MyPass.newShare")
    static let cardDeletedNotification = Notification.Name("MyPass.cardDeleted")
    static let shareExpiredNotification = Notification.Name("MyPass.shareExpired")

    private override init() {
        super.init()
    }

    /// Request notification permission and register for remote notifications with APNs.
    func registerForPushNotifications() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Called when APNs provides a device token. Forwards it to the server.
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        let hexToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        sendTokenToServer(hexToken)
    }

    private func sendTokenToServer(_ pushToken: String) {
        Task {
            guard let deviceId = keychain.deviceId else { return }
            try? await api.updatePushToken(deviceId: deviceId, pushToken: pushToken)
        }
    }

    /// Process a push notification payload.
    func handleNotification(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }

        switch type {
        case "card_update":
            let cardId = userInfo["card_id"] as? String
            NotificationCenter.default.post(
                name: Self.cardUpdatedNotification,
                object: nil,
                userInfo: cardId.map { ["card_id": $0] }
            )

        case "new_share":
            let cardId = userInfo["card_id"] as? String
            NotificationCenter.default.post(
                name: Self.newShareNotification,
                object: nil,
                userInfo: cardId.map { ["card_id": $0] }
            )

        case "card_deleted":
            let cardId = userInfo["card_id"] as? String
            if let cardId {
                KeychainService.shared.deleteUnwrappedKey(forCardId: cardId)
                CacheService.shared.removeCachedCardData(forCardId: cardId)
            }
            NotificationCenter.default.post(
                name: Self.cardDeletedNotification,
                object: nil,
                userInfo: cardId.map { ["card_id": $0] }
            )

        case "share_expired":
            let cardId = userInfo["card_id"] as? String
            if let cardId {
                KeychainService.shared.deleteUnwrappedKey(forCardId: cardId)
                CacheService.shared.removeCachedCardData(forCardId: cardId)
            }
            NotificationCenter.default.post(
                name: Self.shareExpiredNotification,
                object: nil,
                userInfo: cardId.map { ["card_id": $0] }
            )

        default:
            break
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationService: @preconcurrency UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        Task { @MainActor in
            handleNotification(userInfo: userInfo)
        }
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            handleNotification(userInfo: userInfo)
        }
        completionHandler()
    }
}
