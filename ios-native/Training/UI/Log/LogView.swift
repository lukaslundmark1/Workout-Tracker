import SwiftUI

/// The exercise screen: one page per exercise of the day; swipe between them, page dots at the bottom.
struct LogView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: String
    let startExId: String
    @State private var pos: Int?
    @State private var finishFor: GroupKey?

    /// The page is known before the screen is drawn (setting it afterwards made the page dots spring in from the top)
    init(day: String, startExId: String, startIndex: Int) {
        self.day = day; self.startExId = startExId
        _pos = State(initialValue: startIndex)
    }

    private var items: [WorkoutItem] { store.dayOf(day).items }
    /// The workout of the exercise on screen (the timer at the top is that workout's)
    private var group: String { let it = items; let p = min(pos ?? 0, it.count - 1); return p >= 0 ? (it[p].w ?? otherGroup) : otherGroup }

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.pageId) { i, _ in
                        LogPage(day: day, idx: i, onFinish: { g in finishFor = GroupKey(k: day, g: g) }, goTo: { exId in
                            if let j = items.firstIndex(where: { $0.exId == exId && $0.w == otherGroup }) { Motion.run(Motion.screen) { pos = j } }
                        })
                            .containerRelativeFrame(.horizontal)
                            .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $pos)
            .scrollIndicators(.hidden)
            .background(Color.bg)
            .overlay(alignment: .bottom) { bottom }
            .overlay(alignment: .top) { ToastView() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) { TimerButton(day: day, g: group, onFinish: { finishFor = GroupKey(k: day, g: group) }) }
            }
        }
        .onAppear { store.logOpen = true }
        .onChange(of: pos) { old, new in
            if old != nil, new != nil, old != new { Haptics.select(); store.padClose() }
        }
        .onDisappear { store.padClose(); store.logOpen = false }
        .onChange(of: items.count) { _, n in if n == 0 { dismiss() } else if let p = pos, p >= n { pos = n - 1 } }
        .sheet(item: $finishFor) { r in FinishSheet(day: r.k, g: r.g) { finished in if finished { dismiss() } } }
    }

    // Page dots, the rest stopwatch and the number pad, at the bottom of the screen
    private var bottom: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 10) {
                dots
                if let r = store.rest, r.date == store.today, store.pad == nil {
                    RestPill(rest: r).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 8)
            if store.pad != nil {
                NumberPad().transition(.move(edge: .bottom))
            }
        }
        .animation(Motion.reduced ? .easeInOut(duration: 0.2) : Motion.sheet, value: store.pad == nil)
        .animation(Motion.reduced ? .easeInOut(duration: 0.2) : Motion.sheet, value: store.rest)
    }

    @ViewBuilder private var dots: some View {
        if items.count >= 2 && store.pad == nil {
            HStack(spacing: 2) {
                ForEach(items.indices, id: \.self) { i in
                    Button {
                        guard i != pos else { return }
                        Haptics.select()
                        Motion.run(Motion.screen) { pos = i }
                    } label: {
                        Capsule().fill(i == (pos ?? 0) ? Color.primary : Color.label3)
                            .frame(width: i == (pos ?? 0) ? 18 : 7, height: 7)
                            .frame(width: i == (pos ?? 0) ? 26 : 16, height: 28)
                            .animation(Motion.soft, value: pos)   // only the dots grow/shrink; the row itself never springs
                    }
                    .accessibilityLabel("Exercise \(i + 1)")
                }
            }
            .padding(.horizontal, 8)
            .glassEffect(.regular, in: Capsule())
            .transition(.opacity)
        }
    }
}

/// Start / running time / finished duration, top right.
struct TimerButton: View {
    @Environment(Store.self) private var store
    let day: String
    let g: String
    var onFinish: () -> Void

