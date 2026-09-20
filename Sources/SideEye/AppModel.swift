import AppKit
import Combine
import SideEyeCore

enum CameraAccess { case unknown, granted, denied }

/// Wires camera → engine → shield and exposes live state to the popover.
final class AppModel: ObservableObject {
    let settings = Settings()
    let tracker = CameraTracker()
    let shield = ShieldController()

    @Published private(set) var output = ShieldOutput.clear
    @Published private(set) var faces: [DetectedFace] = []
    @Published private(set) var cameraAccess = CameraAccess.unknown

    private var engine: ShieldEngine
    /// Screen locked or asleep: nothing to protect, so the camera is released.
    private var suspended = false
    private var subscriptions: Set<AnyCancellable> = []
    /// `--log`: appends one line per analysed frame to ~/Library/Logs/SideEye.log for tuning.
    private let log: FileHandle? = {
        guard CommandLine.arguments.contains("--log") else { return nil }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SideEye.log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try? FileHandle(forWritingTo: url)
    }()

    init() {
        engine = ShieldEngine(config: settings.engineConfig, center: settings.savedCenter)
        shield.maxRadius = settings.blurStrength

        tracker.onFaces = { [weak self] faces, time in self?.handle(faces, at: time) }

        // Settings publish on willSet, so read them on the next runloop turn.
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.settingsChanged() }
            .store(in: &subscriptions)

        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let suspend = Publishers.Merge(
            workspace.publisher(for: NSWorkspace.screensDidSleepNotification),
            distributed.publisher(for: Notification.Name("com.apple.screenIsLocked"))
        ).map { _ in true }
        let resume = Publishers.Merge(
            workspace.publisher(for: NSWorkspace.screensDidWakeNotification),
            distributed.publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
        ).map { _ in false }
        Publishers.Merge(suspend, resume)
            .receive(on: RunLoop.main)
            .sink { [weak self] suspended in
                self?.suspended = suspended
                self?.settingsChanged()
            }
            .store(in: &subscriptions)
    }

    func start() {
        CameraTracker.requestAccess { [weak self] granted in
            guard let self else { return }
            cameraAccess = granted ? .granted : .denied
            if granted, settings.enabled { tracker.start() }
        }
    }

    func toggleEnabled() {
        settings.enabled.toggle()
    }

    func recenter() {
        engine.recenter()
        settings.savedCenter = engine.center
    }

    private func handle(_ faces: [DetectedFace], at time: TimeInterval) {
        guard settings.enabled, !suspended else { return }
        let output = engine.process(faces: faces.map(\.sample), at: time)
        self.faces = faces
        self.output = output
        if let log {
            let poses = faces.map { String(format: "(yaw %.1f pitch %.1f roll %.1f area %.4f x %.3f y %.3f)", $0.sample.yaw, $0.sample.pitch, $0.roll, $0.sample.area, $0.box.midX, $0.box.midY) }
            let line = String(format: "%.2f level %.2f %@ ", time, output.level, output.reason.rawValue) + (output.sweepToward.map { String(format: "toward(%.2f,%.2f) ", $0.dx, $0.dy) } ?? "") + poses.joined(separator: " ") + "\n"
            log.write(Data(line.utf8))
        }
        shield.setTarget(level: output.level, reason: output.reason, sweepToward: output.sweepToward)
    }

    private func settingsChanged() {
        engine.config = settings.engineConfig
        shield.maxRadius = settings.blurStrength
        guard cameraAccess == .granted else { return }
        if settings.enabled, !suspended {
            tracker.start()
        } else {
            tracker.stop()
            shield.clear()
            output = .clear
            faces = []
            // Fresh timing state so resuming doesn't read the pause as an absence, and a
            // fresh auto-calibration: posture after a break is rarely the same as before it.
            engine = ShieldEngine(config: settings.engineConfig, center: settings.savedCenter)
        }
    }
}
