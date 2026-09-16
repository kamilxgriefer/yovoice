import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native system Picture-in-Picture bridge used by a connected 1:1 video call.
///
/// The bridge sends the native WebRTC track id, the contact display name and
/// the video aspect; never the LiveKit room, URL or token.
abstract class DirectCallPictureInPictureGateway extends Listenable {
  bool get isArmed;
  bool get isInPictureInPicture;

  Future<bool> armRemoteVideo({
    required String trackId,
    required String participantName,
    int width = 16,
    int height = 9,
  });

  Future<void> disarm();

  void dispose();
}

class DirectCallPictureInPictureController extends ChangeNotifier
    implements DirectCallPictureInPictureGateway {
  DirectCallPictureInPictureController({
    MethodChannel? channel,
    bool? platformSupportedOverride,
  }) : _channel = channel ?? const MethodChannel(_channelName),
       _platformSupportedOverride = platformSupportedOverride {
    final channelName = _channel.name;
    final clients = _clients.putIfAbsent(
      channelName,
      () => Set<DirectCallPictureInPictureController>.identity(),
    );
    final installDispatcher = clients.isEmpty;
    clients.add(this);
    if (installDispatcher) {
      // Platform channels hold one Dart handler per name. Every screen shares
      // this dispatcher instead of replacing (and on dispose clearing) the
      // handler of a newer call screen that is still alive.
      _channel.setMethodCallHandler(
        (call) => _dispatchNativeCall(channelName, call),
      );
    }
  }

  static const String _channelName = 'app.yovoice/direct_call_pip';

  /// Live controllers per channel name. The native bridge is a process-wide
  /// singleton, while call screens create and dispose their own controller,
  /// and a route exit transition can overlap the next call screen.
  static final Map<String, Set<DirectCallPictureInPictureController>> _clients =
      <String, Set<DirectCallPictureInPictureController>>{};

  /// The controller whose arm request native PiP last accepted. Only it may
  /// disarm native PiP or observe native mode changes.
  static final Map<String, DirectCallPictureInPictureController> _nativeOwners =
      <String, DirectCallPictureInPictureController>{};

  static Future<void> _dispatchNativeCall(
    String channelName,
    MethodCall call,
  ) async {
    await _nativeOwners[channelName]?._handleNativeCall(call);
  }

  final MethodChannel _channel;
  final bool? _platformSupportedOverride;

  int _requestGeneration = 0;
  bool _disposed = false;
  bool _isArmed = false;
  bool _isInPictureInPicture = false;
  String? _trackId;
  String? _participantName;
  Future<bool>? _pendingArm;
  String? _pendingTrackId;
  String? _pendingParticipantName;

  bool get _canUseNativeBridge {
    final override = _platformSupportedOverride;
    if (override != null) return override;
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  bool get isArmed => _isArmed;

  @override
  bool get isInPictureInPicture => _isInPictureInPicture;

  @override
  Future<bool> armRemoteVideo({
    required String trackId,
    required String participantName,
    int width = 16,
    int height = 9,
  }) async {
    final normalizedTrackId = trackId.trim();
    if (_disposed || !_canUseNativeBridge || normalizedTrackId.isEmpty) {
      return false;
    }
    final normalizedName = participantName.trim();
    final safeWidth = width > 0 ? width : 16;
    final safeHeight = height > 0 ? height : 9;
    if (_isArmed &&
        _trackId == normalizedTrackId &&
        _participantName == normalizedName) {
      return true;
    }

    final pending = _pendingArm;
    if (pending != null &&
        _pendingTrackId == normalizedTrackId &&
        _pendingParticipantName == normalizedName) {
      return pending;
    }

    final generation = ++_requestGeneration;
    _pendingTrackId = normalizedTrackId;
    _pendingParticipantName = normalizedName;
    final request = _sendArmRequest(
      generation: generation,
      trackId: normalizedTrackId,
      participantName: normalizedName,
      width: safeWidth,
      height: safeHeight,
    );
    _pendingArm = request;
    return request;
  }

  Future<bool> _sendArmRequest({
    required int generation,
    required String trackId,
    required String participantName,
    required int width,
    required int height,
  }) async {
    try {
      final supported =
          await _channel.invokeMethod<bool>('setActive', <String, Object>{
            'active': true,
            'trackId': trackId,
            'participantName': participantName,
            'width': width,
            'height': height,
          }) ??
          false;
      if (_disposed || generation != _requestGeneration) return false;
      if (supported) _nativeOwners[_channel.name] = this;
      _trackId = supported ? trackId : null;
      _participantName = supported ? participantName : null;
      if (_isArmed != supported) {
        _isArmed = supported;
        notifyListeners();
      }
      return supported;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } finally {
      if (generation == _requestGeneration) {
        _pendingArm = null;
        _pendingTrackId = null;
        _pendingParticipantName = null;
      }
    }
  }

  @override
  Future<void> disarm() async {
    if (_disposed && !_isArmed && !_isInPictureInPicture) return;
    ++_requestGeneration;
    final changed = _isArmed || _isInPictureInPicture;
    final channelName = _channel.name;
    final ownsNativeState =
        identical(_nativeOwners[channelName], this) || _pendingArm != null;
    if (identical(_nativeOwners[channelName], this)) {
      _nativeOwners.remove(channelName);
    }
    _isArmed = false;
    _isInPictureInPicture = false;
    _trackId = null;
    _participantName = null;
    _pendingArm = null;
    _pendingTrackId = null;
    _pendingParticipantName = null;
    if (changed && !_disposed) notifyListeners();
    // A controller that never armed native PiP, or was superseded by a newer
    // call screen, only resets itself. Closing native PiP here would dismiss
    // (on Android: background) the window that another screen still owns.
    if (!ownsNativeState || !_canUseNativeBridge) return;
    try {
      await _channel.invokeMethod<void>('setActive', const <String, Object>{
        'active': false,
      });
    } on MissingPluginException {
      // Desktop, web and an older native shell simply remain without PiP.
    } on PlatformException {
      // A concurrent Activity/scene teardown already releases native PiP.
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (_disposed || call.method != 'pictureInPictureChanged') return;
    final active = call.arguments == true;
    if (active && !_isArmed) return;
    if (_isInPictureInPicture == active) return;
    _isInPictureInPicture = active;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    // disarm() contacts native code only when this controller owns native PiP
    // or still has an arm request in flight.
    unawaited(disarm());
    _disposed = true;
    final channelName = _channel.name;
    final clients = _clients[channelName];
    clients?.remove(this);
    if (clients == null || clients.isEmpty) {
      _clients.remove(channelName);
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}
