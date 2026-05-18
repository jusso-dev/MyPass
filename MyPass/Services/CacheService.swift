import Foundation

/// File-based local cache for card data and unwrapped keys.
/// Allows offline viewing of previously loaded cards.
final class CacheService {
    static let shared = CacheService()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var cacheDir: URL {
        let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyPassCache", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {}

    // MARK: - Card List Cache

    func cacheCardList(_ cards: [CardSummary]) {
        write(cards, to: "card_list.json")
    }

    func loadCachedCardList() -> [CardSummary]? {
        read([CardSummary].self, from: "card_list.json")
    }

    // MARK: - Decrypted Card Data Cache (per card)

    func cacheCardData(_ data: CardData, forCardId cardId: String) {
        write(data, to: "card_\(cardId).json")
    }

    func loadCachedCardData(forCardId cardId: String) -> CardData? {
        read(CardData.self, from: "card_\(cardId).json")
    }

    func removeCachedCardData(forCardId cardId: String) {
        remove("card_\(cardId).json")
    }

    // MARK: - Received Subscriptions Cache

    func cacheSubscriptions(_ subs: [ReceivedSubscription]) {
        write(subs, to: "subscriptions.json")
    }

    func loadCachedSubscriptions() -> [ReceivedSubscription]? {
        read([ReceivedSubscription].self, from: "subscriptions.json")
    }

    // MARK: - Unwrapped Key Cache (per subscription)

    func cacheUnwrappedKey(_ keyBase64: String, forCardId cardId: String) {
        write(keyBase64, to: "unwrapped_key_\(cardId).json")
    }

    func loadCachedUnwrappedKey(forCardId cardId: String) -> String? {
        read(String.self, from: "unwrapped_key_\(cardId).json")
    }

    func removeCachedUnwrappedKey(forCardId cardId: String) {
        remove("unwrapped_key_\(cardId).json")
    }

    // MARK: - Clear All

    func clearAll() {
        try? fileManager.removeItem(at: cacheDir)
    }

    // MARK: - File Operations

    private func write<T: Encodable>(_ value: T, to filename: String) {
        let url = cacheDir.appendingPathComponent(filename)
        try? encoder.encode(value).write(to: url)
    }

    private func read<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let url = cacheDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func remove(_ filename: String) {
        let url = cacheDir.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }
}
