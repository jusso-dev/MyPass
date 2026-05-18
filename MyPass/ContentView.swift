import SwiftUI
import LocalAuthentication

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingRedeemSheet = false
    @State private var redeemToken: String?
    @State private var redeemKeyFragment: String?
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var isUnlocked = false
    @State private var authError: String?

    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView {
                    withAnimation {
                        hasSeenOnboarding = true
                    }
                }
            } else if !isUnlocked {
                LockScreenView(authError: authError) {
                    authenticate()
                }
            } else if appState.isLoading {
                LaunchView()
            } else if let error = appState.error {
                ErrorView(message: error) {
                    Task { await appState.initialize() }
                }
            } else {
                MainTabView()
            }
        }
        .task {
            if hasSeenOnboarding {
                authenticate()
            }
        }
        .onChange(of: hasSeenOnboarding) {
            if hasSeenOnboarding {
                authenticate()
            }
        }
        .onChange(of: isUnlocked) {
            if isUnlocked && hasSeenOnboarding {
                Task { await appState.initialize() }
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                isUnlocked = false
            }
        }
        .onChange(of: appState.pendingDeepLink) {
            handleDeepLink()
        }
        .sheet(isPresented: $showingRedeemSheet) {
            if let token = redeemToken {
                RedeemShareLinkSheet(token: token, cardKeyBase64: redeemKeyFragment)
            }
        }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock MyPass to access your cards"
            ) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        isUnlocked = true
                        authError = nil
                    } else {
                        authError = authenticationError?.localizedDescription
                    }
                }
            }
        } else {
            // No biometrics or passcode configured — allow access
            isUnlocked = true
        }
    }

    private func handleDeepLink() {
        guard let link = appState.pendingDeepLink else { return }
        appState.pendingDeepLink = nil

        switch link {
        case .redeemShareLink(let token, let keyFragment):
            redeemToken = token
            redeemKeyFragment = keyFragment
            showingRedeemSheet = true
        }
    }
}

// MARK: - Redeem Share Link Sheet

struct RedeemShareLinkSheet: View {
    let token: String
    let cardKeyBase64: String?

    @State private var cardData: CardData?
    @State private var childAlias: String?
    @State private var isLoading = true
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mp.skyFaint.ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.mp.ocean)
                        Text("Redeeming share link...")
                            .font(.subheadline)
                    }
                } else if let cardData {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Shared Card", systemImage: "person.fill.checkmark")
                                .font(.headline)
                                .foregroundStyle(Color.mp.ocean)

                            CardContentView(cardData: cardData)
                        }
                        .padding()
                    }
                } else if let error {
                    ContentUnavailableView {
                        Label("Link Error", systemImage: "link.badge.plus")
                    } description: {
                        Text(error)
                    }
                }
            }
            .navigationTitle(childAlias ?? "Shared Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await redeemLink()
            }
        }
    }

    private func redeemLink() async {
        isLoading = true

        guard let deviceId = KeychainService.shared.deviceId else {
            error = "Device not registered. Please restart the app."
            isLoading = false
            return
        }

        do {
            let response = try await APIClient.shared.redeemShareLink(token: token, deviceId: deviceId)
            childAlias = response.childAlias

            guard let cardKey = cardKeyBase64, !cardKey.isEmpty,
                  Data(base64Encoded: cardKey) != nil else {
                error = "This share link doesn't include a valid decryption key. Ask the card owner to share directly with your sharing code."
                isLoading = false
                return
            }

            // Decrypt using the key from the URL fragment
            let decrypted = try CryptoService.shared.decrypt(
                blob: response.encryptedBlob,
                iv: response.blobIv,
                authTag: response.blobAuthTag,
                withKeyBase64: cardKey
            )

            // Save the key and data locally
            KeychainService.shared.saveUnwrappedKey(cardKey, forCardId: response.cardId)
            CacheService.shared.cacheCardData(decrypted, forCardId: response.cardId)

            cardData = decrypted

            // Refresh shared cards list
            NotificationCenter.default.post(name: .myPassShouldRefresh, object: nil)
        } catch let apiError as APIError where apiError.isExpired {
            error = "This share link has expired or reached its maximum number of uses."
        } catch let apiError as APIError where apiError.isNotFound {
            error = "This share link was not found or has been revoked."
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Launch View

struct LaunchView: View {
    var body: some View {
        ZStack {
            Color.mp.skyFaint.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.mp.ocean)
                    .accessibilityHidden(true)

                Text("MyPass")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.mp.deepBlue)

                Text("Autism awareness cards")
                    .font(.subheadline)
                    .foregroundStyle(Color.mp.ocean)

                ProgressView()
                    .tint(Color.mp.ocean)
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    let authError: String?
    let onAuthenticate: () -> Void

    var body: some View {
        ZStack {
            Color.mp.skyFaint.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.mp.ocean)
                    .accessibilityHidden(true)

                Text("MyPass is Locked")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.mp.deepBlue)

                Text("Authenticate to access your cards")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let authError {
                    Text(authError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    onAuthenticate()
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .font(.headline)
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.mp.ocean)
            }
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.mp.skyFaint.ignoresSafeArea()

            ContentUnavailableView {
                Label("Connection Error", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(Color.mp.ocean)
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { onRetry() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
