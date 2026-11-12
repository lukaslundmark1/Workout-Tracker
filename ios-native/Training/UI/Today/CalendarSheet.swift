import SwiftUI

/// One month as a card: the month's name, weekday letters and a grid of day cells (shared by Calendar and Move).
struct MonthGrid<Cell: View>: View {
    @Environment(Store.self) private var store
    let m: String                       // the first day of the month
    @ViewBuilder var cell: (String) -> Cell

    var body: some View {
        let firstDay = store.data.settings.weekStart
        let names = firstDay == 0 ? ["S", "M", "T", "W", "T", "F", "S"] : ["M", "T", "W", "T", "F", "S", "S"]
        let lead = Day0.between(Day0.weekStart(m, firstDay: firstDay), m)
        let count = Day0.between(m, MonthGrid.monthStart(m, plus: 1))
        let rows = (lead + count + 6) / 7
        VStack(alignment: .leading, spacing: 10) {
            Text("\(Fmt.month(m)) \(String(Fmt.year(m)))").font(.system(size: 20, weight: .bold)).padding(.horizontal, 4)
            // Plain rows of seven (it was a LazyVGrid: a lazy grid in every month of a lazy list of months made opening
            // the calendar take ~300 ms with two years of training; a month is only 28–42 cells)
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(names[i]).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.label2).frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { c in
                            let i = r * 7 + c - lead
                            if i >= 0 && i < count { cell(Day0.add(m, i)) }
                            else { Color.clear.frame(maxWidth: .infinity).frame(height: 50) }
                        }
                    }
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 6)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    static func monthStart(_ k: String, plus n: Int = 0) -> String {
        let first = Day0.add(k, 1 - Day0.dayOfMonth(k))
        guard n != 0, let p = Day0.parts(first) else { return first }
        let total = p.y * 12 + (p.m - 1) + n          // months counted from year 0
        return String(format: "%04d-%02d-01", total / 12, total % 12 + 1)
    }
}

/// A day in a month grid: the number (red = today, blue pill = highlighted) and a dot (trained) or ring (planned).
struct CalendarDay: View {
    @Environment(Store.self) private var store
    let k: String
    var highlighted = false
    var note: String? = nil             // read out after the date (VoiceOver), e.g. ", where it is now"

    var body: some View {
        let isToday = k == store.today
        let trained = store.hasSets(k)
        let planned = !trained && !store.dayOf(k).items.isEmpty
        VStack(spacing: 3) {
            Text("\(Day0.dayOfMonth(k))")
                .font(.rounded(18, isToday || highlighted ? .bold : .medium))
                .foregroundStyle(highlighted ? .white : isToday ? Color.red : k < store.today ? Color.label2 : Color.primary)
            ZStack {
                if trained { Circle().fill(highlighted ? .white : Color.label2) }
                else if planned { Circle().strokeBorder(highlighted ? .white : Color.label3, lineWidth: 1.5) }
            }
            .frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity).frame(height: 50)
        .background {
            if highlighted { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.tint).padding(.horizontal, 3) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Fmt.long(k) + (isToday ? ", today" : "") + (note ?? (trained ? ", trained" : planned ? ", has a workout" : "")))
    }
}

/// The calendar behind the month name on Today: months to scroll through (a dot = trained, a ring = planned, the day
/// you're looking at in blue); tap a day to go to it.
struct CalendarSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let start: String                   // the month it opens on
    var pick: (String) -> Void

    /// From the first month you trained (at least a year back) to a year ahead
    private var months: [String] {
        let now = MonthGrid<EmptyView>.monthStart(store.today)
        let firstLogged = store.index.byDate.keys.min().map { MonthGrid<EmptyView>.monthStart($0) } ?? now
        let yearBack = MonthGrid<EmptyView>.monthStart(now, plus: -12)
        var m = min(firstLogged, yearBack, MonthGrid<EmptyView>.monthStart(start))
        let last = max(MonthGrid<EmptyView>.monthStart(now, plus: 12), MonthGrid<EmptyView>.monthStart(start))
        var out: [String] = []
        while m <= last { out.append(m); m = MonthGrid<EmptyView>.monthStart(m, plus: 1) }
        return out
    }

    @State private var pos: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(months, id: \.self) { m in
                        MonthGrid(m: m) { k in
                            Button {
                                Haptics.select()
                                pick(k)
                                dismiss()
                            } label: { CalendarDay(k: k, highlighted: k == store.selected) }
                            .buttonStyle(PressStyle(scale: 0.88))
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 40)
            }
            // (a starting position, not scrollTo on appear: the lazy stack hasn't laid out far-away months yet)
            .scrollPosition(id: $pos, anchor: .top)
            .onAppear { if pos == nil { pos = MonthGrid<EmptyView>.monthStart(start) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Today") {
                        Haptics.select()
                        Motion.run(Motion.screen) { pos = MonthGrid<EmptyView>.monthStart(store.today) }
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
