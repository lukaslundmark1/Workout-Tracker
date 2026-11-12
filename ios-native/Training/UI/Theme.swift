import SwiftUI
import UIKit

// Colours, motion and haptics, matching the web app (DECISIONS → Design direction, Motion with weight and haptics).

extension Color {
    static let bg = Color(uiColor: .systemGroupedBackground)               // #f2f2f7 / #000
    static let card = Color(uiColor: .secondarySystemGroupedBackground)    // white / #1c1c1e
    static let card2 = Color(uiColor: .tertiarySystemGroupedBackground)
    static let label2 = Color(uiColor: .secondaryLabel)
    static let label3 = Color(uiColor: .tertiaryLabel)
    static let fill = Color(uiColor: .tertiarySystemFill)
    static let fill2 = Color(uiColor: .secondarySystemFill)
    static let fillFaint = Color(uiColor: .quaternarySystemFill)
    static let sep = Color(uiColor: .separator)
    static let tint = Color(uiColor: .systemBlue)      // actions
    static let red = Color(uiColor: .systemRed)        // destructive, today, badges
    static let green = Color(uiColor: .systemGreen)    // done, active
    static let orange = Color(uiColor: .systemOrange)  // personal records
    /// The number pad: light grey sheet with white keys; dark grey with lighter keys
    static let padBg = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1) : .systemGroupedBackground })
    static let padKey = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.227, green: 0.227, blue: 0.235, alpha: 1) : .white })
}

extension Font {
    /// SF Pro Rounded for numbers
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

/// Springs with weight (response / damping from the web app's sampled curves).
enum Motion {
    static let screen = Animation.spring(response: 0.52, dampingFraction: 0.86)
    static let sheet = Animation.spring(response: 0.48, dampingFraction: 0.84)
    static let soft = Animation.spring(response: 0.42, dampingFraction: 0.9)
    static let pop = Animation.spring(response: 0.35, dampingFraction: 0.55)

    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }
    /// A spring, or a plain fade-speed change when Reduce Motion is on
    static func run(_ a: Animation = soft, _ body: () -> Void) {
        withAnimation(reduced ? .easeInOut(duration: 0.2) : a, body)
    }
}

/// selection ticks for choices; impact for ticking a set / deleting / starting the timer;
/// success for finishing / PR; warning for arming a delete; error for ticking a set without numbers.
enum Haptics {
    private static let sel = UISelectionFeedbackGenerator()
    private static let imp = UIImpactFeedbackGenerator(style: .medium)
    private static let note = UINotificationFeedbackGenerator()
    static func select() { sel.selectionChanged() }
    static func impact() { imp.impactOccurred() }
    private static let lifter = UIImpactFeedbackGenerator(style: .rigid)
    private static let dropper = UIImpactFeedbackGenerator(style: .soft)
    /// Picking a row up to drag it, and putting it down (like reordering on the iPhone's home screen)
    static func lift() { lifter.impactOccurred(intensity: 0.75) }
    static func drop() { dropper.impactOccurred() }
    static func success(after: Double = 0) {
        if after > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + after) { note.notificationOccurred(.success) } }
        else { note.notificationOccurred(.success) }
    }
    static func warn() { note.notificationOccurred(.warning) }
    static func error() { note.notificationOccurred(.error) }
}

/// Buttons that press in fast and spring back.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        // the press animation is scoped to the press effect only: a button that moves away when tapped
        // (Done on the number pad) must move with its surroundings, not on the press spring
        configuration.label
            .animation(configuration.isPressed ? .easeOut(duration: 0.08) : Motion.pop) {
                $0.scaleEffect(configuration.isPressed ? scale : 1).opacity(configuration.isPressed ? 0.75 : 1)
            }
    }
}

/// A card row that highlights under the finger.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .animation(.easeOut(duration: configuration.isPressed ? 0.05 : 0.25)) {
                $0.background(configuration.isPressed ? Color.card2 : Color.clear)
            }
    }
}

extension View {
    func card(_ radius: CGFloat = 22) -> some View {
        background(Color.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
