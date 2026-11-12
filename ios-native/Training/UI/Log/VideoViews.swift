import SwiftUI
import PhotosUI
import AVKit

/// "Link video" on the exercise screen: pick the set(s) the video is of, then the video(s) in Photos.
struct LinkVideoSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: String
    let exId: String
    let g: String
    @State private var chosen: Set<String> = []
    @State private var picking = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var denied = false

    private var sets: [LoggedSet] { store.setsOf(exId, day, g).sorted { $0.slot < $1.slot } }

    var body: some View {
        let u = store.units
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if sets.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "video").font(.system(size: 24)).foregroundStyle(Color.label2)
                                .frame(width: 56, height: 56).background(Color.fill, in: Circle())
                            Text("No sets done yet").font(.system(size: 19, weight: .bold)).padding(.top, 8)
                            Text("Tick a set first, then link the video of it.")
                                .font(.system(size: 15)).foregroundStyle(Color.label2).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        Text("Which sets is the video of?")
                            .font(.system(size: 15)).foregroundStyle(Color.label2).padding(.horizontal, 6)
                        VStack(spacing: 0) {
                            ForEach(Array(sets.enumerated()), id: \.element.id) { n, s in
                                let on = chosen.contains(s.id)
                                Button {
                                    Haptics.select()
                                    Motion.run { if on { chosen.remove(s.id) } else { chosen.insert(s.id) } }
                                } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle().strokeBorder(on ? Color.tint : Color.label3, lineWidth: 2)
                                            Circle().fill(Color.tint).scaleEffect(on ? 1 : 0.3).opacity(on ? 1 : 0)
                                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                                .opacity(on ? 1 : 0)
                                        }
                                        .frame(width: 26, height: 26)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Set \(s.slot + 1)").font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
                                            Text("\(u.w(s.weight)) \(u.u) × \(s.reps)" + ((s.v?.count ?? 0) > 0 ? " · " + Fmt.plural(s.v!.count, "video") : ""))
                                                .font(.system(size: 15)).foregroundStyle(Color.label2).monospacedDigit()
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 18).frame(minHeight: 62)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(CardPressStyle())
                                .overlay(alignment: .top) { if n > 0 { Divider().padding(.leading, 58) } }
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        .card()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                        if denied {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("The app needs access to your Photos to link and play videos.")
                                    .font(.system(size: 15)).foregroundStyle(Color.label2)
                                Button("Open Settings") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                }
                                .font(.system(size: 15, weight: .semibold))
                            }
                            .padding(.horizontal, 6).padding(.top, 6)
                        } else if VideoLibrary.access == .limited {
                            Text("You've given access to some photos only. Videos you pick may not play until you allow all photos in Settings.")
                                .font(.footnote).foregroundStyle(Color.label2).padding(.horizontal, 6).padding(.top, 4)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !sets.isEmpty {
                    Button { choose() } label: { Label("Choose from Photos", systemImage: "photo.on.rectangle") }
                        .buttonStyle(PrimaryButton())
                        .disabled(chosen.isEmpty)
                        .padding(.horizontal, 16).padding(.bottom, 8)
                }
            }
            .navigationTitle("Link video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .photosPicker(isPresented: $picking, selection: $picked, maxSelectionCount: 10, selectionBehavior: .ordered,
                          matching: .videos, preferredItemEncoding: .current, photoLibrary: .shared())
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                let locals = items.compactMap(\.itemIdentifier)
                picked = []
                guard !locals.isEmpty else { return }
                store.linkVideos(VideoLibrary.ids(forLocal: locals), to: chosen)
                Haptics.success()
                store.showToast(.init(kind: .done, title: locals.count == 1 ? "Video linked" : "\(locals.count) videos linked",
                                      sub: chosen.count == 1 ? "To set \((sets.first { chosen.contains($0.id) }?.slot ?? 0) + 1)" : "To \(chosen.count) sets"))
                dismiss()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { if sets.count == 1 { chosen = [sets[0].id] } }   // just one set: it's that one
    }

    private func choose() {
        Haptics.select()
        Task {
            var s = VideoLibrary.access
            if s == .notDetermined { s = await VideoLibrary.requestAccess() }
            if s == .authorized || s == .limited { denied = false; picking = true }
            else { Haptics.warn(); Motion.run { denied = true } }
        }
    }
}

