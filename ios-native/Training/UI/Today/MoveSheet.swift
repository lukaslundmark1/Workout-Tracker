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
        MonthGrid(m: m) { k in cell(k) }
    }

    private func cell(_ k: String) -> some View {
        let isFrom = k == from
        return Button {
            guard !isFrom else { return }
            Motion.run { store.moveGroup(group, from: from, to: k) }
            dismiss()
        } label: {
            CalendarDay(k: k, highlighted: isFrom, note: isFrom ? ", where it is now" : nil)
        }
        .buttonStyle(PressStyle(scale: 0.88))
        .disabled(isFrom)
    }
}
