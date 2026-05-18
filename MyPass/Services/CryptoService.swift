import Foundation
import CryptoKit
import CommonCrypto
import Security

/// Handles all on-device cryptographic operations:
/// - P-256 device keypair (for ECDH key agreement)
/// - AES-256-GCM encryption/decryption of card data
/// - ECDH key wrapping for sharing cards with other devices
final class CryptoService {
    static let shared = CryptoService()

    private let keychain = KeychainService.shared

    /// Legacy tag used before iCloud Keychain migration (kSecClassKey).
    private let legacyKeychainTag = "dev.jusso.mypass.deviceKey"

    private init() {}

    // MARK: - Device Key Pair (P-256)

    /// Returns the device's P-256 private key, creating one if it doesn't exist.
    /// The key is stored via KeychainService so it syncs across devices via iCloud Keychain.
    func getOrCreateDevicePrivateKey() throws -> P256.KeyAgreement.PrivateKey {
        // 1. Try loading from syncable KeychainService
        if let base64 = keychain.devicePrivateKey,
           let data = Data(base64Encoded: base64),
           let key = try? P256.KeyAgreement.PrivateKey(x963Representation: data) {
            return key
        }

        // 2. Try migrating from legacy kSecClassKey storage
        if let legacyKey = loadLegacyDevicePrivateKey() {
            let base64 = legacyKey.x963Representation.base64EncodedString()
            keychain.devicePrivateKey = base64
            deleteLegacyDevicePrivateKey()
            return legacyKey
        }

        // 3. Generate a new key
        let newKey = P256.KeyAgreement.PrivateKey()
        keychain.devicePrivateKey = newKey.x963Representation.base64EncodedString()
        return newKey
    }

    /// Returns the device's public key as a base64-encoded string (X9.63 representation).
    func devicePublicKeyBase64() throws -> String {
        let privateKey = try getOrCreateDevicePrivateKey()
        return privateKey.publicKey.x963Representation.base64EncodedString()
    }

    // MARK: - Legacy Device Key Migration

