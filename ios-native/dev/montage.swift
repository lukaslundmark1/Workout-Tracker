// Puts extracted frames side by side in one image (the bottom part of each, from cropTopFraction down).
// swift ios-native/dev/montage.swift <dir> <first> <last> <step> <cropTopFraction 0..1> <out.png>
import AppKit
let a = CommandLine.arguments
let dir = a[1], first = Int(a[2])!, last = Int(a[3])!, step = Int(a[4])!, cropTop = Double(a[5])!
var imgs: [(Int, CGImage)] = []
var i = first
while i <= last {
  let p = "\(dir)/f\(String(format: "%03d", i)).png"
  if let im = NSImage(contentsOfFile: p), let cg = im.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    let h = cg.height, y = Int(Double(h) * cropTop)
    if let c = cg.cropping(to: CGRect(x: 0, y: y, width: cg.width, height: h - y)) { imgs.append((i, c)) }
  }
  i += step
}
let cols = 6, w = imgs[0].1.width, h = imgs[0].1.height
let rows = (imgs.count + cols - 1) / cols
let ctx = CGContext(data: nil, width: cols * w, height: rows * (h + 14), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(NSColor.red.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: cols * w, height: rows * (h + 14)))
for (n, (idx, im)) in imgs.enumerated() {
  let r = n / cols, c = n % cols
  ctx.draw(im, in: CGRect(x: c * w, y: (rows - 1 - r) * (h + 14), width: w, height: h))
  _ = idx
}
let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[6]))
print(imgs.map { $0.0 })
