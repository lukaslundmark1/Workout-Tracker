import SwiftUI

/// One set: number (PR in orange), weight and reps fields that open the number pad, and the tick.
struct SetRow: View {
    @Environment(Store.self) private var store
    let m: LogModel
    let i: Int
    let isPR: Bool
    @State private var playing: VideoRoute?

    var body: some View {
        let done = m.bySlot[i]
        let v = store.rowValues(m, i)
        let u = store.units
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(i + 1)").font(.rounded(17, .bold)).foregroundStyle(done != nil ? Color.primary : Color.label3)
                if isPR { Text("PR").font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(Color.orange) }
                if let done, let first = done.v?.first {
                    // linked video(s): tap to play
                    Button { Haptics.select(); playing = VideoRoute(setId: done.id, start: first) } label: {
                        Image(systemName: "video.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.tint)
                            .frame(width: 30, height: 18, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.8))
                    .accessibilityLabel("Play video of set \(i + 1)")
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .frame(width: 30, alignment: .leading)
            .animation(Motion.soft, value: done?.v)
            field(.w, v.w, placeholder: u.u, done: done != nil)
                .accessibilityLabel("Set \(i + 1) weight in \(u.u)")
            field(.r, v.r, placeholder: "reps", done: done != nil)
                .accessibilityLabel("Set \(i + 1) reps")
            TickButton(done: done != nil, animate: done != nil && store.justTicked == done?.id,
                       unticked: done == nil && store.justUnticked == m.dkey + "|\(i)") {
                Motion.run { store.toggle(m.k, m.idx, i) }
            }
            .accessibilityLabel("\(done != nil ? "Undo" : "Complete") set \(i + 1)")
        }
        .padding(.leading, 18).padding(.trailing, 10)
        .frame(minHeight: 60)
        .sheet(item: $playing) { VideoPlayerSheet(route: $0) }
    }

    private func field(_ f: PadField, _ value: String, placeholder: String, done: Bool) -> some View {
        let p = store.pad
        let active = p != nil && p!.exId == m.ex.id && p!.g == m.g && p!.day == m.k && p!.i == i && p!.field == f
        let fresh = active && p!.fresh && !value.isEmpty
        let isBad = store.bad.contains(m.dkey + "|\(i)|\(f.rawValue)")
        return Button {
            store.padOpen(m.k, m.ex.id, i, f, group: m.g)
        } label: {
            Text(value.isEmpty ? placeholder : value)
                .font(.rounded(18))
                .monospacedDigit()
                .foregroundStyle(value.isEmpty ? Color.label3 : (done || active ? Color.primary : Color.label3))
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(fresh ? Color.tint.opacity(0.16) : active ? Color.card : done ? Color.fill : Color.fillFaint,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                // empty field on a tick: flashes red quickly, fades back slowly
                .animation(isBad ? .easeOut(duration: 0.12) : .easeOut(duration: 0.5)) { v in
                    v.background(Color.red.opacity(isBad ? 0.18 : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(isBad ? Color.red : active ? Color.tint : .clear, lineWidth: 2)
                        }
                }
                .animation(.easeOut(duration: 0.2), value: active)
                .animation(.easeOut(duration: 0.35), value: done)
        }
        .buttonStyle(PressStyle(scale: 0.96))
    }
}

/// The tick: a ring that pops, fills green and draws its check.
struct TickButton: View {
    let done: Bool
    let animate: Bool
    let unticked: Bool
    let action: () -> Void
    @State private var draw: CGFloat = 1
    @State private var bump = 0

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(done ? Color.green : Color.label3, lineWidth: 2)
                Circle().fill(Color.green).scaleEffect(done ? 1 : 0.3).opacity(done ? 1 : 0)
                CheckShape().trim(from: 0, to: done ? draw : 0)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 13, height: 10)
            }
            .frame(width: 30, height: 30)
            .keyframeAnimator(initialValue: 1.0, trigger: bump) { v, s in v.scaleEffect(s) } keyframes: { _ in
                SpringKeyframe(0.78, duration: 0.1)
                SpringKeyframe(1.18, duration: 0.18, spring: .snappy)
                SpringKeyframe(1.05, duration: 0.3, spring: .bouncy)
            }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.82))
        .onChange(of: done) { _, d in
            if d && animate && !Motion.reduced {
                draw = 0
                bump += 1
                withAnimation(.easeOut(duration: 0.32).delay(0.1)) { draw = 1 }
            } else { draw = 1 }
        }
        .animation(Motion.soft, value: done)
    }
}
