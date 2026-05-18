import Foundation
import CryptoKit

// MARK: - Backup Models

struct BackupEnvelope: Codable {
    let version: Int
    // v1 (device-key based) — kept for backward-compatible restore
    let ephemeralPublicKey: String?
    // v2 (password-based) — used for all new backups
    let salt: String?
    // shared
    let encryptedPayload: String
}

struct BackupPayload: Codable {
    let version: Int
    let createdAt: Date
    let deviceId: String
    let cards: [BackupCard]
}

struct BackupCard: Codable {
    let cardId: String
    let ownerSecret: String
    let cardKeyBase64: String
    let cardData: CardData
    let childAlias: String?
    let version: Int
    let schemaVersion: Int
    let subscriberCount: Int
    let createdAt: String
    let updatedAt: String
}

// MARK: - Service

final class BackupService {
    static let shared = BackupService()

    private let crypto = CryptoService.shared
    private let keychain = KeychainService.shared
    private let cache = CacheService.shared
    private let fileManager = FileManager.default

    static let maxBackups = 7

    private let bookmarkKey = "backupFolderBookmark"
    private let lastBackupKey = "lastBackupTimestamp"
    private let queue = DispatchQueue(label: "dev.jusso.mypass.backup", qos: .utility)
    private var lastBackupTime: Date = .distantPast
    private let cooldownInterval: TimeInterval = 5

    private init() {}

    // MARK: - Folder Management

    var hasBackupFolder: Bool { resolveBackupFolder() != nil }

    var backupFolderName: String? { resolveBackupFolder()?.lastPathComponent }

    var lastBackupDate: Date? {
        let ts = UserDefaults.standard.double(forKey: lastBackupKey)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    /// Last backup error message, or nil if the last backup succeeded.
    var lastBackupError: String? {
        UserDefaults.standard.string(forKey: "lastBackupError")
    }

    func setBackupFolder(url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw BackupError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let bookmark = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    func clearBackupFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: lastBackupKey)
    }

