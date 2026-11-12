import SwiftUI

/// One workout on a day: a header (arrow to fold it, the name, Move) above its exercises. Open by default.
struct WorkoutGroupView: View {
    @Environment(Store.self) private var store
    let k: String
    let group: DayGroup
    var onOpen: (LogRoute) -> Void
    var onMove: () -> Void
    var onFinish: () -> Void

    var body: some View {
        let _ = Perf.body("WorkoutGroupView")
        let key = k + "|" + group.id
        let folded = store.collapsed.contains(key)
        let finished = store.isFinished(k, group.id)
        let logged = !store.groupSets(k, group.id).isEmpty
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Haptics.select()
                    Motion.run { if folded { store.collapsed.remove(key) } else { store.collapsed.insert(key) } }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.label2)
                            .rotationEffect(.degrees(folded ? -90 : 0))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.name).font(.system(size: 20, weight: .bold)).tracking(-0.3)
                                .foregroundStyle(Color.primary).lineLimit(1)
                            if let line = statusLine(folded: folded) {
                                Text(line).font(.system(size: 14)).foregroundStyle(finished ? Color.green : Color.label2)
                                    .monospacedDigit().transition(.opacity)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.name), \(folded ? "folded" : "open")")
                .accessibilityHint(folded ? "Shows its exercises" : "Hides its exercises")
                if store.canMove(k, group.id) {
                    Button { Haptics.select(); onMove() } label: {
                        Label("Move", systemImage: "calendar")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.tint)
                            .padding(.horizontal, 12).frame(height: 32)
                    }
                    .buttonStyle(PressStyle(scale: 0.92))
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .accessibilityLabel("Move \(group.name) to another day")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.horizontal, 4)
            if !folded {
                DayExerciseList(k: k, g: group.id, onOpen: onOpen)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                // Each workout ends on its own (the timer only starts and pauses)
                if finished && logged {
                    Button { Haptics.select(); store.summaryFor = GroupKey(k: k, g: group.id) } label: {
                        Label("Workout summary", systemImage: "chart.bar.fill")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.tint)
                            .padding(.horizontal, 14).frame(height: 36)
                    }
                    .buttonStyle(PressStyle(scale: 0.92))
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                } else if !finished && (k == store.today || store.isRunning(k, group.id)) {
                    Button { onFinish() } label: { Label(finishTitle, systemImage: "checkmark") }
                        .buttonStyle(PrimaryButton())
                        .padding(.top, 6)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .animation(Motion.soft, value: finished)
        .animation(Motion.soft, value: store.canMove(k, group.id))
    }

    private var finishTitle: String { group.id == otherGroup ? "Finish workout" : "Finish \(group.name)" }

    /// Under the name: finished time, or (folded) "4 exercises · 3 of 12 sets"
    private func statusLine(folded: Bool) -> String? {
        if let s = store.sessionOf(k, group.id), let end = s.end { return "Finished in \(Fmt.mins(end - s.start))" }
        if store.isRunning(k, group.id) && !folded { return "In progress" }
        return folded ? summary : nil
    }

    /// "4 exercises · 3 of 12 sets" when folded
    private var summary: String {
        let d = store.dayOf(k)
        let items = group.rows.compactMap { $0 < d.items.count ? d.items[$0] : nil }
        let done = items.reduce(0) { $0 + store.setsOf($1.exId, k, group.id).count }
        let total = items.reduce(0) { $0 + max($1.sets ?? 0, store.setsOf($1.exId, k, group.id).count) }
        return Fmt.plural(items.count, "exercise") + (done > 0 ? " · \(done) of \(total) sets" : "")
    }
}

/// A workout's exercises on Today. Tap one to open it; press and hold (or drag ≡) to pick it up and move it within the
/// workout, with the iPhone's lift / tick / drop haptics; the red trash removes it (asks first if sets are logged).
struct DayExerciseList: View {
    @Environment(Store.self) private var store
    let k: String
    let g: String
    var onOpen: (LogRoute) -> Void

