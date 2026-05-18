import SwiftUI

/// Manages sharing a card: subscriptions, key rotation, share links, role selection.
@MainActor
@Observable
final class ShareFlowViewModel {
    var subscribers: [CardSubscriber] = []
    var shareLinks: [ShareLinkInfo] = []
    var shareLink: CreateShareLinkResponse?
    var isLoading = false
    var isRotatingKey = false
    var error: String?
    var needsKeyRotation = false

    let cardId: String
    let ownerSecret: String

    private let api = APIClient.shared
    private let crypto = CryptoService.shared
    private let keychain = KeychainService.shared

    init(cardId: String, ownerSecret: String) {
        self.cardId = cardId
        self.ownerSecret = ownerSecret
    }

    func loadSubscribers() async {
        isLoading = true
        error = nil

        do {
            let response = try await api.listCardSubscribers(cardId: cardId, ownerSecret: ownerSecret)
            subscribers = response.subscriptions
        } catch let error as APIError where error.isNotModified {
            // Data hasn't changed
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadShareLinks() async {
        do {
            let response = try await api.listShareLinks(cardId: cardId, ownerSecret: ownerSecret)
            shareLinks = response.links
        } catch let error as APIError where error.isNotModified {
            // Data hasn't changed
        } catch {
            // Non-critical, don't show error
        }
    }

    /// Share this card with another device by device ID.
    func shareWithDevice(recipientDeviceId: String, role: String = "trusted", expiresAt: String? = nil) async -> Bool {
        guard let cardKey = keychain.cardKey(forCardId: cardId) else {
            error = "Card key not found"
            return false
        }

        do {
            let pubKeyResponse = try await api.fetchPublicKey(deviceId: recipientDeviceId)

            let wrapped = try crypto.wrapKeyForRecipient(
                cardKeyBase64: cardKey,
                recipientPublicKeyBase64: pubKeyResponse.publicKey
            )

            // For editor role, also wrap the owner secret so they can update the card
            var wrappedOwnerSecret: String?
            var ownerSecretEphemeralKey: String?
            if role == "editor" {
                let wrappedSecret = try crypto.wrapKeyForRecipient(
                    cardKeyBase64: Data(ownerSecret.utf8).base64EncodedString(),
                    recipientPublicKeyBase64: pubKeyResponse.publicKey
                )
                wrappedOwnerSecret = wrappedSecret.wrappedKey
                ownerSecretEphemeralKey = wrappedSecret.ephemeralPublicKey
            }

            let request = CreateSubscriptionRequest(
                deviceId: recipientDeviceId,
                wrappedKey: wrapped.wrappedKey,
                ephemeralPublicKey: wrapped.ephemeralPublicKey,
                role: role,
                expiresAt: expiresAt,
                wrappedOwnerSecret: wrappedOwnerSecret,
                ownerSecretEphemeralKey: ownerSecretEphemeralKey
            )

            _ = try await api.createSubscription(cardId: cardId, ownerSecret: ownerSecret, request: request)

            await loadSubscribers()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// The card's AES key (base64), included in QR URL fragment so the recipient can decrypt.
    var cardKeyBase64: String? {
        keychain.cardKey(forCardId: cardId)
    }

    /// Create a QR share link with role and expiry options.
    func createShareLink(role: String = "temporary", maxUses: Int = 1, expiresInMinutes: Int = 1440) async {
        do {
            let request = CreateShareLinkRequest(
                role: role,
                maxUses: maxUses,
                expiresInMinutes: expiresInMinutes
            )

            shareLink = try await api.createShareLink(cardId: cardId, ownerSecret: ownerSecret, request: request)
            await loadShareLinks()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Revoke a subscriber's access and trigger key rotation.
    func revokeSubscription(_ subscriber: CardSubscriber) async -> Bool {
        do {
            try await api.revokeSubscription(subscriptionId: subscriber.subscriptionId, ownerSecret: ownerSecret)
            subscribers.removeAll { $0.subscriptionId == subscriber.subscriptionId }

            // Flag that key rotation is needed
            if !subscribers.isEmpty {
                needsKeyRotation = true
            }

            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Rotate the card's encryption key after revoking a subscriber.
    /// Re-encrypts the card with a new AES key and wraps it for all remaining subscribers.
    func rotateKeyAfterRevocation() async -> Bool {
        guard let oldCardKey = keychain.cardKey(forCardId: cardId) else {
            error = "Card key not found"
            return false
        }

        isRotatingKey = true
        error = nil

        do {
            // 1. Fetch current card and decrypt with old key
            let card = try await api.fetchCard(cardId: cardId, ownerSecret: ownerSecret)
            let cardData = try crypto.decrypt(
                blob: card.encryptedBlob,
                iv: card.blobIv,
                authTag: card.blobAuthTag,
                withKeyBase64: oldCardKey
            )

            // 2. Generate new AES key
            let newCardKey = crypto.generateAESKey()

            // 3. Re-encrypt card with new key
            let encrypted = try crypto.encrypt(cardData: cardData, withKeyBase64: newCardKey)

            // 4. Wrap new key for each remaining subscriber
            var subscriberKeys: [SubscriberKeyUpdate] = []
            for subscriber in subscribers {
                let pubKeyResponse = try await api.fetchPublicKey(deviceId: subscriber.deviceId)
                let wrapped = try crypto.wrapKeyForRecipient(
                    cardKeyBase64: newCardKey,
                    recipientPublicKeyBase64: pubKeyResponse.publicKey
                )
                subscriberKeys.append(SubscriberKeyUpdate(
                    deviceId: subscriber.deviceId,
                    wrappedKey: wrapped.wrappedKey,
                    ephemeralPublicKey: wrapped.ephemeralPublicKey
                ))
            }

            // 5. Atomic server update
            let request = RotateKeyRequest(
                encryptedBlob: encrypted.blob,
                blobIv: encrypted.iv,
                blobAuthTag: encrypted.authTag,
                subscriberKeys: subscriberKeys
            )

            _ = try await api.rotateKey(cardId: cardId, ownerSecret: ownerSecret, request: request)

            // 6. Update local key
            keychain.saveCardKey(newCardKey, forCardId: cardId)

            // 7. Update cache
            CacheService.shared.cacheCardData(cardData, forCardId: cardId)

            needsKeyRotation = false
            isRotatingKey = false
            return true
        } catch {
            self.error = error.localizedDescription
            isRotatingKey = false
            return false
        }
    }

    /// Revoke a share link.
    func revokeShareLink(_ link: ShareLinkInfo) async -> Bool {
        do {
            try await api.revokeShareLink(cardId: cardId, token: link.token, ownerSecret: ownerSecret)
            shareLinks.removeAll { $0.token == link.token }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Rotate the owner secret for this card.
    func rotateOwnerSecret() async -> String? {
        let newSecret = crypto.generateOwnerSecret()

        do {
            try await api.rotateOwnerSecret(cardId: cardId, ownerSecret: ownerSecret, newOwnerSecret: newSecret)
            keychain.saveOwnerSecret(newSecret, forCardId: cardId)
            return newSecret
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
