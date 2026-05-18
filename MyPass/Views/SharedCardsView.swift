import SwiftUI
import Combine

struct SharedCardsView: View {
    @State private var viewModel = SharedCardsViewModel()
    @State private var showingScanner = false
    @State private var viewedCardId: String?

    // In-app QR scan → present RedeemShareLinkSheet
    @State private var scannedToken: String?
    @State private var scannedKeyFragment: String?
    @State private var showingRedeemSheet = false

    @State private var scanError: String?
    @State private var showingScanError = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mp.skyFaint.ignoresSafeArea()

                Group {
                    if viewModel.isLoading && viewModel.subscriptions.isEmpty {
                        ProgressView("Loading shared cards...")
                            .tint(Color.mp.ocean)
                    } else if viewModel.subscriptions.isEmpty {
                        EmptySharedView()
                    } else {
                        sharedCardList
                    }
                }
            }
            .navigationTitle("Shared With Me")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title3)
                    }
                    .accessibilityLabel("Scan QR code")
                }
            }
            .navigationDestination(for: ReceivedSubscription.self) { subscription in
                SharedCardDetailView(subscription: subscription)
                    .onAppear { viewedCardId = subscription.cardId }
                    .onDisappear {
                        if viewedCardId == subscription.cardId {
                            viewedCardId = nil
                            // Refresh list so stale badge clears after viewing a card
                            Task { await viewModel.loadSharedCards() }
                        }
                    }
            }
            .sheet(isPresented: $showingScanner, onDismiss: {
                // After scanner dismisses, present redeem sheet if we have a scanned token
                if scannedToken != nil {
                    showingRedeemSheet = true
                }
            }) {
                QRScannerSheet { code in
                    handleScannedCode(code)
                }
            }
            .sheet(isPresented: $showingRedeemSheet, onDismiss: {
                scannedToken = nil
                scannedKeyFragment = nil
                // Refresh after redeem sheet closes
                APIClient.shared.clearThrottles()
                Task { await viewModel.loadSharedCards() }
            }) {
                if let token = scannedToken {
                    RedeemShareLinkSheet(token: token, cardKeyBase64: scannedKeyFragment)
                }
            }
            .onAppear {
                APIClient.shared.clearThrottles()
                Task { await viewModel.loadSharedCards() }
            }
            .onReceive(NotificationCenter.default.publisher(for: PushNotificationService.newShareNotification)) { _ in
                APIClient.shared.clearThrottles()
                Task { await viewModel.loadSharedCards() }
            }
            .onReceive(NotificationCenter.default.publisher(for: PushNotificationService.cardDeletedNotification)) { _ in
                APIClient.shared.clearThrottles()
                Task { await viewModel.loadSharedCards() }
            }
            .onReceive(NotificationCenter.default.publisher(for: PushNotificationService.shareExpiredNotification)) { _ in
                APIClient.shared.clearThrottles()
                Task { await viewModel.loadSharedCards() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .myPassShouldRefresh)) { _ in
                APIClient.shared.clearThrottles()
                Task { await viewModel.loadSharedCards() }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK") { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
            .alert("Invalid QR Code", isPresented: $showingScanError) {
                Button("OK") { scanError = nil }
            } message: {
                Text(scanError ?? "")
            }
        }
    }

    private var sharedCardList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.subscriptions) { subscription in
                    NavigationLink(value: subscription) {
                        SharedCardRowView(subscription: subscription)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .refreshable {
            APIClient.shared.clearThrottles()
            await viewModel.loadSharedCards()
        }
    }

    private func handleScannedCode(_ code: String) {
        print("📱 QR scanned: \(code)")

        guard let url = URL(string: code) else {
            print("📱 QR failed: could not parse URL from scanned code")
            scanError = "Could not parse URL from QR code"
            showingScanError = true
            return
        }

        print("📱 QR URL parsed — scheme: \(url.scheme ?? "nil"), host: \(url.host ?? "nil"), path: \(url.path), fragment: \(url.fragment?.prefix(10) ?? "nil")...")

        guard let link = DeepLink(url: url) else {
            print("📱 QR failed: DeepLink parsing failed for \(url)")
            scanError = "Unrecognized QR code format"
            showingScanError = true
            return
        }

        switch link {
        case .redeemShareLink(let token, let keyFragment):
            print("📱 QR redeeming token: \(token.prefix(10))..., hasKey: \(keyFragment != nil)")
            scannedToken = token
            scannedKeyFragment = keyFragment
            // Scanner will dismiss, then onDismiss triggers showingRedeemSheet
        }
    }
}

// MARK: - Empty State

private struct EmptySharedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 56))
                .foregroundStyle(Color.mp.sky)
                .accessibilityHidden(true)

            Text("No Shared Cards")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.mp.deepBlue)

            Text("Cards shared with you by\nfamilies and carers will appear here.\n\nTap the QR scanner to scan a share code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Shared Card Row

struct SharedCardRowView: View {
    let subscription: ReceivedSubscription
    @State private var now = Date()

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(roleColor(for: subscription.role).gradient)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(subscription.childAlias ?? "Shared Card")
                        .font(.headline)
                        .foregroundStyle(Color.mp.deepBlue)

                    if subscription.isStale {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .accessibilityLabel("Update available")
                    }
                }

                HStack(spacing: 8) {
                    RoleBadge(role: subscription.role)

                    if subscription.isStale {
                        Text("Update available")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let remaining = expiryText {
                        Label(remaining, systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(expiryUrgent ? .red : .orange)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color.mp.softWhite)
        .clipShape(.rect(cornerRadius: 14))
        .shadow(color: Color.mp.ocean.opacity(0.08), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .onReceive(timer) { _ in now = Date() }
    }

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
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        }
        return "\(minutes)m left"
    }

    private var expiryUrgent: Bool {
        guard let expiry = expiryDate else { return false }
        return expiry.timeIntervalSince(now) < 900 // < 15 minutes
    }
}

extension ReceivedSubscription: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(subscriptionId)
    }

    public static func == (lhs: ReceivedSubscription, rhs: ReceivedSubscription) -> Bool {
        lhs.subscriptionId == rhs.subscriptionId
    }
}
