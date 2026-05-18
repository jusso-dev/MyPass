import SwiftUI

struct CardListView: View {
    @State private var viewModel = CardListViewModel()
    @State private var showingEditor = false
    @State private var showingGettingStarted = false
    @State private var cardToDelete: CardSummary?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mp.skyFaint.ignoresSafeArea()

                Group {
                    if viewModel.isLoading && viewModel.cards.isEmpty {
                        ProgressView("Loading cards...")
                            .tint(Color.mp.ocean)
                    } else if viewModel.cards.isEmpty {
                        EmptyCardsView()
                    } else {
                        cardList
                    }
                }
            }
            .navigationTitle("My Cards")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingGettingStarted = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel("Getting started guide")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Create new card")
                }
            }
            .navigationDestination(for: CardSummary.self) { card in
                CardDetailView(cardSummary: card)
            }
            .sheet(isPresented: $showingGettingStarted) {
                GettingStartedView()
            }
            .sheet(isPresented: $showingEditor) {
                Task { await viewModel.loadCards() }
            } content: {
                CardEditorView()
            }
            .task {
                await viewModel.loadCards()
            }
            .onReceive(NotificationCenter.default.publisher(for: PushNotificationService.cardUpdatedNotification)) { _ in
                APIClient.shared.clearThrottles()
                Task { await viewModel.loadCards() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .myPassShouldRefresh)) { _ in
                Task { await viewModel.loadCards() }
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
                "Delete Card?",
                isPresented: .init(
                    get: { cardToDelete != nil },
                    set: { if !$0 { cardToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let card = cardToDelete {
                        Task { _ = await viewModel.deleteCard(card) }
                        cardToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { cardToDelete = nil }
            } message: {
                Text("This will permanently delete this card and revoke access for all subscribers.")
            }
        }
    }

    private var cardList: some View {
        List {
            ForEach(viewModel.cards) { card in
                NavigationLink(value: card) {
                    CardRowView(card: card)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        cardToDelete = card
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        cardToDelete = card
                    } label: {
                        Label("Delete Card", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.loadCards()
        }
    }
}

// MARK: - Empty State

private struct EmptyCardsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 56))
                .foregroundStyle(Color.mp.sky)
                .accessibilityHidden(true)

            Text("No Cards Yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.mp.deepBlue)

            Text("Create your first MyPass card\nto help others understand and support\nyour child's needs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Card Row

struct CardRowView: View {
    let card: CardSummary

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.mp.sky.gradient)
                .frame(width: 44, height: 44)
                .overlay {
                    Text(initials)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.childAlias ?? "Unnamed Card")
                    .font(.headline)
                    .foregroundStyle(Color.mp.deepBlue)

                HStack(spacing: 12) {
                    Label("\(card.subscriberCount) shared", systemImage: "person.2")
                    Label("v\(card.version)", systemImage: "clock.arrow.circlepath")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
    }

    private var initials: String {
        let name = card.childAlias ?? ""
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
