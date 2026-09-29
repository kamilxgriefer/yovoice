// Apple oracle for the Yeel rotation goldens (ADR-235).
//
//   swift tool/fixtures/verify_reel_rotation_avfoundation.swift test/fixtures/reels/*.mp4 test/fixtures/reels/*.mov
//
// For every file prints what AVFoundation — and therefore
// video_player_avfoundation — makes of the video track matrix:
//   * the track's preferredTransform (a b c d tx ty),
//   * AVPlayerItem.presentationSize, the size the plugin reports to Flutter,
//     both plain and with the plugin's rotation videoComposition,
//   * which quadrant the red marker lands in on a frame rendered with the
//     preferred transform applied (TL for identity; TR / BR / BL for r = 1/2/3).
import AVFoundation
import AppKit
import Foundation

func quadrant(of image: CGImage) -> String {
  let rep = NSBitmapImageRep(cgImage: image)
  let width = rep.pixelsWide, height = rep.pixelsHigh
  func red(_ x: Int, _ y: Int) -> Bool {
    guard let color = rep.colorAt(x: x, y: y) else { return false }
    return color.redComponent > 0.6 && color.blueComponent < 0.3
  }
  let hits = [
    ("TL", red(width / 4, height / 4)), ("TR", red(3 * width / 4, height / 4)),
    ("BL", red(width / 4, 3 * height / 4)), ("BR", red(3 * width / 4, 3 * height / 4)),
  ].filter { $0.1 }.map { $0.0 }
  return "\(width)x\(height) red=\(hits.joined(separator: ","))"
}

func presentationSize(_ url: URL, withComposition: Bool) -> CGSize {
  let asset = AVURLAsset(url: url)
  let item = AVPlayerItem(asset: asset)
  if withComposition, let track = asset.tracks(withMediaType: .video).first {
    // The plugin's FVPGetStandardizedTrackTransform path: a composition whose
    // render size is the rotated natural size.
    let composition = AVMutableVideoComposition(propertiesOf: asset)
    let transform = track.preferredTransform
    let degrees = Int((atan2(transform.b, transform.a) * 180 / .pi).rounded())
    composition.renderSize =
      (degrees == 90 || degrees == -90)
      ? CGSize(width: track.naturalSize.height, height: track.naturalSize.width)
      : track.naturalSize
    item.videoComposition = composition
  }
  let player = AVPlayer(playerItem: item)
  var spins = 0
  while item.status != .readyToPlay && spins < 500 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    spins += 1
  }
  _ = player
  return item.presentationSize
}

for path in CommandLine.arguments.dropFirst() {
  let url = URL(fileURLWithPath: path)
  let asset = AVURLAsset(url: url)
  guard let track = asset.tracks(withMediaType: .video).first else {
    print("\(url.lastPathComponent): no video track")
    continue
  }
  let t = track.preferredTransform
  let generator = AVAssetImageGenerator(asset: asset)
  generator.appliesPreferredTrackTransform = true
  generator.requestedTimeToleranceBefore = .positiveInfinity
  generator.requestedTimeToleranceAfter = .positiveInfinity
  var marker = "no frame"
  if let image = try? generator.copyCGImage(at: CMTime(value: 1, timescale: 10), actualTime: nil) {
    marker = quadrant(of: image)
  }
  print(
    url.lastPathComponent,
    "transform=[\(t.a) \(t.b) \(t.c) \(t.d) \(t.tx) \(t.ty)]",
    "natural=\(track.naturalSize)",
    "presentation=\(presentationSize(url, withComposition: false))",
    "presentation+composition=\(presentationSize(url, withComposition: true))",
    "frame=\(marker)")
}
