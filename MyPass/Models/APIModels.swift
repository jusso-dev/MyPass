import Foundation

// MARK: - Device

struct RegisterDeviceRequest: Codable {
    let publicKey: String
    let pushToken: String?
    let platform: String?

    enum CodingKeys: String, CodingKey {
        case publicKey = "public_key"
        case pushToken = "push_token"
        case platform
    }
}

struct RegisterDeviceResponse: Codable {
    let deviceId: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
    }
}

struct UpdatePushTokenRequest: Codable {
    let pushToken: String
    let platform: String

    enum CodingKeys: String, CodingKey {
        case pushToken = "push_token"
        case platform
    }
}

struct PublicKeyResponse: Codable {
    let publicKey: String

    enum CodingKeys: String, CodingKey {
        case publicKey = "public_key"
    }
}

// MARK: - Card

struct CreateCardRequest: Codable {
    let ownerDeviceId: String
    let ownerSecret: String
    let encryptedBlob: String
    let blobIv: String
    let blobAuthTag: String
    let schemaVersion: Int?
    let childAlias: String?

    enum CodingKeys: String, CodingKey {
        case ownerDeviceId = "owner_device_id"
        case ownerSecret = "owner_secret"
        case encryptedBlob = "encrypted_blob"
        case blobIv = "blob_iv"
        case blobAuthTag = "blob_auth_tag"
        case schemaVersion = "schema_version"
        case childAlias = "child_alias"
    }
}

struct CreateCardResponse: Codable {
    let cardId: String
    let version: Int

    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case version
    }
}

struct FetchCardResponse: Codable {
    let cardId: String
    let encryptedBlob: String
    let blobIv: String
    let blobAuthTag: String
    let version: Int
    let schemaVersion: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case encryptedBlob = "encrypted_blob"
        case blobIv = "blob_iv"
        case blobAuthTag = "blob_auth_tag"
        case version
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
    }
}

struct UpdateCardRequest: Codable {
    let encryptedBlob: String
    let blobIv: String
    let blobAuthTag: String
    let schemaVersion: Int?
    let childAlias: String?

    enum CodingKeys: String, CodingKey {
        case encryptedBlob = "encrypted_blob"
        case blobIv = "blob_iv"
        case blobAuthTag = "blob_auth_tag"
        case schemaVersion = "schema_version"
        case childAlias = "child_alias"
    }
}

struct UpdateCardResponse: Codable {
    let cardId: String
    let version: Int
    let subscribersNotified: Int

    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case version
        case subscribersNotified = "subscribers_notified"
    }
}

struct CardSummary: Codable, Identifiable, Hashable {
    let cardId: String
    let childAlias: String?
    let version: Int
    let schemaVersion: Int
    let subscriberCount: Int
    let createdAt: String
    let updatedAt: String

    var id: String { cardId }

    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case childAlias = "child_alias"
        case version
        case schemaVersion = "schema_version"
        case subscriberCount = "subscriber_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CardListResponse: Codable {
    let cards: [CardSummary]
}

// MARK: - Key Rotation

struct SubscriberKeyUpdate: Codable {
    let deviceId: String
    let wrappedKey: String
    let ephemeralPublicKey: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case wrappedKey = "wrapped_key"
        case ephemeralPublicKey = "ephemeral_public_key"
    }
}

struct RotateKeyRequest: Codable {
    let encryptedBlob: String
    let blobIv: String
    let blobAuthTag: String
    let subscriberKeys: [SubscriberKeyUpdate]

    enum CodingKeys: String, CodingKey {
        case encryptedBlob = "encrypted_blob"
        case blobIv = "blob_iv"
        case blobAuthTag = "blob_auth_tag"
        case subscriberKeys = "subscriber_keys"
    }
}

struct RotateKeyResponse: Codable {
    let cardId: String
    let version: Int
    let rotated: Bool

    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case version
        case rotated
    }
}

// MARK: - Subscriptions

struct CreateSubscriptionRequest: Codable {
    let deviceId: String
    let wrappedKey: String
    let ephemeralPublicKey: String
    let role: String?
    let expiresAt: String?
    let wrappedOwnerSecret: String?
    let ownerSecretEphemeralKey: String?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case wrappedKey = "wrapped_key"
        case ephemeralPublicKey = "ephemeral_public_key"
        case role
        case expiresAt = "expires_at"
        case wrappedOwnerSecret = "wrapped_owner_secret"
        case ownerSecretEphemeralKey = "owner_secret_ephemeral_key"
    }
}

