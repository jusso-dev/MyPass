import SwiftUI

struct GettingStartedView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    welcomeHeader
                    whatIsMyPassSection
                    creatingCardSection
                    sharingSection
                    rolesSection
                    qrCodeSection
                    securitySection
                    tipsSection
                }
                .padding()
            }
            .background(Color.mp.skyFaint)
            .navigationTitle("Getting Started")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var welcomeHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(Color.mp.ocean)
                .accessibilityHidden(true)

            Text("Welcome to MyPass")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.mp.deepBlue)

            Text("A simple, private way to share your child's needs with teachers, caregivers, and anyone who supports them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private var whatIsMyPassSection: some View {
        GuideSection(icon: "questionmark.circle", title: "What is MyPass?") {
            Text("MyPass lets you create a digital card that describes your child's unique needs, preferences, and helpful information. You can then share this card securely with anyone who needs it — teachers, babysitters, family members, therapists, or coaches.")
            Text("Everything is encrypted and private. The server never sees your child's information — only you and the people you share with can read it.")
            Text("While this app is designed to work offline most of the time, it does occasionally need to reach out to a server — to sync cards in an encrypted manner with others you have granted access to, to send anonymous crash log data, or to fetch remote configuration items the app requires.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var creatingCardSection: some View {
        GuideSection(icon: "plus.circle", title: "Creating a Card") {
            GuideStep(number: 1, text: "Tap the + button on the My Cards tab.")
            GuideStep(number: 2, text: "Fill in your child's name (or a nickname) and any information you want to share — things like sensory preferences, communication style, calming strategies, allergies, or anything helpful.")
            GuideStep(number: 3, text: "Tap Save. Your card is encrypted on your device and uploaded securely.")
            Text("You can create multiple cards — one for each child, or different cards with different levels of detail for different audiences.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sharingSection: some View {
        GuideSection(icon: "person.badge.plus", title: "Sharing a Card") {
            Text("There are two ways to share your card with someone:")

            GuideBullet(title: "By QR Code", description: "Generate a QR code that the other person scans with their phone. This is the easiest way — they don't need MyPass installed, just a phone camera.")

            GuideBullet(title: "By Sharing Code", description: "If the other person has MyPass installed, they can find their sharing code in Settings. Enter it on the Share screen to give them direct, ongoing access.")
        }
    }

    private var rolesSection: some View {
        GuideSection(icon: "person.2.circle", title: "Access Levels") {
            Text("When you share a card, you choose an access level that controls what the other person can do:")

            RoleExplainer(
                role: "Can Edit",
                color: Color.mp.editor,
                description: "For people who need to update the card too — like a spouse or co-parent. They can view and edit the card just like you can. Both of you will see each other's changes."
            )

            RoleExplainer(
                role: "Full Access",
                color: Color.mp.trusted,
                description: "For people in your child's inner circle — family, primary caregivers, therapists. They get full ongoing access and will see updates whenever you change the card."
            )

            RoleExplainer(
                role: "Temporary Access",
                color: Color.mp.temporary,
                description: "For short-term situations — a substitute teacher, a weekend babysitter, a playdate parent. Access can expire automatically after a set time."
            )

            RoleExplainer(
                role: "View Only",
                color: Color.mp.readonly,
                description: "For people who just need to view the card once or a few times. They can read it but won't get push notifications about updates."
            )

            Text("You can change or remove someone's access at any time from the Share screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var qrCodeSection: some View {
        GuideSection(icon: "qrcode", title: "QR Codes & Links") {
            Text("When you generate a QR code, it creates a special one-time (or limited-use) link that expires after a set time.")
            Text("The other person scans the QR code with their phone camera. If they have MyPass installed, the card opens directly. The QR code includes an encryption key so only the scanner can read it — the server never sees this key.")

            GuideBullet(title: "Max uses", description: "How many times the QR code can be scanned before it stops working. Default is 1 (single use).")
            GuideBullet(title: "Expiry", description: "How long the QR code stays active. Default is 24 hours. After that, it can't be used even if it hasn't reached max uses.")
        }
    }

    private var securitySection: some View {
        GuideSection(icon: "lock.shield", title: "Security") {
            GuideBullet(
                title: "Securing after removing access",
                description: "If you remove someone's access, the app will offer to secure the card. This changes the encryption so the removed person can't read any future updates. You should always do this after removing someone."
            )

            GuideBullet(
                title: "Reset Card Ownership",
                description: "This is an advanced option in the Share screen. Only use it if you believe your phone or account has been compromised. It will revoke everyone's access and you'll need to re-share with each person."
            )

            Text("You don't need to worry about these for day-to-day use. Just share and update your cards — the app handles the encryption for you.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var tipsSection: some View {
        GuideSection(icon: "lightbulb", title: "Tips") {
            GuideBullet(title: "Keep it updated", description: "Your child's needs may change over time. Update the card whenever something important changes — all trusted recipients will get the update automatically.")
            GuideBullet(title: "Start simple", description: "You don't have to fill in everything at once. Start with the most important things (name, key needs, emergency info) and add more later.")
            GuideBullet(title: "Multiple cards", description: "Consider making a detailed card for close family and a simpler one for casual caregivers with only the essentials.")
            GuideBullet(title: "Your Sharing Code", description: "You can find and copy your sharing code in the Settings tab. Share it with someone if they want to send you a card directly.")
        }
    }
}

// MARK: - Helper Views

private struct GuideSection<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Color.mp.ocean)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mp.softWhite)
        .clipShape(.rect(cornerRadius: 14))
        .shadow(color: Color.mp.ocean.opacity(0.08), radius: 6, y: 2)
    }
}

private struct GuideStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.mp.ocean)
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
        }
    }
}

private struct GuideBullet: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .fontWeight(.semibold)
            Text(description)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}

private struct RoleExplainer: View {
    let role: String
    let color: Color
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(role)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(Capsule())
                .frame(width: 80, alignment: .leading)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