    func resolveBackupFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale) else { return nil }
        if isStale { try? setBackupFolder(url: url) }
        return url
    }

    // MARK: - Schedule Backup (debounced, background)

    /// Triggers a backup on a background queue with a 5-second cooldown to avoid rapid successive writes.
    func scheduleBackup() {
        queue.async { [self] in
            guard Date().timeIntervalSince(lastBackupTime) >= cooldownInterval else { return }
            performBackupSync()
        }
    }

    /// Runs a backup immediately on a background queue, ignoring cooldown.
    func performBackupNow() {
        queue.async { [self] in
            performBackupSync()
        }
    }

    // MARK: - Backup Logic

    private func performBackupSync() {
        guard let folderURL = resolveBackupFolder() else {
            recordBackupError("Backup folder is no longer accessible. Please re-select it in Settings.")
            return
        }
        guard let password = keychain.backupPassword, !password.isEmpty else {
            recordBackupError("No backup password set. Please set one in Settings.")
            return
        }
        guard folderURL.startAccessingSecurityScopedResource() else {
            recordBackupError("Cannot access backup folder. Please re-select it in Settings.")
            return
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        do {
            guard let cardList = cache.loadCachedCardList(), !cardList.isEmpty else { return }

            var backupCards: [BackupCard] = []
            for summary in cardList {
                guard let ownerSecret = keychain.ownerSecret(forCardId: summary.cardId),
                      let cardKey = keychain.cardKey(forCardId: summary.cardId),
                      let cardData = cache.loadCachedCardData(forCardId: summary.cardId) else {
                    continue
                }
                backupCards.append(BackupCard(
                    cardId: summary.cardId,
                    ownerSecret: ownerSecret,
                    cardKeyBase64: cardKey,
                    cardData: cardData,
                    childAlias: summary.childAlias,
                    version: summary.version,
                    schemaVersion: summary.schemaVersion,
                    subscriberCount: summary.subscriberCount,
                    createdAt: summary.createdAt,
                    updatedAt: summary.updatedAt
                ))
            }

            guard !backupCards.isEmpty else { return }

            let payload = BackupPayload(
                version: 1,
                createdAt: Date(),
                deviceId: keychain.deviceId ?? "unknown",
                cards: backupCards
            )

            let jsonData = try JSONEncoder().encode(payload)
            let encrypted = try crypto.encryptWithPassword(jsonData, password: password)

            let envelope = BackupEnvelope(
                version: 2,
                ephemeralPublicKey: nil,
                salt: encrypted.salt,
                encryptedPayload: encrypted.sealedPayload
            )

            let envelopeData = try JSONEncoder().encode(envelope)

            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let fileURL = folderURL.appendingPathComponent("MyPass-Backup-\(timestamp).mypassbackup")

            try envelopeData.write(to: fileURL)

            lastBackupTime = Date()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastBackupKey)
            UserDefaults.standard.removeObject(forKey: "lastBackupError")

            pruneOldBackups(in: folderURL)
        } catch {
            recordBackupError("Backup failed: \(error.localizedDescription)")
        }
    }

    private func recordBackupError(_ message: String) {
        UserDefaults.standard.set(message, forKey: "lastBackupError")
    }

    // MARK: - Restore

    /// Checks the version of a backup file. Returns 1 (device-key) or 2 (password-based).
    func backupVersion(fileURL: URL) throws -> Int {
        guard fileURL.startAccessingSecurityScopedResource() else {
            throw BackupError.accessDenied
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: fileURL)
        let envelope = try JSONDecoder().decode(BackupEnvelope.self, from: data)
        return envelope.version
    }

    /// Decrypts a backup file and restores card keys to Keychain and data to cache.
    /// For v2 backups, a password is required. For v1, the device key is used (may fail across devices).
    /// Returns the number of cards restored.
    func restoreFromBackup(fileURL: URL, password: String? = nil) throws -> Int {
        guard fileURL.startAccessingSecurityScopedResource() else {
            throw BackupError.accessDenied
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: fileURL)
        let envelope = try JSONDecoder().decode(BackupEnvelope.self, from: data)

        let plaintext: Data
        do {
            if envelope.version >= 2, let salt = envelope.salt {
                // v2: password-based
                guard let password, !password.isEmpty else {
                    throw BackupError.passwordRequired
                }
                plaintext = try crypto.decryptWithPassword(
                    saltBase64: salt,
                    sealedPayloadBase64: envelope.encryptedPayload,
                    password: password
                )
            } else if let ephemeralKey = envelope.ephemeralPublicKey {
                // v1: device-key based (backward compat)
                plaintext = try crypto.decryptBackupPayload(
                    ephemeralPublicKeyBase64: ephemeralKey,
                    sealedPayloadBase64: envelope.encryptedPayload
                )
            } else {
                throw BackupError.corruptedFile
            }
        } catch is CryptoKitError {
            if envelope.version >= 2 {
                throw BackupError.wrongPassword
            } else {
                throw BackupError.wrongDeviceKey
            }
        }

        let payload = try JSONDecoder().decode(BackupPayload.self, from: plaintext)

        var restoredCount = 0

        // Start with existing cached card list to merge into
        var cardMap: [String: CardSummary] = [:]
        if let existing = cache.loadCachedCardList() {
            for card in existing {
                cardMap[card.cardId] = card
            }
        }

        for card in payload.cards {
            // Skip cards that already have live keys — don't overwrite with stale backup data
            let hasExistingKeys = keychain.ownerSecret(forCardId: card.cardId) != nil
                && keychain.cardKey(forCardId: card.cardId) != nil

            if !hasExistingKeys {
                keychain.saveOwnerSecret(card.ownerSecret, forCardId: card.cardId)
                keychain.saveCardKey(card.cardKeyBase64, forCardId: card.cardId)
                cache.cacheCardData(card.cardData, forCardId: card.cardId)
                restoredCount += 1
            }

            // Always update the card list entry (may have newer metadata)
            cardMap[card.cardId] = CardSummary(
                cardId: card.cardId,
                childAlias: card.childAlias,
                version: card.version,
                schemaVersion: card.schemaVersion,
                subscriberCount: card.subscriberCount,
                createdAt: card.createdAt,
                updatedAt: card.updatedAt
            )
        }

        cache.cacheCardList(Array(cardMap.values))

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .myPassShouldRefresh, object: nil)
        }

        return restoredCount
    }

    // MARK: - Prune Old Backups

    private func pruneOldBackups(in folderURL: URL) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let backups = files
            .filter { $0.pathExtension == "mypassbackup" }
            .sorted { url1, url2 in
                let d1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let d2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return d1 > d2 // newest first
            }

        for file in backups.dropFirst(Self.maxBackups) {
            try? fileManager.removeItem(at: file)
        }
    }
}

// MARK: - Errors

enum BackupError: LocalizedError {
    case accessDenied
    case corruptedFile
    case wrongDeviceKey
    case passwordRequired
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Cannot access the backup location. Please re-select the folder."
        case .corruptedFile:
            return "The backup file is corrupted or unreadable."
        case .wrongDeviceKey:
            return "This is an older backup format that requires the same device key. It can't be restored on this device."
        case .passwordRequired:
            return "This backup requires a password to restore."
        case .wrongPassword:
            return "Incorrect password. Please check your backup password and try again."
        }
    }
}