    private func loadLegacyDevicePrivateKey() -> P256.KeyAgreement.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: legacyKeychainTag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }

        return try? P256.KeyAgreement.PrivateKey(x963Representation: data)
    }

    private func deleteLegacyDevicePrivateKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: legacyKeychainTag.data(using: .utf8)!,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - AES-256-GCM Encryption

    /// Generates a new random AES-256 key and returns it as base64.
    func generateAESKey() -> String {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    /// Encrypts CardData using AES-256-GCM with the given key.
    /// Returns (encryptedBlob, iv, authTag) all as base64 strings.
    func encrypt(cardData: CardData, withKeyBase64 keyBase64: String) throws -> (blob: String, iv: String, authTag: String) {
        guard let keyData = Data(base64Encoded: keyBase64) else {
            throw CryptoError.invalidKey
        }
        let key = SymmetricKey(data: keyData)

        let plaintext = try JSONEncoder().encode(cardData)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)

        let ciphertext = sealedBox.ciphertext.base64EncodedString()
        let nonce = Data(sealedBox.nonce).base64EncodedString()
        let tag = sealedBox.tag.base64EncodedString()

        return (blob: ciphertext, iv: nonce, authTag: tag)
    }

    /// Decrypts an AES-256-GCM encrypted card blob back into CardData.
    func decrypt(blob: String, iv: String, authTag: String, withKeyBase64 keyBase64: String) throws -> CardData {
        guard let keyData = Data(base64Encoded: keyBase64),
              let ciphertext = Data(base64Encoded: blob),
              let nonceData = Data(base64Encoded: iv),
              let tagData = Data(base64Encoded: authTag) else {
            throw CryptoError.invalidData
        }

        let key = SymmetricKey(data: keyData)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tagData)
        let plaintext = try AES.GCM.open(sealedBox, using: key)

        return try JSONDecoder().decode(CardData.self, from: plaintext)
    }

    // MARK: - ECDH Key Wrapping (for sharing)

    /// Wraps an AES card key for a recipient device using ECDH.
    /// Returns (wrappedKey, ephemeralPublicKey) as base64 strings.
    func wrapKeyForRecipient(cardKeyBase64: String, recipientPublicKeyBase64: String) throws -> (wrappedKey: String, ephemeralPublicKey: String) {
        guard let recipientKeyData = Data(base64Encoded: recipientPublicKeyBase64) else {
            throw CryptoError.invalidKey
        }

        let recipientPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: recipientKeyData)

        // Generate ephemeral key pair for this sharing operation
        let ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        let ephemeralPublicKey = ephemeralPrivateKey.publicKey

        // Derive shared secret via ECDH
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)

        // Derive wrapping key from shared secret
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "MyPass-KeyWrap".data(using: .utf8)!,
            outputByteCount: 32
        )

        // Encrypt the card AES key with the derived wrapping key
        guard let cardKeyData = Data(base64Encoded: cardKeyBase64) else {
            throw CryptoError.invalidKey
        }

        let sealedBox = try AES.GCM.seal(cardKeyData, using: wrappingKey)
        let wrappedKeyData = sealedBox.combined!

        return (
            wrappedKey: wrappedKeyData.base64EncodedString(),
            ephemeralPublicKey: ephemeralPublicKey.x963Representation.base64EncodedString()
        )
    }

    /// Unwraps a received AES card key using ECDH with this device's private key.
    func unwrapKey(wrappedKeyBase64: String, ephemeralPublicKeyBase64: String) throws -> String {
        guard let wrappedData = Data(base64Encoded: wrappedKeyBase64),
              let ephemeralPubData = Data(base64Encoded: ephemeralPublicKeyBase64) else {
            throw CryptoError.invalidData
        }

        let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: ephemeralPubData)
        let devicePrivateKey = try getOrCreateDevicePrivateKey()

        // Derive same shared secret
        let sharedSecret = try devicePrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)

        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "MyPass-KeyWrap".data(using: .utf8)!,
            outputByteCount: 32
        )

        // Decrypt the wrapped key
        let sealedBox = try AES.GCM.SealedBox(combined: wrappedData)
        let cardKeyData = try AES.GCM.open(sealedBox, using: wrappingKey)

        return cardKeyData.base64EncodedString()
    }

    // MARK: - Backup Encryption

    /// Encrypts a backup payload using ECDH with the device's own public key.
    /// Returns (ephemeralPublicKey, sealedPayload) as base64 strings.
    func encryptBackupPayload(_ data: Data) throws -> (ephemeralPublicKey: String, sealedPayload: String) {
        let devicePrivateKey = try getOrCreateDevicePrivateKey()
        let ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()

        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: devicePrivateKey.publicKey)

        let key = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "MyPass-Backup".data(using: .utf8)!,
            outputByteCount: 32
        )

        let sealedBox = try AES.GCM.seal(data, using: key)

        return (
            ephemeralPublicKey: ephemeralPrivateKey.publicKey.x963Representation.base64EncodedString(),
            sealedPayload: sealedBox.combined!.base64EncodedString()
        )
    }

    /// Decrypts a backup payload using ECDH with the device's private key.
    func decryptBackupPayload(ephemeralPublicKeyBase64: String, sealedPayloadBase64: String) throws -> Data {
        guard let ephPubData = Data(base64Encoded: ephemeralPublicKeyBase64),
              let sealedData = Data(base64Encoded: sealedPayloadBase64) else {
            throw CryptoError.invalidData
        }

        let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: ephPubData)
        let devicePrivateKey = try getOrCreateDevicePrivateKey()

        let sharedSecret = try devicePrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)

        let key = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "MyPass-Backup".data(using: .utf8)!,
            outputByteCount: 32
        )

        let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Password-Based Backup Encryption (PBKDF2 + AES-256-GCM)

    /// Derives an AES-256 key from a password and salt using PBKDF2-SHA256.
    private func deriveKeyFromPassword(_ password: String, salt: Data, iterations: Int = 600_000) -> SymmetricKey {
        var derivedKey = [UInt8](repeating: 0, count: 32)
        password.withCString { passwordPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordPtr,
                    strlen(passwordPtr),
                    saltPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &derivedKey,
                    32
                )
            }
        }
        return SymmetricKey(data: Data(derivedKey))
    }

    /// Encrypts data with a password. Returns (salt, sealedPayload) as base64.
    func encryptWithPassword(_ data: Data, password: String) throws -> (salt: String, sealedPayload: String) {
        var saltBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &saltBytes)
        let salt = Data(saltBytes)

        let key = deriveKeyFromPassword(password, salt: salt)
        let sealedBox = try AES.GCM.seal(data, using: key)

        return (
            salt: salt.base64EncodedString(),
            sealedPayload: sealedBox.combined!.base64EncodedString()
        )
    }

    /// Decrypts data encrypted with a password.
    func decryptWithPassword(saltBase64: String, sealedPayloadBase64: String, password: String) throws -> Data {
        guard let salt = Data(base64Encoded: saltBase64),
              let sealedData = Data(base64Encoded: sealedPayloadBase64) else {
            throw CryptoError.invalidData
        }

        let key = deriveKeyFromPassword(password, salt: salt)
        let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Owner Secret Generation

    /// Generates a random 32-byte owner secret as base64.
    func generateOwnerSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
}

// MARK: - Errors

enum CryptoError: LocalizedError {
    case invalidKey
    case invalidData
    case keychainSaveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "Invalid cryptographic key"
        case .invalidData: return "Invalid encrypted data"
        case .keychainSaveFailed(let status): return "Failed to save key to Keychain (status: \(status))"
        }
    }
}
