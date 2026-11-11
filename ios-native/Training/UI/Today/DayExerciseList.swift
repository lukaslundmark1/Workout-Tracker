import SwiftUI

/// A day's exercises on Today. Tap one to open it; press and hold (or drag ≡) to pick it up and move it,
/// with the iPhone's lift / tick / drop haptics; the red trash removes it from the day (asks first if sets are logged).
struct DayExerciseList: View {
    @Environment(Store.self) private var store
    let k: String
    var onOpen: (LogRoute) -> Void

    @State private var drag = Reorder()
    @State private var dragging: String?
    @State private var heights: [String: CGFloat] = [:]
    @State private var armed: String?                // trash tapped once on an exercise with logged sets
    @State private var droppedAt = Date.distantPast  // the tap that ends a drag doesn't open the exercise

    var body: some View {
        let items = store.dayOf(k).items
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
                        .simultaneousGesture(reorder(id, after: 0.3))   // taps still open the exercise
                        .transition(AnyTransition.rowInOut)
                }
            }
        }
        .animation(Motion.soft, value: dragging)
        .card()
    }

    private func row(_ ex: Exercise, _ it: WorkoutItem) -> some View {
        let s = store.setsOf(it.exId, k)
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
        onOpen(LogRoute(day: k, exId: id))
    }

    private func trash(_ id: String, hasSets: Bool) {
        if hasSets && armed != id {
            Haptics.warn()
            armed = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if armed == id { withAnimation(Motion.pop) { armed = nil } } }
            return
        }
        armed = nil
        Motion.run { store.removeExercise(id, from: k) }
    }

    // MARK: Dragging

    /// Press and hold anywhere on the row, then drag
    private func reorder(_ id: String, after hold: Double) -> some Gesture {
        LongPressGesture(minimumDuration: hold, maximumDistance: 10)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { v in
                guard case .second(true, let drag) = v else { return }
                if dragging == nil { pickUp(id) }
                if let drag { move(drag.translation.height) }
            }
            .onEnded { _ in putDown() }
    }

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
        drag = Reorder(id: id, order: store.dayOf(k).items.map(\.exId))
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
        store.reorderExercises(in: k, drag.order)
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
