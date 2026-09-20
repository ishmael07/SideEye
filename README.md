# SideEye 👀

Webcam privacy shield for macOS. Your screen blurs when:

- **you look away** — progressive blur as your head turns past the comfort zone
- **you step away** — no face in frame
- **someone else looks** — a second face appears behind you

No AirPods, no hardware. Face tracking runs on-device with Apple Vision; frames are
never stored or sent anywhere. The blur is live (video keeps playing underneath) and
needs no Screen Recording permission.

## Build & run

Needs only the Xcode Command Line Tools.

    make run     # build build/SideEye.app, ad-hoc sign, launch
    make test    # engine unit tests
    make demo    # sweep the shield through every state without the camera

Rebuilding changes the ad-hoc signature, so macOS asks for camera access again after each build.

## Use

Menu bar 👁 icon → live preview, triggers, sliders.

| Shortcut | Action |
|---|---|
| ⌃⌥C | Recenter — look at your screen, then press |
| ⌃⌥S | Pause / resume (camera off while paused) |

Debug flags: `--log` (per-frame poses to `~/Library/Logs/SideEye.log`), `--popover`,
`--snapshot <png>` (offscreen render of the popover).
