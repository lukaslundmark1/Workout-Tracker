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

// MARK: Page colours in sheets
// The web app shows the exercise screen, History, the summary, the calendar, Add exercise, the database, plans,
// workout/plan editors and profiles as full pages: black background, #1c1c1e cards in dark mode. Here they slide up
// as sheets, and iOS draws every sheet one shade lighter (#1c1c1e / #2c2c2e, "elevated"). `.pageColors()` puts the
// sheet back on the base level so it matches the web page. Small pop-ups (note, Finish, Move, sign in, send…) are
// sheets in the web app too and keep iOS's lighter sheet colours, like the web's --sheet-bg / --sheet-card.

/// Sets the containing sheet's interface level to `.base` as soon as it's in the view controller tree.
private struct BaseLevel: UIViewControllerRepresentable {
    final class Controller: UIViewController {
        override func willMove(toParent parent: UIViewController?) {
            super.willMove(toParent: parent)
            apply(from: parent)
        }
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply(from: parent)
        }
        private func apply(from start: UIViewController?) {
            var vc = start
            while let p = vc?.parent { vc = p }
            // reading an override that isn't set asserts, so ask first
            guard let top = vc, !top.traitOverrides.contains(UITraitUserInterfaceLevel.self) else { return }
            top.traitOverrides.userInterfaceLevel = .base
        }
    }
    func makeUIViewController(context: Context) -> Controller {
        let c = Controller(); c.view.isUserInteractionEnabled = false; c.view.backgroundColor = .clear; return c
    }
    func updateUIViewController(_ uiViewController: Controller, context: Context) {}
}

extension View {
    /// A sheet that is a full page in the web app: black background and #1c1c1e cards in dark mode.
    func pageColors() -> some View {
        background { BaseLevel().frame(width: 0, height: 0).accessibilityHidden(true) }
            .presentationBackground(Color.bg)
    }
    /// A small pop-up sheet (a sheet in the web app too): solid #1c1c1e in dark mode, like the web's --sheet-bg.
    /// Without it, iOS 26 draws half-height sheets as see-through glass, which looks grey and lighter than the web.
    func sheetColors() -> some View { presentationBackground(Color.bg) }
}

// MARK: Pop-ups over a page sheet
// In dark mode iOS pushes a sheet back when another sheet opens on top of it and switches it to lighter colours, so the
// black exercise screen turned grey behind the Duration pop-up (Lukas, 2026-11-12). SwiftUI can't turn that off, so a
// pop-up opened from a page sheet is drawn by the page itself with `PopUpHost`: it slides up from the bottom, can be pulled
// down, closes on a tap outside, and darkens the page like the web app's backdrop instead of lightening it.

extension Color {
    /// Pop-up colours that don't depend on the interface level (inside a page sheet the level is `.base`):
    /// #1c1c1e / #2c2c2e in dark mode like the web's --sheet-bg / --sheet-card, #f2f2f7 / white in light mode.
    static let popBg = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1) : .systemGroupedBackground })
    static let popCard = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.173, green: 0.173, blue: 0.18, alpha: 1) : .white })
}

/// Shows `content` as a pop-up floating at the bottom of the page while `item` is set.
struct PopUpHost<Item: Identifiable, Content: View>: View {
    @Binding var item: Item?
    @ViewBuilder var content: (Item) -> Content
    @State private var drag: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    private var anim: Animation { Motion.reduced ? .easeInOut(duration: 0.2) : Motion.sheet }
    private func close() { withAnimation(anim) { item = nil } }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(item == nil ? 0 : (scheme == .dark ? 0.5 : 0.2))
                .ignoresSafeArea()
                .allowsHitTesting(item != nil)
                .onTapGesture { close() }
                .accessibilityHidden(true)
            if let it = item {
                content(it)
                    .background(Color.popBg)
                    .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 20, y: 4)
                    .padding(.horizontal, 8).padding(.bottom, 8)     // floats just above the bottom edge, like iOS's own sheets
                    .offset(y: max(0, drag))
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { drag = $0.translation.height > 0 ? $0.translation.height : $0.translation.height / 6 }
                            .onEnded { v in
                                if v.translation.height > 110 || v.predictedEndTranslation.height > 260 { close() }
                                withAnimation(anim) { drag = 0 }
                            }
                    )
                    .transition(Motion.reduced ? .opacity : .move(edge: .bottom))
                    .id(it.id)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(anim, value: item == nil)
    }
}
