import SwiftUI

/// "Can't make it today" / "Move back a day": up to three choices of how far the change reaches, each with a 7-day preview.
struct MoveBackSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: String
    @State private var pick: String?? = .none     // .none = not chosen yet; .some(nil) = "Everything from here"

    private struct Option: Identifiable { var v: String?; var t: String; var d: String; var days: [(k: String, name: String)]; var id: String { v ?? "" } }

    var body: some View {
        if let pd = store.planDayFor(day), let w = pd.workout {
            let base = (0..<7).map { i -> String in let k = Day0.add(day, i); return store.dayLabelFor(k, in: store.schedule, days: store.data.days) }
            let week = pd.plan.days.count == 7
            let all = [
                Option(v: "next", t: "Just this workout", d: "It takes the next rest day. Everything after that stays the same.", days: store.previewDays(day, absorb: "next")),
                Option(v: "round", t: week ? "The rest of the week" : "The rest of this round",
                       d: "Everything moves a day later and the \(week ? "week's" : "round's") last rest day is dropped.", days: store.previewDays(day, absorb: "round")),
                Option(v: nil, t: "Everything from here", d: "The whole plan moves a day later, from now on.", days: store.previewDays(day, absorb: nil)),
            ]
            // A choice that comes out exactly the same as an earlier one isn't shown
            let shown: [Option] = {
                var seen = Set<String>()
                return all.filter { o in seen.insert(o.days.map(\.name).joined(separator: "|") + (o.v == nil ? "*" : "")).inserted }
            }()
            let current: String? = {
                if case .some(let v) = pick, shown.contains(where: { $0.v == v }) { return v }
                return shown[0].v
            }()
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(day == store.today ? "Today" : Fmt.long(day)) becomes a rest day and \(w.name) moves back a day. How far should the change reach?")
                            .font(.system(size: 15)).foregroundStyle(Color.label2)
                            .padding(.horizontal, 8).padding(.bottom, 2)
                        ForEach(shown) { o in option(o, on: o.v == current, base: base) }
                        Button {
                            Haptics.impact()
                            let v = current
                            dismiss()
                            Motion.run { store.moveBack(day, absorb: v) }
                        } label: { Text("Move") }
                            .buttonStyle(PrimaryButton())
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
                .background(Color(uiColor: .secondarySystemBackground))
                .navigationTitle("Move \(w.name)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                    }
                }
            }
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    private func option(_ o: Option, on: Bool, base: [String]) -> some View {
        Button {
            if !on { Haptics.select() }
            Motion.run { pick = .some(o.v) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle().strokeBorder(on ? Color.tint : Color.label3, lineWidth: on ? 7 : 2)
                    .frame(width: 22, height: 22).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(o.t).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                    Text(o.d).font(.system(size: 14)).foregroundStyle(Color.label2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        ForEach(Array(o.days.enumerated()), id: \.offset) { i, d in
                            let changed = d.name != base[i], rest = d.name == "Rest"
                            VStack(spacing: 1) {
                                Text(Fmt.weekdayShort(d.k).uppercased()).font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(changed ? Color.tint : Color.label2)
                                Text(d.name).font(.system(size: 11, weight: rest ? .medium : .semibold))
                                    .foregroundStyle(changed ? Color.tint : rest ? Color.label2 : Color.primary)
                                    .lineLimit(1).truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5).padding(.horizontal, 2)
                            .background(changed ? Color.tint.opacity(0.14) : Color.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? Color.tint : .clear, lineWidth: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }
}
