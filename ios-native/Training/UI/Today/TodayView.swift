import SwiftUI

struct LogRoute: Hashable, Identifiable { var day: String; var exId: String; var id: String { day + "|" + exId } }

/// The Today tab: month header, week strip, and the day itself, which you swipe left/right.
struct TodayView: View {
    @Environment(Store.self) private var store
    @State private var openLog: LogRoute?
    @State private var base = Day0.today          // day offsets count from here (fixed while the view lives)
    @State private var dayPos: Int? = 0
    @State private var weekPos: Int? = 0
    @State private var showAdd = false
    @State private var finishFor: DayKey?
    @State private var moveFor: DayKey?

    private var firstDay: Int { store.data.settings.weekStart }
    private var baseWeek: String { Day0.weekStart(base, firstDay: firstDay) }
    private func dayKey(_ off: Int) -> String { Day0.add(base, off) }
    private func weekKey(_ off: Int) -> String { Day0.add(baseWeek, off * 7) }
    private func weekOff(of k: String) -> Int { Day0.between(baseWeek, Day0.weekStart(k, firstDay: firstDay)) / 7 }
    private var shownWeek: String { weekKey(weekPos ?? 0) }

    var body: some View {
        VStack(spacing: 0) {
                header
                WeekStrip(pos: $weekPos, weekKey: weekKey, select: { k in
                    guard k != store.selected else { return }
                    Haptics.select()
                    Motion.run { store.selected = k }
                })
                .padding(.bottom, 14)
                dayPager
        }
        .background(Color.bg)
        // The exercise screen slides up from the bottom; swipe it down (or tap ⌄) and it goes back down
        .sheet(item: $openLog) { r in
            LogView(day: r.day, startExId: r.exId, startIndex: store.dayOf(r.day).items.firstIndex { $0.exId == r.exId } ?? 0)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(38)
        }
        .onAppear { sync(to: store.selected, animated: false) }
        .onChange(of: dayPos) { _, p in
            guard let p else { return }
            let k = dayKey(p)
            if k != store.selected {
                store.padClose()
                Motion.run { store.selected = k }
            }
            let w = weekOff(of: k)
            if weekPos != w { Motion.run { weekPos = w } }
        }
        .onChange(of: store.selected) { _, k in sync(to: k, animated: true) }
        .sheet(isPresented: $showAdd) {
            AddSheet(day: store.selected) { exId in
                // a single exercise opens right away, like the web app; a workout stays on the day
                if let exId { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { openLog = LogRoute(day: store.selected, exId: exId) } }
            }
        }
        .sheet(item: $finishFor) { d in FinishSheet(day: d.k) { _ in } }
        .sheet(item: Binding(get: { store.summaryFor.map { DayKey(k: $0) } }, set: { store.summaryFor = $0?.k })) { d in
            SummaryView(day: d.k) { exId in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { openLog = LogRoute(day: d.k, exId: exId) }
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $moveFor) { d in MoveBackSheet(day: d.k).presentationDetents([.large]) }
        // Stored copies of planned days that no longer match the plan are dropped (like every redraw in the web app)
        .onChange(of: store.data) { store.purgeStalePlanDays() }
        .onAppear { store.purgeStalePlanDays() }
    }

    private func sync(to k: String, animated: Bool) {
        let p = Day0.between(base, k)
        if dayPos != p { if animated { Motion.run(Motion.screen) { dayPos = p } } else { dayPos = p } }
        let w = weekOff(of: k)
        if weekPos != w { if animated { Motion.run { weekPos = w } } else { weekPos = w } }
    }

    // Month name, Today (only when looking at another week), previous/next week
    private var header: some View {
        let label = Fmt.weekLabel(shownWeek)
        let otherWeek = (weekPos ?? 0) != weekOff(of: store.today)
        return HStack(spacing: 8) {
            Text("\(label.text)\(Text(label.year.map { " " + $0 } ?? "").foregroundStyle(Color.label2))")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(Motion.soft, value: label.text)
            Spacer(minLength: 4)
            if otherWeek {
                Button("Today") {
                    Haptics.select()
                    Motion.run { weekPos = weekOff(of: store.today) }
                    if store.selected != store.today { Motion.run { store.selected = store.today } }
                }
                .buttonStyle(.glass)
                .transition(.scale(0.8).combined(with: .opacity))
            }
            HStack(spacing: 0) {
                Button { Haptics.select(); Motion.run { weekPos = (weekPos ?? 0) - 1 } } label: {
                    Image(systemName: "chevron.left").frame(width: 46, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Previous week")
                Button { Haptics.select(); Motion.run { weekPos = (weekPos ?? 0) + 1 } } label: {
                    Image(systemName: "chevron.right").frame(width: 46, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Next week")
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .buttonStyle(PressStyle(scale: 0.85))
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .animation(Motion.soft, value: otherWeek)
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    // Days side by side; swipe to go to the previous/next day (quick flicks in a row go further)
    private var dayPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(-800...400, id: \.self) { off in
                    DayPage(k: dayKey(off), onOpen: { openLog = $0 }, onAdd: { showAdd = true }, onFinish: { finishFor = DayKey(k: $0) },
                            onMove: { moveFor = DayKey(k: $0) })
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $dayPos)
        .scrollIndicators(.hidden)
        .scrollDisabled(store.reordering)
    }
}

struct DayKey: Identifiable, Hashable { var k: String; var id: String { k } }

/// One day: date, what's planned, progress, the exercises, Finish and Add.
struct DayPage: View {
    @Environment(Store.self) private var store
    let k: String
    var onOpen: (LogRoute) -> Void
    var onAdd: () -> Void
    var onFinish: (String) -> Void
    var onMove: (String) -> Void

    var body: some View {
        let day = store.dayOf(k)
        let logged = store.hasSets(k)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(Fmt.long(k))
                    .font(.system(size: 22, weight: .bold)).tracking(-0.4)
                    .padding(.horizontal, 2).padding(.bottom, 2)
                Text(store.dayLabel(k))
                    .font(.system(size: 15)).foregroundStyle(Color.label2)
                    .padding(.horizontal, 2).padding(.bottom, 14)

                planButtons(day, logged)

                if !day.items.isEmpty && (day.session != nil || logged) { progress(day) }

                if day.items.isEmpty { empty } else { DayExerciseList(k: k, onOpen: onOpen) }

                // Finish is how a workout ends (the timer only starts and pauses)
                if !day.items.isEmpty && !store.isFinished(k) && (k == store.today || store.isRunning(k)) {
                    Button { onFinish(k) } label: { Label("Finish workout", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButton())
                        .padding(.top, 16)
                }
                Button { onAdd() } label: { Label("Add exercise / workout", systemImage: "plus") }
                    .buttonStyle(TintedButton())
                    .padding(.top, 14)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
            .animation(Motion.soft, value: day)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(store.reordering)
    }

    // Do X today / Do it today / Can't make it today (Move back a day) / Undo move / Undo
    @ViewBuilder private func planButtons(_ day: Day, _ logged: Bool) -> some View {
        let tk = store.today, pd = store.planDayFor(k), st = store.data.days[k]
        let untouched = !logged && day.session == nil
        let canRest = pd?.workout != nil && k >= tk && untouched && !(st != nil && st!.plan == nil && !st!.items.isEmpty) && st?.pinned != true
        let canUnrest = k >= tk && st?.rest == true && st!.items.isEmpty && !logged
        let canUnpin = k >= tk && st?.pinned == true && untouched
        let nx = k == tk && store.todayIsFree && pd != nil && pd!.workout == nil && !pd!.extra ? store.upNext() : nil
        let canDo = store.canDoToday(k)
        let summary = store.isFinished(k) && logged
        if summary || nx != nil || canDo || canRest || canUnrest || canUnpin {
            HStack(spacing: 8) {
                if summary { capsule("Workout summary", "chart.bar.fill") { Haptics.select(); store.summaryFor = k } }
                if let nx { capsule("Do \(nx.workout.name) today", "play.fill") { Motion.run { store.pinToday() } } }
                if canDo { capsule("Do it today", "checkmark") { Motion.run { store.doToday(k) } } }
                if canRest { capsule(k == tk ? "Can't make it today" : "Move back a day", "arrow.right") { Haptics.select(); onMove(k) } }
                if canUnrest { capsule("Undo move", "arrow.counterclockwise") { Haptics.select(); Motion.run { store.unrest(k) } } }
                if canUnpin { capsule("Undo", "arrow.counterclockwise") { Haptics.select(); Motion.run { store.unpin(k) } } }
            }
            .padding(.top, -4).padding(.bottom, 14)
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
        }
    }
    private func capsule(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.tint)
                .padding(.horizontal, 14).frame(height: 36)
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private func progress(_ day: Day) -> some View {
        let total = day.items.reduce(0) { $0 + max($1.sets ?? 0, store.setsOf($1.exId, k).count) }
        let done = day.items.reduce(0) { $0 + store.setsOf($1.exId, k).count }
        return Group {
            if total > 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.fill)
                        Capsule().fill(done >= total ? Color.green : Color.tint)
                            .frame(width: g.size.width * CGFloat(done) / CGFloat(total))
                    }
                }
                .frame(height: 5)
                .padding(.horizontal, 2).padding(.top, -4).padding(.bottom, 16)
                .animation(Motion.screen, value: done)
                .accessibilityElement().accessibilityLabel("Sets done").accessibilityValue("\(done) of \(total)")
            }
        }
    }

    private var empty: some View {
        let past = k < store.today
        let pd = store.planDayFor(k), restDay = pd != nil && pd!.workout == nil
        return VStack(spacing: 4) {
            Image(systemName: restDay ? "moon.fill" : "dumbbell").font(.system(size: 24)).foregroundStyle(Color.label2)
                .frame(width: 56, height: 56).background(Color.fill, in: Circle())
            Text(restDay ? "Rest day" : past ? "Nothing logged" : "Nothing planned").font(.system(size: 19, weight: .bold)).padding(.top, 10)
            Text(restDay ? "Recovery is part of the plan." : past ? "You can still add what you did." : "Add an exercise or a workout to get going.")
                .font(.system(size: 15)).foregroundStyle(Color.label2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 34).padding(.bottom, 26).padding(.horizontal, 20)
    }
}

/// A small ring showing how much of an exercise is done (a green check when it's all done).
struct ProgressRing: View {
    let done: Int, total: Int
    var body: some View {
        let full = total > 0 && done >= total
        ZStack {
            Circle().stroke(Color.fill2, lineWidth: 3)
            Circle().trim(from: 0, to: total > 0 ? CGFloat(min(done, total)) / CGFloat(total) : 0)
                .stroke(Color.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle().fill(Color.green).scaleEffect(full ? 1.08 : 0.4).opacity(full ? 1 : 0)
            CheckShape().trim(from: 0, to: full ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(width: 10, height: 8)
        }
        .frame(width: 20, height: 20)
        .padding(4)
        .animation(Motion.soft, value: done)
        .animation(Motion.soft, value: total)
    }
}

/// A check mark drawn as a path (so it can draw itself in).
struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(LinearGradient(colors: [Color.tint.mix(with: .white, by: 0.1), Color.tint], startPoint: .top, endPoint: .bottom), in: Capsule())
            .shadow(color: Color.tint.opacity(0.35), radius: 10, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.12) : Motion.pop, value: configuration.isPressed)
    }
}
struct TintedButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.tint)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Color.tint.opacity(0.14), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.12) : Motion.pop, value: configuration.isPressed)
    }
}
