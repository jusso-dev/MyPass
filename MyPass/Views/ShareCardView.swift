import SwiftUI
import CoreImage.CIFilterBuiltins

struct ShareCardView: View {
    let cardId: String
    let ownerSecret: String

    @State private var viewModel: ShareFlowViewModel
    @State private var recipientDeviceId = ""
    @State private var qrLink: CreateShareLinkResponse?
    @State private var selectedRole = "trusted"
    @State private var ttlHours = 1
    @State private var ttlMinutes = 0
    @State private var showingRotateConfirmation = false
    @State private var showingOwnerSecretRotation = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    init(cardId: String, ownerSecret: String) {
        self.cardId = cardId
        self.ownerSecret = ownerSecret
        _viewModel = State(initialValue: ShareFlowViewModel(cardId: cardId, ownerSecret: ownerSecret))
    }

    var body: some View {
        NavigationStack {
            List {
                shareViaLinkSection
                accessLevelSection
                activeLinksSection
                subscribersSection
                shareWithCodeSection
                securitySection
            }
            .scrollContentBackground(.hidden)
            .background(Color.mp.skyFaint)
            .navigationTitle("Share Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $qrLink) { link in
                QRCodeSheet(
                    token: link.token,
                    expiresAt: link.expiresAt,
                    maxUses: link.maxUses,
                    cardKeyBase64: viewModel.cardKeyBase64
                )
            }
            .task {
                await viewModel.loadSubscribers()
                await viewModel.loadShareLinks()
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK") { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
            .confirmationDialog(
                "Secure this card?",
                isPresented: $showingRotateConfirmation,
                titleVisibility: .visible
            ) {
                Button("Secure Now") {
                    Task { _ = await viewModel.rotateKeyAfterRevocation() }
                }
                Button("Skip for Now", role: .cancel) {}
            } message: {
                Text("Someone's access was removed. Securing the card ensures they can no longer read future updates.")
            }
            .fullScreenCover(isPresented: $showingOwnerSecretRotation) {
                RotateSecretWarningView(
                    onConfirm: {
                        showingOwnerSecretRotation = false
                        Task { _ = await viewModel.rotateOwnerSecret() }
                    },
                    onCancel: {
                        showingOwnerSecretRotation = false
                    }
                )
            }
        }
    }

    // MARK: - Sections

    private var shareViaLinkSection: some View {
        Section {
            Button {
                Task {
                    if selectedRole == "temporary" {
                        await viewModel.createShareLink(role: selectedRole, expiresInMinutes: ttlTotalMinutes)
                    } else {
                        await viewModel.createShareLink(role: selectedRole)
                    }
                    qrLink = viewModel.shareLink
                }
            } label: {
                Label("Generate QR Code", systemImage: "qrcode")
            }
        } header: {
            ShareSectionLabel(icon: "qrcode", title: "Share via QR Code")
        } footer: {
            Text("The easiest way to share. The other person just scans the code with their phone camera.")
        }
    }

    private var accessLevelSection: some View {
        Section {
            Picker("Access Level", selection: $selectedRole) {
                Text("Can Edit").tag("editor")
                Text("Full Access").tag("trusted")
                Text("Temporary Access").tag("temporary")
                Text("View Only").tag("readonly")
            }

            if selectedRole == "temporary" {
                ttlPickerContent
            }
        } header: {
            ShareSectionLabel(icon: "person.badge.shield.checkmark", title: "Access Level")
        } footer: {
            Text(accessLevelDescription)
                .font(.caption)
        }
    }

    private var ttlPickerContent: some View {
        VStack(spacing: 8) {
            Text("Expires after")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                Picker("Hours", selection: $ttlHours) {
                    ForEach(0...23, id: \.self) { h in
                        Text("\(h) hr").tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 100, height: 120)
                .clipped()

                Picker("Minutes", selection: $ttlMinutes) {
                    ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { m in
                        Text("\(m) min").tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 100, height: 120)
                .clipped()
            }
            .onChange(of: ttlHours) {
                // If 24 hours, clamp minutes to 0
                if ttlHours >= 24 { ttlHours = 23; ttlMinutes = 55 }
                // Ensure at least 5 minutes
                if ttlHours == 0 && ttlMinutes == 0 { ttlMinutes = 5 }
            }
            .onChange(of: ttlMinutes) {
                if ttlHours == 0 && ttlMinutes == 0 { ttlMinutes = 5 }
            }

            Text("Maximum 24 hours")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Total TTL in minutes from the picker selection.
    private var ttlTotalMinutes: Int {
        max(5, ttlHours * 60 + ttlMinutes)
    }

    /// ISO 8601 expiry timestamp computed from ttlTotalMinutes.
    private var computedExpiresAt: String {
        let expiry = Date().addingTimeInterval(TimeInterval(ttlTotalMinutes * 60))
        return ISO8601DateFormatter().string(from: expiry)
    }

    private var accessLevelDescription: String {
        switch selectedRole {
        case "editor": return "They can view and update this card — ideal for a spouse or co-parent."
        case "trusted": return "Ongoing full access with automatic updates — for close family or therapists."
        case "temporary": return "Short-term access that can expire — for babysitters or substitute teachers."
        case "readonly": return "Can view the card but won't get update notifications."
        default: return ""
        }
    }

    private var shareWithCodeSection: some View {
        Section {
            HStack {
                TextField("Their sharing code", text: $recipientDeviceId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Share") {
                    if recipientDeviceId == appState.deviceId {
                        viewModel.error = "You can't share a card with your own device."
                        return
                    }
                    Task {
                        _ = await viewModel.shareWithDevice(
                            recipientDeviceId: recipientDeviceId,
                            role: selectedRole,
                            expiresAt: selectedRole == "temporary" ? computedExpiresAt : nil
                        )
                        recipientDeviceId = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(recipientDeviceId.isEmpty)
            }
        } header: {
            ShareSectionLabel(icon: "person.badge.plus", title: "Share with Sharing Code")
        } footer: {
            Text("Ask the other person for their sharing code (found in their Settings tab). This gives them direct, ongoing access.")
        }
    }

    private var activeLinksSection: some View {
        Section {
            if viewModel.shareLinks.isEmpty {
                Text("No active share links")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(viewModel.shareLinks) { link in
                    ShareLinkRow(link: link) {
                        Task { _ = await viewModel.revokeShareLink(link) }
                    }
                }
            }
        } header: {
            ShareSectionLabel(icon: "link.circle", title: "Active Links (\(viewModel.shareLinks.count))")
        }
    }

    private var subscribersSection: some View {
        Section {
            if viewModel.needsKeyRotation {
                Button {
                    showingRotateConfirmation = true
                } label: {
                    Label("Secure this card", systemImage: "lock.rotation")
                        .foregroundStyle(.orange)
                }
            }

            if viewModel.isRotatingKey {
                HStack {
                    ProgressView()
                        .tint(Color.mp.ocean)
                    Text("Securing card...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.subscribers.isEmpty {
                Text("No one has access yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(viewModel.subscribers) { subscriber in
                    SubscriberRow(subscriber: subscriber) {
                        Task {
                            let revoked = await viewModel.revokeSubscription(subscriber)
                            if revoked && viewModel.needsKeyRotation {
                                showingRotateConfirmation = true
                            }
                        }
                    }
                }
            }
        } header: {
            ShareSectionLabel(icon: "person.2", title: "People with Access (\(viewModel.subscribers.count))")
        }
    }

    private var securitySection: some View {
        Section {
            Button {
                showingOwnerSecretRotation = true
            } label: {
                Label("Reset Card Ownership", systemImage: "key.fill")
            }
        } header: {
            ShareSectionLabel(icon: "lock.shield", title: "Advanced Security")
        } footer: {
            Text("Only use this if you believe your account has been compromised. This will revoke all existing access and you'll need to re-share with everyone.")
        }
    }
}

// MARK: - Section Label

private struct ShareSectionLabel: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .foregroundStyle(Color.mp.ocean)
            .fontWeight(.medium)
    }
}

// MARK: - Subscriber Row

private struct SubscriberRow: View {
    let subscriber: CardSubscriber
    let onRevoke: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Code:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(subscriber.deviceId)
                        .font(.caption)
                        .monospaced()
                        .lineLimit(1)
                }

                RoleBadge(role: subscriber.role)
            }

            Spacer()

            if let version = subscriber.lastFetchedVersion {
                Text("v\(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                onRevoke()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .accessibilityLabel("Revoke access")
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Share Link Row

private struct ShareLinkRow: View {
    let link: ShareLinkInfo
    let onRevoke: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    RoleBadge(role: link.role)
                    Text("\(link.usedCount)/\(link.maxUses) used")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("Expires: \(link.expiresAt)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(role: .destructive) {
                onRevoke()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .accessibilityLabel("Revoke link")
        }
    }
}

// MARK: - QR Code Sheet

struct QRCodeSheet: View {
    let token: String
    let expiresAt: String
    let maxUses: Int
    let cardKeyBase64: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mp.skyFaint.ignoresSafeArea()

                VStack(spacing: 24) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.mp.ocean)
                        .accessibilityHidden(true)

                    Text("Scan to access this card")
                        .font(.headline)
                        .foregroundStyle(Color.mp.deepBlue)

                    if let qrImage = generateQRCode(from: shareURL) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .padding()
                            .background(Color.white)
                            .clipShape(.rect(cornerRadius: 16))
                            .shadow(color: Color.mp.ocean.opacity(0.1), radius: 8, y: 4)
                            .accessibilityLabel("QR code for sharing card")
                    }

                    VStack(spacing: 6) {
                        Label("Max uses: \(maxUses)", systemImage: "number.circle")
                        Label("Expires: \(expiresAt)", systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Share Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Full deep link URL: mypass://links/TOKEN#CARD_KEY
    /// The fragment (after #) never leaves the device — it's not sent to the server.
    private var shareURL: String {
        if let key = cardKeyBase64 {
            return "mypass://links/\(token)#\(key)"
        }
        return "mypass://links/\(token)"
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = 10.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
