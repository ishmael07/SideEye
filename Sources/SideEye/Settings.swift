import Foundation
import SideEyeCore

/// User-facing settings, persisted in UserDefaults.
final class Settings: ObservableObject {
    private let defaults: UserDefaults

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var lookAwayEnabled: Bool { didSet { defaults.set(lookAwayEnabled, forKey: "lookAwayEnabled") } }
    @Published var absentEnabled: Bool { didSet { defaults.set(absentEnabled, forKey: "absentEnabled") } }
    @Published var intruderEnabled: Bool { didSet { defaults.set(intruderEnabled, forKey: "intruderEnabled") } }
    /// Blur sweeps in from the side opposite a head turn instead of fading the whole screen.
    @Published var directionalBlur: Bool { didSet { defaults.set(directionalBlur, forKey: "directionalBlur") } }
    /// Degrees of free head movement.
    @Published var comfortZone: Double { didSet { defaults.set(comfortZone, forKey: "comfortZone") } }
    /// Degrees past the comfort zone over which the blur fades in.
    @Published var fadeDistance: Double { didSet { defaults.set(fadeDistance, forKey: "fadeDistance") } }
    /// Blur radius in points at full shield.
    @Published var blurStrength: Double { didSet { defaults.set(blurStrength, forKey: "blurStrength") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "enabled": true,
            "lookAwayEnabled": true,
            "absentEnabled": true,
            "intruderEnabled": true,
            "directionalBlur": true,
            "comfortZone": 15.0,
            "fadeDistance": 35.0,
            "blurStrength": 48.0,
        ])
        enabled = defaults.bool(forKey: "enabled")
        lookAwayEnabled = defaults.bool(forKey: "lookAwayEnabled")
        absentEnabled = defaults.bool(forKey: "absentEnabled")
        intruderEnabled = defaults.bool(forKey: "intruderEnabled")
        directionalBlur = defaults.bool(forKey: "directionalBlur")
        comfortZone = defaults.double(forKey: "comfortZone")
        fadeDistance = defaults.double(forKey: "fadeDistance")
        blurStrength = defaults.double(forKey: "blurStrength")
    }

    var engineConfig: ShieldConfig {
        var config = ShieldConfig()
        config.lookAwayEnabled = lookAwayEnabled
        config.absentEnabled = absentEnabled
        config.intruderEnabled = intruderEnabled
        config.directionalEnabled = directionalBlur
        config.comfortZone = comfortZone
        config.fullAngle = comfortZone + fadeDistance
        return config
    }

    /// Only a manual recenter is saved (for setups where the camera is off to one side);
    /// otherwise every launch auto-calibrates to the current posture.
    var savedCenter: HeadPose? {
        get {
            guard defaults.object(forKey: "centerYaw") != nil else { return nil }
            return HeadPose(yaw: defaults.double(forKey: "centerYaw"), pitch: defaults.double(forKey: "centerPitch"))
        }
        set {
            if let newValue {
                defaults.set(newValue.yaw, forKey: "centerYaw")
                defaults.set(newValue.pitch, forKey: "centerPitch")
            } else {
                defaults.removeObject(forKey: "centerYaw")
                defaults.removeObject(forKey: "centerPitch")
            }
        }
    }
}
