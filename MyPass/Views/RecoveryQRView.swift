import SwiftUI
import CoreImage.CIFilterBuiltins

struct RecoveryQRView: View {
    private let recovery = RecoveryService.shared

    @State private var didSaveToPhotos = false
    @State private var saveError: String?
    @State private var showingSaveError = false

    var body: some View {
        ZStack {
            Color.mp.skyFaint.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.mp.ocean)
                        .accessibilityHidden(true)

                    Text("Emergency Recovery QR")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.mp.deepBlue)

                    Text("Save this QR code somewhere safe. If you ever lose access to this device and iCloud, you can use it to recover your cards.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let url = recovery.recoveryURL,
                       let qrImage = generateQRCode(from: url) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 240, height: 240)
                            .padding()
                            .background(Color.white)
                            .clipShape(.rect(cornerRadius: 16))
                            .shadow(color: Color.mp.ocean.opacity(0.1), radius: 8, y: 4)
                            .accessibilityLabel("Emergency recovery QR code")

                        Button {
                            saveToPhotos(qrImage)
                        } label: {
                            Label(didSaveToPhotos ? "Saved to Photos" : "Save to Photos",
                                  systemImage: didSaveToPhotos ? "checkmark.circle.fill" : "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(didSaveToPhotos ? .green : Color.mp.ocean)
                        .padding(.horizontal)
                    } else {
                        ContentUnavailableView {
                            Label("Not Available", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text("Create a card first to generate your recovery QR code.")
                        }
                    }

                    if let lastUpdated = recovery.lastUpdated {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text("Last updated: ")
                            Text(lastUpdated, style: .relative)
                            Text("ago")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Keep this QR code private", systemImage: "eye.slash")
                        Label("Anyone with this code can access your cards", systemImage: "exclamationmark.triangle")
                        Label("Save a screenshot or print it for safekeeping", systemImage: "printer")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.mp.ocean.opacity(0.05))
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(.horizontal)
                }
                .padding()
            }
        }
        .navigationTitle("Recovery QR")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Save Error", isPresented: $showingSaveError) {
            Button("OK") {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func saveToPhotos(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        withAnimation { didSaveToPhotos = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { didSaveToPhotos = false }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = 10.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
