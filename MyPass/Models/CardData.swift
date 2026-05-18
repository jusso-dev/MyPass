import Foundation

/// The plaintext card data that gets encrypted/decrypted on-device.
/// This is the autism awareness card content that the server never sees.
struct CardData: Equatable {
    // MARK: - Personal Info
    var childName: String = ""
    var dateOfBirth: String = ""
    var photoData: Data? = nil

    // MARK: - Diagnosis & Communication
    var diagnosis: String = ""
    var communicationMethod: String = ""
    var communicationNotes: String = ""

    // MARK: - Sensory Profile
    var sensorySeeks: String = ""
    var sensoryAvoids: String = ""
    var stimmingBehaviours: String = ""

    // MARK: - Behaviour & Regulation
    var signsOfOverwhelm: String = ""
    var meltdownSupport: String = ""
    var shutdownSupport: String = ""
    var calmingStrategies: String = ""
    var elopementRisk: String = ""

    // MARK: - Routines & Interests
    var routineNeeds: String = ""
    var specialInterests: String = ""
    var safeFoods: String = ""

    // MARK: - Medical
    var medications: String = ""
    var allergies: String = ""
    var otherMedical: String = ""

    // MARK: - Emergency Contact
    var emergencyContactName: String = ""
    var emergencyContactPhone: String = ""
    var emergencyContactRelationship: String = ""

    // MARK: - Additional
    var additionalNotes: String = ""

    static let schemaVersion = 2
}

// MARK: - Codable (tolerant of missing keys for schema migration)

extension CardData: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        childName = try c.decodeIfPresent(String.self, forKey: .childName) ?? ""
        dateOfBirth = try c.decodeIfPresent(String.self, forKey: .dateOfBirth) ?? ""
        photoData = try c.decodeIfPresent(Data.self, forKey: .photoData)

        diagnosis = try c.decodeIfPresent(String.self, forKey: .diagnosis) ?? ""
        communicationMethod = try c.decodeIfPresent(String.self, forKey: .communicationMethod) ?? ""
        communicationNotes = try c.decodeIfPresent(String.self, forKey: .communicationNotes) ?? ""

        sensorySeeks = try c.decodeIfPresent(String.self, forKey: .sensorySeeks) ?? ""
        sensoryAvoids = try c.decodeIfPresent(String.self, forKey: .sensoryAvoids) ?? ""
        stimmingBehaviours = try c.decodeIfPresent(String.self, forKey: .stimmingBehaviours) ?? ""

        signsOfOverwhelm = try c.decodeIfPresent(String.self, forKey: .signsOfOverwhelm) ?? ""
        meltdownSupport = try c.decodeIfPresent(String.self, forKey: .meltdownSupport) ?? ""
        shutdownSupport = try c.decodeIfPresent(String.self, forKey: .shutdownSupport) ?? ""
        calmingStrategies = try c.decodeIfPresent(String.self, forKey: .calmingStrategies) ?? ""
        elopementRisk = try c.decodeIfPresent(String.self, forKey: .elopementRisk) ?? ""

        routineNeeds = try c.decodeIfPresent(String.self, forKey: .routineNeeds) ?? ""
        specialInterests = try c.decodeIfPresent(String.self, forKey: .specialInterests) ?? ""
        safeFoods = try c.decodeIfPresent(String.self, forKey: .safeFoods) ?? ""

        medications = try c.decodeIfPresent(String.self, forKey: .medications) ?? ""
        allergies = try c.decodeIfPresent(String.self, forKey: .allergies) ?? ""
        otherMedical = try c.decodeIfPresent(String.self, forKey: .otherMedical) ?? ""

        emergencyContactName = try c.decodeIfPresent(String.self, forKey: .emergencyContactName) ?? ""
        emergencyContactPhone = try c.decodeIfPresent(String.self, forKey: .emergencyContactPhone) ?? ""
        emergencyContactRelationship = try c.decodeIfPresent(String.self, forKey: .emergencyContactRelationship) ?? ""

        additionalNotes = try c.decodeIfPresent(String.self, forKey: .additionalNotes) ?? ""
    }
}

/// Local representation of an owned card with its decrypted data and owner secret.
struct OwnedCard: Identifiable {
    let cardId: String
    let ownerSecret: String
    var cardData: CardData
    var version: Int
    var subscriberCount: Int
    var childAlias: String?
    var createdAt: String
    var updatedAt: String

    var id: String { cardId }

    var displayName: String {
        childAlias ?? (cardData.childName.isEmpty ? "Unnamed Card" : cardData.childName)
    }
}

/// Local representation of a card shared with this device.
struct SharedCard: Identifiable {
    let subscriptionId: String
    let cardId: String
    let role: String
    let wrappedKey: String
    let ephemeralPublicKey: String
    var cardData: CardData?
    var childAlias: String?
    var cardVersion: Int
    var isStale: Bool

    var id: String { subscriptionId }

    var displayName: String {
        childAlias ?? cardData?.childName ?? "Shared Card"
    }
}
