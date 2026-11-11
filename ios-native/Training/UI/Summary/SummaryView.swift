import SwiftUI

/// After Finish: a big check, duration / sets / kg lifted / exercises (counting up), personal records,
/// and each exercise's best set compared with last time.
struct SummaryView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: String
    var g: String? = nil                   // one workout, or the whole day
    var open: (String) -> Void             // tap an exercise: open it on the exercise screen
    @State private var shown = false       // numbers count up and the check pops when it opens

    var body: some View {
        let s = store.summary(day, g), u = store.units
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero
                    Image(systemName: "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 72, height: 72).background(Color.green, in: Circle())
                        .scaleEffect(shown ? 1 : 0.4).opacity(shown ? 1 : 0)
                        .padding(.bottom, 12)
                    Text(day == store.today ? "Workout complete" : "Workout summary").font(.system(size: 34, weight: .bold)).tracking(-0.8)
                    Text("\(s.title) · \(Fmt.long(day))").font(.system(size: 15)).foregroundStyle(Color.label2).multilineTextAlignment(.center)
                        .padding(.top, 2).padding(.bottom, 18)

                    // Stats
                    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            stat(s.durationMs.map { Fmt.mins($0) } ?? "–", "duration", count: nil)
                            stat("\(s.sets)", "sets", count: Double(s.sets))
                        }
                        GridRow {
                            stat(fmtStat(u.toU(s.volumeKg), .volume), "\(u.u) lifted", count: u.toU(s.volumeKg), volume: true)
                            stat("\(s.exercises.count)", s.exercises.count == 1 ? "exercise" : "exercises", count: Double(s.exercises.count))
                        }
                    }

                    if !s.prs.isEmpty {
                        header("Personal records")
                        VStack(spacing: 0) {
                            ForEach(Array(s.prs.enumerated()), id: \.element.id) { i, p in
                                if i > 0 { Divider().padding(.leading, 60) }
                                Button { go(p.id) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "trophy.fill").foregroundStyle(Color.orange)
                                            .frame(width: 32, height: 32).background(Color.orange.opacity(0.16), in: Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(p.name).foregroundStyle(Color.primary)
                                            Text("Est. 1RM \(fmtStat(u.toU(p.now), .e1rm)) \(u.u) · up \(fmtStat(u.toU(p.now - p.prev), .e1rm)) \(u.u)")
                                                .font(.system(size: 15)).foregroundStyle(Color.label2).monospacedDigit()
                                        }
                                        Spacer(minLength: 4)
                                        Text(u.setText(p.set)).foregroundStyle(Color.label2).monospacedDigit()
                                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.label3)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                                }
                                .buttonStyle(CardPressStyle())
                            }
                        }
                        .card().clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }

                    if !s.exercises.isEmpty {
                        header("Exercises")
                        VStack(spacing: 0) {
                            ForEach(Array(s.exercises.enumerated()), id: \.element.id) { i, r in
                                if i > 0 { Divider().padding(.leading, 16) }
                                Button { go(r.id) } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(r.name).foregroundStyle(Color.primary)
                                            Text("\(Fmt.plural(r.sets, "set")) · best \(u.setText(r.best))").font(.system(size: 15)).foregroundStyle(Color.label2).monospacedDigit()
                                        }
                                        Spacer(minLength: 4)
                                        delta(r.delta)
                                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.label3)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                                }
                                .buttonStyle(CardPressStyle())
                            }
                        }
                        .card().clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        Text("Arrows compare each exercise's best set (estimated 1RM) with the last time you did it.")
                            .font(.system(size: 13)).foregroundStyle(Color.label2)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 8)
                    }

                    Button("Done") { Haptics.select(); dismiss() }
                        .buttonStyle(PrimaryButton())
                        .padding(.top, 24)
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Close")
                }
            }
        }
        .onAppear {
            if Motion.reduced { shown = true; return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.15)) { shown = true }
        }
    }

    private func go(_ exId: String) { Haptics.select(); dismiss(); open(exId) }

    /// A number tile; whole numbers count up from 0 when the summary opens
    private func stat(_ text: String, _ label: String, count: Double?, volume: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if let count {
                    let v = shown ? count : 0
                    Text(volume ? fmtStat(v, .volume) : "\(Int(v.rounded()))").contentTransition(.numericText(value: v))
                } else {
                    Text(text)
                }
            }
            .font(.rounded(26, .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            .animation(.easeOut(duration: 0.9).delay(0.1), value: shown)
            Text(label).font(.system(size: 13)).foregroundStyle(Color.label2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .card()
    }

    private func header(_ t: String) -> some View {
        Text(t).font(.system(size: 20, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4).padding(.top, 26).padding(.bottom, 8)
    }

    @ViewBuilder private func delta(_ d: WorkoutSummary.Delta) -> some View {
        switch d {
        case .first: Text("First time").foregroundStyle(Color.label2)
        case .same:   // grey, between the green ▲ and the red ▼
            Image(systemName: "equal").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.label2)
                .frame(minWidth: 22).accessibilityLabel("Same as last time")
        case .up(let p): Text("▲ \(p)%").fontWeight(.semibold).foregroundStyle(Color.green).monospacedDigit()
        case .down(let p): Text("▼ \(p)%").fontWeight(.semibold).foregroundStyle(Color.red).monospacedDigit()
        }
    }
}
