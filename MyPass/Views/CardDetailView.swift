import SwiftUI

struct CardDetailView: View {
    let cardSummary: CardSummary

    @State private var cardData: CardData?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingEditor = false
    @State private var showingShareSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var pdfURL: URL?

    private let api = APIClient.shared
    private let crypto = CryptoService.shared
    private let keychain = KeychainService.shared

    var body: some View {
        ZStack {
            Color.mp.skyFaint.ignoresSafeArea()

            if isLoading {
                ProgressView("Decrypting card...")
                    .tint(Color.mp.ocean)
            } else if let cardData {
                CardContentView(cardData: cardData)
            } else if let error {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            }
        }
        .navigationTitle(cardSummary.childAlias ?? "Card Details")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share card")

                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "pencil.circle")
                }
                .accessibilityLabel("Edit card")

                Menu {
                    Button {
                        exportPDF()
                    } label: {
                        Label("Export as PDF", systemImage: "doc.richtext")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Card", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More options")
            }
        }
        .sheet(isPresented: $showingEditor) {
            Task { await loadCard() }
        } content: {
            CardEditorView(editingCardId: cardSummary.cardId, editingChildAlias: cardSummary.childAlias)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let ownerSecret = keychain.ownerSecret(forCardId: cardSummary.cardId) {
                ShareCardView(cardId: cardSummary.cardId, ownerSecret: ownerSecret)
            }
        }
        .task {
            await loadCard()
        }
        .onReceive(NotificationCenter.default.publisher(for: PushNotificationService.cardUpdatedNotification)) { notification in
            if let cardId = notification.userInfo?["card_id"] as? String,
               cardId == cardSummary.cardId {
                APIClient.shared.clearThrottles()
                Task { await loadCard() }
            }
        }
        .confirmationDialog(
            "Delete Card?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteCard() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this card and revoke access for all subscribers.")
        }
    }

    @Environment(\.dismiss) private var dismiss

    private func deleteCard() async {
        guard let ownerSecret = keychain.ownerSecret(forCardId: cardSummary.cardId) else {
            error = "Owner secret not found"
            return
        }

        do {
            try await api.deleteCard(cardId: cardSummary.cardId, ownerSecret: ownerSecret)
            keychain.deleteOwnerSecret(forCardId: cardSummary.cardId)
            keychain.deleteCardKey(forCardId: cardSummary.cardId)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadCard() async {
        // Show cached data instantly while fetching
        if cardData == nil, let cached = CacheService.shared.loadCachedCardData(forCardId: cardSummary.cardId) {
            cardData = cached
            isLoading = false
        } else {
            isLoading = true
        }
        error = nil

        guard let ownerSecret = keychain.ownerSecret(forCardId: cardSummary.cardId),
              let cardKey = keychain.cardKey(forCardId: cardSummary.cardId) else {
            error = "Card credentials not found locally"
            isLoading = false
            return
        }

        do {
            let response = try await api.fetchCard(cardId: cardSummary.cardId, ownerSecret: ownerSecret)
            let decrypted = try crypto.decrypt(
                blob: response.encryptedBlob,
                iv: response.blobIv,
                authTag: response.blobAuthTag,
                withKeyBase64: cardKey
            )
            cardData = decrypted
            CacheService.shared.cacheCardData(decrypted, forCardId: cardSummary.cardId)
        } catch let error as APIError where error.isNotModified {
            // Card hasn't changed, keep showing cached data
        } catch {
            // If we have no cached data, show error
            if cardData == nil {
                self.error = error.localizedDescription
            }
        }

        isLoading = false
    }

    private func exportPDF() {
        guard let cardData else { return }
        let data = PDFExportService.generatePDF(from: cardData)
        let fileName = (cardData.childName.isEmpty ? "MyPass-Card" : "MyPass-\(cardData.childName)")
            .replacingOccurrences(of: " ", with: "-")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).pdf")
        do {
            try data.write(to: tempURL)
        } catch {
            self.error = "Failed to create PDF file."
            return
        }
        pdfURL = tempURL

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.keyWindow?.rootViewController else { return }
        let topVC = rootVC.presentedViewController ?? rootVC
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = topVC.view
        topVC.present(activityVC, animated: true)
    }
}

// MARK: - Card Content (extracted subview for performance)

struct CardContentView: View {
    let cardData: CardData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                CardHeaderView(cardData: cardData)

