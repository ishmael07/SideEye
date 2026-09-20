import AppKit

/// A layer that blurs whatever is behind its window, with the radius at each point
/// scaled by a mask's alpha: true progressive blur, zero where the mask is clear.
///
/// Built on the private `CABackdropLayer` (window-server aware, the mechanism behind
/// NSVisualEffectView) and `CAFilter`'s `variableBlur`. Everything is resolved at
/// runtime, so if a future macOS drops either, `make()` returns nil and the caller
/// falls back to a uniform blur.
final class VariableBlurLayer {
    let layer: CALayer
    private let filterClass: NSObject.Type

    static let isAvailable = make() != nil

    static func make() -> VariableBlurLayer? {
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
              filterClass.responds(to: filterWithType)
        else { return nil }

        let layer = backdropClass.init()
        layer.setValue(true, forKey: "windowServerAware")
        return VariableBlurLayer(layer: layer, filterClass: filterClass)
    }

    private static let filterWithType = NSSelectorFromString("filterWithType:")

    private init(layer: CALayer, filterClass: NSObject.Type) {
        self.layer = layer
        self.filterClass = filterClass
    }

    func update(radius: Double, mask: CGImage?) {
        guard let mask,
              let filter = filterClass.perform(Self.filterWithType, with: "variableBlur")?.takeUnretainedValue() as? NSObject
        else { return }
        // A fresh filter each time: reassigning a mutated one is not picked up as a change.
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(mask, forKey: "inputMaskImage")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        layer.filters = [filter]
    }
}
