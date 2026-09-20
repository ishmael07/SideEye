import AVFoundation
import SideEyeCore
import Vision

struct DetectedFace: Equatable {
    var sample: FaceSample
    /// Vision bounding box: normalized, origin bottom-left, unmirrored.
    var box: CGRect
}

/// Webcam → Vision face detection. Frames live only in memory for the duration
/// of one Vision request; nothing is stored or sent anywhere.
final class CameraTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    /// Called on the main queue with every analysed frame.
    var onFaces: (([DetectedFace], TimeInterval) -> Void)?

    private let sessionQueue = DispatchQueue(label: "sideeye.session")
    private let videoQueue = DispatchQueue(label: "sideeye.video", qos: .userInitiated)
    private var configured = false
    private var lastAnalysed: TimeInterval = 0
    // Every camera frame (30 fps source): tracking latency is what makes the blur feel slow.
    private let minFrameInterval = 0.025
    private let minConfidence: Float = 0.5

    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func start() {
        sessionQueue.async { [self] in
            if !configured { configured = configure() }
            if configured, !session.isRunning { session.startRunning() }
        }
    }

    /// Stops capture entirely, so the camera indicator light turns off.
    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() -> Bool {
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device)
        else { return false }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        return true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastAnalysed >= minFrameInterval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        lastAnalysed = now

        // Revision 3 reports continuous yaw/pitch; earlier revisions quantize yaw to 45° steps.
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        guard (try? handler.perform([request])) != nil else { return }

        let faces = (request.results ?? [])
            .filter { $0.confidence >= minConfidence }
            .map { observation in
                DetectedFace(
                    sample: FaceSample(
                        yaw: degrees(observation.yaw),
                        pitch: degrees(observation.pitch),
                        area: Double(observation.boundingBox.width * observation.boundingBox.height),
                        roll: degrees(observation.roll)
                    ),
                    box: observation.boundingBox
                )
            }
        DispatchQueue.main.async { [weak self] in self?.onFaces?(faces, now) }
    }

    private func degrees(_ radians: NSNumber?) -> Double {
        (radians?.doubleValue ?? 0) * 180 / .pi
    }
}
