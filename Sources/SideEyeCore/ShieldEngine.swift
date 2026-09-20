import Foundation

/// One detected face in a camera frame. Angles are degrees, `area` is the
/// bounding-box area as a fraction of the frame (0…1).
public struct FaceSample: Equatable, Sendable {
    public var yaw: Double
    public var pitch: Double
    public var area: Double

    public init(yaw: Double, pitch: Double, area: Double) {
        self.yaw = yaw
        self.pitch = pitch
        self.area = area
    }
}

public struct ShieldConfig: Equatable, Sendable {
    /// Degrees of head movement allowed before any blur appears.
    public var comfortZone = 15.0
    /// Deviation at which the blur is complete.
    public var fullAngle = 30.0
    /// Once shielded, the comfort threshold shrinks by this much so the edge doesn't chatter.
    public var hysteresis = 2.0
    /// Pitch is noisier than yaw and glancing at the keyboard is normal, so it counts for less.
    public var pitchWeight = 0.6
    /// Time constant (seconds) of the exponential smoothing applied to the head pose.
    public var smoothingTau = 0.12

    public var lookAwayEnabled = true

    public var absentEnabled = true
    public var absentDelay = 0.4

    public var intruderEnabled = true
    /// Smallest extra face that counts as someone who could read the screen.
    public var intruderMinArea = 0.003
    /// An extra face must persist this long; single-frame detections are usually false positives.
    public var intruderConfirm = 0.2
    /// Keep the shield up this long after the intruder was last seen.
    public var intruderHold = 1.5

    /// Auto-calibration adopts the mean pose once it has stayed this steady for this long.
    public var calibrationWindow = 1.0
    public var calibrationMaxYawRange = 6.0
    public var calibrationMaxPitchRange = 10.0
    /// The camera sits on the screen, so a steady pose far off-axis is someone looking elsewhere.
    public var calibrationMaxYaw = 20.0

    public init() {}
}

public enum ShieldReason: String, Equatable, Sendable {
    case none, lookingAway, absent, intruder
}

public struct ShieldOutput: Equatable, Sendable {
    /// Target blur level, 0 (clear) … 1 (fully shielded).
    public var level: Double
    public var reason: ShieldReason
    /// Smoothed head offset from the calibrated center, if a face is visible.
    public var yawOffset: Double?
    public var pitchOffset: Double?
    public var faceCount: Int
    /// True while a face is visible but no center pose has been established yet.
    public var calibrating = false

    public static let clear = ShieldOutput(level: 0, reason: .none, yawOffset: nil, pitchOffset: nil, faceCount: 0)
}

public struct HeadPose: Equatable, Sendable {
    public var yaw: Double
    public var pitch: Double

    public init(yaw: Double, pitch: Double) {
        self.yaw = yaw
        self.pitch = pitch
    }
}

/// Turns a stream of per-frame face detections into a blur level.
/// Pure logic: no camera, no UI, caller supplies the clock.
public struct ShieldEngine: Sendable {
    public var config: ShieldConfig
    /// Head pose that means "looking at the screen". Nil until auto-calibration
    /// has seen a steady, roughly on-axis pose (or `recenter()` is called).
    public var center: HeadPose?

    private var smoothed: HeadPose?
    private var firstTime: TimeInterval?
    private var lastTime: TimeInterval?
    private var lastSeen: TimeInterval?
    private var awayActive = false
    private var awayLevel = 0.0
    private var intruderSince: TimeInterval?
    private var intruderUntil: TimeInterval?
    private var calibrationSamples: [(time: TimeInterval, pose: HeadPose)] = []

    /// A gap this long without a face means the old smoothed pose is stale.
    private let staleGap = 0.5

    public init(config: ShieldConfig = ShieldConfig(), center: HeadPose? = nil) {
        self.config = config
        self.center = center
    }

    /// Makes the current head pose the new "looking at the screen" reference.
    public mutating func recenter() {
        center = smoothed
        awayActive = false
        awayLevel = 0
    }

