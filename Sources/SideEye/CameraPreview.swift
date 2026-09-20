import AVFoundation
import SwiftUI

/// Mirrored live camera feed.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.black.cgColor
        view.layer = layer
        view.wantsLayer = true
        mirror(layer)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // The connection only exists once the session has inputs.
        if let layer = view.layer as? AVCaptureVideoPreviewLayer { mirror(layer) }
    }

    private func mirror(_ layer: AVCaptureVideoPreviewLayer) {
        guard let connection = layer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}

/// Face boxes over the mirrored 4:3 preview: green for the owner, red for anyone else.
struct FaceBoxes: View {
    let faces: [DetectedFace]

    var body: some View {
        GeometryReader { geometry in
            let primary = faces.max { $0.sample.area < $1.sample.area }
            ForEach(Array(faces.enumerated()), id: \.offset) { _, face in
                let box = face.box
                let rect = CGRect(
                    x: (1 - box.maxX) * geometry.size.width,
                    y: (1 - box.maxY) * geometry.size.height,
                    width: box.width * geometry.size.width,
                    height: box.height * geometry.size.height
                )
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(face == primary ? Color.green : Color.red, lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }
}
