import SwiftUI

/// Handles creating, updating encrypted cards, and owner secret rotation.
@MainActor
@Observable
final class CardEditorViewModel {
    var cardData = CardData()
    var childAlias: String = ""
    var isSaving = false
    var error: String?

    private let api = APIClient.shared
    private let crypto = CryptoService.shared
    private let keychain = KeychainService.shared
    private let cache = CacheService.shared

    // For editing existing cards
    var existingCardId: String?
    var existingOwnerSecret: String?
    var existingCardKeyBase64: String?

    /// Load an existing card for editing.
    func loadCard(cardId: String) async {
        guard let ownerSecret = keychain.ownerSecret(forCardId: cardId),
              let cardKey = keychain.cardKey(forCardId: cardId) else {
            error = "Card credentials not found locally"
            return
        }

        existingCardId = cardId
        existingOwnerSecret = ownerSecret
        existingCardKeyBase64 = cardKey

        // Try cache first for instant display
        if let cached = cache.loadCachedCardData(forCardId: cardId) {
            cardData = cached
        }

        do {
            let response = try await api.fetchCard(cardId: cardId, ownerSecret: ownerSecret)
            cardData = try crypto.decrypt(
                blob: response.encryptedBlob,
                iv: response.blobIv,
                authTag: response.blobAuthTag,
                withKeyBase64: cardKey
            )
            cache.cacheCardData(cardData, forCardId: cardId)
        } catch let error as APIError where error.isNotModified {
            // Card hasn't changed, keep showing cached data
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Create a new card on the server.
    func createCard() async -> String? {
        guard let deviceId = keychain.deviceId else {
            error = "Device not registered"
            return nil
        }

        isSaving = true
        error = nil

        do {
            let cardKey = crypto.generateAESKey()
            let ownerSecret = crypto.generateOwnerSecret()

            let encrypted = try crypto.encrypt(cardData: cardData, withKeyBase64: cardKey)

            let request = CreateCardRequest(
                ownerDeviceId: deviceId,
                ownerSecret: ownerSecret,
                encryptedBlob: encrypted.blob,
                blobIv: encrypted.iv,
                blobAuthTag: encrypted.authTag,
                schemaVersion: CardData.schemaVersion,
                childAlias: childAlias.isEmpty ? nil : childAlias
            )

            let response = try await api.createCard(request: request)

            keychain.saveOwnerSecret(ownerSecret, forCardId: response.cardId)
            keychain.saveCardKey(cardKey, forCardId: response.cardId)
            cache.cacheCardData(cardData, forCardId: response.cardId)
            BackupService.shared.scheduleBackup()

            isSaving = false
            return response.cardId
        } catch {
            self.error = error.localizedDescription
            isSaving = false
            return nil
        }
    }

    /// Update an existing card on the server.
    func updateCard() async -> Bool {
        guard let cardId = existingCardId,
              let ownerSecret = existingOwnerSecret,
              let cardKey = existingCardKeyBase64 else {
            error = "Missing card credentials"
            return false
        }

        isSaving = true
        error = nil

        do {
            let encrypted = try crypto.encrypt(cardData: cardData, withKeyBase64: cardKey)

            let request = UpdateCardRequest(
                encryptedBlob: encrypted.blob,
                blobIv: encrypted.iv,
                blobAuthTag: encrypted.authTag,
                schemaVersion: CardData.schemaVersion,
                childAlias: childAlias.isEmpty ? nil : childAlias
            )

            _ = try await api.updateCard(cardId: cardId, ownerSecret: ownerSecret, request: request)
            cache.cacheCardData(cardData, forCardId: cardId)
            BackupService.shared.scheduleBackup()

            isSaving = false
            return true
        } catch {
            self.error = error.localizedDescription
            isSaving = false
            return false
        }
    }

    /// Rotate the owner secret for the current card.
    func rotateOwnerSecret() async -> Bool {
        guard let cardId = existingCardId,
              let ownerSecret = existingOwnerSecret else {
            error = "No card loaded"
            return false
        }

        let newSecret = crypto.generateOwnerSecret()

        do {
            try await api.rotateOwnerSecret(cardId: cardId, ownerSecret: ownerSecret, newOwnerSecret: newSecret)
            keychain.saveOwnerSecret(newSecret, forCardId: cardId)
            existingOwnerSecret = newSecret
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
