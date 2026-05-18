import SwiftUI

/// Manages the list of cards owned by this device with offline caching.
@MainActor
@Observable
final class CardListViewModel {
    var cards: [CardSummary] = []
    var isLoading = false
    var error: String?

    private let api = APIClient.shared
    private let keychain = KeychainService.shared
    private let cache = CacheService.shared

    func loadCards() async {
        guard let deviceId = keychain.deviceId else { return }

        // Show cached data immediately if available
        if cards.isEmpty, let cached = cache.loadCachedCardList() {
            cards = cached
        }

        isLoading = cards.isEmpty
        error = nil

        do {
            let response = try await api.listCards(deviceId: deviceId)
            var mergedCards = response.cards
            let serverCardIds = Set(response.cards.map(\.cardId))

            // Preserve restored cards that have valid keys but aren't owned by this device ID.
            // These come from backup restores and can still be accessed via their owner secret.
            if let cached = cache.loadCachedCardList() {
                for cachedCard in cached where !serverCardIds.contains(cachedCard.cardId) {
                    if keychain.ownerSecret(forCardId: cachedCard.cardId) != nil,
                       keychain.cardKey(forCardId: cachedCard.cardId) != nil {
                        mergedCards.append(cachedCard)
                    }
                }
            }

            cards = mergedCards
            cache.cacheCardList(mergedCards)
            BackupService.shared.scheduleBackup()
        } catch let error as APIError where error.isNotModified {
            // Data hasn't changed, keep showing cached data
        } catch {
            // Only show error if we have no cached data
            if cards.isEmpty {
                self.error = error.localizedDescription
            }
        }

        isLoading = false
    }

    func deleteCard(_ card: CardSummary) async -> Bool {
        guard let ownerSecret = keychain.ownerSecret(forCardId: card.cardId) else {
            error = "Owner secret not found"
            return false
        }

        do {
            try await api.deleteCard(cardId: card.cardId, ownerSecret: ownerSecret)
            keychain.deleteOwnerSecret(forCardId: card.cardId)
            keychain.deleteCardKey(forCardId: card.cardId)
            cache.removeCachedCardData(forCardId: card.cardId)
            cards.removeAll { $0.cardId == card.cardId }
            cache.cacheCardList(cards)
            BackupService.shared.scheduleBackup()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
