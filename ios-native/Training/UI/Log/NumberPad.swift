import SwiftUI

/// The app's own number pad (kept from the web app at Lukas's request):
/// "Set N" · kg/Reps switch · Next (Reps › → Next set › → Done); −/+ steps; keys 1–9, "." or hide, 0, delete.
struct NumberPad: View {
    @Environment(Store.self) private var store
    @Namespace private var seg
    static let height: CGFloat = 10 + 40 + 8 + 52 + 10 + (54 * 4 + 8 * 3) + 12

    var body: some View {
        if let p = store.pad {
            let isW = p.field == .w
            let u = store.units
            let last = p.field == .r && p.i + 1 >= store.padRows
            let value = store.padValue
            VStack(spacing: 0) {
                // Set N · kg | Reps · Next
                HStack {
                    Text("Set \(p.i + 1)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.label2)
                        .contentTransition(.numericText()).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 0) {
                        segButton(u.u, on: isW) { store.padKey("w") }
                        segButton("Reps", on: !isW) { store.padKey("r") }
                    }
                    .padding(2)
                    .background(Color.fill, in: Capsule())
                    Button { store.padKey("next") } label: {
                        Text(last ? "Done" : isW ? "Reps ›" : "Next set ›")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 14).frame(height: 34)
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
            .animation(.easeOut(duration: 0.15), value: value)
            .animation(Motion.soft, value: p.field)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Number pad")
        }
    }

    private func segButton(_ t: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? Color.primary : Color.label2)
                .frame(minWidth: 62).padding(.horizontal, 12).frame(height: 30)
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
        Button { store.padKey(k) } label: {
            Text(t).font(.rounded(16, .bold)).monospacedDigit()
                .frame(width: 68, height: 46)
                .background(Color.fill, in: Capsule())
        }
        .foregroundStyle(.primary)
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    private func key(_ k: String, fn: Bool = false) -> some View {
        Button { store.padKey(k) } label: {
            Text(k).font(.rounded(26, .medium))
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(fn ? Color.clear : Color.padKey, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: fn ? .clear : .black.opacity(0.08), radius: 0, y: 1)
        }
        .foregroundStyle(.primary)
        .buttonStyle(KeyStyle())
    }
    private func keyIcon(_ icon: String, _ k: String, label: String) -> some View {
        Button { store.padKey(k) } label: {
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
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.fill2).opacity(configuration.isPressed ? 1 : 0) }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.06) : Motion.pop, value: configuration.isPressed)
    }
}
