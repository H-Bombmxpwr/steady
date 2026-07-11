import SwiftUI
import AVFoundation

/// Camera barcode scanner for packaged foods (EAN-13/EAN-8/UPC-E/Code128).
/// A center reticle shows where to aim; only codes inside it are read.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        private let session = AVCaptureSession()
        private let output = AVCaptureMetadataOutput()
        private var preview: AVCaptureVideoPreviewLayer?
        private var handled = false

        private let dimLayer = CAShapeLayer()
        private let bracketLayer = CAShapeLayer()
        private let laserLayer = CALayer()
        private let hintLabel = UILabel()

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.ean13, .ean8, .upce, .code128]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)
            self.preview = preview

            // Dim everything outside the scan window (even-odd cutout).
            dimLayer.fillRule = .evenOdd
            dimLayer.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor
            view.layer.addSublayer(dimLayer)

            // Corner brackets around the window.
            bracketLayer.strokeColor = UIColor.white.cgColor
            bracketLayer.fillColor = UIColor.clear.cgColor
            bracketLayer.lineWidth = 4
            bracketLayer.lineCap = .round
            view.layer.addSublayer(bracketLayer)

            // Horizontal "laser" line to line the barcode up against.
            laserLayer.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8).cgColor
            laserLayer.cornerRadius = 1
            view.layer.addSublayer(laserLayer)

            hintLabel.text = "Center the barcode in the frame"
            hintLabel.textColor = .white
            hintLabel.font = .preferredFont(forTextStyle: .subheadline)
            hintLabel.textAlignment = .center
            view.addSubview(hintLabel)

            // rectOfInterest conversion needs a running session; set it once
            // capture actually starts.
            NotificationCenter.default.addObserver(
                self, selector: #selector(sessionStarted),
                name: .AVCaptureSessionDidStartRunning, object: session)

            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }

        /// Scan window: centered, a bit above the middle, barcode-shaped.
        private var scanRect: CGRect {
            let width = min(view.bounds.width * 0.78, 340)
            let height = width * 0.5
            return CGRect(x: (view.bounds.width - width) / 2,
                          y: (view.bounds.height - height) / 2 - 40,
                          width: width, height: height)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
            layoutReticle()
            updateRectOfInterest()
        }

        @objc private func sessionStarted() {
            DispatchQueue.main.async { self.updateRectOfInterest() }
        }

        private func updateRectOfInterest() {
            guard let preview, session.isRunning else { return }
            output.rectOfInterest = preview.metadataOutputRectConverted(fromLayerRect: scanRect)
        }

        private func layoutReticle() {
            let rect = scanRect

            let dimPath = UIBezierPath(rect: view.bounds)
            dimPath.append(UIBezierPath(roundedRect: rect, cornerRadius: 12))
            dimLayer.path = dimPath.cgPath
            dimLayer.frame = view.bounds

            // Four L-shaped corner brackets.
            let len: CGFloat = 26
            let brackets = UIBezierPath()
            for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                     (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                     (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                                     (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
                brackets.move(to: CGPoint(x: corner.x, y: corner.y + dy * len))
                brackets.addLine(to: corner)
                brackets.addLine(to: CGPoint(x: corner.x + dx * len, y: corner.y))
            }
            bracketLayer.path = brackets.cgPath
            bracketLayer.frame = view.bounds

            laserLayer.frame = CGRect(x: rect.minX + 14, y: rect.midY - 1,
                                      width: rect.width - 28, height: 2)

            hintLabel.frame = CGRect(x: 20, y: rect.maxY + 16,
                                     width: view.bounds.width - 40, height: 22)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            session.stopRunning()
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !handled,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = object.stringValue else { return }
            handled = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCode?(code)
        }
    }
}
