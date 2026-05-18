# MyPass

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%2026%2B-blue)]()
[![Swift](https://img.shields.io/badge/swift-5.0-orange)]()

A zero-knowledge encrypted profile-card iOS app, built in SwiftUI for iOS 26+. Originally designed for families to share autism awareness cards (communication method, sensory profile, meltdown support, medications, emergency contacts) with carers, teachers, and first responders — but the architecture generalises to any "encrypted profile you want to share with specific people" use case.

All card data is encrypted on-device using AES-256-GCM. The server never sees plaintext. Sharing is brokered through ECDH key agreement: only authorised devices can unwrap a card's key.

This is the iOS client for [MyPass-Server](https://github.com/jusso-dev/MyPass-Server) (Rust + Axum + PostgreSQL).

## How it works

### Card owners

1. **Create** a card with whichever fields apply (communication, sensory, behaviour, medical, emergency contact, free-form notes).
2. **Everything is encrypted on your device** before it leaves. The server stores only ciphertext.
3. **Share** with trusted people via their device ID or a time-limited QR code.
4. **Revoke** access at any time. After revoking, rotate the card's encryption key so revoked devices cannot decrypt future updates.

### Subscribers

1. **Receive** a shared card via device ID or by scanning the owner's QR code.
2. **View** the decrypted card. Your device unwraps the card's AES key with your private ECDH key.
3. **Get notified** when the card is updated, deleted, or your access expires (via APNs).

## Architecture

```
+------------------+                    +------------------+
|   iOS Device A   |   encrypted blob   |   MyPass Server  |
|   (card owner)   | -----------------> |   (Rust / Axum)  |
|                  |                    |                  |
|  AES-256-GCM     |   ECDH-wrapped key |  Stores only:    |
|  P-256 keypair   | -----------------> |  - ciphertext    |
|  Keychain        |                    |  - wrapped keys  |
+------------------+                    |  - HMAC hashes   |
                                        +------------------+
+------------------+                           |
|   iOS Device B   |   encrypted blob          |
|   (subscriber)   | <-------------------------|
|                  |
|  ECDH unwrap     |
|  AES-256-GCM     |
|  decrypt         |
+------------------+
```

The server is a dumb blob relay — storage and key exchange only, zero knowledge of card contents. Identity is a device P-256 keypair, not a user account.

## Security model

| Concern | Approach |
|---------|----------|
| Card encryption | AES-256-GCM, random 256-bit key per card |
| Key storage | iOS Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` for device keys; iCloud-syncing items for cross-device recovery |
| Device identity | P-256 keypair generated on first launch |
| Card ownership | HMAC-SHA256 of a 32-byte client-generated secret. Raw secret in Keychain only; server stores hash; constant-time comparison |
| Sharing | ECDH-P256: owner wraps the card AES key with each recipient's public key via an ephemeral keypair |
| Key rotation | After revoking a subscriber, owner re-encrypts the card with a new AES key and re-wraps for remaining subscribers (atomic server transaction) |
| Share links | Time-limited, use-limited URL-safe random tokens. **Decryption key lives in the URL fragment (`#key`) and never reaches the server** |
| Biometric gate | Face ID / Touch ID prompt before decrypting card contents (configurable) |
| Recovery | Optional iCloud-Keychain-backed recovery blob lets you restore cards on a new device |
| Transport | HTTPS in production. ATS exception in `Info.plist` is for local-network development only — remove for App Store builds |

No accounts. No passwords. No JWTs. No sessions. The device's P-256 public key is its identity.

## Card data fields

Cards ship with a schema tailored to autism awareness:

| Section | Fields |
|---------|--------|
| Personal | Name, date of birth, diagnosis |
| Communication | Method (verbal, AAC, Auslan, PECS, …), notes |
| Sensory profile | Seeks, avoids, stimming behaviours |
| Behaviour & regulation | Signs of overwhelm, meltdown support, shutdown support, calming strategies, elopement risk |
| Routines & interests | Routine needs, special interests, safe foods |
| Medical | Medications, allergies, co-occurring conditions |
| Emergency contact | Name, relationship, phone |
| Notes | Free-form |

The card schema is versioned and decoders are forward-compatible: new fields in future versions still decode old ciphertexts cleanly.

## Tech stack

| Layer | Technology |
|-------|------------|
| UI | SwiftUI (iOS 26+), `@Observable` MVVM, `@UIApplicationDelegateAdaptor` for push |
| Crypto | CryptoKit — AES-256-GCM, P-256 + ECDH, HKDF, HMAC |
| Storage | iOS Keychain via Security framework |
| Networking | URLSession with async/await |
| QR codes | CoreImage `CIQRCodeGenerator` (generate), `AVCaptureMetadataOutput` (scan) |
| Push | APNs (silent + alert) via `UNUserNotificationCenter` |
| Backup | iCloud Keychain sync + optional encrypted file export |
| Server | [MyPass-Server](https://github.com/jusso-dev/MyPass-Server) (Rust, Axum, PostgreSQL) |

**No external Swift package dependencies** — pure Apple SDKs.

## Requirements

- Xcode 17+
- iOS 26.2+ deployment target
- A running instance of [MyPass-Server](https://github.com/jusso-dev/MyPass-Server)

## Getting started

### 1. Start the server

```bash
git clone https://github.com/jusso-dev/MyPass-Server
cd MyPass-Server
cp .env.example .env
# Fill in HMAC_KEY (openssl rand -hex 32) and POSTGRES_PASSWORD
docker compose up -d
```

### 2. Configure signing

Open `MyPass.xcodeproj` in Xcode. The project ships with an empty `DEVELOPMENT_TEAM` — pick your own team under the project's *Signing & Capabilities* tab for each target (MyPass, MyPassTests, MyPassUITests). Bundle ID is `dev.jusso.mypass` — change if you want to ship under your own identifier.

### 3. Run

Build and run on the simulator (defaults to `http://localhost:3000`). For a physical device, open the in-app **Settings** screen and point it at your Mac's local IP (e.g. `http://192.168.1.x:3000`).

### 4. Create a card

Tap **+** on the My Cards tab, fill in whatever applies, tap **Create**. The card is encrypted on-device; only the ciphertext leaves the simulator.

## Project structure

```
MyPass/
├── MyPassApp.swift                 App entry, AppDelegate for APNs
├── ContentView.swift               Root loading / error / main routing
├── Theme.swift                     Colour palette and shared style modifiers
├── Info.plist                      ATS exceptions for local dev, URL scheme
│
├── Models/
│   ├── APIModels.swift             Request/response types for server endpoints
│   └── CardData.swift              Plaintext card struct, schema-tolerant Codable
│
├── Services/
│   ├── APIClient.swift             URLSession async/await client
│   ├── CryptoService.swift         P-256, AES-GCM, ECDH (CryptoKit)
│   ├── KeychainService.swift       Keychain wrapper for secrets and keys
│   ├── PushNotificationService.swift  APNs registration + payload routing
│   ├── BackupService.swift         Encrypted file export + import
│   ├── CacheService.swift          On-device decrypted-card cache (memory + disk)
│   ├── RecoveryService.swift       iCloud-Keychain recovery blob
│   ├── PDFExportService.swift      Print/export decrypted card as PDF
│   └── NetworkMonitor.swift        NWPathMonitor reachability
│
├── ViewModels/
│   ├── AppState.swift              Device registration, global app state
│   ├── CardListViewModel.swift
│   ├── CardEditorViewModel.swift
│   ├── SharedCardsViewModel.swift
│   └── ShareFlowViewModel.swift
│
└── Views/
    ├── MainTabView.swift
    ├── CardListView.swift          Owned cards, context-menu actions
    ├── CardDetailView.swift        Decrypted card display
    ├── CardEditorView.swift        Form editor
    ├── SharedCardsView.swift       Cards shared with this device
    ├── SharedCardDetailView.swift  Subscriber view with role badge
    ├── ShareCardView.swift         Share by device ID or QR
    ├── ScanQRCodeView.swift        Camera QR scanner
    └── SettingsView.swift          Server URL, biometric gate, device reset
```

## Design

A warm light-blue palette designed to feel approachable for families in stressful situations:

- **Sky** `#87CEEB` — Avatar backgrounds, accents
- **Ocean** `#409CC2` — Primary brand, section headers, tint
- **Deep Blue** `#296B8F` — Headings, card names
- **Soft White** `#FAFCFF` — Card backgrounds
- **Sky Faint** `#E8F5FE` — Screen backgrounds

Cards use rounded corners, soft shadows, and coloured section icons to make information easy to scan when a carer is dealing with a high-arousal moment.

## License

MIT — see [LICENSE](LICENSE).
