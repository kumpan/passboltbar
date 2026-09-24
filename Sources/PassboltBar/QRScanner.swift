import AVFoundation
import SwiftUI
import Vision

/// Reads QR codes from the Mac's camera and reports the first otpauth / otpauth-migration payload.
final class QRScanner: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "PassboltBar.qr")
    private var onCode: ((String) -> Void)?
    private var found = false

    /// Asks for camera access if needed, then starts scanning.
    func start(onCode: @escaping (String) -> Void) async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { throw Self.denied }
        default: throw Self.denied
        }
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CLIError(message: "No camera found.")
        }
        self.onCode = onCode
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        queue.async { self.session.startRunning() }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !found, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(cvPixelBuffer: pixels).perform([request])
        guard let payload = request.results?.compactMap(\.payloadStringValue)
            .first(where: { $0.lowercased().hasPrefix("otpauth") }) else { return }
        found = true
        session.stopRunning()
        DispatchQueue.main.async { self.onCode?(payload) }
    }

    private static let denied = CLIError(message:
        "PassboltBar isn't allowed to use the camera. Turn it on in System Settings → Privacy & Security → Camera.")
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer // layer-hosting view
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Camera viewfinder for scanning Google Authenticator's export QR code.
struct QRScanView: View {
    let onCode: (String) -> Void
    let onCancel: () -> Void
    @State private var scanner = QRScanner()
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.85))
                if let problem {
                    Label(problem, systemImage: "video.slash")
                        .font(.system(size: 12)).foregroundStyle(.white).multilineTextAlignment(.center).padding()
                } else {
                    CameraPreview(session: scanner.session)
                        .scaleEffect(x: -1, y: 1) // mirror, so moving the phone feels natural
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                        .frame(width: 150, height: 150)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("In Google Authenticator on your phone:").font(.system(size: 12, weight: .semibold))
                Text("☰ → Transfer accounts → Export accounts → select only Passbolt → Next. Hold the QR code up to your Mac's camera.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Cancel", action: onCancel).controlSize(.large)
        }
        .task {
            do { try await scanner.start(onCode: onCode) } catch { problem = error.localizedDescription }
        }
        .onDisappear { scanner.stop() }
    }
}
