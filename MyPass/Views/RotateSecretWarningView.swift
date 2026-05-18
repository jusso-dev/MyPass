import SwiftUI

/// Full-screen destructive warning shown before rotating an owner secret.
/// Requires the user to type a confirmation phrase before proceeding.
struct RotateSecretWarningView: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var confirmationText = ""
    @State private var showFinalConfirmation = false
    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var contentOpacity: Double = 0

    private let confirmationPhrase = "ROTATE"

    private var isConfirmationValid: Bool {
        confirmationText.trimmingCharacters(in: .whitespaces).uppercased() == confirmationPhrase
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient — warm red to dark
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.05, blue: 0.05),
                        Color(red: 0.35, green: 0.08, blue: 0.08),
                        Color(red: 0.55, green: 0.12, blue: 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        // Animated warning icon
                        warningIcon
                            .padding(.top, 40)

                        // Main content
                        warningContent
                            .opacity(contentOpacity)

                        // What will break
                        breakageList
                            .opacity(contentOpacity)

                        // Confirmation input
                        confirmationInput
                            .opacity(contentOpacity)

                        // Action buttons
                        actionButtons
                            .opacity(contentOpacity)

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    iconScale = 1.0
                    iconOpacity = 1.0
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                    contentOpacity = 1.0
                }
            }
            .alert("Are you absolutely sure?", isPresented: $showFinalConfirmation) {
                Button("Yes, Rotate Secret", role: .destructive) {
                    onConfirm()
                }
                Button("Go Back", role: .cancel) {}
            } message: {
                Text("This action cannot be undone. All existing shared access to this card will permanently break.")
            }
        }
    }

    // MARK: - Warning Icon

    private var warningIcon: some View {
        ZStack {
            // Pulsing outer ring
            Circle()
                .stroke(Color.red.opacity(0.3), lineWidth: 2)
                .frame(width: 120, height: 120)
                .scaleEffect(iconScale * 1.2)
                .opacity(iconOpacity * 0.6)

            Circle()
                .fill(Color.red.opacity(0.15))
                .frame(width: 100, height: 100)

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating)
        }
        .scaleEffect(iconScale)
        .opacity(iconOpacity)
    }

    // MARK: - Warning Content

    private var warningContent: some View {
        VStack(spacing: 14) {
            Text("Destructive Action")
                .font(.title.bold())
                .foregroundStyle(.white)

            Text("You are about to rotate the owner secret for this card. This is a critical security operation that **cannot be undone**.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Breakage List

    private var breakageList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "bolt.slash.fill")
                    .foregroundStyle(.orange)
                Text("What will break")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .background(.white.opacity(0.15))

            // Items
            BreakageRow(
                icon: "person.2.slash",
                text: "All people you've shared this card with will **permanently lose access**"
            )

            BreakageRow(
                icon: "key.slash",
                text: "Their copies of the card will become **unreadable encrypted data**"
            )

            BreakageRow(
                icon: "arrow.triangle.2.circlepath.circle",
                text: "You will need to **re-share the card** with every person individually"
            )

            BreakageRow(
                icon: "link.badge.plus",
                text: "All active share links will **stop working**"
            )
        }
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.red.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Confirmation Input

    private var confirmationInput: some View {
        VStack(spacing: 10) {
            Text("Type **\(confirmationPhrase)** to confirm")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))

            TextField("", text: $confirmationText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.title3.monospaced().bold())
                .padding()
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isConfirmationValid ? Color.red : Color.white.opacity(0.2),
                            lineWidth: isConfirmationValid ? 2 : 1
                        )
                )
                .foregroundStyle(isConfirmationValid ? .red : .white)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                showFinalConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.octagon.fill")
                    Text("Rotate Owner Secret")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isConfirmationValid ? Color.red : Color.red.opacity(0.3))
                .foregroundStyle(isConfirmationValid ? .white : .white.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!isConfirmationValid)

            Button {
                onCancel()
            } label: {
                Text("Cancel — Keep Current Secret")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.1))
                    .foregroundStyle(.white.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Breakage Row

private struct BreakageRow: View {
    let icon: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.red)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
