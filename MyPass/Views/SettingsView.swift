import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var serverURL = ""
    @State private var healthStatus: String?
    @State private var isCheckingHealth = false
    @State private var showingResetConfirmation = false

    // Backup state
    @State private var hasBackupFolder = BackupService.shared.hasBackupFolder
    @State private var backupFolderName = BackupService.shared.backupFolderName
    @State private var lastBackupDate = BackupService.shared.lastBackupDate
    @State private var lastBackupError = BackupService.shared.lastBackupError
    @State private var activeFilePicker: FilePicker?
    @State private var restoreMessage: String?
    @State private var showingRestoreAlert = false
    @State private var showingDisableConfirmation = false

    // Password flows
    @State private var pendingFolderURL: URL?
    @State private var pendingRestoreURL: URL?
    @State private var showingPasswordSetup = false
    @State private var showingRestorePassword = false
    @State private var showingChangePassword = false
    @State private var passwordField = ""
    @State private var passwordConfirmField = ""
    @State private var passwordError: String?

    private enum FilePicker: Identifiable {
        case folder, restore
        var id: Self { self }
    }

    private let backupService = BackupService.shared

    var body: some View {
        NavigationStack {
            Form {
                deviceSection
                recoverySection
                backupSection
                aboutSection
                dangerZoneSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.mp.skyFaint)
            .navigationTitle("Settings")
            .onAppear {
                serverURL = appState.serverURL
                refreshBackupState()
            }
            .confirmationDialog(
                "Reset Device?",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    appState.resetDevice()
                    Task { await appState.initialize() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will create a new device identity. You will lose access to any cards owned by this device.")
            }
            .confirmationDialog(
                "Disable Backups?",
                isPresented: $showingDisableConfirmation,
                titleVisibility: .visible
            ) {
                Button("Disable", role: .destructive) {
                    backupService.clearBackupFolder()
                    refreshBackupState()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Automatic backups will stop. Existing backup files in your chosen folder will not be deleted.")
            }
            .sheet(item: $activeFilePicker) { picker in
                switch picker {
                case .folder:
                    FolderPicker { url in
                        activeFilePicker = nil
                        if let url {
                            pendingFolderURL = url
                            if KeychainService.shared.backupPassword != nil {
                                // Already have a password, just update the folder
                                try? backupService.setBackupFolder(url: url)
                                refreshBackupState()
                                backupService.performBackupNow()
                                pendingFolderURL = nil
                            } else {
                                // Need to set a password first
                                passwordField = ""
                                passwordConfirmField = ""
                                passwordError = nil
                                showingPasswordSetup = true
                            }
                        }
                    }
                case .restore:
                    RestoreFilePicker { url in
                        activeFilePicker = nil
                        if let url {
                            pendingRestoreURL = url
                            // Check backup version to decide if we need a password
                            do {
                                let version = try backupService.backupVersion(fileURL: url)
                                if version >= 2 {
                                    passwordField = ""
                                    passwordError = nil
                                    showingRestorePassword = true
                                } else {
                                    // v1: try device-key restore directly
                                    let count = try backupService.restoreFromBackup(fileURL: url)
                                    restoreMessage = "Restored \(count) card\(count == 1 ? "" : "s") successfully."
                                    showingRestoreAlert = true
                                    pendingRestoreURL = nil
                                }
                            } catch {
                                restoreMessage = error.localizedDescription
                                showingRestoreAlert = true
                                pendingRestoreURL = nil
                            }
                        }
                    }
                }
            }
            .alert("Restore", isPresented: $showingRestoreAlert) {
                Button("OK") { restoreMessage = nil }
            } message: {
                Text(restoreMessage ?? "")
            }
            .alert("Set Backup Password", isPresented: $showingPasswordSetup) {
                SecureField("Password", text: $passwordField)
                SecureField("Confirm password", text: $passwordConfirmField)
                Button("Save") { completePasswordSetup() }
                Button("Cancel", role: .cancel) {
                    pendingFolderURL = nil
                }
            } message: {
                Text(passwordError ?? "Choose a password to protect your backups. You'll need this password to restore on any device.")
            }
            .alert("Enter Backup Password", isPresented: $showingRestorePassword) {
                SecureField("Password", text: $passwordField)
                Button("Restore") { completePasswordRestore() }
                Button("Cancel", role: .cancel) {
                    pendingRestoreURL = nil
                }
            } message: {
                Text(passwordError ?? "Enter the password that was used to create this backup.")
            }
            .alert("Change Backup Password", isPresented: $showingChangePassword) {
                SecureField("New password", text: $passwordField)
                SecureField("Confirm password", text: $passwordConfirmField)
                Button("Save") { completePasswordChange() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(passwordError ?? "Choose a new password for future backups. Existing backups will still use their original password.")
            }
        }
    }

    private func completePasswordSetup() {
        guard !passwordField.isEmpty else {
            passwordError = "Password cannot be empty."
            showingPasswordSetup = true
            return
        }
        guard passwordField == passwordConfirmField else {
            passwordError = "Passwords don't match. Please try again."
            passwordField = ""
            passwordConfirmField = ""
            showingPasswordSetup = true
            return
        }
        KeychainService.shared.backupPassword = passwordField
        if let url = pendingFolderURL {
            try? backupService.setBackupFolder(url: url)
            refreshBackupState()
            backupService.performBackupNow()
        }
        pendingFolderURL = nil
        passwordField = ""
        passwordConfirmField = ""
        passwordError = nil
    }

    private func completePasswordRestore() {
        guard let url = pendingRestoreURL else { return }
        do {
            let count = try backupService.restoreFromBackup(fileURL: url, password: passwordField)
            restoreMessage = "Restored \(count) card\(count == 1 ? "" : "s") successfully."
            showingRestoreAlert = true
        } catch BackupError.wrongPassword {
            passwordError = "Incorrect password. Please try again."
            passwordField = ""
            showingRestorePassword = true
            return
        } catch {
            restoreMessage = error.localizedDescription
            showingRestoreAlert = true
        }
        pendingRestoreURL = nil
        passwordField = ""
        passwordError = nil
    }

    private func completePasswordChange() {
        guard !passwordField.isEmpty else {
            passwordError = "Password cannot be empty."
            showingChangePassword = true
            return
        }
        guard passwordField == passwordConfirmField else {
            passwordError = "Passwords don't match. Please try again."
            passwordField = ""
            passwordConfirmField = ""
            showingChangePassword = true
            return
        }
        KeychainService.shared.backupPassword = passwordField
        passwordField = ""
        passwordConfirmField = ""
        passwordError = nil
    }

    // MARK: - Sections

    @State private var didCopySharingCode = false

    private var deviceSection: some View {
        Section {
            LabeledContent("Your Sharing Code") {
                Text(appState.deviceId ?? "Not registered")
                    .font(.caption)
                    .monospaced()
                    .lineLimit(1)
            }
            .onLongPressGesture {
                copySharingCode()
            }

            if appState.deviceId != nil {
                Button {
                    copySharingCode()
                } label: {
                    Label(didCopySharingCode ? "Copied!" : "Copy Sharing Code",
                          systemImage: didCopySharingCode ? "checkmark" : "doc.on.doc")
                }
            }

        } header: {
            Label("Your Device", systemImage: "iphone")
                .foregroundStyle(Color.mp.ocean)
                .fontWeight(.medium)
        } footer: {
            Text("Share this code with someone who wants to send you a card directly. It's like a phone number for this app.")
        }
    }

    private func copySharingCode() {
        guard let deviceId = appState.deviceId else { return }
        UIPasteboard.general.string = deviceId
        withAnimation { didCopySharingCode = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { didCopySharingCode = false }
        }
    }

    private var recoverySection: some View {
        Section {
            NavigationLink {
                RecoveryQRView()
            } label: {
                HStack {
                    Label("Emergency Recovery QR", systemImage: "lock.shield")
                    Spacer()
                    if RecoveryService.shared.hasRecoveryKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }

            if let lastUpdated = RecoveryService.shared.lastUpdated {
                LabeledContent("Last Updated") {
                    Text(lastUpdated, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Recovery", systemImage: "lock.shield")
                .foregroundStyle(Color.mp.ocean)
                .fontWeight(.medium)
        } footer: {
            Text("Save this QR code offline. If you lose this device and iCloud access, it's the only way to recover your cards.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("App", value: "MyPass")
            LabeledContent("Version", value: "1.0.0")
            .padding(.vertical, 4)
        } header: {
            Label("About", systemImage: "info.circle")
                .foregroundStyle(Color.mp.ocean)
                .fontWeight(.medium)
        } footer: {
            Text("While this app is designed to work offline most of the time, it does occasionally need to reach out to a server — to sync cards in an encrypted manner with others you have granted access to, to send anonymous crash log data, or to fetch remote configuration items the app requires.")
        }
    }

    private var backupSection: some View {
        Section {
            if hasBackupFolder {
                LabeledContent("Folder") {
                    Text(backupFolderName ?? "Unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let date = lastBackupDate {
                    LabeledContent("Last Backup") {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = lastBackupError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Button {
                    backupService.performBackupNow()
                    // Refresh after a short delay to show updated timestamp
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        refreshBackupState()
                    }
                } label: {
                    Label("Back Up Now", systemImage: "arrow.clockwise")
                }

                Button {
                    activeFilePicker = .restore
                } label: {
                    Label("Restore from Backup", systemImage: "arrow.counterclockwise")
                }

                Button {
                    passwordField = ""
                    passwordConfirmField = ""
                    passwordError = nil
                    showingChangePassword = true
                } label: {
                    Label("Change Backup Password", systemImage: "key")
                }

                Button {
                    activeFilePicker = .folder
                } label: {
                    Label("Change Backup Folder", systemImage: "folder")
                }

                Button(role: .destructive) {
                    showingDisableConfirmation = true
                } label: {
                    Label("Disable Backups", systemImage: "xmark.circle")
                }
            } else {
                Text("Encrypted backups are protected with a password you choose. You can restore them on any device — no account needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    activeFilePicker = .folder
                } label: {
                    Label("Choose Backup Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    activeFilePicker = .restore
                } label: {
                    Label("Restore from Backup", systemImage: "arrow.counterclockwise")
                }
            }
        } header: {
            Label("Backups", systemImage: "arrow.clockwise.icloud")
                .foregroundStyle(Color.mp.ocean)
                .fontWeight(.medium)
        } footer: {
            Text("Up to \(BackupService.maxBackups) backups are kept. Backups run automatically when the app opens and when cards change. Remember your backup password — it's the only way to restore.")
        }
    }

    private func refreshBackupState() {
        hasBackupFolder = backupService.hasBackupFolder
        backupFolderName = backupService.backupFolderName
        lastBackupDate = backupService.lastBackupDate
        lastBackupError = backupService.lastBackupError
    }

    private var dangerZoneSection: some View {
        Section {
            Button("Reset This Device", role: .destructive) {
                showingResetConfirmation = true
            }
        } header: {
            Label("Advanced", systemImage: "gearshape.2")
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
        } footer: {
            Text("This will unlink this device and create a new sharing code. Only use this if you're having trouble connecting to the server.")
        }
    }
}

// MARK: - Document Picker Wrappers

/// Picks a folder using UIDocumentPickerViewController.
private struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}

/// Picks a file for restore using UIDocumentPickerViewController.
private struct RestoreFilePicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
