import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/server_list_item.dart';

abstract interface class ServerSharedListRepository {
  String get currentUserId;
  String newRequestId();

  Stream<List<ServerListItem>> watchItems(String serverId, String channelId);

  Future<void> createItem({
    required String serverId,
    required String channelId,
    required String text,
    required String requestId,
  });

  Future<void> updateItem({
    required ServerListItem item,
    required Map<String, Object?> patch,
    required String requestId,
  });

  Future<void> deleteItem({
    required ServerListItem item,
    required String requestId,
  });
}

class ServerSharedListService implements ServerSharedListRepository {
  ServerSharedListService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    Future<Map<Object?, Object?>> Function(
      String name,
      Map<String, Object?> data,
    )?
    callOverride,
    String? currentUserIdOverride,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functionsOverride = functions,
       _authOverride = auth,
       _callOverride = callOverride,
       _currentUserIdOverride = currentUserIdOverride;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions? _functionsOverride;
  final FirebaseAuth? _authOverride;
  final Future<Map<Object?, Object?>> Function(
    String name,
    Map<String, Object?> data,
  )?
  _callOverride;
  final String? _currentUserIdOverride;

  @override
  String get currentUserId =>
      _currentUserIdOverride ??
      (_authOverride ?? FirebaseAuth.instance).currentUser?.uid ??
      '';

  @override
  String newRequestId() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  CollectionReference<Map<String, dynamic>> _items(
    String serverId,
    String channelId,
  ) => _firestore
      .collection('clubs')
      .doc(serverId)
      .collection('channels')
      .doc(channelId)
      .collection('listItems');

  @override
  Stream<List<ServerListItem>> watchItems(String serverId, String channelId) =>
      _items(serverId, channelId).orderBy('createdAt').snapshots().map((
        snapshot,
      ) {
        final items = <ServerListItem>[];
        for (final document in snapshot.docs) {
          try {
            items.add(
              ServerListItem.fromFirestore(
                document,
                serverId: serverId,
                channelId: channelId,
              ),
            );
          } on FormatException {
            // One malformed row cannot conceal the rest of a private list.
          }
        }
        return List<ServerListItem>.unmodifiable(items);
      });

  Future<void> _call(String name, Map<String, Object?> data) async {
    final override = _callOverride;
    if (override != null) {
      await override(name, data);
      return;
    }
    await (_functionsOverride ??
            FirebaseFunctions.instanceFor(region: 'europe-west1'))
        .httpsCallable(name)
        .call<Map<Object?, Object?>>(data);
  }

  @override
  Future<void> createItem({
    required String serverId,
    required String channelId,
    required String text,
    required String requestId,
  }) => _call('createServerListItemV1', {
    'serverId': serverId,
    'channelId': channelId,
    'requestId': requestId,
    'text': text.trim(),
  });

  @override
  Future<void> updateItem({
    required ServerListItem item,
    required Map<String, Object?> patch,
    required String requestId,
  }) => _call('updateServerListItemV1', {
    'serverId': item.serverId,
    'channelId': item.channelId,
    'itemId': item.id,
    'requestId': requestId,
    'expectedRevision': item.revision,
    'patch': patch,
  });

  @override
  Future<void> deleteItem({
    required ServerListItem item,
    required String requestId,
  }) => _call('deleteServerListItemV1', {
    'serverId': item.serverId,
    'channelId': item.channelId,
    'itemId': item.id,
    'requestId': requestId,
    'expectedRevision': item.revision,
  });
}
