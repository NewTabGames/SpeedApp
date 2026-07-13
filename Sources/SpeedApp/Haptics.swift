import UIKit

/// Central place for haptic feedback so every tap feels consistent and the "Haptic Feedback"
/// setting is respected in one spot instead of being re-checked at each call site.
///
/// `enabled` is kept in sync from SettingsStore. When it's off, every method here is a no-op.
enum Haptics {
    static var enabled = true

    /// A light tap — for routine taps: toggles, selections, minor buttons.
    static func tap() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// A medium tap — for more significant actions: start/stop, confirm, primary buttons.
    static func impact() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// A crisp selection tick — for moving through options (pickers, segmented controls, tabs).
    static func selection() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Success notification — a ride saved, an action completed.
    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Warning notification — over the speed limit, a destructive confirmation.
    static func warning() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