struct CreateSubscriptionResponse: Codable {
    let subscriptionId: String
    let cardId: String
    let deviceId: String
    let role: String
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case subscriptionId = "subscription_id"
        case cardId = "card_id"
        case deviceId = "device_id"
        case role
        case expiresAt = "expires_at"
    }
}

struct ReceivedSubscription: Codable, Identifiable {
    let subscriptionId: String
    let cardId: String
    let childAlias: String?
    let role: String
    let expiresAt: String?
    let wrappedKey: String
    let ephemeralPublicKey: String
    let wrappedOwnerSecret: String?
    let ownerSecretEphemeralKey: String?
    let cardVersion: Int
    let lastFetchedVersion: Int?
    let isStale: Bool

    var id: String { subscriptionId }

    enum CodingKeys: String, CodingKey {
        case subscriptionId = "subscription_id"
        case cardId = "card_id"
        case childAlias = "child_alias"
        case role
        case expiresAt = "expires_at"
        case wrappedKey = "wrapped_key"
        case ephemeralPublicKey = "ephemeral_public_key"
        case wrappedOwnerSecret = "wrapped_owner_secret"
        case ownerSecretEphemeralKey = "owner_secret_ephemeral_key"
        case cardVersion = "card_version"
        case lastFetchedVersion = "last_fetched_version"
        case isStale = "is_stale"
    }
}

struct ReceivedSubscriptionsResponse: Codable {
    let subscriptions: [ReceivedSubscription]
}

struct CardSubscriber: Codable, Identifiable {
    let subscriptionId: String
    let deviceId: String
    let role: String
    let expiresAt: String?
    let lastFetchedAt: String?
    let lastFetchedVersion: Int?
    let createdAt: String

    var id: String { subscriptionId }

    enum CodingKeys: String, CodingKey {
        case subscriptionId = "subscription_id"
        case deviceId = "device_id"
        case role
        case expiresAt = "expires_at"
        case lastFetchedAt = "last_fetched_at"
        case lastFetchedVersion = "last_fetched_version"
        case createdAt = "created_at"
    }
}

struct CardSubscribersResponse: Codable {
    let subscriptions: [CardSubscriber]
}

// MARK: - Share Links

struct CreateShareLinkRequest: Codable {
    let role: String?
    let maxUses: Int?
    let expiresInMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case role
        case maxUses = "max_uses"
        case expiresInMinutes = "expires_in_minutes"
    }
}

struct CreateShareLinkResponse: Codable, Identifiable {
    var id: String { token }
    let token: String
    let expiresAt: String
    let maxUses: Int

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case maxUses = "max_uses"
    }
}

struct RedeemShareLinkResponse: Codable {
    let cardId: String
    let encryptedBlob: String
    let blobIv: String
    let blobAuthTag: String
    let version: Int
    let schemaVersion: Int
    let childAlias: String?
    let role: String

    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case encryptedBlob = "encrypted_blob"
        case blobIv = "blob_iv"
        case blobAuthTag = "blob_auth_tag"
        case version
        case schemaVersion = "schema_version"
        case childAlias = "child_alias"
        case role
    }
}

// MARK: - Share Link Info (list endpoint)

struct ShareLinkInfo: Codable, Identifiable {
    let token: String
    let role: String
    let maxUses: Int
    let usedCount: Int
    let expiresAt: String
    let createdAt: String

    var id: String { token }

    enum CodingKeys: String, CodingKey {
        case token, role
        case maxUses = "max_uses"
        case usedCount = "used_count"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

struct ShareLinksResponse: Codable {
    let links: [ShareLinkInfo]
}

// MARK: - Owner Secret Rotation

struct RotateOwnerSecretRequest: Codable {
    let newOwnerSecret: String

    enum CodingKeys: String, CodingKey {
        case newOwnerSecret = "new_owner_secret"
    }
}

// MARK: - Generic

struct OkResponse: Codable {
    let ok: Bool
}

struct ErrorResponse: Codable {
    let error: String
}

struct HealthResponse: Codable {
    let status: String
    let timestamp: String
}
