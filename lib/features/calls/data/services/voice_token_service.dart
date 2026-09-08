import 'package:cloud_functions/cloud_functions.dart';

import '../models/voice_connection_info.dart';

class VoiceTokenService {
  VoiceTokenService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFunctions _functions;

  /// Client-side deadline for `createLiveKitToken`.
  ///
  /// The token is the last hop before audio; until it answers the room screen
  /// shows "Connecting to live audio…" with no way out, and the plugin's
  /// default is 60 s. Re-minting is harmless — the callable is a pure read of
  /// room state plus a signature, rate limited at 12 per minute — so a bounded
  /// wait that surfaces as a retryable error is strictly better than a minute
  /// of silence.
  static const Duration createTokenTimeout = Duration(seconds: 15);

  Future<VoiceConnectionInfo> createJoinToken({
    required String roomId,
    required String participantName,
  }) async {
    final cleanRoomId = roomId.trim();
    final cleanName = participantName.trim();

    if (cleanRoomId.isEmpty) {
      throw ArgumentError.value(roomId, 'roomId', 'Room ID cannot be empty.');
    }

    final callable = _functions.httpsCallable(
      'createLiveKitToken',
      options: HttpsCallableOptions(timeout: createTokenTimeout),
    );
    final response = await callable.call<Map<String, dynamic>>({
      'roomId': cleanRoomId,
      'participantName': cleanName,
    });

    return VoiceConnectionInfo.fromMap(response.data);
  }
}
