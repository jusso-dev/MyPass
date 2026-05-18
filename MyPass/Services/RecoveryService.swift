import Foundation
import CryptoKit

/// Manages emergency recovery: generates a recovery AES key, encrypts all card
/// keys and owner secrets into a blob that can be decrypted with the recovery key.
/// The recovery key is displayed as a QR code the user saves offline.
/// A future web app can scan the QR and use it to recover cards from the server.
final class RecoveryService {
    static let shared = RecoveryService()

    private let keychain = KeychainService.shared
    private let cache = CacheService.shared
    private let crypto = CryptoService.shared

    private init() {}

    // MARK: - Recovery Key

    /// Returns the recovery key (base64), creating one if needed.
    /// Returns nil only if keychain write fails.
    func getOrCreateRecoveryKey() -> String? {
        if let existing = keychain.recoveryKey {
            return existing
        }
        let key = crypto.generateAESKey()
        keychain.recoveryKey = key
        return key
    }

    /// Whether a recovery key exists.
    var hasRecoveryKey: Bool {
        keychain.recoveryKey != nil
    }

    /// The full recovery URL for encoding in QR code: mypass://recover/DEVICE_ID#KEY
    var recoveryURL: String? {
        guard let key = keychain.recoveryKey,
              let deviceId = keychain.deviceId else { return nil }
        return "mypass://recover/\(deviceId)#\(key)"
    }

    /// Date of last successful recovery blob update.
    var lastUpdated: Date? {
        let ts = UserDefaults.standard.double(forKey: "recoveryBlobTimestamp")
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    // MARK: - Recovery Blob

    /// Builds and encrypts a recovery blob containing all owned card keys and secrets.
    /// Stores the encrypted blob locally (ready for server upload when endpoint is available).
    func updateRecoveryBlob() {
        guard let recoveryKey = keychain.recoveryKey,
              let recoveryKeyData = Data(base64Encoded: recoveryKey),
              let cardList = cache.loadCachedCardList(), !cardList.isEmpty else {
            return
        }

        var cards: [RecoveryCard] = []
        for summary in cardList {
            guard let ownerSecret = keychain.ownerSecret(forCardId: summary.cardId),
                  let cardKey = keychain.cardKey(forCardId: summary.cardId) else {
                continue
            }
            cards.append(RecoveryCard(
                cardId: summary.cardId,
                ownerSecret: ownerSecret,
                cardKeyBase64: cardKey,
                childAlias: summary.childAlias
            ))
        }

        guard !cards.isEmpty else { return }

        let payload = RecoveryPayload(
            version: 1,
            createdAt: Date(),
            deviceId: keychain.deviceId ?? "unknown",
            cards: cards
        )

        do {
            let jsonData = try JSONEncoder().encode(payload)
            let key = SymmetricKey(data: recoveryKeyData)
            let sealedBox = try AES.GCM.seal(jsonData, using: key)

            guard let combined = sealedBox.combined else { return }

            let envelope = RecoveryEnvelope(
                version: 1,
                encryptedPayload: combined.base64EncodedString()
            )

            let envelopeData = try JSONEncoder().encode(envelope)

            // Store locally in Documents (survives cache clears)
            let url = recoveryBlobURL
            try envelopeData.write(to: url)

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "recoveryBlobTimestamp")
        } catch {
            print("Recovery blob update failed: \(error)")
        }
    }

    /// Decrypts a recovery blob with the given key. Used for testing and future web app parity.
    func decryptRecoveryBlob(encryptedPayload: String, recoveryKeyBase64: String) throws -> RecoveryPayload {
        guard let keyData = Data(base64Encoded: recoveryKeyBase64),
              let sealedData = Data(base64Encoded: encryptedPayload) else {
            throw CryptoError.invalidData
        }

        let key = SymmetricKey(data: keyData)
        let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
        let plaintext = try AES.GCM.open(sealedBox, using: key)

        return try JSONDecoder().decode(RecoveryPayload.self, from: plaintext)
    }

    // MARK: - File Location

    private var recoveryBlobURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("recovery.mypassrecovery")
    }
}

// MARK: - Models

struct RecoveryEnvelope: Codable {
    let version: Int
    let encryptedPayload: String
}

struct RecoveryPayload: Codable {
    let version: Int
    let createdAt: Date
    let deviceId: String
    let cards: [RecoveryCard]
}

struct RecoveryCard: Codable {
    let cardId: String
    let ownerSecret: String
    let cardKeyBase64: String
    let childAlias: String?
}