    var body: some View {
        let s = store.sessionOf(day, g)
        if s == nil && day != store.today {
            // no timer when filling in another day
        } else if let s, let end = s.end {
            Button { onFinish() } label: {
                HStack(spacing: 5) { Image(systemName: "checkmark"); Text(Fmt.mins(end - s.start)) }.foregroundStyle(Color.green)   // (toolbars drop a Label's text)
            }
            .font(.rounded(15)).monospacedDigit()
            .accessibilityLabel("Workout finished, tap to change duration")
        } else if s != nil {
            // Running: tap to pause; paused: tap to carry on. (Finish workout ends it.)
            let paused = store.isPaused(day, g)
            Button { withAnimation(Motion.pop) { store.tapTimer(day, g) } } label: {
                HStack(spacing: 6) {
                    if paused {
                        Image(systemName: "pause.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.orange)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                            .phaseAnimator([1.0, 0.35]) { c, o in c.opacity(o) } animation: { _ in .easeInOut(duration: 0.8) }
                            .transition(.scale.combined(with: .opacity))
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(Fmt.dur(store.elapsed(day, g))).font(.rounded(15)).monospacedDigit()
                            .foregroundStyle(paused ? Color.label2 : Color.primary)
                    }
                }
            }
            .accessibilityLabel(paused ? "Timer paused, tap to carry on" : "Session time, tap to pause")
        } else {
            Button { store.startTimer(day, g) } label: { HStack(spacing: 5) { Image(systemName: "timer"); Text("Start") } }
                .font(.rounded(15))
                .accessibilityLabel("Start session timer")
        }
    }
}

extension WorkoutItem {
    /// Tells pages apart when an exercise is in two workouts on one day
    var pageId: String { exId + "|" + (w ?? otherGroup) }
}

/// Where each set row is on screen (kept out of SwiftUI state so scrolling doesn't redraw anything).
final class RowFrames { var rows: [Int: CGRect] = [:]; var viewport: CGRect = .zero }

/// One exercise: Last time, note, instructions, the set rows, add/remove a set, Finish.
struct LogPage: View {
    @Environment(Store.self) private var store
    let day: String
    let idx: Int
    var onFinish: (String) -> Void          // finish this page's workout
    var goTo: (String) -> Void
    @State private var frames = RowFrames()
    @State private var editNote = false
    @State private var showAdd = false
    @State private var history = false

    var body: some View {
        if let m = store.logModel(day, idx) {
            ScrollViewReader { proxy in
                ScrollView {
                    content(m)
                        .contentShape(Rectangle())
                        .onTapGesture { store.padClose() }   // tapping outside the pad and the fields puts it away
                        .padding(.horizontal, 16)
                        .padding(.bottom, store.pad?.exId == m.ex.id && store.pad?.g == m.g ? 430 : 140)
                }
                .scrollIndicators(.hidden)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.viewport = $0 }
                .onChange(of: store.pad) { _, p in reveal(p, m, proxy) }
            }
            .sheet(isPresented: $editNote) { NoteSheet(exId: m.ex.id) }
            .sheet(isPresented: $history) { ExerciseDetail(exId: m.ex.id, mode: .history).presentationDragIndicator(.visible) }
            .sheet(isPresented: $showAdd) { AddSheet(day: day, exercisesOnly: true) { exId in
                if let exId { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { goTo(exId) } }
            } }
        } else {
            Color.bg
        }
    }

    // Keep the field you're typing in visible above the number pad
    private func reveal(_ p: PadState?, _ m: LogModel, _ proxy: ScrollViewProxy) {
        guard let p, p.exId == m.ex.id, p.g == m.g, p.day == day, let row = frames.rows[p.i] else { return }
        let vp = frames.viewport
        let padTop = store.screen.height - NumberPad.height - store.screen.safeBottom - 8 - 14
        let topLimit = vp.minY + 10
        guard row.maxY > padTop || row.minY < topLimit else { return }
        let target = (row.maxY > padTop ? padTop : topLimit + row.height) - vp.minY   // where the row's bottom should be
        let a = max(0, min(1, (target - row.height) / max(1, vp.height - row.height)))
        Motion.run(Motion.sheet) { proxy.scrollTo("row\(p.i)", anchor: UnitPoint(x: 0.5, y: a)) }
    }