                // Communication
                if hasContent(cardData.communicationMethod, cardData.communicationNotes) {
                    DetailSection(title: "Communication", icon: "bubble.left.and.bubble.right", color: Color.mp.ocean) {
                        DetailField(label: "Method", value: cardData.communicationMethod)
                        DetailField(label: "Notes", value: cardData.communicationNotes)
                    }
                }

                // Sensory Profile
                if hasContent(cardData.sensorySeeks, cardData.sensoryAvoids, cardData.stimmingBehaviours) {
                    DetailSection(title: "Sensory Profile", icon: "hand.raised.fingers.spread", color: Color.mp.sky) {
                        DetailField(label: "Sensory Seeks", value: cardData.sensorySeeks)
                        DetailField(label: "Sensory Avoids", value: cardData.sensoryAvoids)
                        DetailField(label: "Stimming Behaviours", value: cardData.stimmingBehaviours)
                    }
                }

                // Behaviour & Regulation
                if hasContent(cardData.signsOfOverwhelm, cardData.meltdownSupport, cardData.shutdownSupport, cardData.calmingStrategies, cardData.elopementRisk) {
                    DetailSection(title: "Behaviour & Regulation", icon: "heart.circle", color: .orange) {
                        DetailField(label: "Signs of Overwhelm", value: cardData.signsOfOverwhelm)
                        DetailField(label: "Meltdown Support", value: cardData.meltdownSupport)
                        DetailField(label: "Shutdown Support", value: cardData.shutdownSupport)
                        DetailField(label: "Calming Strategies", value: cardData.calmingStrategies)
                        DetailField(label: "Elopement Risk", value: cardData.elopementRisk)
                    }
                }

                // Routines & Interests
                if hasContent(cardData.routineNeeds, cardData.specialInterests, cardData.safeFoods) {
                    DetailSection(title: "Routines & Interests", icon: "star.circle", color: Color.mp.trusted) {
                        DetailField(label: "Routine Needs", value: cardData.routineNeeds)
                        DetailField(label: "Special Interests", value: cardData.specialInterests)
                        DetailField(label: "Safe Foods", value: cardData.safeFoods)
                    }
                }

                // Medical
                if hasContent(cardData.medications, cardData.allergies, cardData.otherMedical) {
                    DetailSection(title: "Medical", icon: "cross.case", color: .red) {
                        DetailField(label: "Medications", value: cardData.medications)
                        DetailField(label: "Allergies", value: cardData.allergies)
                        DetailField(label: "Other Medical", value: cardData.otherMedical)
                    }
                }

                // Emergency Contact
                if hasContent(cardData.emergencyContactName, cardData.emergencyContactPhone) {
                    DetailSection(title: "Emergency Contact", icon: "phone.circle.fill", color: .red) {
                        DetailField(label: "Name", value: cardData.emergencyContactName)
                        DetailField(label: "Relationship", value: cardData.emergencyContactRelationship)
                        DetailField(label: "Phone", value: cardData.emergencyContactPhone)
                    }
                }

                // Additional Notes
                if !cardData.additionalNotes.isEmpty {
                    DetailSection(title: "Additional Notes", icon: "note.text", color: .secondary) {
                        Text(cardData.additionalNotes)
                            .font(.body)
                    }
                }
            }
            .padding()
        }
    }

    private func hasContent(_ values: String...) -> Bool {
        values.contains { !$0.isEmpty }
    }
}

// MARK: - Card Header

struct CardHeaderView: View {
    let cardData: CardData

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.mp.sky.gradient)
                .frame(width: 64, height: 64)
                .overlay {
                    Text(initials)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(cardData.childName.isEmpty ? "Unnamed" : cardData.childName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.mp.deepBlue)

                if !cardData.dateOfBirth.isEmpty {
                    Text("Born: \(cardData.dateOfBirth)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mp.softWhite)
        .clipShape(.rect(cornerRadius: 14))
        .shadow(color: Color.mp.ocean.opacity(0.08), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
    }

    private var initials: String {
        let parts = cardData.childName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(cardData.childName.prefix(2)).uppercased()
    }
}

// MARK: - Detail Section

struct DetailSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
        .cardSectionStyle()
    }
}

// MARK: - Detail Field

struct DetailField: View {
    let label: String
    let value: String

    var body: some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