    public mutating func process(faces: [FaceSample], at time: TimeInterval) -> ShieldOutput {
        let dt = lastTime.map { max(0, time - $0) } ?? 0
        lastTime = time
        if firstTime == nil { firstTime = time }

        let sorted = faces.sorted { $0.area > $1.area }
        let intruder = intruderActive(others: sorted.dropFirst(), at: time)

        var absent = false
        var offsets: (yaw: Double, pitch: Double)?
        if let primary = sorted.first {
            offsets = track(primary, dt: dt, at: time)
        } else {
            calibrationSamples.removeAll()
            let missingFor = time - (lastSeen ?? firstTime ?? time)
            absent = config.absentEnabled && missingFor >= config.absentDelay
            // Otherwise hold `awayLevel`: a head turned past ~60° drops out of
            // detection, and that must not read as "looking at the screen".
        }

        let away = config.lookAwayEnabled ? awayLevel : 0
        let level: Double
        let reason: ShieldReason
        if intruder {
            (level, reason) = (1, .intruder)
        } else if absent {
            (level, reason) = (1, .absent)
        } else if away > 0 {
            (level, reason) = (away, .lookingAway)
        } else {
            (level, reason) = (0, .none)
        }
        return ShieldOutput(
            level: level,
            reason: reason,
            yawOffset: offsets?.yaw,
            pitchOffset: offsets?.pitch,
            faceCount: faces.count,
            calibrating: center == nil && !faces.isEmpty
        )
    }

    private mutating func track(_ face: FaceSample, dt: Double, at time: TimeInterval) -> (yaw: Double, pitch: Double)? {
        let stale = lastSeen.map { time - $0 > staleGap } ?? true
        lastSeen = time

        var pose = HeadPose(yaw: face.yaw, pitch: face.pitch)
        if let previous = smoothed, !stale {
            let alpha = config.smoothingTau > 0 ? 1 - exp(-dt / config.smoothingTau) : 1
            pose.yaw = previous.yaw + alpha * (face.yaw - previous.yaw)
            pose.pitch = previous.pitch + alpha * (face.pitch - previous.pitch)
        }
        smoothed = pose
        if center == nil { calibrate(with: pose, at: time) }
        guard let reference = center else {
            awayLevel = 0
            awayActive = false
            return nil
        }

        let yawOffset = pose.yaw - reference.yaw
        let pitchOffset = pose.pitch - reference.pitch
        let deviation = max(abs(yawOffset), abs(pitchOffset) * config.pitchWeight)

        let threshold = awayActive ? config.comfortZone - config.hysteresis : config.comfortZone
        let span = max(config.fullAngle - threshold, 0.1)
        awayLevel = min(max((deviation - threshold) / span, 0), 1)
        awayActive = awayLevel > 0
        return (yawOffset, pitchOffset)
    }

    /// Adopts the mean of the last `calibrationWindow` seconds once the pose has been
    /// steady and roughly on-axis. A single frame is not trusted: the first sighting is
    /// often mid-movement (sitting down, clicking the camera permission dialog).
    private mutating func calibrate(with pose: HeadPose, at time: TimeInterval) {
        calibrationSamples.append((time, pose))
        calibrationSamples.removeAll { $0.time < time - config.calibrationWindow }
        guard let first = calibrationSamples.first, time - first.time >= config.calibrationWindow * 0.9 else { return }

        let yaws = calibrationSamples.map(\.pose.yaw)
        let pitches = calibrationSamples.map(\.pose.pitch)
        let meanYaw = yaws.reduce(0, +) / Double(yaws.count)
        let meanPitch = pitches.reduce(0, +) / Double(pitches.count)
        guard yaws.max()! - yaws.min()! <= config.calibrationMaxYawRange,
              pitches.max()! - pitches.min()! <= config.calibrationMaxPitchRange,
              abs(meanYaw) <= config.calibrationMaxYaw
        else { return }
        center = HeadPose(yaw: meanYaw, pitch: meanPitch)
        calibrationSamples.removeAll()
    }

    private mutating func intruderActive(others: ArraySlice<FaceSample>, at time: TimeInterval) -> Bool {
        guard config.intruderEnabled else {
            intruderSince = nil
            intruderUntil = nil
            return false
        }
        if others.contains(where: { $0.area >= config.intruderMinArea }) {
            let since = intruderSince ?? time
            intruderSince = since
            if time - since >= config.intruderConfirm {
                intruderUntil = time + config.intruderHold
            }
        } else {
            intruderSince = nil
        }
        return intruderUntil.map { time < $0 } ?? false
    }
}
