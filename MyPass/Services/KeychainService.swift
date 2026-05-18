import Foundation
import Security

/// Manages persistent storage of secrets in the iOS Keychain.
/// All items are stored with iCloud Keychain sync enabled so they
/// survive device loss and are available across the user's devices.
final class KeychainService {
    static let shared = KeychainService()

    private let servicePrefix = "dev.jusso.mypass"

    private init() {}

    // MARK: - Device Identity

    var deviceId: String? {
        get { read(key: "device_id") }
        set {
            if let newValue {
                save(key: "device_id", value: newValue)
            } else {
                delete(key: "device_id")
            }
        }
    }

    // MARK: - Device Private Key (P-256, base64 X9.63)

    var devicePrivateKey: String? {
        get { read(key: "device_private_key") }
        set {
            if let newValue {
                save(key: "device_private_key", value: newValue)
            } else {
                delete(key: "device_private_key")
            }
        }
    }

    // MARK: - Owner Secrets (per card)

    func ownerSecret(forCardId cardId: String) -> String? {
        read(key: "owner_secret_\(cardId)")
    }

    func saveOwnerSecret(_ secret: String, forCardId cardId: String) {
        save(key: "owner_secret_\(cardId)", value: secret)
    }

    func deleteOwnerSecret(forCardId cardId: String) {
        delete(key: "owner_secret_\(cardId)")
    }

    // MARK: - AES Card Keys (per owned card, base64-encoded)

    func cardKey(forCardId cardId: String) -> String? {
        read(key: "card_key_\(cardId)")
    }

    func saveCardKey(_ keyBase64: String, forCardId cardId: String) {
        save(key: "card_key_\(cardId)", value: keyBase64)
    }

    func deleteCardKey(forCardId cardId: String) {
        delete(key: "card_key_\(cardId)")
    }

    // MARK: - Unwrapped Key Cache (for shared cards)

    func unwrappedKey(forCardId cardId: String) -> String? {
        read(key: "unwrapped_key_\(cardId)")
    }

    func saveUnwrappedKey(_ keyBase64: String, forCardId cardId: String) {
        save(key: "unwrapped_key_\(cardId)", value: keyBase64)
    }

    func deleteUnwrappedKey(forCardId cardId: String) {
        delete(key: "unwrapped_key_\(cardId)")
    }

    // MARK: - Recovery Key (AES-256, base64)

    var recoveryKey: String? {
        get { read(key: "recovery_key") }
        set {
            if let newValue {
                save(key: "recovery_key", value: newValue)
            } else {
                delete(key: "recovery_key")
            }
        }
    }

    // MARK: - Backup Password

    var backupPassword: String? {
        get { read(key: "backup_password") }
        set {
            if let newValue {
                save(key: "backup_password", value: newValue)
            } else {
                delete(key: "backup_password")
            }
        }
    }

    // MARK: - Push Token

    var pushToken: String? {
        get { read(key: "push_token") }
        set {
            if let newValue {
                save(key: "push_token", value: newValue)
            } else {
                delete(key: "push_token")
            }
        }
    }

    // MARK: - Server URL

    var serverURL: String? {
        get { read(key: "server_url") }
        set {
            if let newValue {
                save(key: "server_url", value: newValue)
            } else {
                delete(key: "server_url")
            }
        }
    }

    // MARK: - Generic Keychain Operations (iCloud-syncable)

    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first (both syncable and legacy)
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicePrefix,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: true,
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private func read(key: String) -> String? {
        // Try syncable item first
        let syncQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicePrefix,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        var status = SecItemCopyMatching(syncQuery as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }

        // Fall back to legacy device-only item and migrate it
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicePrefix,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        result = nil
        status = SecItemCopyMatching(legacyQuery as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Migrate: save to syncable, delete legacy
        save(key: key, value: value)
        deleteLegacy(key: key)
        return value
    }

    private func delete(key: String) {
        // Delete syncable item
        let syncQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicePrefix,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: true,
        ]
        SecItemDelete(syncQuery as CFDictionary)

        // Also delete any legacy device-only item
        deleteLegacy(key: key)
    }

    private func deleteLegacy(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicePrefix,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
