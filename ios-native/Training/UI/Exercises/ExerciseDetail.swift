import SwiftUI
import Charts

/// An exercise's page (Exercises tab), or its History (from "Last time" on the exercise screen):
/// the progress chart with four stats, then every session newest first.
struct ExerciseDetail: View {
    enum Mode { case detail, history }
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exId: String
    let mode: Mode
    @AppStorage("tt.stat") private var statRaw = StatKind.e1rm.rawValue
    @State private var editing = false

    private var stat: StatKind { StatKind(rawValue: statRaw) ?? .e1rm }

    var body: some View {
        NavigationStack {
            if let ex = store.exById(exId) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Picker("Show", selection: Binding(get: { stat }, set: { v in Haptics.select(); Motion.run { statRaw = v.rawValue } })) {
                            ForEach(StatKind.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 12)
                        ProgressCard(exId: exId, stat: stat)
                        if stat == .e1rm && !store.exDates(exId).isEmpty {
                            footnote("Best set of each session, estimated with the Wathan formula. Most accurate for sets of about 10 reps or fewer.")
                        }
                        if mode == .detail { info(ex) }
                        HistoryList(exId: exId)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 40)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle(mode == .detail ? ex.name : "History")
                .navigationSubtitle(mode == .history ? ex.name : "")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Close")
                    }
                    if mode == .detail {
                        ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
                    }
                }
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .sheet(isPresented: $editing) { ExerciseForm(exId: exId, deleted: { dismiss() }) }
    }

    @ViewBuilder private func info(_ ex: Exercise) -> some View {
        if let note = ex.note, !note.isEmpty {
            section("Note")
            Text(note).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 12).card()
        }
        section("Instructions")
        VStack(alignment: .leading, spacing: 0) {
            if !ex.instructions.isEmpty { Text(ex.instructions).lineSpacing(3).padding(.horizontal, 16).padding(.vertical, 12) }
            if let v = ytId(ex.video), let url = URL(string: "https://www.youtube.com/watch?v=\(v)") {
                if !ex.instructions.isEmpty { Divider().padding(.leading, 16) }
                Link(destination: url) { Label("Watch video on YouTube", systemImage: "play.rectangle.fill").frame(maxWidth: .infinity).padding(.vertical, 13) }
            }
            if ex.instructions.isEmpty && ytId(ex.video) == nil {
                Text("No instructions yet. Tap Edit to add some.").foregroundStyle(Color.label2).frame(maxWidth: .infinity).padding(.vertical, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 20, weight: .bold)).padding(.horizontal, 4).padding(.top, 26).padding(.bottom, 8)
    }
    private func footnote(_ t: String) -> some View {
        Text(t).font(.system(size: 13)).foregroundStyle(Color.label2).padding(.horizontal, 16).padding(.top, 8)
    }
}

/// Latest value, change since the first session and the best, over the chart.
struct ProgressCard: View {
    @Environment(Store.self) private var store
    let exId: String
    let stat: StatKind
    var ix: SetIndex? = nil              // someone else's sets (a friend's); nil = yours
    @AppStorage("tt.range") private var rangeRaw = ChartRange.all.rawValue

    private var range: ChartRange { ChartRange(rawValue: rangeRaw) ?? .all }

