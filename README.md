# SideEye 👀

**A privacy screen for your Mac that uses the webcam you already have.** Your screen blurs when:

- **you look away**: the blur sweeps in from the side you turned away from, so the part you can still see stays readable
- **you walk away**: no face in frame, no screen
- **someone side-eyes you**: a second face appears behind you and everything hides

No AirPods, no subscription, no account. Free and open source (MIT).

**[Website and live demo](https://ishmael07.github.io/SideEye/)** · **[Download](https://github.com/ishmael07/SideEye/releases/latest)**

## Install

macOS 14 (Sonoma) or later, Apple silicon or Intel.

```sh
curl -fsSL https://raw.githubusercontent.com/ishmael07/SideEye/main/install.sh | bash
```

That puts the latest release in `/Applications` and opens it ([read the script](install.sh) first if you like).

Or by hand: download [`SideEye.dmg`](https://github.com/ishmael07/SideEye/releases/latest/download/SideEye.dmg), open it, drag
SideEye to Applications and open it. SideEye isn't notarized by Apple yet, so macOS blocks the first launch of a
browser download: try to open it once, dismiss the warning, then open **System Settings → Privacy & Security** and choose
**Open Anyway**. (Or clear the flag yourself: `xattr -dr com.apple.quarantine /Applications/SideEye.app`.)

SideEye lives in the menu bar (the eye icon). macOS asks for camera access on first launch.

## Use

| | |
|---|---|
| Menu-bar eye | live preview, triggers, comfort zone, fade distance, blur strength |
| ⌃⌥C | recenter: look at your screen, then press |
| ⌃⌥S | pause or resume (the camera turns off while paused) |

It calibrates itself in the first second you face the screen, and slowly follows changes in posture after that.

## Privacy

- Face tracking runs on-device with Apple's Vision framework. Frames live in memory for a few milliseconds and are never saved.
- There is no network code in the app. No account, no analytics, no updates phoning home.
- It never looks at your screen: the blur is done by the macOS window server, so SideEye doesn't need (or ask for) Screen Recording permission.
- The camera is off while SideEye is paused, the Mac is locked, or the display is asleep.

## How it works

`Sources/SideEyeCore` is a pure-logic engine with unit tests: face samples in, blur level and direction out
(smoothing, comfort zone with hysteresis, absence and intruder timing, auto-calibration, drift tracking).
`Sources/SideEye` is the app: AVFoundation capture → Vision face rectangles (yaw, pitch, roll) → engine →
a click-through overlay window per display.

The overlay uses two private macOS mechanisms, resolved at runtime with fallbacks: a window-server-aware
`CABackdropLayer` with a `variableBlur` filter for the directional blur, and `CGSSetWindowBackgroundBlurRadius`
if that is unavailable, then `NSVisualEffectView`. Because of them SideEye can't go on the Mac App Store, and a
future macOS could change how the blur looks.

## Build from source

Needs only the Xcode Command Line Tools.

```sh
make run       # build build/SideEye.app (ad-hoc signed) and launch it
make test      # engine unit tests
make demo      # sweep the shield through every state without using the camera
make release   # universal (Apple silicon + Intel) build/SideEye.dmg and SideEye.zip
```

Rebuilding changes the ad-hoc signature, so macOS asks for camera access again after each build.
Debug flags: `--log` (per-frame poses to `~/Library/Logs/SideEye.log`), `--popover`, `--snapshot <png>`.

## The website

`site/` is a static page with an interactive demo: the same blur rules as the app, a rigged 3D person in the
camera preview, and a "My camera" mode that runs MediaPipe face tracking in the browser. Serve it with
`python3 -m http.server -d site`. `site/dev/test-camera.sh` tests the camera mode against a synthetic webcam feed;
`site/dev/make-avatar.py` converts a Rocketbox avatar for the preview.

## Known limits

- The camera's green light stays on while SideEye is watching. macOS doesn't let apps hide it, and SideEye wouldn't want to.
- Face tracking needs some light. In a dark room it will read you as away.
- Not notarized yet (that needs a paid Apple Developer account), hence the install note above.

## Credits and licence

SideEye is MIT licensed, see [LICENSE](LICENSE). The demo's 3D people come from the
[Microsoft Rocketbox Avatar Library](https://github.com/microsoft/Microsoft-Rocketbox) (MIT) and its fallback head from
MediaPipe's canonical face model (Apache 2.0); see [site/assets/person/CREDITS.md](site/assets/person/CREDITS.md).
