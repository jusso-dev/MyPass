# MyPass

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%2026%2B-blue)]()
[![Swift](https://img.shields.io/badge/swift-5.0-orange)]()

> **Tell the story once. Share it with the people who need to know. Take it back whenever you want.**

MyPass is an iOS app for parents and carers of autistic children. It exists so a family never has to retell their child's story from scratch to every new teacher, support worker, babysitter, paediatrician, or emergency responder.

You build the card once — *how they communicate, what overwhelms them, what calms them, what they love, what they need* — and share it securely, on your terms, with the people who matter. When the relationship ends, you take the access back.

## The problem this tries to solve

Families of autistic children spend an enormous amount of energy translating their child to the world.

- A new respite carer arrives — you sit down for an hour and explain triggers, stims, communication, routines.
- A new term starts — you write the same email to a new teacher, hoping it reaches the right people.
- A grandparent has the kids overnight — you scribble notes on the fridge about safe foods and meltdown support.
- A paramedic shows up at a crisis — and your child is non-speaking, and there is no time to explain anything.

The information is the same every time. The audience changes. The cost — emotional, physical, repeated — falls on the family.

MyPass lets you write your child's story once, in their voice and yours, and hand it to the people who need it for exactly as long as they need it.

## What a card holds

A MyPass card is structured around what actually matters when someone is trying to support an autistic child:

| Section | What goes in it |
|---------|----------------|
| **Communication** | Verbal, AAC, Auslan, PECS, gestures — and the notes that go with them (e.g. "uses two-word phrases when calm, echolalia when stressed") |
| **Sensory profile** | Seeks (deep pressure, spinning, humming), avoids (loud noises, fluorescent light, tags in clothes), stimming behaviours and what they mean |
| **Behaviour & regulation** | Signs of overwhelm, what helps in a meltdown, what helps in a shutdown, calming strategies that work, elopement risk |
| **Routines & interests** | Routine needs, special interests, safe foods |
| **Medical** | Medications, allergies, co-occurring conditions |
| **Emergency contact** | Who to call, what relationship, what number |
| **Notes** | Anything else the person needs to know |

This is the difference between "my son is autistic" and *"my son understands everything you say, he can't speak when he's overwhelmed, deep pressure helps, do not block exits, and his safe food is plain pasta."*

## How sharing works

MyPass is built so **you control who sees the card and for how long**, and **the server cannot read it**.

### Share by device or QR

- **Share with a known person** by entering their device ID — for partners, grandparents, long-term carers, a school principal.
- **Share with someone new** by generating a QR code with an expiry timer — for a single appointment, a respite weekend, a new aide for a term, an emergency contact at a camp.

### Time-bound by design

Every share is scoped:

- **Permanent share** for someone in your child's life long-term.
- **Time-limited share** that expires automatically (you pick the window — five minutes to a month).
- **Use-limited share** for a QR code (one-time view, or up to ten).

When a share expires, the app tells you, the subscriber's app tells them, and access is gone.

### Revocable, instantly

If a carer leaves, a relationship ends, or you just change your mind — revoke their access. The next thing they try to view will fail. Then **rotate the card's encryption key** so even cached ciphertext on their device becomes unreadable.

### Zero-knowledge by design

The server is a **dumb blob relay**. It holds:

- The encrypted card (it never has the key)
- Per-subscriber wrapped keys (only the subscriber's private key can unwrap them)
- HMAC hashes of ownership secrets (one-way; the originals stay on your device)

Even if the server were fully compromised, a card on the server is just ciphertext. No accounts. No usernames. No emails. No backups of plaintext anywhere.

## Architecture (the short version)

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

Identity is a P-256 keypair held in the device's Secure Enclave. No user accounts, no passwords, no JWTs, no sessions. The public key *is* the identity.

## Security model

| Concern | Approach |
|---------|----------|
| Card encryption | AES-256-GCM with a random 256-bit key per card |
| Key storage | iOS Keychain (`afterFirstUnlockThisDeviceOnly` for device keys; iCloud-syncing items for cross-device recovery) |
| Device identity | P-256 keypair generated on first launch, private key never leaves the device |
| Card ownership | HMAC-SHA256 of a client-generated 32-byte secret; server stores the hash only, constant-time comparison |
| Sharing | ECDH-P256 with an ephemeral keypair: the owner wraps the card AES key for each recipient's public key |
| Key rotation | After revoking a subscriber, the owner re-encrypts the card with a new AES key and re-wraps for remaining subscribers in an atomic server transaction |
| Share links | Time-limited, use-limited URL-safe random tokens. **The decryption key lives in the URL fragment (`#key`) and never reaches the server** |
| Biometric gate | Face ID / Touch ID before decrypting card content |
| Recovery | Optional iCloud-Keychain-backed recovery blob so cards survive a lost or replaced device |
| Transport | HTTPS in production; ATS exception in `Info.plist` is for local-network development only |

## Tech stack

| Layer | Technology |
|-------|------------|
| UI | SwiftUI (iOS 26+), `@Observable` MVVM, `@UIApplicationDelegateAdaptor` for APNs |
| Crypto | CryptoKit — AES-256-GCM, P-256 ECDH, HKDF, HMAC |
| Storage | iOS Keychain (Security framework) |
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

Open `MyPass.xcodeproj` in Xcode. The project ships with an empty `DEVELOPMENT_TEAM` — pick your own team under *Signing & Capabilities* for each target. Bundle ID defaults to `dev.jusso.mypass`.

### 3. Run

Build and run on the simulator (defaults to `http://localhost:3000`). For a physical device, open the in-app **Settings** screen and point it at your Mac's local IP (e.g. `http://192.168.1.x:3000`).

### 4. Create a card

Tap **+** on the My Cards tab. Fill in whatever applies — you don't need to fill everything. Tap **Create**. The card is encrypted on-device; only ciphertext leaves your device.

## Project structure

```
MyPass/
├── MyPassApp.swift                    App entry, AppDelegate for APNs
├── ContentView.swift                  Root loading / error / main routing
├── Theme.swift                        Colour palette and shared style modifiers
├── Info.plist                         ATS exceptions for local dev, URL scheme
│
├── Models/
│   ├── APIModels.swift                Request/response types
│   └── CardData.swift                 Plaintext card struct, schema-tolerant Codable
│
├── Services/
│   ├── APIClient.swift                URLSession async/await client
│   ├── CryptoService.swift            P-256, AES-GCM, ECDH (CryptoKit)
│   ├── KeychainService.swift          Keychain wrapper for secrets and keys
│   ├── PushNotificationService.swift  APNs registration + payload routing
│   ├── BackupService.swift            Encrypted file export + import
│   ├── CacheService.swift             On-device decrypted-card cache (memory + disk)
│   ├── RecoveryService.swift          iCloud-Keychain recovery blob
│   ├── PDFExportService.swift         Print / export decrypted card as PDF
│   └── NetworkMonitor.swift           NWPathMonitor reachability
│
├── ViewModels/
│   ├── AppState.swift                 Device registration, global state
│   ├── CardListViewModel.swift
│   ├── CardEditorViewModel.swift
│   ├── SharedCardsViewModel.swift
│   └── ShareFlowViewModel.swift
│
└── Views/
    ├── MainTabView.swift
    ├── CardListView.swift             Owned cards, context-menu actions
    ├── CardDetailView.swift           Decrypted card display
    ├── CardEditorView.swift           Form editor
    ├── SharedCardsView.swift          Cards shared with this device
    ├── SharedCardDetailView.swift     Subscriber view with role badge
    ├── ShareCardView.swift            Share by device ID or QR
    ├── ScanQRCodeView.swift           Camera QR scanner
    └── SettingsView.swift             Server URL, biometric gate, device reset
```

## Design

The colour palette is warm and low-arousal on purpose. Families using this app are often using it under stress — pickup at school, a meltdown in a supermarket, a new respite worker at the door. The UI is built to be skim-readable, with section icons and clear typography so a stranger can find what they need in seconds.

- **Sky** `#87CEEB` — Avatar backgrounds, accents
- **Ocean** `#409CC2` — Primary brand, section headers, tint
- **Deep Blue** `#296B8F` — Headings, card names
- **Soft White** `#FAFCFF` — Card backgrounds
- **Sky Faint** `#E8F5FE` — Screen backgrounds

## License

MIT — see [LICENSE](LICENSE).
