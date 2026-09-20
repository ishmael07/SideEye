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
    /// 1€ filter on the head pose: heavy smoothing while the head is still (kills tracking
    /// jitter), light smoothing while it moves (keeps the blur in step with a real turn).
    public var smoothingMinCutoff = 1.2
    public var smoothingBeta = 0.02
    /// Offsets on the minor axis below this many degrees don't tilt a sweep; pitch noise
    /// would otherwise make a sideways sweep wobble.
    public var sweepAxisDeadband = 8.0

    public var lookAwayEnabled = true
    /// Sweep the blur in from the side opposite a head turn instead of fading the whole screen.
    public var directionalEnabled = true

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
    /// While the screen is clear the center slowly follows the head with this time
    /// constant (seconds), so gradual posture changes don't need a recenter. 0 disables.
    public var driftTau = 60.0

    public init() {}
}

public enum ShieldReason: String, Equatable, Sendable {
    case none, lookingAway, absent, intruder
}

/// Unit vector in screen space (x right, y up) pointing at the part of the screen the
/// viewer is still turned toward. A directional blur enters from the opposite side.
public struct SweepDirection: Equatable, Sendable {
    public var dx: Double
    public var dy: Double

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }
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
    /// Non-nil when `level` is how far a blur front has crossed the screen, leaving
    /// the side the viewer is still turned toward readable.
    /// Nil means `level` is the strength of a whole-screen blur.
    public var sweepToward: SweepDirection?

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
    private var awaySweep: SweepDirection?
    private var recentYaw: [Double] = []
    private var recentPitch: [Double] = []
    private var yawFilter = OneEuroFilter()
    private var pitchFilter = OneEuroFilter()

    /// Sign of Vision's yaw when the viewer turns toward their own left.
    public static let leftTurnYawSign = 1.0
    /// Sign of Vision's pitch when the viewer tilts their head down.
    public static let downTiltPitchSign = 1.0

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
        awaySweep = nil
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
        let sweeps = reason == .lookingAway && config.directionalEnabled
        return ShieldOutput(
            level: level,
            reason: reason,
            yawOffset: offsets?.yaw,
            pitchOffset: offsets?.pitch,
            faceCount: faces.count,
            calibrating: center == nil && !faces.isEmpty,
            sweepToward: sweeps ? awaySweep : nil
        )
    }

    private mutating func track(_ face: FaceSample, dt: Double, at time: TimeInterval) -> (yaw: Double, pitch: Double)? {
        let stale = lastSeen.map { time - $0 > staleGap } ?? true
        lastSeen = time

        if stale {
            recentYaw.removeAll()
            recentPitch.removeAll()
            yawFilter = OneEuroFilter()
            pitchFilter = OneEuroFilter()
        }
        // Median of 3 drops single-frame outliers before the 1€ filter sees them.
        let pose = HeadPose(
            yaw: yawFilter.filter(median3(&recentYaw, face.yaw), dt: dt, minCutoff: config.smoothingMinCutoff, beta: config.smoothingBeta),
            pitch: pitchFilter.filter(median3(&recentPitch, face.pitch), dt: dt, minCutoff: config.smoothingMinCutoff, beta: config.smoothingBeta)
        )
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
        if !awayActive, config.driftTau > 0 {
            let alpha = 1 - exp(-dt / config.driftTau)
            center = HeadPose(yaw: reference.yaw + alpha * yawOffset, pitch: reference.pitch + alpha * pitchOffset)
        }
        awaySweep = awayActive ? sweepDirection(yawOffset: yawOffset, pitchOffset: pitchOffset) : nil
        return (yawOffset, pitchOffset)
    }

    /// Where on the screen the viewer is still turned toward. Turned left → left, tilted
    /// down → bottom. Each axis only counts once it clears the deadband.
    private func sweepDirection(yawOffset: Double, pitchOffset: Double) -> SweepDirection? {
        func beyondDeadband(_ value: Double) -> Double {
            value.sign == .minus ? min(value + config.sweepAxisDeadband, 0) : max(value - config.sweepAxisDeadband, 0)
        }
        let dx = -beyondDeadband(yawOffset) * Self.leftTurnYawSign
        let dy = -beyondDeadband(pitchOffset * config.pitchWeight) * Self.downTiltPitchSign
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return awaySweep }
        return SweepDirection(dx: dx / length, dy: dy / length)
    }

    private func median3(_ recent: inout [Double], _ value: Double) -> Double {
        recent.append(value)
        if recent.count > 3 { recent.removeFirst() }
        return recent.sorted()[recent.count / 2]
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

/// 1€ filter (Casiez et al.): a low-pass whose cutoff rises with the signal's speed.
struct OneEuroFilter: Sendable {
    private var value: Double?
    private var derivative = 0.0
    private let derivativeCutoff = 1.0

    mutating func filter(_ x: Double, dt: Double, minCutoff: Double, beta: Double) -> Double {
        guard let previous = value, dt > 0 else {
            value = x
            return x
        }
        let rate = (x - previous) / dt
        derivative += Self.alpha(cutoff: derivativeCutoff, dt: dt) * (rate - derivative)
        let cutoff = minCutoff + beta * abs(derivative)
        let next = previous + Self.alpha(cutoff: cutoff, dt: dt) * (x - previous)
        value = next
        return next
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}
