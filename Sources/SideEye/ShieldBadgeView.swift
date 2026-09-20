import SideEyeCore
import SwiftUI

/// Sharp content drawn on top of the blurred screen, explaining why it's hidden.
struct ShieldBadgeView: View {
    @ObservedObject var presentation: ShieldPresentation

    var body: some View {
        let reason = presentation.reason
        // Stay out of the way while part of the screen is still readable.
        let visibility = smoothstep(presentation.level, from: 0.8, to: 0.98)

        VStack(spacing: 14) {
            Image(systemName: symbol(for: reason))
                .font(.system(size: 54, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(title(for: reason))
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle(for: reason))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .opacity(0.75)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 44)
        .padding(.vertical, 34)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(reason == .intruder ? Color(red: 0.75, green: 0.1, blue: 0.15).opacity(0.78) : Color.black.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        .scaleEffect(0.92 + 0.08 * visibility)
        .opacity(visibility)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: reason)
    }

    private func symbol(for reason: ShieldReason) -> String {
        switch reason {
        case .intruder: "eyes"
        case .absent: "lock.fill"
        case .lookingAway, .none: "eye.slash.fill"
        }
    }

    private func title(for reason: ShieldReason) -> String {
        switch reason {
        case .intruder: "Side eye detected"
        case .absent: "Screen hidden"
        case .lookingAway, .none: "Screen hidden"
        }
    }

    private func subtitle(for reason: ShieldReason) -> String {
        switch reason {
        case .intruder: "Someone else is looking at your screen"
        case .absent: "Come back to pick up where you left off"
        case .lookingAway, .none: "Look back to pick up where you left off"
        }
    }

    private func smoothstep(_ x: Double, from a: Double, to b: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
