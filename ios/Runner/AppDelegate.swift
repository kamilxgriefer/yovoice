import AVFAudio
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var directVideoAudioChannel: FlutterMethodChannel?
  private var directCallPictureInPictureChannel: FlutterMethodChannel?
  private var directCallPictureInPicture: DirectCallPictureInPictureController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "app.yovoice/direct_video_audio",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "prepareMoviePlayback" else {
        result(FlutterMethodNotImplemented)
        return
      }

      do {
        let session = AVAudioSession.sharedInstance()
        // This single API call replaces both the category and LiveKit's
        // previous voice/video-chat mode. Playback bypasses the silent switch;
        // mixing keeps other device audio eligible when no YO Voice RTC owner
        // is active (the Dart registry enforces that boundary).
        try session.setCategory(
          .playback,
          mode: .moviePlayback,
          options: [.mixWithOthers]
        )
        try session.setActive(true)
        result(true)
      } catch {
        result(
          FlutterError(
            code: "audio_session_unavailable",
            message: "Could not prepare iOS movie playback audio.",
            details: error.localizedDescription
          )
        )
      }
    }
    directVideoAudioChannel = channel

    let pictureInPictureChannel = FlutterMethodChannel(
      name: "app.yovoice/direct_call_pip",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    let pictureInPicture = DirectCallPictureInPictureController(
      channel: pictureInPictureChannel
    )
    pictureInPictureChannel.setMethodCallHandler { call, result in
      guard call.method == "setActive" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        result(pictureInPicture.setActive(arguments: call.arguments))
      }
    }
    directCallPictureInPictureChannel = pictureInPictureChannel
    directCallPictureInPicture = pictureInPicture
  }
}
