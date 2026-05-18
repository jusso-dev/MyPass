import SwiftUI
import Combine
import CryptoKit

struct SharedCardDetailView: View {
    let subscription: ReceivedSubscription

    @State private var cardData: CardData?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingEditor = false
    @State private var now = Date()

    private var isEditor: Bool { subscription.role == "editor" }

    private let expiryTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.mp.skyFaint.ignoresSafeArea()

            if isLoading {
                ProgressView("Decrypting shared card...")
                    .tint(Color.mp.ocean)
            } else if let cardData {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            RoleBadge(role: subscription.role)
                            if let remaining = expiryText {
                                Label(remaining, systemImage: "clock")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(expiryUrgent ? .red : .orange)
                            }
                        }
                        CardContentView(cardData: cardData)
                    }
                    .padding()
                }
            } else if let error {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            }
        }
        .navigationTitle(subscription.childAlias ?? "Shared Card")
        .toolbar {
            if isEditor {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "pencil.circle")
                    }
                    .accessibilityLabel("Edit card")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            Task { await loadAndDecrypt() }
        } content: {
            CardEditorView(editingCardId: subscription.cardId, editingChildAlias: subscription.childAlias)
        }
        .task {
            await loadAndDecrypt()
        }
        .onReceive(NotificationCenter.default.publisher(for: PushNotificationService.cardUpdatedNotification)) { notification in
            // Refresh if this card was updated
            if let cardId = notification.userInfo?["card_id"] as? String,
               cardId == subscription.cardId {
                APIClient.shared.clearThrottles()
                Task { await loadAndDecrypt() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: PushNotificationService.cardDeletedNotification)) { notification in
            if let cardId = notification.userInfo?["card_id"] as? String,
               cardId == subscription.cardId {
                dismiss()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: PushNotificationService.shareExpiredNotification)) { notification in
            if let cardId = notification.userInfo?["card_id"] as? String,
               cardId == subscription.cardId {
                dismiss()
            }
        }
        .onReceive(expiryTimer) { _ in
            now = Date()
            if let expiry = expiryDate, expiry <= now {
                // Clean up local data for expired card
                KeychainService.shared.deleteUnwrappedKey(forCardId: subscription.cardId)
                CacheService.shared.removeCachedCardData(forCardId: subscription.cardId)
                dismiss()
            }
        }
    }

    // MARK: - Expiry Helpers

    private var expiryDate: Date? {
        guard let expiresAt = subscription.expiresAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiresAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expiresAt)
    }

    private var expiryText: String? {
        guard let expiry = expiryDate else { return nil }
        let remaining = expiry.timeIntervalSince(now)
        guard remaining > 0 else { return "Expired" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s remaining"
        }
        return "\(seconds)s remaining"
    }

    private var expiryUrgent: Bool {
        guard let expiry = expiryDate else { return false }
        return expiry.timeIntervalSince(now) < 900
    }

    private func loadAndDecrypt() async {
        isLoading = true
        error = nil

        let keychain = KeychainService.shared
        let crypto = CryptoService.shared
        let cache = CacheService.shared

        guard let deviceId = keychain.deviceId else {
            error = "Device not registered"
            isLoading = false
            return
        }

        do {
            // Try cached unwrapped key first
            var cardKey: String
            if let cached = keychain.unwrappedKey(forCardId: subscription.cardId) {
                cardKey = cached
            } else {
                cardKey = try crypto.unwrapKey(
                    wrappedKeyBase64: subscription.wrappedKey,
                    ephemeralPublicKeyBase64: subscription.ephemeralPublicKey
                )
                keychain.saveUnwrappedKey(cardKey, forCardId: subscription.cardId)
            }

            // For editor role, unwrap and store the owner secret so editing works
            if subscription.role == "editor",
               let wrappedSecret = subscription.wrappedOwnerSecret,
               let secretEphemeralKey = subscription.ownerSecretEphemeralKey,
               keychain.ownerSecret(forCardId: subscription.cardId) == nil {
                let unwrappedSecretBase64 = try crypto.unwrapKey(
                    wrappedKeyBase64: wrappedSecret,
                    ephemeralPublicKeyBase64: secretEphemeralKey
                )
                if let secretData = Data(base64Encoded: unwrappedSecretBase64),
                   let ownerSecret = String(data: secretData, encoding: .utf8) {
                    keychain.saveOwnerSecret(ownerSecret, forCardId: subscription.cardId)
                    keychain.saveCardKey(cardKey, forCardId: subscription.cardId)
                }
            }

            let card = try await APIClient.shared.fetchCardAsSubscriber(
                cardId: subscription.cardId,
                deviceId: deviceId
            )

            let decrypted = try crypto.decrypt(
                blob: card.encryptedBlob,
                iv: card.blobIv,
                authTag: card.blobAuthTag,
                withKeyBase64: cardKey
            )

            cardData = decrypted
            cache.cacheCardData(decrypted, forCardId: subscription.cardId)
        } catch let apiError as APIError where apiError.isNotModified {
            // Card hasn't changed, load from cache for display
            cardData = cache.loadCachedCardData(forCardId: subscription.cardId)
        } catch let apiError as APIError where apiError.isAccessRevoked {
            keychain.deleteUnwrappedKey(forCardId: subscription.cardId)
            self.error = "Your access to this card has been revoked."
        } catch is CryptoKit.CryptoKitError {
            // Cached key is stale from key rotation
            keychain.deleteUnwrappedKey(forCardId: subscription.cardId)
            self.error = "This card was re-encrypted. Your access may have been revoked."
        } catch {
            // Try offline cache
            if let cached = CacheService.shared.loadCachedCardData(forCardId: subscription.cardId) {
                cardData = cached
            } else {
                self.error = error.localizedDescription
            }
        }

        isLoading = false
    }
}
