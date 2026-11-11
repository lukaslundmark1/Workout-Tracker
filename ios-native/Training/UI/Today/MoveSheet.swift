import SwiftUI

/// Move one workout to another day: a calendar (a ring = something planned, a dot = trained); tap a day and the workout
/// goes there, next to whatever that day already has. Replaces "Can't make it today" / "Move back a day" (2026-11-11, Lukas).
struct MoveSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let from: String
    let group: String

    /// The month of the day it's on, a month before and six after
    private var months: [String] {
        let first = Day0.add(from, 1 - Day0.dayOfMonth(from))
        return (-1...6).map { monthStart(first, plus: $0) }
    }
    private func monthStart(_ k: String, plus n: Int) -> String {
        Day0.key(Day0.cal.date(byAdding: .month, value: n, to: Day0.date(k))!)
    }
    private var name: String { store.groups(from).first { $0.id == group }?.name ?? "workout" }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26, pinnedViews: []) {
                        ForEach(months, id: \.self) { m in month(m).id(m) }
                    }
                    .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 40)
                }
                .onAppear { proxy.scrollTo(Day0.add(from, 1 - Day0.dayOfMonth(from)), anchor: .top) }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("Tap the day \(name) should move to.")
                    .font(.system(size: 15)).foregroundStyle(Color.label2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.bottom, 10)
            }
            .navigationTitle("Move \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func month(_ m: String) -> some View {
        let firstDay = store.data.settings.weekStart
        let names = firstDay == 0 ? ["S", "M", "T", "W", "T", "F", "S"] : ["M", "T", "W", "T", "F", "S", "S"]
        let lead = Day0.between(Day0.weekStart(m, firstDay: firstDay), m)
        let count = Day0.cal.range(of: .day, in: .month, for: Day0.date(m))!.count
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(Fmt.month(m)) \(String(Fmt.year(m)))").font(.system(size: 20, weight: .bold)).padding(.horizontal, 4)
            LazyVGrid(columns: cols, spacing: 6) {
                // (each cell needs its own id in one grid: plain 0, 1, 2… repeated made days 1–7 disappear)
                ForEach(0..<7, id: \.self) { i in
                    Text(names[i]).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.label2).id("h\(i)")
                }
                ForEach((0..<lead).map { "p\($0)" }, id: \.self) { _ in Color.clear.frame(height: 50) }
                ForEach((0..<count).map { Day0.add(m, $0) }, id: \.self) { k in cell(k) }
            }
            .padding(.vertical, 12).padding(.horizontal, 6)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func cell(_ k: String) -> some View {
        let isToday = k == store.today, isFrom = k == from
        let trained = store.hasSets(k)
        let planned = !trained && !store.dayOf(k).items.isEmpty
        return Button {
            guard !isFrom else { return }
            Motion.run { store.moveGroup(group, from: from, to: k) }
            dismiss()
        } label: {
            VStack(spacing: 3) {
                Text("\(Day0.dayOfMonth(k))")
                    .font(.rounded(18, isToday || isFrom ? .bold : .medium))
                    .foregroundStyle(isFrom ? .white : isToday ? Color.red : k < store.today ? Color.label2 : Color.primary)
                ZStack {
                    if trained { Circle().fill(isFrom ? .white : Color.label2) }
                    else if planned { Circle().strokeBorder(isFrom ? .white : Color.label3, lineWidth: 1.5) }
                }
                .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .background {
                if isFrom { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.tint).padding(.horizontal, 3) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.88))
        .disabled(isFrom)
        .accessibilityLabel(Fmt.long(k) + (isFrom ? ", where it is now" : planned ? ", has a workout" : trained ? ", trained" : ""))
    }
}
