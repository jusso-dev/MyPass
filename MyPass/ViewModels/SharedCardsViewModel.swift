import SwiftUI

/// Manages cards shared with this device with key caching.
@MainActor
@Observable
final class SharedCardsViewModel {
    var subscriptions: [ReceivedSubscription] = []
    var isLoading = false
    var error: String?

    private let api = APIClient.shared
    private let keychain = KeychainService.shared
    private let cache = CacheService.shared
    private let crypto = CryptoService.shared

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func loadSharedCards() async {
        guard let deviceId = keychain.deviceId else { return }

        // Show cached data immediately
        if subscriptions.isEmpty, let cached = cache.loadCachedSubscriptions() {
            subscriptions = filterExpired(cached)
        }

        isLoading = subscriptions.isEmpty
        error = nil

        do {
            let response = try await api.listReceivedSubscriptions(deviceId: deviceId)
            subscriptions = filterExpired(response.subscriptions)
            cache.cacheSubscriptions(response.subscriptions)
        } catch let error as APIError where error.isNotModified {
            // Data hasn't changed, but filter out any newly expired
            subscriptions = filterExpired(subscriptions)
        } catch {
            if subscriptions.isEmpty {
                self.error = error.localizedDescription
            }
        }

        isLoading = false
    }

    /// Remove expired subscriptions from the list and clean up their local data.
    private func filterExpired(_ subs: [ReceivedSubscription]) -> [ReceivedSubscription] {
        let now = Date()
        var active: [ReceivedSubscription] = []
        for sub in subs {
            if let expiresAt = sub.expiresAt,
               let expiry = Self.isoFormatter.date(from: expiresAt) ?? Self.isoFormatterNoFrac.date(from: expiresAt),
               expiry <= now {
                // Expired — clean up local cached data
                keychain.deleteUnwrappedKey(forCardId: sub.cardId)
                cache.removeCachedCardData(forCardId: sub.cardId)
            } else {
                active.append(sub)
            }
        }
        return active
    }

    /// Fetch and decrypt a shared card, using cached unwrapped key when available.
    func decryptSharedCard(_ subscription: ReceivedSubscription) async -> CardData? {
        guard let deviceId = keychain.deviceId else { return nil }

        do {
            // Try cached unwrapped key first
            var cardKey: String
            if let cached = keychain.unwrappedKey(forCardId: subscription.cardId) {
                cardKey = cached
            } else {
                // Unwrap via ECDH and cache
                cardKey = try crypto.unwrapKey(
                    wrappedKeyBase64: subscription.wrappedKey,
                    ephemeralPublicKeyBase64: subscription.ephemeralPublicKey
                )
                keychain.saveUnwrappedKey(cardKey, forCardId: subscription.cardId)
            }

            // Fetch encrypted card
            let card = try await api.fetchCardAsSubscriber(cardId: subscription.cardId, deviceId: deviceId)

            // Decrypt
            let cardData = try crypto.decrypt(
                blob: card.encryptedBlob,
                iv: card.blobIv,
                authTag: card.blobAuthTag,
                withKeyBase64: cardKey
            )

            // Cache decrypted data
            cache.cacheCardData(cardData, forCardId: subscription.cardId)

            return cardData
        } catch let apiError as APIError where apiError.isNotModified {
            // Card hasn't changed, return cached data
            return cache.loadCachedCardData(forCardId: subscription.cardId)
        } catch let apiError as APIError where apiError.isAccessRevoked {
            // Access was revoked or key was rotated
            keychain.deleteUnwrappedKey(forCardId: subscription.cardId)
            cache.removeCachedCardData(forCardId: subscription.cardId)
            self.error = "Your access to this card has been revoked."
            return nil
        } catch is CryptoKit.CryptoKitError {
            // Key rotation happened - cached key is stale
            keychain.deleteUnwrappedKey(forCardId: subscription.cardId)
            self.error = "This card was re-encrypted. Your access may have been revoked."
            return nil
        } catch {
            // Try returning cached data for offline viewing
            if let cached = cache.loadCachedCardData(forCardId: subscription.cardId) {
                return cached
            }
            self.error = error.localizedDescription
            return nil
        }
    }
}

import CryptoKit
