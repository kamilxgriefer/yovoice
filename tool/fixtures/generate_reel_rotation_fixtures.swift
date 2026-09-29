// Generates the tiny H.264 fixtures behind the Yeel rotation tests (ADR-235).
//
//   swift tool/fixtures/generate_reel_rotation_fixtures.swift test/fixtures/reels
//
// macOS only (AVAssetWriter). Every frame is the same synthetic picture — a
// red top-left quadrant on dark blue — so any oracle (AVFoundation, Chrome,
// ExoPlayer) can read the orientation it applied from where the red lands.
// No personal video is ever involved. The writer stamps creation times into
// mvhd/tkhd, so a regenerated file is not byte-identical to the committed one;
// regenerate the *.rotN goldens afterwards with tool/reel_rotate_fixture.dart.
import AVFoundation
import CoreVideo
import Foundation

struct Fixture {
  let name: String
  let fileType: AVFileType
  let rotation: Int  // clockwise degrees written through AVAssetWriterInput.transform
  let withAudio: Bool
  let moovFirst: Bool
  let videoTracks: Int
}

let width = 64, height = 36, frames = 10
let fps: Int32 = 10

let fixtures = [
  // The "Pixel pointed down" case: an upright shot saved landscape with an
  // identity matrix. ftyp, moov, mdat; video only.
  Fixture(name: "reel_landscape_faststart.mp4", fileType: .mp4, rotation: 0,
          withAudio: false, moovFirst: true, videoTracks: 1),
  // ftyp, mdat, moov; video + AAC; identity.
  Fixture(name: "reel_landscape_av_moovlast.mp4", fileType: .mp4, rotation: 0,
          withAudio: true, moovFirst: false, videoTracks: 1),
  // 'qt  ' brand; ftyp, wide, mdat, moov; the iPhone 90° matrix + AAC.
  Fixture(name: "reel_iphone_rot90.mov", fileType: .mov, rotation: 90,
          withAudio: true, moovFirst: false, videoTracks: 1),
  // Two 'vide' traks.
  Fixture(name: "reel_two_video_tracks.mp4", fileType: .mp4, rotation: 0,
          withAudio: false, moovFirst: true, videoTracks: 2),
]

func picture() -> CVPixelBuffer {
  var buffer: CVPixelBuffer?
  CVPixelBufferCreate(
    nil, width, height, kCVPixelFormatType_32BGRA,
    [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &buffer)
  let pixels = buffer!
  CVPixelBufferLockBaseAddress(pixels, [])
  let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
  let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
  for y in 0..<height {
    for x in 0..<width {
      let pixel = base + y * rowBytes + x * 4
      let red = x < width / 2 && y < height / 2
      pixel[0] = red ? 0 : 120  // B
      pixel[1] = red ? 0 : 30  // G
      pixel[2] = red ? 255 : 20  // R
      pixel[3] = 255
    }
  }
  CVPixelBufferUnlockBaseAddress(pixels, [])
  return pixels
}

func transform(for rotation: Int) -> CGAffineTransform {
  switch rotation {
  case 90: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0)
  case 180:
    return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: CGFloat(width), ty: CGFloat(height))
  case 270: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: CGFloat(width))
  default: return .identity
  }
}

func write(_ fixture: Fixture, into directory: URL) throws {
  let url = directory.appendingPathComponent(fixture.name)
  try? FileManager.default.removeItem(at: url)
  let writer = try AVAssetWriter(outputURL: url, fileType: fixture.fileType)
  writer.shouldOptimizeForNetworkUse = fixture.moovFirst
  var inputs: [AVAssetWriterInput] = []
  var adaptors: [AVAssetWriterInputPixelBufferAdaptor] = []
  for _ in 0..<fixture.videoTracks {
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: 20_000,
          AVVideoMaxKeyFrameIntervalKey: 1000,
          AVVideoAllowFrameReorderingKey: false,
        ],
      ])
    input.expectsMediaDataInRealTime = false
    input.transform = transform(for: fixture.rotation)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ])
    writer.add(input)
    inputs.append(input)
    adaptors.append(adaptor)
  }
  var audio: AVAssetWriterInput?
  if fixture.withAudio {
    let input = AVAssetWriterInput(
      mediaType: .audio,
      outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 8000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 8000,
      ])
    input.expectsMediaDataInRealTime = false
    writer.add(input)
    audio = input
  }
  guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
  writer.startSession(atSourceTime: .zero)
  let frame = picture()
  for index in 0..<frames {
    for (track, input) in inputs.enumerated() {
      while !input.isReadyForMoreMediaData { usleep(1000) }
      adaptors[track].append(
        frame, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
    }
  }
  if let audio {
    // Generated silence: 8 kHz mono PCM, encoded to AAC by the writer.
    let rate = 8000.0
    let total = Int(Double(frames) / Double(fps) * rate)
    var description = AudioStreamBasicDescription(
      mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
      mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
      mBitsPerChannel: 16, mReserved: 0)
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(
      allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0,
      magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
    var written = 0
    while written < total {
      let count = min(1024, total - written)
      var block: CMBlockBuffer?
      CMBlockBufferCreateWithMemoryBlock(
        allocator: nil, memoryBlock: nil, blockLength: count * 2, blockAllocator: nil,
        customBlockSource: nil, offsetToData: 0, dataLength: count * 2,
        flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
      CMBlockBufferFillDataBytes(
        with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: count * 2)
      var sample: CMSampleBuffer?
      CMAudioSampleBufferCreateReadyWithPacketDescriptions(
        allocator: nil, dataBuffer: block!, formatDescription: format!, sampleCount: count,
        presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: CMTimeScale(rate)),
        packetDescriptions: nil, sampleBufferOut: &sample)
      while !audio.isReadyForMoreMediaData { usleep(1000) }
      audio.append(sample!)
      written += count
    }
    audio.markAsFinished()
  }
  for input in inputs { input.markAsFinished() }
  writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: fps))
  let done = DispatchSemaphore(value: 0)
  writer.finishWriting { done.signal() }
  done.wait()
  guard writer.status == .completed else {
    throw writer.error ?? CocoaError(.fileWriteUnknown)
  }
  let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
  print("\(fixture.name) \(size) bytes")
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
  print("usage: swift tool/fixtures/generate_reel_rotation_fixtures.swift <output directory>")
  exit(64)
}
let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for fixture in fixtures {
  do {
    try write(fixture, into: directory)
  } catch {
    print("FAILED \(fixture.name): \(error)")
    exit(1)
  }
}
