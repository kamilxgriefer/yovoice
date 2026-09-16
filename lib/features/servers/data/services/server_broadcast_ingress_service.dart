import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

class ServerBroadcastIngressReceipt {
  const ServerBroadcastIngressReceipt({
    required this.serverId,
    required this.channelId,
    required this.sessionId,
    required this.ingressId,
    required this.serverUrl,
    required this.streamKey,
  });

  final String serverId;
  final String channelId;
  final String sessionId;
  final String ingressId;
  final String serverUrl;
  final String streamKey;

  factory ServerBroadcastIngressReceipt.fromMap(
    Map<Object?, Object?> value, {
    required String serverId,
    required String channelId,
    required String sessionId,
  }) {
    String text(String key) {
      final result = value[key];
      if (result is! String || result.isEmpty || result.trim() != result) {
        throw const FormatException('Malformed OBS broadcast response.');
      }
      return result;
    }

    const keys = {
      'schemaVersion',
      'serverId',
      'channelId',
      'sessionId',
      'ingressId',
      'serverUrl',
      'streamKey',
    };
    if (value.length != keys.length ||
        !keys.every(value.containsKey) ||
        value['schemaVersion'] != 1 ||
        value['serverId'] != serverId ||
        value['channelId'] != channelId ||
        value['sessionId'] != sessionId) {
      throw const FormatException('Malformed OBS broadcast binding.');
    }
    final serverUrl = text('serverUrl');
    final uri = Uri.tryParse(serverUrl);
    if (uri == null ||
        !(uri.scheme == 'rtmp' || uri.scheme == 'rtmps') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        serverUrl.length > 2048) {
      throw const FormatException('Malformed OBS server URL.');
    }
    final streamKey = text('streamKey');
    if (streamKey.length < 8 || streamKey.length > 1024) {
      throw const FormatException('Malformed OBS stream key.');
    }
    return ServerBroadcastIngressReceipt(
      serverId: serverId,
      channelId: channelId,
      sessionId: sessionId,
      ingressId: text('ingressId'),
      serverUrl: serverUrl,
      streamKey: streamKey,
    );
  }
}

abstract interface class ServerBroadcastIngressRepository {
  Future<ServerBroadcastIngressReceipt> provision({
    required String serverId,
    required String channelId,
    required String sessionId,
  });
}

class ServerBroadcastIngressService
    implements ServerBroadcastIngressRepository {
  ServerBroadcastIngressService({
    FirebaseFunctions? functions,
    Future<Map<Object?, Object?>> Function(
      String name,
      Map<String, Object?> data,
    )?
    callOverride,
  }) : _functions = functions,
       _callOverride = callOverride;

  final FirebaseFunctions? _functions;
  final Future<Map<Object?, Object?>> Function(
    String name,
    Map<String, Object?> data,
  )?
  _callOverride;

  String _requestId() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  Future<ServerBroadcastIngressReceipt> provision({
    required String serverId,
    required String channelId,
    required String sessionId,
  }) async {
    final payload = <String, Object?>{
      'serverId': serverId,
      'channelId': channelId,
      'sessionId': sessionId,
      'requestId': _requestId(),
    };
    final override = _callOverride;
    final result = override != null
        ? await override('createServerBroadcastIngressV1', payload)
        : (await (_functions ??
                      FirebaseFunctions.instanceFor(region: 'europe-west1'))
                  .httpsCallable('createServerBroadcastIngressV1')
                  .call<Map<Object?, Object?>>(payload))
              .data;
    return ServerBroadcastIngressReceipt.fromMap(
      result,
      serverId: serverId,
      channelId: channelId,
      sessionId: sessionId,
    );
  }
}
