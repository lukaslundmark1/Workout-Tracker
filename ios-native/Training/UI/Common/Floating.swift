import SwiftUI

/// Rest stopwatch: counts up from the last ticked set. ✕ turns it off.
struct RestPill: View {
    @Environment(Store.self) private var store
    let rest: RestState

    var body: some View {
        HStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("REST").font(.system(size: 13, weight: .semibold)).tracking(0.5).foregroundStyle(Color.label2)
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text(Fmt.dur(nowMs() - rest.start)).font(.rounded(24, .bold)).monospacedDigit()
                }
                if let ex = store.exById(rest.exId) {
                    Text(ex.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.label2).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { Haptics.select(); store.rest = nil } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.label2).frame(width: 42, height: 42).contentShape(Circle())
            }
            .buttonStyle(PressStyle(scale: 0.85))
            .accessibilityLabel("Stop rest stopwatch")
        }
        .padding(.leading, 20).padding(.trailing, 6)
        .frame(height: 54)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 24)
    }
}

/// "New personal record" / "All planned sets done", sliding down from the top.
struct ToastView: View {
    @Environment(Store.self) private var store
    var body: some View {
        ZStack {
            if let t = store.toast {
                let (icon, color): (String, Color) = t.kind == .pr ? ("trophy.fill", .orange) : t.kind == .done ? ("checkmark", .green) : t.kind == .gift ? ("gift.fill", .tint) : ("arrow.right", .tint)
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(color)
                        .frame(width: 34, height: 34)
                        .background(color.opacity(0.16), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.system(size: 15, weight: .semibold))
                        if let s = t.sub { Text(s).font(.system(size: 13)).foregroundStyle(Color.label2) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10).padding(.trailing, 18).padding(.vertical, 9)
                .background(Color.card.opacity(0.75), in: Capsule())   // solid enough to read over the header
                .glassEffect(.regular, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .id(t.id)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { store.toast = nil }
            }
        }
        .animation(Motion.sheet, value: store.toast)
    }
}