    @ViewBuilder private func content(_ m: LogModel) -> some View {
        let u = store.units
        let pr = store.prFor(m.ex.id, day)
        VStack(alignment: .leading, spacing: 0) {
            let gs = store.groups(day)
            Text("Exercise \(m.idx + 1) of \(m.total)" + (gs.count > 1 ? " · " + (gs.first { $0.id == m.g }?.name ?? "") : ""))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.label2)
                .padding(.horizontal, 2).padding(.top, 6)
            Text(m.ex.name)
                .font(.system(size: 34, weight: .bold)).tracking(-0.8)
                .padding(.bottom, 14)

            // Last time → History
            Button { history = true } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.prevK.map { "Last time · \(Fmt.short($0))" } ?? "Last time")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.label2)
                        Text(m.prevK != nil ? u.compact(m.prevSets) : "No earlier sessions")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.primary).monospacedDigit()
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 2) { Text("History"); Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)) }
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.tint)
                }
                .padding(.vertical, 14).padding(.leading, 18).padding(.trailing, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(CardPressStyle())
            .card()
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.bottom, 14)

            // Note
            if let note = m.ex.note, !note.isEmpty {
                Button { editNote = true } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "pencil").foregroundStyle(Color.label2)
                        Text(note).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 13).padding(.horizontal, 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CardPressStyle())
                .card()
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.top, -4).padding(.bottom, 14)
                .accessibilityLabel("Note: \(note). Tap to edit")
            } else {
                Button { editNote = true } label: { Label("Add a note", systemImage: "pencil") }
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.tint)
                    .buttonStyle(PressStyle())
                    .padding(.horizontal, 6).padding(.top, -4).padding(.bottom, 16)
            }

            if !m.ex.instructions.isEmpty { Instructions(text: m.ex.instructions).padding(.bottom, 14) }

            // Set rows
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("Set").frame(width: 30, alignment: .leading)
                    Text(u.u).frame(maxWidth: .infinity)
                    Text("Reps").frame(maxWidth: .infinity)
                    Color.clear.frame(width: 48, height: 1)
                }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.label2)
                .padding(.leading, 18).padding(.trailing, 10)
                .frame(height: 40).padding(.top, 6)

                if m.n == 0 {
                    Text("No sets planned.").foregroundStyle(Color.label2).frame(maxWidth: .infinity).padding(.vertical, 20)
                }
                ForEach(0..<m.n, id: \.self) { i in
                    SetRow(m: m, i: i, isPR: pr != nil && m.bySlot[i]?.id == pr?.set.id)
                        .id("row\(i)")
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.rows[i] = $0 }
                        .overlay(alignment: .top) { if i > 0 { Divider().padding(.horizontal, 18) } }
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)), removal: .opacity))
                }
            }
            .card()
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            // − N sets +
            HStack(spacing: 0) {
                Button { Motion.run { store.removeRow(day, idx) } } label: { Image(systemName: "minus").frame(width: 52, height: 44) }
                    .disabled(!(m.n > 0 && m.bySlot[m.n - 1] == nil))
                    .accessibilityLabel("Remove a set")
                Text(Fmt.plural(m.n, "set")).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.label2)
                    .frame(minWidth: 70).contentTransition(.numericText()).monospacedDigit()
                Button { Motion.run { store.addRow(day, idx) } } label: { Image(systemName: "plus").frame(width: 52, height: 44) }
                    .accessibilityLabel("Add a set")
            }
            .font(.system(size: 20, weight: .medium))
            .buttonStyle(PressStyle(scale: 0.8))
            .foregroundStyle(.primary)
            .glassEffect(.regular.interactive(), in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.top, 16)

            let isLast = m.idx == m.total - 1
            let lastOfWorkout = !m.day.items.indices.contains { $0 > m.idx && m.day.items[$0].w == m.g }
            if (store.canFinish(day, m.g) || (day == store.today && !store.isFinished(day, m.g))) && (lastOfWorkout || store.setsLeft(day, m.g) == 0) {
                let name = store.groups(day).count > 1 && m.g != otherGroup ? (store.groups(day).first { $0.id == m.g }?.name ?? "workout") : "workout"
                Button { onFinish(m.g) } label: { Label("Finish \(name)", systemImage: "checkmark") }
                    .buttonStyle(PrimaryButton())
                    .padding(.top, 22)
            }
            if isLast {
                Button { showAdd = true } label: { Label("Add exercise", systemImage: "plus") }
                    .buttonStyle(TintedButton())
                    .padding(.top, 14)
            }
        }
        .animation(Motion.soft, value: m.n)
    }
}

struct Instructions: View {
    let text: String
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { Haptics.select(); Motion.run { open.toggle() } } label: {
                HStack {
                    Text("Instructions").fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).rotationEffect(.degrees(open ? 180 : 0))
                }
                .foregroundStyle(Color.tint)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                Divider()
                Text(text).lineSpacing(3).padding(.vertical, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 18)
        .card()
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
