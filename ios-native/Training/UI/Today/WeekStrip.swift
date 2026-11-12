import SwiftUI

/// Seven days per page; swipe for other weeks. The selection capsule slides (red on today).
/// Dot = trained that day; ring = a workout still to come.
struct WeekStrip: View {
    @Environment(Store.self) private var store
    @Binding var pos: Int?
    @Binding var range: ClosedRange<Int>           // the weeks that exist (a window around the one shown: TodayView)
    let weekKey: (Int) -> String
    let select: (String) -> Void
    @Namespace private var capsule

    var body: some View {
        let _ = Perf.body("WeekStrip")
        ScrollViewReader { proxy in
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(range, id: \.self) { off in
                    week(weekKey(off))
                        .padding(.horizontal, 12)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $pos)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()   // lets today's red glow show
        .frame(height: 74)
        // stopped near the window's edge: a new window, with the same week put back in place in the same pass
        .onScrollPhaseChange { _, phase in
            guard phase == .idle, let p = pos,
                  let w = TodayView.recentered(range, at: p, edge: TodayView.weekEdge, half: TodayView.weekHalf) else { return }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { range = w; proxy.scrollTo(p, anchor: .leading) }
        }
        }
    }

    private func week(_ ws: String) -> some View {
        let names = store.data.settings.weekStart == 0 ? ["S", "M", "T", "W", "T", "F", "S"] : ["M", "T", "W", "T", "F", "S", "S"]
        return HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let k = Day0.add(ws, i)
                dayCell(k, names[i])
            }
        }
    }

    private func dayCell(_ k: String, _ wd: String) -> some View {
        let isToday = k == store.today, sel = k == store.selected
        let trained = store.hasSets(k)
        let planned = !trained && k >= store.today && !store.dayOf(k).items.isEmpty
        let fg: Color = sel ? (isToday ? .white : Color.bg) : (isToday ? .red : .primary)
        return Button { select(k) } label: {
            VStack(spacing: 4) {
                Text(wd).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(sel ? fg : (isToday ? Color.red : Color.label2))
                Text("\(Day0.dayOfMonth(k))").font(.rounded(20)).foregroundStyle(fg)
                    .frame(height: 24)
                ZStack {
                    if trained { Circle().fill(sel ? fg.opacity(isToday ? 1 : 0.7) : Color.label2) }
                    else if planned { Circle().strokeBorder(sel ? fg : Color.label3, lineWidth: 1.5) }
                }
                .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10).padding(.bottom, 8)
            .background {
                if sel {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(isToday ? Color.red : Color.primary)
                        .shadow(color: isToday ? Color.red.opacity(0.45) : .clear, radius: 8, y: 6)
                        .matchedGeometryEffect(id: "sel", in: capsule)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel(Fmt.long(k))
        .accessibilityAddTraits(sel ? .isSelected : [])
    }
}
