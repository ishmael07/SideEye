import AppKit
import SideEyeCore
import SwiftUI

/// What the overlay's SwiftUI badge renders.
final class ShieldPresentation: ObservableObject {
    /// How hidden the screen is overall, 0…1.
    @Published var level: Double = 0
    @Published var reason: ShieldReason = .none
}

/// Owns one click-through overlay window per display and eases the visible blur
/// toward the engine's target.
///
/// Three eased values drive it: `strength` (blur radius where covered), `coverage`
/// (how far the blur front has crossed the screen) and `toward` (the side that stays
/// readable). A whole-screen blur is coverage 1 with varying strength; a sweep is
/// strength 1 with varying coverage. `VariableBlurLayer` renders them with a gradient
/// mask, so the readable side gets exactly zero blur and zero tint.
final class ShieldController {
    /// Blur radius in points at full strength.
    var maxRadius: Double = 48

    private struct Surface {
        let window: NSWindow
        let blur: VariableBlurLayer?
        let tint: CALayer
        let fallback: NSVisualEffectView?
    }

    private let presentation = ShieldPresentation()
    private var surfaces: [Surface] = []
    private var timer: Timer?
    private var lastTick: TimeInterval = 0

    private var coverage = 0.0
    private var strength = 0.0
    private var toward = SweepDirection(dx: -1, dy: 0)
    private var targetCoverage = 0.0
    private var targetStrength = 0.0
    private var targetToward = SweepDirection(dx: -1, dy: 0)
    /// Whether the shield last came up as a sweep, so it also leaves as one.
    private var sweeping = false

