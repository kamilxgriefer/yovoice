import AVKit
import Flutter
import UIKit
import WebRTC
import flutter_webrtc

/// System Picture-in-Picture for one connected direct video call.
///
/// The PiP view binds directly to flutter_webrtc's public native track lookup,
/// so decoded frames never leave the device and no LiveKit credentials cross
/// the Flutter platform channel. AVPictureInPictureVideoCallViewController is
/// available from iOS 15, which preserves YO Voice's existing deployment
/// target instead of raising it for a young third-party PiP package.
final class DirectCallPictureInPictureController: NSObject {
  private weak var channel: FlutterMethodChannel?
  private var pictureInPictureController: AVPictureInPictureController?
  private var callViewController: DirectCallPiPVideoCallViewController?
  private var isArmed = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  func setActive(arguments: Any?) -> Bool {
    guard let values = arguments as? [String: Any] else { return false }
    guard values["active"] as? Bool == true else {
      disarm()
      return AVPictureInPictureController.isPictureInPictureSupported()
    }
    guard AVPictureInPictureController.isPictureInPictureSupported(),
          let trackId = (values["trackId"] as? String)?.trimmingCharacters(
            in: .whitespacesAndNewlines
          ),
          !trackId.isEmpty,
          let sourceView = activeSourceView(),
          let track = FlutterWebRTCPlugin.sharedSingleton()?.remoteTrack(forId: trackId)
            as? RTCVideoTrack
    else {
      disarm()
      return false
    }

    let participantName = (values["participantName"] as? String) ?? "YO Voice"
    let width = (values["width"] as? NSNumber)?.doubleValue ?? 16
    let height = (values["height"] as? NSNumber)?.doubleValue ?? 9

    if pictureInPictureController == nil {
      let callController = DirectCallPiPVideoCallViewController()
      let source = AVPictureInPictureController.ContentSource(
        activeVideoCallSourceView: sourceView,
        contentViewController: callController
      )
      let controller = AVPictureInPictureController(contentSource: source)
      controller.delegate = self
      pictureInPictureController = controller
      callViewController = callController
    }

    callViewController?.participantName = participantName
    callViewController?.remoteTrack = track
    callViewController?.setPreferredAspect(width: width, height: height)
    // Loading the content view before backgrounding makes the call source
    // eligible for the first automatic Home/minimize transition.
    _ = callViewController?.view
    pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = true
    isArmed = true
    return true
  }

  func disarm() {
    isArmed = false
    pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = false
    pictureInPictureController?.stopPictureInPicture()
    callViewController?.remoteTrack = nil
    pictureInPictureController?.delegate = nil
    pictureInPictureController = nil
    callViewController = nil
    notifyFlutter(isActive: false)
  }

  private func activeSourceView() -> UIView? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let foreground = scenes.first { $0.activationState == .foregroundActive }
      ?? scenes.first { $0.activationState == .foregroundInactive }
    let windows = foreground?.windows ?? scenes.flatMap(\.windows)
    return windows.first(where: \.isKeyWindow)?.rootViewController?.view
      ?? windows.first(where: { !$0.isHidden })?.rootViewController?.view
  }

  private func notifyFlutter(isActive: Bool) {
    channel?.invokeMethod("pictureInPictureChanged", arguments: isActive)
  }
}

extension DirectCallPictureInPictureController: AVPictureInPictureControllerDelegate {
  func pictureInPictureControllerWillStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    guard isArmed else {
      pictureInPictureController.stopPictureInPicture()
      return
    }
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    notifyFlutter(isActive: true)
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    notifyFlutter(isActive: false)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    notifyFlutter(isActive: false)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
      @escaping (Bool) -> Void
  ) {
    // The Flutter call route stays mounted while PiP is active, so bringing
    // YO Voice forward already restores the complete call controls.
    completionHandler(isArmed)
  }
}

private final class DirectCallPiPVideoCallViewController:
  AVPictureInPictureVideoCallViewController,
  RTCVideoViewDelegate
{
  private let remoteRenderer = RTCMTLVideoView(frame: .zero)
  private let fallbackLabel = UILabel(frame: .zero)
  private var boundTrack: RTCVideoTrack?

  var participantName: String = "YO Voice" {
    didSet { fallbackLabel.text = initials(for: participantName) }
  }

  var remoteTrack: RTCVideoTrack? {
    get { boundTrack }
    set {
      guard boundTrack !== newValue else { return }
      if let boundTrack { boundTrack.remove(remoteRenderer) }
      boundTrack = newValue
      if let newValue { newValue.add(remoteRenderer) }
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(red: 0.055, green: 0.025, blue: 0.09, alpha: 1)

    fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
    fallbackLabel.text = initials(for: participantName)
    fallbackLabel.textAlignment = .center
    fallbackLabel.textColor = .white
    fallbackLabel.font = .systemFont(ofSize: 62, weight: .bold)
    fallbackLabel.backgroundColor = UIColor(red: 0.45, green: 0.12, blue: 0.92, alpha: 1)
    fallbackLabel.layer.cornerRadius = 54
    fallbackLabel.clipsToBounds = true

    remoteRenderer.translatesAutoresizingMaskIntoConstraints = false
    remoteRenderer.videoContentMode = .scaleAspectFill
    remoteRenderer.delegate = self
    remoteRenderer.isEnabled = true

    view.addSubview(fallbackLabel)
    view.addSubview(remoteRenderer)
    NSLayoutConstraint.activate([
      fallbackLabel.widthAnchor.constraint(equalToConstant: 108),
      fallbackLabel.heightAnchor.constraint(equalToConstant: 108),
      fallbackLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      fallbackLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      remoteRenderer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      remoteRenderer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      remoteRenderer.topAnchor.constraint(equalTo: view.topAnchor),
      remoteRenderer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    preferredContentSize = CGSize(width: 320, height: 180)
  }

  func setPreferredAspect(width: Double, height: Double) {
    guard width > 0, height > 0 else { return }
    let ratio = min(max(width / height, 1 / 2.39), 2.39)
    preferredContentSize = ratio >= 1
      ? CGSize(width: 240 * ratio, height: 240)
      : CGSize(width: 240, height: 240 / ratio)
  }

  func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
    DispatchQueue.main.async { [weak self] in
      self?.setPreferredAspect(width: size.width, height: size.height)
    }
  }

  deinit {
    boundTrack?.remove(remoteRenderer)
  }

  private func initials(for name: String) -> String {
    let components = name
      .split(whereSeparator: \.isWhitespace)
      .prefix(2)
      .compactMap(\.first)
    let value = String(components).uppercased()
    return value.isEmpty ? "YO" : value
  }
}