    var body: some View {
        let x = ix ?? store.index
        let all = x.series(exId, stat, store.units), pts = x.series(exId, stat, store.units, range, today: store.today), unit = store.statUnit(stat)
        VStack(alignment: .leading, spacing: 2) {
            if let last = all.last {
                Text("Latest · \(Fmt.short(last.k))").font(.system(size: 15)).foregroundStyle(Color.label2)
                Text("\(Text(fmtStat(last.v, stat)).font(.rounded(34, .bold)))\(Text(" " + unit).font(.rounded(17)).foregroundStyle(Color.label2))")
                    .contentTransition(.numericText()).monospacedDigit()
                // change and best within the range shown
                if pts.count > 1, let lastIn = pts.last {
                    let diff = lastIn.v - pts[0].v, best = pts.map(\.v).max() ?? 0
                    Text("\(Text("\(diff >= 0 ? "+" : "−")\(fmtStat(abs(diff), stat)) \(unit)").foregroundStyle(diff > 0 ? Color.green : Color.label2)) since \(Fmt.tiny(pts[0].k)) · Best \(fmtStat(best, stat))")
                        .font(.system(size: 15)).foregroundStyle(Color.label2).monospacedDigit()
                        .contentTransition(.numericText())
                }
                if pts.isEmpty {
                    Text("No sessions in the last \(range.long).").foregroundStyle(Color.label2)
                        .frame(maxWidth: .infinity).frame(height: 236)
                } else {
                    ProgressChart(pts: pts, stat: stat, unit: unit).padding(.top, 12)
                }
                Picker("Range", selection: Binding(get: { range }, set: { v in Haptics.select(); Motion.run(Motion.screen) { rangeRaw = v.rawValue } })) {
                    ForEach(ChartRange.allCases) { r in Text(r.short).accessibilityLabel(r.long).tag(r) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 14)
            } else {
                Text("Log some sets to see your progress here.").foregroundStyle(Color.label2).frame(maxWidth: .infinity).padding(.vertical, 20)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .animation(Motion.soft, value: stat)
        .animation(Motion.screen, value: range)
    }
}

/// A smooth line (never overshoots) with a soft fill, the latest point ringed; drag across it to read any session.
struct ProgressChart: View {
    let pts: [StatPoint]
    let stat: StatKind
    let unit: String
    @State private var selDate: Date?
    @State private var reveal: CGFloat = 0
    @State private var lastSel: String?

    private var ticks: [Double] {
        var lo = pts.map(\.v).min() ?? 0, hi = pts.map(\.v).max() ?? 1
        if lo == hi { let p = max(1, abs(lo) * 0.05); lo -= p; hi += p }
        return niceTicks(lo, hi, 4)
    }
    private var selected: StatPoint? {
        guard let d = selDate else { return nil }
        return pts.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) }
    }

    var body: some View {
        let t = ticks, y0 = t.first ?? 0, y1 = t.last ?? 1
        let fill = LinearGradient(stops: [.init(color: Color.tint.opacity(0.26), location: 0), .init(color: Color.tint.opacity(0.05), location: 0.65), .init(color: Color.tint.opacity(0), location: 1)],
                                  startPoint: .top, endPoint: .bottom)
        Chart {
            ForEach(pts) { p in
                if pts.count > 1 {
                    AreaMark(x: .value("Day", p.date), yStart: .value("Base", y0), yEnd: .value(stat.label, p.v))
                        .interpolationMethod(.monotone).foregroundStyle(fill)
                }
                LineMark(x: .value("Day", p.date), y: .value(stat.label, p.v))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.75, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.tint)
                if pts.count <= 24 && p.id != pts.last?.id {
                    PointMark(x: .value("Day", p.date), y: .value(stat.label, p.v)).symbolSize(30).foregroundStyle(Color.tint)
                }
            }
            if let last = pts.last {
                PointMark(x: .value("Day", last.date), y: .value(stat.label, last.v)).symbolSize(320).foregroundStyle(Color.tint.opacity(0.18))
                PointMark(x: .value("Day", last.date), y: .value(stat.label, last.v)).symbolSize(70).foregroundStyle(Color.tint)
            }
            if let s = selected {
                RuleMark(x: .value("Day", s.date)).foregroundStyle(Color.label2.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text("\(Text("\(fmtStat(s.v, stat)) \(unit)").bold()) · \(Fmt.tiny(s.k)) · \(s.note)")
                            .font(.system(size: 13)).monospacedDigit()
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(uiColor: .tertiarySystemBackground), in: Capsule())
                            .overlay { Capsule().strokeBorder(Color.sep.opacity(0.5), lineWidth: 0.5) }
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    }
                PointMark(x: .value("Day", s.date), y: .value(stat.label, s.v)).symbolSize(110).foregroundStyle(Color.tint)
            }
        }
        .chartYScale(domain: y0...y1)
        .chartXScale(range: .plotDimension(padding: pts.count == 1 ? 40 : 8))
        .chartYAxis {
            AxisMarks(position: .leading, values: t) { v in
                AxisGridLine().foregroundStyle(Color.sep.opacity(0.6))
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(stat == .volume && y1 >= 10000 ? "\(Int((d / 1000).rounded()))k" : num(d)).font(.system(size: 11)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: pts.count > 1 ? [pts.first!.date, pts.last!.date] : pts.map(\.date)) { v in
                AxisValueLabel(anchor: v.index == 0 && pts.count > 1 ? .topLeading : (pts.count > 1 ? .topTrailing : .top)) {
                    if let d = v.as(Date.self) { Text(Fmt.tiny(Day0.key(d))).font(.system(size: 11)) }
                }
            }
        }
        .chartXSelection(value: $selDate)
        .onChange(of: selected?.id) { _, id in if id != nil && lastSel != nil && id != lastSel { Haptics.select() }; lastSel = id }   // a tick from point to point
        .frame(height: 210)
        .padding(.top, 26)   // room for the reading above the chart
        .mask(alignment: .leading) { GeometryReader { g in Rectangle().frame(width: g.size.width * reveal) } }
        .onAppear { if Motion.reduced { reveal = 1 } else { withAnimation(.easeOut(duration: 0.9)) { reveal = 1 } } }   // draws in once
        .accessibilityLabel("\(stat.label) over time")
    }
}