    // Shield comes up fast (privacy), clears a little slower (comfort).
    private let attackTau = 0.09
    private let releaseTau = 0.18
    private let turnTau = 0.15
    /// Width of the fade, as a fraction of the distance the front travels. Wide on
    /// purpose: the shield should read as the screen fading to dark, not a moving edge.
    private let frontWidth = 0.55
    /// The visible part of the shield is a fade to near-black; the blur underneath is the
    /// privacy backstop for the part of the fade that is still see-through.
    private let fullTint: Float = 0.8

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildWindows() }
    }

    /// `sweepToward` nil: `level` is the strength of a whole-screen blur. Otherwise `level`
    /// is how far the blur front has crossed the screen, advancing toward that side.
    func setTarget(level: Double, reason: ShieldReason, sweepToward: SweepDirection? = nil) {
        let level = min(max(level, 0), 1)
        if reason != .none { presentation.reason = reason }
        let hidden = coverage * strength < 0.004

        if level == 0 {
            // Leave the way we came: a sweep retreats, a fade fades.
            if sweeping { targetCoverage = 0 } else { targetStrength = 0 }
        } else if let sweepToward, VariableBlurLayer.isAvailable {
            sweeping = true
            targetStrength = 1
            if hidden {
                (toward, targetToward) = (sweepToward, sweepToward)
                (coverage, strength) = (0, 1)
                targetCoverage = level
            } else if coverage < 0.98, toward.dx * sweepToward.dx + toward.dy * sweepToward.dy < 0 {
                // Front is mid-screen coming from the other side: pull it back first.
                targetCoverage = 0
            } else {
                targetToward = sweepToward
                targetCoverage = level
            }
        } else {
            sweeping = false
            if hidden { (coverage, strength) = (1, 0) }
            targetCoverage = 1
            targetStrength = level
        }
        if coverage != targetCoverage || strength != targetStrength || toward != targetToward { startTimer() }
    }

    /// Drops the shield immediately (pause / disable).
    func clear() {
        (coverage, strength, targetCoverage, targetStrength) = (0, 0, 0, 0)
        apply()
    }

    private func startTimer() {
        guard timer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastTick
        lastTick = now
        coverage = eased(coverage, toward: targetCoverage, dt: dt)
        strength = eased(strength, toward: targetStrength, dt: dt)
        turn(dt: dt)

        if coverage == targetCoverage, strength == targetStrength, toward == targetToward {
            timer?.invalidate()
            timer = nil
        }
        apply()
    }

    private func eased(_ value: Double, toward target: Double, dt: Double) -> Double {
        let tau = target > value ? attackTau : releaseTau
        let next = value + (target - value) * (1 - exp(-dt / tau))
        return abs(target - next) < 0.003 ? target : next
    }

    private func turn(dt: Double) {
        let alpha = 1 - exp(-dt / turnTau)
        let dx = toward.dx + (targetToward.dx - toward.dx) * alpha
        let dy = toward.dy + (targetToward.dy - toward.dy) * alpha
        let length = (dx * dx + dy * dy).squareRoot()
        let close = abs(targetToward.dx - dx) < 0.01 && abs(targetToward.dy - dy) < 0.01
        toward = close || length < 0.01 ? targetToward : SweepDirection(dx: dx / length, dy: dy / length)
    }

    private func apply() {
        let hiddenness = coverage * strength
        presentation.level = hiddenness
        if hiddenness <= 0 {
            surfaces.forEach { $0.window.orderOut(nil) }
            return
        }
        if surfaces.isEmpty { rebuildWindows() }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for surface in surfaces {
            if !surface.window.isVisible { surface.window.orderFrontRegardless() }
            if let blur = surface.blur {
                let mask = frontMask(aspect: surface.window.frame.height / surface.window.frame.width)
                blur.update(radius: maxRadius * strength, mask: mask)
                surface.tint.contents = mask
                surface.tint.opacity = fullTint * Float(strength)
            } else if let fallback = surface.fallback {
                fallback.alphaValue = hiddenness
                surface.tint.backgroundColor = NSColor(white: 0.04, alpha: 0.55 * hiddenness).cgColor
            } else {
                WindowBlur.setRadius(Int((maxRadius * hiddenness).rounded()), for: surface.window)
                // The window-server blur only renders under non-transparent pixels.
                surface.tint.backgroundColor = NSColor(white: 0.04, alpha: 0.02 + 0.38 * hiddenness).cgColor
            }
        }
        CATransaction.commit()
    }

    /// Black image whose alpha is the blur amount at each point: 0 on the side the viewer
    /// is turned toward, easing up to 1 across the front, 1 behind it.
    private func frontMask(aspect: Double) -> CGImage? {
        let width = 256.0
        let height = (width * aspect).rounded()
        guard let context = CGContext(
            data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Distances are measured along `away`, from the screen center out to the far side.
        let away = (x: -toward.dx, y: -toward.dy)
        let extent = abs(away.x) * width / 2 + abs(away.y) * height / 2
        let band = frontWidth * 2 * extent
        let start = extent - coverage * (2 * extent + band)
        func point(at distance: Double) -> CGPoint {
            CGPoint(x: width / 2 + away.x * distance, y: height / 2 + away.y * distance)
        }
        // Smootherstep: zero slope at both ends, so the fade has no visible start or end line.
        let stops: [CGFloat] = (0...12).map { CGFloat($0) / 12 }
        let colors = stops.map { t in
            CGColor(red: 0, green: 0, blue: 0, alpha: t * t * t * (t * (t * 6 - 15) + 10))
        } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: stops) else { return nil }
        context.drawLinearGradient(gradient, start: point(at: start), end: point(at: start + band), options: [.drawsAfterEndLocation])
        return context.makeImage()
    }

    private func rebuildWindows() {
        surfaces.forEach { $0.window.orderOut(nil) }
        surfaces = NSScreen.screens.enumerated().map { index, screen in
            makeSurface(for: screen, showsBadge: index == 0)
        }
        if coverage * strength > 0 { apply() }
    }

    private func makeSurface(for screen: NSScreen, showsBadge: Bool) -> Surface {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.backgroundColor = .clear

        let bounds = NSRect(origin: .zero, size: screen.frame.size)
        let container = NSView(frame: bounds)
        container.autoresizingMask = [.width, .height]

        // Layer-hosting view for the blur and tint, kept below the badge.
        let canvas = NSView(frame: bounds)
        canvas.autoresizingMask = [.width, .height]
        canvas.layer = CALayer()
        canvas.wantsLayer = true
        container.addSubview(canvas)

        let blur = VariableBlurLayer.make()
        let tint = CALayer()
        for layer in [blur?.layer, tint].compactMap({ $0 }) {
            layer.frame = bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            canvas.layer?.addSublayer(layer)
        }

        // Last resort when neither private blur is available: whole-screen material blur.
        var fallback: NSVisualEffectView?
        if blur == nil, !WindowBlur.isAvailable {
            let effect = NSVisualEffectView(frame: bounds)
            effect.autoresizingMask = [.width, .height]
            effect.material = .fullScreenUI
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.alphaValue = 0
            container.addSubview(effect)
            fallback = effect
        }
        if showsBadge {
            let badge = NSHostingView(rootView: ShieldBadgeView(presentation: presentation))
            badge.frame = bounds
            badge.autoresizingMask = [.width, .height]
            container.addSubview(badge)
        }
        window.contentView = container
        return Surface(window: window, blur: blur, tint: tint, fallback: fallback)
    }
}
