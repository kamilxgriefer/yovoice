import 'package:cloud_functions/cloud_functions.dart';

import '../models/voice_connection_info.dart';

class VoiceTokenService {
  VoiceTokenService({
    FirebaseFunctions? functions,
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFunctions _functions;

  Future<VoiceConnectionInfo> createJoinToken({
    required String roomId,
    required String participantName,
  }) async {
    final cleanRoomId = roomId.trim();
    final cleanName = participantName.trim();

    if (cleanRoomId.isEmpty) {
      throw ArgumentError.value(roomId, 'roomId', 'Room ID cannot be empty.');
    }

    final callable = _functions.httpsCallable('createLiveKitToken');
    final response = await callable.call<Map<String, dynamic>>({
      'roomId': cleanRoomId,
      'participantName': cleanName,
    });

    return VoiceConnectionInfo.fromMap(response.data);
  }
}
