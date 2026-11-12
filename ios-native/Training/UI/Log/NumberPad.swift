import SwiftUI

/// The app's own number pad (kept from the web app at Lukas's request):
/// "Set N" · kg/Reps switch · Next (Reps › → Next set › → Done); −/+ steps; keys 1–9, "." or hide, 0, delete.
struct NumberPad: View {
    @Environment(Store.self) private var store
    @Namespace private var seg
    @State private var dragY: CGFloat = 0      // swipe down to put it away
    @State private var dragged = false         // a swipe that started on a key doesn't type it
    static let height: CGFloat = 10 + 40 + 8 + 52 + 10 + (54 * 4 + 8 * 3) + 12

    /// What the pad shows. When it closes, it keeps showing the last of it while it slides away
    /// (otherwise it empties at once and only a pressed button is left to fall on its own).
    private struct Shown: Equatable { var p: PadState; var value: String; var rows: Int }
    @State private var lastShown: Shown?
    private var live: Shown? { store.pad.map { Shown(p: $0, value: store.padValue, rows: store.padRows) } }

    var body: some View {
        content(live ?? lastShown)
            .onAppear { lastShown = live }
            .onChange(of: live) { _, v in if let v { lastShown = v } }
    }

    @ViewBuilder private func content(_ shown: Shown?) -> some View {
        if let shown {
            let p = shown.p
            let isW = p.field == .w
            let u = store.units
            let last = p.field == .r && p.i + 1 >= shown.rows
            let value = shown.value
            // Switching kg ↔ Reps (or to the next set) springs; typing a digit is a quick fade. One rule for both: with two
            // (a fast one keyed on the value, a spring on the field) a switch that also changed the number shown took the
            // fast one, and the whole pad, its sliding capsule included, snapped across (Lukas: "choppy once logged").
            // (`lastShown` is still the previous state while this is drawn; it's updated right after.)
            let switching = lastShown.map { $0.p.field != p.field || $0.p.i != p.i || $0.p.exId != p.exId } ?? false
            VStack(spacing: 0) {
                // Set N · kg | Reps · Next (sized so "Next set ›" fits at the standard text size on a 6.3" phone)
                HStack(spacing: 4) {
                    Text("Set \(p.i + 1)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.label2)
                        .contentTransition(.numericText()).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 0) {
                        segButton(u.u, on: isW) { key(press: "w") }
                        segButton("Reps", on: !isW) { key(press: "r") }
                    }
                    .padding(2)
                    .background(Color.fill, in: Capsule())
                    Button { key(press: "next") } label: {
                        Text(last ? "Done" : isW ? "Reps ›" : "Next set ›")
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 12).frame(height: 34)
                            .background(Color.tint.opacity(0.14), in: Capsule())
                            .contentTransition(.interpolate)
                    }
                    .foregroundStyle(Color.tint)
                    .buttonStyle(PressStyle(scale: 0.92))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.leading, 10).padding(.trailing, 4)
                .frame(height: 40)

                // −2.5   77.5 kg   +2.5
                HStack(spacing: 8) {
                    stepButton(isW ? "−\(num(u.step))" : "−1", "minus", label: isW ? "Minus \(num(u.step)) \(u.u)" : "Minus 1 rep")
                    Group {
                        if value.isEmpty {
                            Text(isW ? u.u : "reps").font(.rounded(30, .bold)).foregroundStyle(Color.label3)
                        } else {
                            Text("\(Text(value).font(.rounded(40, .bold)))\(Text(" " + (isW ? u.u : (value == "1" ? "rep" : "reps"))).font(.rounded(18)).foregroundStyle(Color.label2))")
                        }
                    }
                    .monospacedDigit().tracking(-0.5).lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .accessibilityAddTraits(.updatesFrequently)
                    stepButton(isW ? "+\(num(u.step))" : "+1", "plus", label: isW ? "Plus \(num(u.step)) \(u.u)" : "Plus 1 rep")
                }
                .padding(.top, 8).padding(.bottom, 10)

                // Keys
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(0..<3) { r in
                        GridRow { ForEach(1...3, id: \.self) { c in key(String(r * 3 + c)) } }
                    }
                    GridRow {
                        if isW { key(".", fn: true) }
                        else { keyIcon("chevron.down", "done", label: "Hide number pad") }
                        key("0")
                        keyIcon("delete.left", "back", label: "Delete")
                    }
                }
            }
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 12)
            .frame(height: NumberPad.height)
            .background(Color.padBg, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Color.sep, lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .offset(y: dragY)
            .simultaneousGesture(      // alongside the keys, so it follows the finger from the first move
                DragGesture(minimumDistance: 10)
                    .onChanged { v in
                        dragged = true
                        let t = v.translation.height
                        dragY = t > 0 ? t : t / 8          // follows the finger down, barely moves up
                    }
                    .onEnded { v in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { dragged = false }   // after the key's own release
                        if v.translation.height > 70 || v.predictedEndTranslation.height > 200 {
                            Haptics.select(); store.padClose()     // slides the rest of the way from where the finger left it
                        } else {
                            withAnimation(Motion.soft) { dragY = 0 }
                        }
                    }
            )
            .animation(switching ? Motion.soft : .easeOut(duration: 0.15), value: AnimKey(field: p.field, i: p.i, value: value))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Number pad")
        }
    }

    private struct AnimKey: Equatable { var field: PadField; var i: Int; var value: String }

    /// A key press, unless the finger was swiping the pad
    private func key(press k: String) { if !dragged { store.padKey(k) } }

    private func segButton(_ t: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? Color.primary : Color.label2)
                .frame(minWidth: 54).padding(.horizontal, 10).frame(height: 30)
                .background {
                    if on {
                        Capsule().fill(Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.39, alpha: 1) : .white }))
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                            .matchedGeometryEffect(id: "on", in: seg)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func stepButton(_ t: String, _ k: String, label: String) -> some View {
        Button { key(press: k) } label: {
            Text(t).font(.rounded(16, .bold)).monospacedDigit()
                .frame(width: 68, height: 46)
                .background(Color.fill, in: Capsule())
        }
        .foregroundStyle(.primary)
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    private func key(_ k: String, fn: Bool = false) -> some View {
        Button { key(press: k) } label: {
            Text(k).font(.rounded(26, .medium))
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(fn ? Color.clear : Color.padKey, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: fn ? .clear : .black.opacity(0.08), radius: 0, y: 1)
        }
        .foregroundStyle(.primary)
        .buttonStyle(KeyStyle())
    }
    private func keyIcon(_ icon: String, _ k: String, label: String) -> some View {
        Button { key(press: k) } label: {
            Image(systemName: icon).font(.system(size: 21, weight: .medium))
                .frame(maxWidth: .infinity).frame(height: 54)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .buttonStyle(KeyStyle())
        .accessibilityLabel(label)
    }
}

private struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .animation(configuration.isPressed ? .easeOut(duration: 0.06) : Motion.pop) {   // only the press effect (see PressStyle)
                $0.overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.fill2).opacity(configuration.isPressed ? 1 : 0) }
                    .scaleEffect(configuration.isPressed ? 0.94 : 1)
            }
    }
}
