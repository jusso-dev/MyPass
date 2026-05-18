import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "heart.text.clipboard",
            iconColor: Color.mp.ocean,
            title: "Welcome to MyPass",
            subtitle: "A simple, private card that helps others understand and support your child.",
            details: "Create a digital card with your child's needs, preferences, and important information — then share it securely with the people who care for them."
        ),
        OnboardingPage(
            icon: "plus.circle.fill",
            iconColor: Color.mp.sky,
            title: "Create a Card",
            subtitle: "Fill in what matters most.",
            details: "Start with your child's name and the essentials — sensory needs, communication style, calming strategies, allergies. You can always add more later."
        ),
        OnboardingPage(
            icon: "qrcode",
            iconColor: Color.mp.trusted,
            title: "Share Securely",
            subtitle: "Give the right people the right access.",
            details: "Generate a QR code for quick sharing, or send a card directly using someone's sharing code. You choose who can see what — and you can remove access at any time."
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            iconColor: Color.mp.editor,
            title: "Private by Design",
            subtitle: "Your child's information stays yours.",
            details: "Everything is encrypted on your device before it leaves your phone. The server never sees your child's data — only you and the people you share with can read it."
        ),
    ]

    var body: some View {
        ZStack {
            Color.mp.skyFaint.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                bottomControls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.mp.ocean : Color.mp.ocean.opacity(0.25))
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(.easeInOut(duration: 0.25), value: currentPage)
                }
            }

            // Buttons
            if currentPage == pages.count - 1 {
                Button {
                    onComplete()
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.mp.ocean)
                        .foregroundStyle(.white)
                        .clipShape(.rect(cornerRadius: 14))
                }
            } else {
                HStack {
                    Button {
                        onComplete()
                    } label: {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        withAnimation {
                            currentPage += 1
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Next")
                                .font(.headline)
                            Image(systemName: "arrow.right")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.mp.ocean)
                        .foregroundStyle(.white)
                        .clipShape(.rect(cornerRadius: 12))
                    }
                }
            }
        }
    }
}

// MARK: - Page Model

private struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let details: String
}

// MARK: - Page View

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 72))
                .foregroundStyle(page.iconColor)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.mp.deepBlue)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.title3)
                    .foregroundStyle(Color.mp.ocean)
                    .multilineTextAlignment(.center)
            }

            Text(page.details)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}
