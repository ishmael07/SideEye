import AppKit
import Carbon.HIToolbox
import Combine
import SideEyeCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private let hotKeys = HotKeys()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.delegate = self
        let controller = NSHostingController(rootView: PopoverView(model: model))
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller

        hotKeys.register(keyCode: kVK_ANSI_S, modifiers: controlKey | optionKey) { [model] in model.toggleEnabled() }
        hotKeys.register(keyCode: kVK_ANSI_C, modifiers: controlKey | optionKey) { [model] in model.recenter() }

        model.$output.map(\.reason).removeDuplicates()
            .combineLatest(model.settings.$enabled)
            .sink { [weak self] reason, enabled in self?.updateIcon(reason: reason, enabled: enabled) }
            .store(in: &subscriptions)

        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
            snapshotPopover(to: CommandLine.arguments[index + 1])
            NSApp.terminate(nil)
        } else if CommandLine.arguments.contains("--demo") {
            runDemo()
        } else {
            model.start()
        }
        if CommandLine.arguments.contains("--popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.togglePopover() }
        }
    }

    private func updateIcon(reason: ShieldReason, enabled: Bool) {
        let symbol: String
        if !enabled {
            symbol = "eye.slash"
        } else {
            switch reason {
            case .none: symbol = "eye"
            case .intruder: symbol = "eyes.inverse"
            case .lookingAway, .absent: symbol = "eye.trianglebadge.exclamationmark"
            }
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SideEye")
            ?? NSImage(systemSymbolName: "eye", accessibilityDescription: "SideEye")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    func popoverDidClose(_ notification: Notification) {
        model.isPopoverVisible = false
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.isPopoverVisible = true
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// `--snapshot <path>`: renders the popover offscreen to a PNG (works with the screen locked).
    private func snapshotPopover(to path: String) {
        let view = NSHostingView(rootView: PopoverView(model: model))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        view.appearance = NSAppearance(named: .darkAqua)
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// `--demo`: sweeps the shield through each reason without touching the camera.
    private func runDemo() {
        let left = SweepDirection(dx: -1, dy: 0)
        let down = SweepDirection(dx: 0, dy: -1)
        let upRight = SweepDirection(dx: 0.7071, dy: 0.7071)
        let steps: [(Double, Double, ShieldReason, SweepDirection?)] = [
            (1.0, 0.35, .lookingAway, left), (2.5, 0.7, .lookingAway, left), (4.0, 1.0, .lookingAway, left),
            (5.5, 0, .none, nil),
            (7.0, 0.5, .lookingAway, down), (8.5, 0, .none, nil),
            (10.0, 0.5, .lookingAway, upRight), (11.5, 0, .none, nil),
            (13.0, 1.0, .intruder, nil), (15.0, 0, .none, nil),
            (16.5, 1.0, .absent, nil), (18.5, 0, .none, nil),
        ]
        for (delay, level, reason, toward) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [model] in
                model.shield.setTarget(level: level, reason: reason, sweepToward: toward)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