/// "Nice" axis steps (1, 2, 2.5, 5, 10 × a power of ten), like the web app's chart.
func niceTicks(_ lo: Double, _ hi: Double, _ n: Int) -> [Double] {
    let raw = (hi - lo) / Double(n)
    let mag = pow(10, floor(log10(raw)))
    let norm = raw / mag
    let step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 2.5 ? 2.5 : norm <= 5 ? 5 : 10) * mag
    var out: [Double] = []
    var v = floor(lo / step) * step
    while true { out.append((v * 1e6).rounded() / 1e6); if v >= hi - 1e-9 || out.count > 50 { break }; v += step }
    return out
}

/// Every session of an exercise, newest first: the day, its estimated 1RM, and each set (PR in orange).
struct HistoryList: View {
    @Environment(Store.self) private var store
    let exId: String
    var ix: SetIndex? = nil              // someone else's sets (a friend's); nil = yours
    @State private var playing: VideoRoute?
    @State private var openLog: LogRoute?

    var body: some View {
        let x = ix ?? store.index
        let dates = Array((x.exDates[exId] ?? []).reversed()), prs = x.prSets(exId)   // PRs once per list, not per card
        Text("History").font(.system(size: 20, weight: .bold)).padding(.horizontal, 4).padding(.top, 26).padding(.bottom, 8)
        if dates.isEmpty {
            Text("No sets logged yet.").foregroundStyle(Color.label2).frame(maxWidth: .infinity).padding(.vertical, 18).card()
        }
        LazyVStack(spacing: 10) {
            ForEach(dates, id: \.self) { k in
                // Your own days open that day's exercise screen on top; closing it comes back here (2026-11-12, Lukas)
                if ix == nil, store.logStart(exId, k) != nil {
                    Button { Haptics.select(); openLog = LogRoute(day: k, exId: exId) } label: { dayCard(k, x, prs, tappable: true) }
                        .buttonStyle(CardPressStyle())
                        .card()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .accessibilityHint("Opens the exercise on that day")
                } else {
                    dayCard(k, x, prs, tappable: false).card()
                }
            }
        }
        .sheet(item: $playing) { VideoPlayerSheet(route: $0) }
        .sheet(item: $openLog) { r in
            LogView(day: r.day, startExId: r.exId, startIndex: store.logStart(r.exId, r.day) ?? 0)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(38)
        }
    }

    private func dayCard(_ k: String, _ x: SetIndex, _ prs: [String: String], tappable: Bool) -> some View {
        let ss = x.byExDate[exId + "|" + k] ?? [], u = store.units
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(store.relDay(k)).fontWeight(.semibold).foregroundStyle(.primary)
                Spacer()
                Text("e1RM \(fmtStat(u.toU(ss.map(e1rm).max() ?? 0), .e1rm)) \(u.u)").font(.system(size: 15)).foregroundStyle(Color.label2).monospacedDigit()
                if tappable {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.label3)
                }
            }
            .padding(.bottom, 6)
            ForEach(Array(ss.enumerated()), id: \.element.id) { i, s in
                HStack(spacing: 12) {
                    Text("\(i + 1)").font(.rounded(15, .bold)).foregroundStyle(Color.label3).frame(width: 18, alignment: .leading)
                    Text("\(u.w(s.weight)) \(u.u) × \(s.reps)").monospacedDigit().foregroundStyle(.primary)
                    if prs[k] == s.id {
                        Text("PR").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.orange.opacity(0.16), in: Capsule())
                    }
                    // videos linked to the set (yours only: a friend's are in their Photos)
                    if ix == nil, let vs = s.v, !vs.isEmpty {
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            ForEach(vs.prefix(3), id: \.self) { id in
                                Button { Haptics.select(); playing = VideoRoute(setId: s.id, start: id) } label: { VideoThumb(id: id, size: 52) }
                                    .buttonStyle(PressStyle(scale: 0.92))
                            }
                            if vs.count > 3 { Text("+\(vs.count - 3)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.label2) }
                        }
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
