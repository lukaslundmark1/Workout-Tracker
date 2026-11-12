import Photos
import UIKit
import AVFoundation

/// Videos linked to sets (2026-11-12, Lukas): the video stays in Photos; a set only remembers which one it is.
/// The id is Photos' cloud identifier, the same on every device signed in to the same iCloud Photos, so links survive a
/// new phone. When Photos can't give one (iCloud Photos off, say), "local:<id>" works on this phone only.
/// Sets sync as before (`LoggedSet.v`); the web app keeps the field and doesn't show it.
extension Store {
    /// Adds videos to sets (each set gets every video; ones it already has aren't doubled)
    func linkVideos(_ ids: [String], to setIds: Set<String>) {
        guard !ids.isEmpty, !setIds.isEmpty else { return }
        var sets = data.sets
        for i in sets.indices where setIds.contains(sets[i].id) {
            var v = sets[i].v ?? []
            for id in ids where !v.contains(id) { v.append(id) }
            sets[i].v = Array(v.prefix(20))
        }
        data.sets = sets
    }

    func unlinkVideo(_ id: String, from setId: String) {
        var sets = data.sets
        guard let i = sets.firstIndex(where: { $0.id == setId }) else { return }
        let v = (sets[i].v ?? []).filter { $0 != id }
        sets[i].v = v.isEmpty ? nil : v
        data.sets = sets
    }
}

/// Finding linked videos in Photos: ids ↔ assets, thumbnails, playback.
enum VideoLibrary {
    private static var assets: [String: PHAsset] = [:]
    private static let thumbs = NSCache<NSString, UIImage>()

    static var access: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// The ids to store for videos picked in Photos (local identifiers on this phone)
    static func ids(forLocal locals: [String]) -> [String] {
        let map = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: locals)
        return locals.map { l in
            if case .success(let c)? = map[l] { return c.stringValue }
            return "local:" + l
        }
    }

    /// The video in Photos for a stored id (nil = not on this phone, or no access)
    static func asset(_ id: String) -> PHAsset? {
        if let a = assets[id] { return a }
        guard access == .authorized || access == .limited else { return nil }
        var local: String?
        if id.hasPrefix("local:") { local = String(id.dropFirst(6)) }
        else if case .success(let l)? = PHPhotoLibrary.shared().localIdentifierMappings(for: [PHCloudIdentifier(stringValue: id)]).first?.value {
            local = l
        }
        guard let local, let a = PHAsset.fetchAssets(withLocalIdentifiers: [local], options: nil).firstObject else { return nil }
        assets[id] = a
        return a
    }

    static func thumbnail(_ id: String, size: CGFloat) async -> UIImage? {
        let key = "\(id)|\(Int(size))" as NSString
        if let t = thumbs.object(forKey: key) { return t }
        guard let a = asset(id) else { return nil }
        let o = PHImageRequestOptions()
        o.deliveryMode = .highQualityFormat          // one answer only (opportunistic answers twice)
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = true
        let px = size * 3
        let img: UIImage? = await withCheckedContinuation { c in
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: px, height: px), contentMode: .aspectFill, options: o) { img, _ in
                c.resume(returning: img)
            }
        }
        if let img { thumbs.setObject(img, forKey: key) }
        return img
    }

    /// Something to play (downloads from iCloud if the phone only keeps a small copy)
    static func playerItem(_ a: PHAsset) async -> AVPlayerItem? {
        let o = PHVideoRequestOptions()
        o.isNetworkAccessAllowed = true
        o.deliveryMode = .automatic
        return await withCheckedContinuation { c in
            PHImageManager.default().requestPlayerItem(forVideo: a, options: o) { item, _ in c.resume(returning: item) }
        }
    }

    /// Sound while a video plays: like a video app, it plays even with the phone on silent (iOS's default for apps
    /// mutes it), pausing other apps' music; closing the player hands the sound back to them.
    static func movieSound(_ on: Bool) {
        let s = AVAudioSession.sharedInstance()
        if on {
            try? s.setCategory(.playback, mode: .moviePlayback)
            try? s.setActive(true)
        } else {
            try? s.setActive(false, options: .notifyOthersOnDeactivation)
            try? s.setCategory(.soloAmbient)
        }
    }

    static func duration(_ a: PHAsset) -> String {
        let s = Int(a.duration.rounded())
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
