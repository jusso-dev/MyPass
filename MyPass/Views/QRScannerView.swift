import SwiftUI
import AVFoundation

/// Camera-based QR code scanner using AVFoundation.
struct QRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onCodeScanned = onCodeScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCodeScanned: ((String) -> Void)?
        private var captureSession: AVCaptureSession?
        private var hasScanned = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            let session = AVCaptureSession()

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                showPermissionDenied()
                return
            }

            if session.canAddInput(input) {
                session.addInput(input)
            }

            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
            }

            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.frame = view.layer.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)

            captureSession = session

            // Add scan frame overlay
            let overlay = UIView()
            overlay.layer.borderColor = UIColor.white.cgColor
            overlay.layer.borderWidth = 2
            overlay.layer.cornerRadius = 12
            overlay.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(overlay)

            NSLayoutConstraint.activate([
                overlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                overlay.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                overlay.widthAnchor.constraint(equalToConstant: 250),
                overlay.heightAnchor.constraint(equalToConstant: 250),
            ])

            Task.detached { [weak session] in
                session?.startRunning()
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            captureSession?.stopRunning()
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !hasScanned,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else { return }

            hasScanned = true
            captureSession?.stopRunning()

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onCodeScanned?(value)
        }

        private func showPermissionDenied() {
            let label = UILabel()
            label.text = "Camera access is required to scan QR codes"
            label.textColor = .white
            label.textAlignment = .center
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)

            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            ])
        }
    }
}

/// Sheet wrapper for QR scanning with title and dismiss.
struct QRScannerSheet: View {
    let onScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QRScannerView { code in
                onScanned(code)
                dismiss()
            }
            .ignoresSafeArea()
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