    @State private var drag = Reorder()
    @State private var dragging: String?
    @State private var heights: [String: CGFloat] = [:]
    @State private var armed: String?                // trash tapped once on an exercise with logged sets
    @State private var droppedAt = Date.distantPast  // the tap that ends a drag doesn't open the exercise

    var body: some View {
        let _ = Perf.body("DayExerciseList")
        let items = store.dayOf(k).items.filter { $0.w == g }
        let ids = dragging != nil ? drag.order : items.map(\.exId)
        VStack(spacing: 0) {
            ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                if let it = items.first(where: { $0.exId == id }), let ex = store.exById(id) {
                    let lifted = dragging == id
                    row(ex, it)
                        .background { if lifted { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.card) } }
                        .overlay(alignment: .top) {
                            if i > 0 && !lifted && ids[i - 1] != dragging { Divider().padding(.leading, 92) }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[id] = $0 }
                        .scaleEffect(lifted ? 1.03 : 1)
                        .shadow(color: .black.opacity(lifted ? 0.18 : 0), radius: lifted ? 16 : 0, y: lifted ? 8 : 0)
                        .offset(y: lifted ? drag.offset : 0)
                        .zIndex(lifted ? 1 : 0)
                        .transaction { if lifted && dragging != nil { $0.animation = nil } }   // it stays under your finger
                        .transition(AnyTransition.rowInOut)
                }
            }
        }
        .animation(Motion.soft, value: dragging)
        .card()
    }

    private func row(_ ex: Exercise, _ it: WorkoutItem) -> some View {
        let s = store.setsOf(it.exId, k, g)
        let total = max(it.sets ?? 0, s.count)
        let u = store.units
        let sub = s.isEmpty ? Fmt.plural(total, "set") : u.compact(s) + (s.count < total ? " · \(total - s.count) to go" : "")
        let isArmed = armed == ex.id
        return HStack(spacing: 0) {
            // ≡ drags straight away
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.label3)
                .frame(width: 36).frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(grip(ex.id))
                .accessibilityLabel("Drag to reorder \(ex.name)")
            Button { open(ex.id) } label: {
                HStack(spacing: 14) {
                    ProgressRing(done: s.count, total: total)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name).font(.system(size: 17)).foregroundStyle(Color.primary)
                        Text(sub).font(.system(size: 15)).foregroundStyle(Color.label2).monospacedDigit().lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                // press and hold, then drag (the iPhone's own long press, inside the button so it's asked first;
                // a finger that moves before the hold is up scrolls the page, a quick tap opens the exercise)
                .gesture(LongPressDrag(began: { pickUp(ex.id) }, changed: { move($0) }, ended: { putDown() }))
            }
            .buttonStyle(.plain)
            Button { trash(ex.id, hasSets: !s.isEmpty) } label: {
                Group {
                    if isArmed {
                        Text("Delete").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 32).background(Color.red, in: Capsule())
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else {
                        Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(Color.red)
                            .frame(width: 32, height: 32)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 10).frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.85))
            .accessibilityLabel(isArmed ? "Delete \(ex.name) and its logged sets" : "Remove \(ex.name)")
        }
        .padding(.leading, 4).padding(.trailing, 2)
        .animation(Motion.pop, value: isArmed)
    }

    private func open(_ id: String) {
        guard dragging == nil, Date().timeIntervalSince(droppedAt) > 0.4 else { return }
        armed = nil
        store.selected = k
        onOpen(LogRoute(day: k, exId: id, g: g))
    }

    private func trash(_ id: String, hasSets: Bool) {
        if hasSets && armed != id {
            Haptics.warn()
            armed = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if armed == id { withAnimation(Motion.pop) { armed = nil } } }
            return
        }
        armed = nil
        Motion.run { store.removeExercise(id, group: g, from: k) }
    }

    // MARK: Dragging

    /// ≡ follows the finger from its very first movement
    private func grip(_ id: String) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                if dragging == nil { pickUp(id) }
                move(v.translation.height)
            }
            .onEnded { _ in putDown() }
    }

    private func pickUp(_ id: String) {
        Haptics.lift()
        armed = nil
        drag = Reorder(id: id, order: store.dayOf(k).items.filter { $0.w == g }.map(\.exId))
        store.reordering = true
        withAnimation(Motion.pop) { dragging = id }
    }

    private func move(_ t: CGFloat) {
        var d = drag
        let swaps = d.move(to: t, heights: heights)
        if swaps > 0 {
            withAnimation(Motion.soft) { drag = d }
            for _ in 0..<swaps { Haptics.select() }   // a tick for each row it passes
        } else {
            drag = d
        }
    }

    private func putDown() {
        guard dragging != nil else { return }
        Haptics.drop()
        droppedAt = Date()
        store.reorderExercises(in: k, group: g, drag.order)
        withAnimation(Motion.soft) { drag.offset = 0; dragging = nil }
        store.reordering = false
    }
}

