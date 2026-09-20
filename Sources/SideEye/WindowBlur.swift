import AppKit

/// Live, variable-radius blur of whatever is behind a window, done by the window
/// server. Private API, resolved at runtime so a missing symbol degrades to the
/// NSVisualEffectView fallback instead of failing to launch.
enum WindowBlur {
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias SetBlurFn = @convention(c) (Int32, Int32, Int32) -> Int32

    private static let handle = dlopen(nil, RTLD_NOW)
    private static let mainConnection: ConnectionFn? = symbol("CGSMainConnectionID")
    private static let setBlurRadius: SetBlurFn? = symbol("CGSSetWindowBackgroundBlurRadius")

    private static func symbol<T>(_ name: String) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static var isAvailable: Bool { mainConnection != nil && setBlurRadius != nil }

    @discardableResult
    static func setRadius(_ radius: Int, for window: NSWindow) -> Bool {
        guard let mainConnection, let setBlurRadius, window.windowNumber > 0 else { return false }
        return setBlurRadius(mainConnection(), Int32(window.windowNumber), Int32(max(0, radius))) == 0
    }
}
