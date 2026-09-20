# SideEye — design

Webcam-based privacy shield for macOS. Blurs every display when the owner looks
away, leaves, or when a second face appears in frame. Answer to Shyglass
(AirPods head tracking, $3.99): no hardware needed, and it can see shoulder surfers.

Scope for v1: reel demo on the author's Mac (M1, macOS 26, Command Line Tools only,
no Xcode). No licensing, notarization or distribution.

## Units

| Unit | Responsibility | Depends on |
|---|---|---|
| `SideEyeCore.ShieldEngine` | Pure logic: face samples + timestamps in, blur level 0…1 + reason out | Foundation only |
| `CameraTracker` | AVCaptureSession (640×480) → Vision face rectangles (rev 3: continuous yaw/pitch) → `[DetectedFace]` at ≤15 fps | AVFoundation, Vision |
| `ShieldController` | One click-through overlay window per screen at shielding level; eases displayed level toward the target at 60 Hz; live blur via `CGSSetWindowBackgroundBlurRadius` (dlsym), `NSVisualEffectView` fallback | AppKit |
| `AppModel` | Wires tracker → engine → shield; owns settings, pause, recenter | all of the above |
| `PopoverView` | Menu-bar popover: live preview with face boxes, yaw gauge, toggles, sliders | SwiftUI |
| `HotKeys` | Global ⌃⌥S (toggle) and ⌃⌥C (recenter) via Carbon; no Accessibility permission | Carbon |

## Engine rules

- Primary face = largest bounding box. Yaw/pitch exponentially smoothed (τ ≈ 0.12 s).
- Center pose auto-calibrates on first sighting; `recenter()` resets it.
- Deviation = max(|Δyaw|, |Δpitch| × 0.6). Level ramps 0→1 between `comfortZone`
  and `fullAngle`; once active, the comfort threshold drops by `hysteresis` degrees.
- No face for `absentDelay` (0.4 s) → level 1, reason `absent`. During the grace
  window the last look-away level is held.
- Any non-primary face with area ≥ `intruderMinArea`, seen continuously for
  `intruderConfirm` (0.2 s) → level 1, reason `intruder`, held `intruderHold`
  (1.5 s) after it disappears.
- Reason priority: intruder > absent > lookingAway. Each trigger can be disabled.

## Privacy

Frames are processed in memory on-device and never stored or sent anywhere.
Pausing stops the capture session (camera light off).

## Build

SwiftPM package; `make app` assembles `build/SideEye.app` (Info.plist with
`LSUIElement` + `NSCameraUsageDescription`) and ad-hoc signs it.

## Testing

Swift Testing unit tests over `ShieldEngine` (XCTest is unavailable without Xcode).
`--demo` launch argument sweeps the shield without the camera for visual checks.

## Deferred

Eyes-only glance detection from pupil landmarks (experimental toggle) — after the
head-pose core is tuned on real footage.
