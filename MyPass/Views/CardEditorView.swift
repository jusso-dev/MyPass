import SwiftUI

struct CardEditorView: View {
    var editingCardId: String? = nil
    var editingChildAlias: String? = nil

    @State private var viewModel = CardEditorViewModel()
    @Environment(\.dismiss) private var dismiss

    private var isEditing: Bool { editingCardId != nil }

    var body: some View {
        NavigationStack {
            Form {
                personalInfoSection
                communicationSection
                sensoryProfileSection
                behaviourSection
                routinesSection
                medicalSection
                emergencyContactSection
                additionalNotesSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.mp.skyFaint)
            .navigationTitle(isEditing ? "Edit Card" : "New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.isSaving || viewModel.childAlias.isEmpty)
                }
            }
            .overlay {
                if viewModel.isSaving {
                    savingOverlay
                }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK") { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
            .task {
                if let cardId = editingCardId {
                    if let alias = editingChildAlias {
                        viewModel.childAlias = alias
                    }
                    await viewModel.loadCard(cardId: cardId)
                }
            }
        }
    }

    // MARK: - Sections

    private var personalInfoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                LabeledField("Alias / Nickname", text: $viewModel.childAlias, hint: "e.g. Buddy, Little J — visible on the server")
                Text("This is stored as plain text. Do not use the child's real name.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            LabeledField("Child's Full Name", text: $viewModel.cardData.childName, hint: "Encrypted — only visible to people you share with")
            LabeledDateField("Date of Birth", dateString: $viewModel.cardData.dateOfBirth)
        } header: {
            EditorSectionHeader(icon: "person.fill", title: "Personal Information")
        }
    }

    private var communicationSection: some View {
        Section {
            LabeledField("Communication Method", text: $viewModel.cardData.communicationMethod, hint: "e.g. Verbal, AAC, Auslan, PECS")
            LabeledField("Communication Notes", text: $viewModel.cardData.communicationNotes, multiline: true)
        } header: {
            EditorSectionHeader(icon: "bubble.left.and.bubble.right", title: "Communication")
        }
    }

    private var sensoryProfileSection: some View {
        Section {
            LabeledField("Sensory Seeks", text: $viewModel.cardData.sensorySeeks, hint: "Input they enjoy or seek out", multiline: true)
            LabeledField("Sensory Avoids", text: $viewModel.cardData.sensoryAvoids, hint: "Input that causes distress", multiline: true)
            LabeledField("Stimming Behaviours", text: $viewModel.cardData.stimmingBehaviours, hint: "e.g. hand flapping, rocking, vocal stims", multiline: true)
        } header: {
            EditorSectionHeader(icon: "hand.raised.fingers.spread", title: "Sensory Profile")
        }
    }

    private var behaviourSection: some View {
        Section {
            LabeledField("Signs of Overwhelm", text: $viewModel.cardData.signsOfOverwhelm, hint: "Early warning signs", multiline: true)
            LabeledField("Meltdown Support", text: $viewModel.cardData.meltdownSupport, hint: "What helps during a meltdown?", multiline: true)
            LabeledField("Shutdown Support", text: $viewModel.cardData.shutdownSupport, hint: "What helps during a shutdown?", multiline: true)
            LabeledField("Calming Strategies", text: $viewModel.cardData.calmingStrategies, hint: "De-escalation approaches", multiline: true)
            LabeledField("Elopement Risk", text: $viewModel.cardData.elopementRisk, hint: "Wandering tendencies & response", multiline: true)
        } header: {
            EditorSectionHeader(icon: "heart.circle", title: "Behaviour & Regulation")
        }
    }

    private var routinesSection: some View {
        Section {
            LabeledField("Routine Needs", text: $viewModel.cardData.routineNeeds, hint: "Important routines & transition support", multiline: true)
            LabeledField("Special Interests", text: $viewModel.cardData.specialInterests, hint: "Topics & activities they love", multiline: true)
            LabeledField("Safe Foods", text: $viewModel.cardData.safeFoods, hint: "Foods they will reliably eat", multiline: true)
        } header: {
            EditorSectionHeader(icon: "star.circle", title: "Routines & Interests")
        }
    }

    private var medicalSection: some View {
        Section {
            LabeledField("Medications", text: $viewModel.cardData.medications, multiline: true)
            LabeledField("Allergies", text: $viewModel.cardData.allergies, multiline: true)
            LabeledField("Other Medical Info", text: $viewModel.cardData.otherMedical, hint: "Co-occurring conditions, therapies", multiline: true)
        } header: {
            EditorSectionHeader(icon: "cross.case", title: "Medical")
        }
    }

    private var emergencyContactSection: some View {
        Section {
            LabeledField("Contact Name", text: $viewModel.cardData.emergencyContactName)
            LabeledField("Relationship", text: $viewModel.cardData.emergencyContactRelationship)
            LabeledPhoneField("Phone Number", text: $viewModel.cardData.emergencyContactPhone)
        } header: {
            EditorSectionHeader(icon: "phone.circle.fill", title: "Emergency Contact")
        }
    }

    private var additionalNotesSection: some View {
        Section {
            LabeledField("Additional Notes", text: $viewModel.cardData.additionalNotes, hint: "Anything else someone should know", multiline: true, lineRange: 3...8)
        } header: {
            EditorSectionHeader(icon: "note.text", title: "Additional Notes")
        }
    }

    private var savingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color.mp.ocean)
            Text("Encrypting & saving...")
                .font(.subheadline)
                .foregroundStyle(Color.mp.deepBlue)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Actions

    private func save() async {
        if isEditing {
            if await viewModel.updateCard() {
                dismiss()
            }
        } else {
            if await viewModel.createCard() != nil {
                dismiss()
            }
        }
    }
}

// MARK: - Section Header

private struct EditorSectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .foregroundStyle(Color.mp.ocean)
            .fontWeight(.medium)
    }
}

// MARK: - Labeled Field (clear label above the text field)

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    let hint: String?
    let multiline: Bool
    let lineRange: ClosedRange<Int>

    init(_ label: String, text: Binding<String>, hint: String? = nil, multiline: Bool = false, lineRange: ClosedRange<Int> = 2...5) {
        self.label = label
        self._text = text
        self.hint = hint
        self.multiline = multiline
        self.lineRange = lineRange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.mp.deepBlue)

            if multiline {
                TextField(hint ?? label, text: $text, axis: .vertical)
                    .lineLimit(lineRange)
                    .font(.body)
            } else {
                TextField(hint ?? label, text: $text)
                    .font(.body)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Labeled Date Field

private struct LabeledDateField: View {
    let label: String
    @Binding var dateString: String
    @State private var selectedDate: Date = Date()
    @State private var hasInitialized = false

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    init(_ label: String, dateString: Binding<String>) {
        self.label = label
        self._dateString = dateString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.mp.deepBlue)

            DatePicker(
                label,
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
        .padding(.vertical, 2)
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            if let parsed = Self.displayFormatter.date(from: dateString) {
                selectedDate = parsed
            }
        }
        .onChange(of: selectedDate) {
            dateString = Self.displayFormatter.string(from: selectedDate)
        }
    }
}

// MARK: - Labeled Phone Field

private struct LabeledPhoneField: View {
    let label: String
    @Binding var text: String

    init(_ label: String, text: Binding<String>) {
        self.label = label
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.mp.deepBlue)

            TextField(label, text: $text)
                .keyboardType(.phonePad)
                .font(.body)
        }
        .padding(.vertical, 2)
    }
}
