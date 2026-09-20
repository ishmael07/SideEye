import SideEyeCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings

    init(model: AppModel) {
        self.model = model
        settings = model.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.cameraAccess == .denied {
                cameraDenied
            } else {
                preview
                YawGauge(
                    offset: model.output.yawOffset,
                    comfortZone: settings.comfortZone,
                    fullAngle: settings.comfortZone + settings.fadeDistance
                )
            }
            Divider()
            triggers
            Divider()
            sliders
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "eyes")
                .font(.system(size: 20, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text("SideEye").font(.system(size: 15, weight: .bold, design: .rounded))
                Text(statusText).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $settings.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var statusText: String {
        guard settings.enabled else { return "Paused · camera off" }
        if model.output.calibrating { return "Calibrating · look at your screen" }
        switch model.output.reason {
        case .none: return model.output.faceCount == 0 ? "Starting…" : "Watching · screen visible"
        case .lookingAway: return "Shielded · you looked away"
        case .absent: return "Shielded · nobody here"
        case .intruder: return "Shielded · someone's looking"
        }
    }

    private var preview: some View {
        ZStack {
            if settings.enabled {
                CameraPreview(session: model.tracker.session)
                FaceBoxes(faces: model.faces)
            } else {
                Color.black
                Label("Camera off", systemImage: "video.slash.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 288, height: 216) // 4:3, matches the capture preset so face boxes line up
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topLeading) {
            if settings.enabled {
                Text(model.output.faceCount == 1 ? "1 face" : "\(model.output.faceCount) faces")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(8)
            }
        }
    }

    private var cameraDenied: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SideEye needs the camera", systemImage: "video.slash.fill")
                .font(.system(size: 13, weight: .semibold))
            Text("Face tracking runs entirely on this Mac. Nothing is recorded or sent anywhere.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("Open Camera Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
            }
        }
    }

    private var triggers: some View {
        VStack(alignment: .leading, spacing: 8) {
            TriggerRow(symbol: "eye.slash.fill", title: "I look away", isOn: $settings.lookAwayEnabled)
            TriggerRow(symbol: "figure.walk", title: "I step away", isOn: $settings.absentEnabled)
            TriggerRow(symbol: "eyes", title: "Someone else looks", isOn: $settings.intruderEnabled)
        }
    }

    private var sliders: some View {
        VStack(alignment: .leading, spacing: 10) {
            TriggerRow(symbol: "rectangle.righthalf.inset.filled", title: "Blur sweeps in as I turn", isOn: $settings.directionalBlur)
                .help("On: the side of the screen you're still turned toward stays readable until you've turned all the way. Off: the whole screen fades at once.")
            LabeledSlider(title: "Comfort zone", value: $settings.comfortZone, range: 5...30, unit: "°")
            LabeledSlider(title: "Fade distance", value: $settings.fadeDistance, range: 5...60, unit: "°")
            LabeledSlider(title: "Blur strength", value: $settings.blurStrength, range: 16...90, unit: "")
        }
    }

    private var footer: some View {
        HStack {
            Button {
                model.recenter()
            } label: {
                Label("Recenter", systemImage: "scope")
            }
            .help("Look at your screen, then click. Shortcut: ⌃⌥C")
            Text("⌃⌥C · ⌃⌥S pause")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }
}

private struct TriggerRow: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Label(title, systemImage: symbol).font(.system(size: 12))
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11))
                Spacer()
                Text("\(Int(value.rounded()))\(unit)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range).controlSize(.small)
        }
    }
}

/// Head-yaw needle over the comfort zone (green) and fade band (amber), ±60°.
private struct YawGauge: View {
    let offset: Double?
    let comfortZone: Double
    let fullAngle: Double

    private let span = 60.0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let scale = width / (span * 2)
            ZStack {
                Capsule().fill(Color.red.opacity(0.35))
                Capsule().fill(Color.orange.opacity(0.6))
                    .frame(width: min(fullAngle, span) * 2 * scale)
                Capsule().fill(Color.green.opacity(0.75))
                    .frame(width: min(comfortZone, span) * 2 * scale)
                if let offset {
                    // Mirrored like the preview: turning your head right moves the needle right.
                    Capsule().fill(.white)
                        .frame(width: 4, height: 14)
                        .shadow(radius: 1.5)
                        .offset(x: min(max(-offset, -span), span) * scale)
                        .animation(.linear(duration: 0.08), value: offset)
                }
            }
            .frame(width: width, height: geometry.size.height)
        }
        .frame(height: 8)
        .padding(.vertical, 3)
    }
}
