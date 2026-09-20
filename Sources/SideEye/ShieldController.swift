import AppKit
import SideEyeCore
import SwiftUI

/// What the overlay's SwiftUI badge renders.
final class ShieldPresentation: ObservableObject {
    @Published var level: Double = 0
    @Published var reason: ShieldReason = .none
}

/// Owns one click-through overlay window per display and eases the visible blur
/// toward the engine's target level.
final class ShieldController {
    /// Blur radius in points at level 1.
    var maxRadius: Double = 48

    private let presentation = ShieldPresentation()
    private var windows: [NSWindow] = []
    private var target = 0.0
    private var current = 0.0
    private var timer: Timer?
    private var lastTick: TimeInterval = 0

    // Shield comes up fast (privacy), clears a little slower (comfort).
    private let attackTau = 0.07
    private let releaseTau = 0.16

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildWindows() }
    }

    func setTarget(level: Double, reason: ShieldReason) {
        target = min(max(level, 0), 1)
        if reason != .none { presentation.reason = reason }
        if target != current { startTimer() }
    }

    /// Drops the shield immediately (pause / disable).
    func clear() {
        target = 0
        current = 0
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
        let tau = target > current ? attackTau : releaseTau
        current += (target - current) * (1 - exp(-dt / tau))
        if abs(target - current) < 0.004 {
            current = target
            timer?.invalidate()
            timer = nil
        }
        apply()
    }

    private func apply() {
        if current <= 0 {
            windows.forEach { $0.orderOut(nil) }
            presentation.level = 0
            return
        }
        if windows.isEmpty { rebuildWindows() }
        presentation.level = current
        for window in windows {
            if !window.isVisible { window.orderFrontRegardless() }
            if WindowBlur.setRadius(Int((current * maxRadius).rounded()), for: window) {
                // The blur only renders under non-transparent pixels; the tint also
                // kills bright leftovers that a blur alone lets through.
                window.backgroundColor = NSColor(white: 0.04, alpha: 0.02 + 0.38 * current)
            } else {
                window.backgroundColor = NSColor(white: 0.04, alpha: 0.55 * current)
                window.contentView?.subviews.first?.alphaValue = current
            }
        }
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.enumerated().map { index, screen in
            makeWindow(for: screen, showsBadge: index == 0)
        }
        if current > 0 { apply() }
    }

    private func makeWindow(for screen: NSScreen, showsBadge: Bool) -> NSWindow {
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

        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.autoresizingMask = [.width, .height]

        // Fallback blur when the window-server call is unavailable. Kept first in `subviews`.
        let effect = NSVisualEffectView(frame: container.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .fullScreenUI
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.alphaValue = 0
        effect.isHidden = WindowBlur.isAvailable
        container.addSubview(effect)

        if showsBadge {
            let badge = NSHostingView(rootView: ShieldBadgeView(presentation: presentation))
            badge.frame = container.bounds
            badge.autoresizingMask = [.width, .height]
            container.addSubview(badge)
        }
        window.contentView = container
        return window
    }
}
