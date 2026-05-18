import SwiftUI

struct MainTabView: View {
    private var network = NetworkMonitor.shared

    var body: some View {
        VStack(spacing: 0) {
            if !network.isConnected {
                OfflineBanner()
            }

            TabView {
                Tab("My Cards", systemImage: "heart.text.clipboard") {
                    CardListView()
                }

                Tab("Shared", systemImage: "person.2.fill") {
                    SharedCardsView()
                }

                Tab("Settings", systemImage: "gear") {
                    SettingsView()
                }
            }
        }
    }
}

// MARK: - Offline Banner

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption)
            Text("You're offline — viewing cached data. Changes will sync when reconnected.")
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color.orange.opacity(0.15))
        .foregroundStyle(.orange)
    }
}