/// The maths of dragging a row: where it is relative to its slot, and when it passes a neighbour (swap).
struct Reorder: Equatable {
    var id = ""
    var order: [String] = []
    var offset: CGFloat = 0      // the dragged row, relative to its current slot
    var shift: CGFloat = 0       // how far its slot has moved since it was picked up

    /// The finger has moved `t` since pick-up. Returns how many rows it passed.
    mutating func move(to t: CGFloat, heights: [String: CGFloat]) -> Int {
        guard var i = order.firstIndex(of: id) else { return 0 }
        var swaps = 0
        offset = t - shift
        // Passing the middle of the next/previous row swaps them
        while offset > 0, i + 1 < order.count, offset > (heights[order[i + 1]] ?? 64) / 2 {
            let h = heights[order[i + 1]] ?? 64
            order.swapAt(i, i + 1); shift += h; offset -= h; i += 1; swaps += 1
        }
        while offset < 0, i > 0, -offset > (heights[order[i - 1]] ?? 64) / 2 {
            let h = heights[order[i - 1]] ?? 64
            order.swapAt(i, i - 1); shift -= h; offset += h; i -= 1; swaps += 1
        }
        // It stops at the workout's first and last place, however far the finger goes
        if i == 0 && offset < 0 { offset = 0 }
        if i == order.count - 1 && offset > 0 { offset = 0 }
        return swaps
    }
}

/// A row being removed fades and shrinks, and can't be tapped while it does (so quick taps reach the row sliding up).
private struct Leave: ViewModifier {
    var gone: Bool
    func body(content: Content) -> some View {
        content.opacity(gone ? 0 : 1).scaleEffect(gone ? 0.95 : 1).allowsHitTesting(!gone)
    }
}

extension AnyTransition {
    /// Rows fade in; leaving rows fade and shrink and ignore taps
    static var rowInOut: AnyTransition {
        .asymmetric(insertion: .opacity, removal: .modifier(active: Leave(gone: true), identity: Leave(gone: false)))
    }
}

/// Press and hold, then drag: a UIKit long press, so a finger that starts moving before the hold is up scrolls the page
/// instead (SwiftUI's long-press-then-drag kept the page from scrolling when the finger started on a row). Reports how
/// far the finger has moved up or down since it was picked up.
struct LongPressDrag: UIGestureRecognizerRepresentable {
    var hold: Double = 0.3
    var began: () -> Void
    var changed: (CGFloat) -> Void
    var ended: () -> Void

    final class Coordinator { var startY: CGFloat = 0 }
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let g = UILongPressGestureRecognizer()
        g.minimumPressDuration = hold
        g.allowableMovement = 10
        return g
    }
    func handleUIGestureRecognizerAction(_ g: UILongPressGestureRecognizer, context: Context) {
        let y = g.location(in: nil).y
        switch g.state {
        case .began: context.coordinator.startY = y; began()
        case .changed: changed(y - context.coordinator.startY)
        case .ended, .cancelled, .failed: ended()
        default: break
        }
    }
}
