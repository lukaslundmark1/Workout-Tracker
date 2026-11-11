// Extracts frames from a Simulator recording, to check animations frame by frame.
// xcrun simctl io booted recordVideo --codec=h264 --force out.mp4   (Ctrl-C / kill -INT to stop)
// swift ios-native/dev/frames.swift out.mp4 <outdir> <fps> <maxSeconds>
import AVFoundation
import AppKit
let a = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
gen.maximumSize = CGSize(width: 330, height: 717)
let fps = Double(a[3])!, maxS = Double(a[4])!
let dur = min(CMTimeGetSeconds(asset.duration), maxS)
var t = 0.0, n = 0
while t < dur {
  if let img = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) {
    let rep = NSBitmapImageRep(cgImage: img)
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(a[2])/f\(String(format: "%03d", n)).png"))
  }
  t += 1 / fps; n += 1
}
print("frames:", n, "duration:", CMTimeGetSeconds(asset.duration))