/// A linked video's thumbnail with a play mark and its length (a dashed box if it's not in Photos on this phone).
struct VideoThumb: View {
    let id: String
    var size: CGFloat = 52
    @State private var img: UIImage?
    @State private var missing = false
    @State private var length = ""

    var body: some View {
        ZStack {
            if let img {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: size, height: size).clipped()
                    .transition(.opacity)
                Color.black.opacity(0.18)
                Image(systemName: "play.fill").font(.system(size: size * 0.28)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 3)
                if size >= 48 && !length.isEmpty {
                    Text(length).font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(4)
                }
            } else {
                Color.fill
                Image(systemName: missing ? "video.slash" : "video").font(.system(size: size * 0.3)).foregroundStyle(Color.label2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .task(id: id) {
            if let a = VideoLibrary.asset(id) { length = VideoLibrary.duration(a) }
            let t = await VideoLibrary.thumbnail(id, size: size)
            withAnimation(.easeOut(duration: 0.25)) { img = t; missing = t == nil }
        }
        .accessibilityLabel(missing ? "Video not found" : "Video" + (length.isEmpty ? "" : ", \(length)"))
    }
}

struct VideoRoute: Identifiable, Hashable { var setId: String; var start: String; var id: String { setId + "|" + start } }

/// Plays a set's videos (swipe between them if there are several); unlink one from the menu.
struct VideoPlayerSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let route: VideoRoute
    @State private var current: String?

    private var set: LoggedSet? { store.data.sets.first { $0.id == route.setId } }

    var body: some View {
        let ids = set?.v ?? []
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if ids.isEmpty {
                    Text("No videos linked").foregroundStyle(.white.opacity(0.7))
                } else {
                    TabView(selection: $current) {
                        ForEach(ids, id: \.self) { id in
                            VideoPage(id: id, setId: route.setId, active: current == id).tag(Optional(id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: ids.count > 1 ? .always : .never))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                }
                if let current, ids.contains(current) {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(role: .destructive) {
                                Haptics.impact()
                                let left = ids.filter { $0 != current }
                                Motion.run { store.unlinkVideo(current, from: route.setId) }
                                if left.isEmpty { dismiss() } else { self.current = left.first }
                            } label: { Label("Unlink from this set", systemImage: "link.badge.minus") }
                        } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("More")
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { if current == nil { current = route.start }; VideoLibrary.movieSound(true) }
        .onDisappear { VideoLibrary.movieSound(false) }
    }

    private var title: String {
        guard let s = set else { return "Video" }
        let name = store.exById(s.exId)?.name ?? "Set"
        return "\(name) · set \(s.slot + 1)"
    }
}

/// One video: loads it from Photos (from iCloud if needed) and plays it.
private struct VideoPage: View {
    @Environment(Store.self) private var store
    let id: String
    let setId: String
    let active: Bool
    @State private var player: AVPlayer?
    @State private var state: Loading = .loading
    enum Loading { case loading, ready, missing }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch state {
                case .loading: ProgressView().tint(.white)
                case .ready: if let player { VideoPlayer(player: player) }
                case .missing:
                    VStack(spacing: 10) {
                        Image(systemName: "video.slash").font(.system(size: 30)).foregroundStyle(.white.opacity(0.7))
                        Text("This video isn't in Photos on this phone").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        Text("It may have been deleted. If you've just switched phones, iCloud Photos may still be bringing it over.")
                            .font(.system(size: 15)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let s = setInfo {
                Text(s).font(.system(size: 15)).foregroundStyle(.white.opacity(0.75)).monospacedDigit()
                    .padding(.top, 10).padding(.bottom, 44)
            }
        }
        .task(id: id) {
            guard let a = VideoLibrary.asset(id) else { state = .missing; return }
            guard let item = await VideoLibrary.playerItem(a) else { state = .missing; return }
            player = AVPlayer(playerItem: item)
            state = .ready
            if active { player?.play() }
        }
        .onChange(of: active) { _, on in if on { player?.play() } else { player?.pause() } }
        .onDisappear { player?.pause() }
    }

    private var setInfo: String? {
        guard let s = store.data.sets.first(where: { $0.id == setId }) else { return nil }
        let u = store.units
        return "\(u.w(s.weight)) \(u.u) × \(s.reps) · \(Fmt.dayYear(s.date))"
    }
}
