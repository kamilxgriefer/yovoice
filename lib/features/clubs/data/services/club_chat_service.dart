import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:yovoice/features/clubs/data/models/club_chat_authority.dart';
import 'package:yovoice/features/clubs/data/models/club_member.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';

/// One short-lived read grant for a server channel photo or video, as
/// `getServerChannelMessageMediaAccessV1` issues it: a generation-bound V4 URL
/// that expires within 90 seconds. Never stored, never written to Firestore.
class ServerMediaGrant {
  const ServerMediaGrant({
    required this.messageId,
    required this.url,
    required this.type,
    required this.contentType,
    required this.size,
    required this.durationSeconds,
    required this.expiresAt,
  });

  final String messageId;
  final Uri url;
  final String type;
  final String contentType;
  final int size;
  final int? durationSeconds;
  final DateTime expiresAt;

  bool get isVideo => type == 'video';
}

/// Uploads the reserved object and answers with its Storage generation. The
/// production implementation is Firebase Storage `putData`; tests inject one.
typedef ServerMediaUploader =
    Future<String> Function({
      required String storagePath,
      required Uint8List bytes,
      required String contentType,
      required Map<String, String> customMetadata,
      void Function(double progress)? onProgress,
    });

class _ServerMediaGrantBatch {
  _ServerMediaGrantBatch(this.serverId, this.channelId);

  final String serverId;
  final String channelId;
  final Map<String, Completer<ServerMediaGrant?>> waiting = {};
}

typedef ClubMessageModerationInvoker =
    Future<Map<Object?, Object?>> Function(Map<String, Object?> request);
typedef ClubMessageSendInvoker =
    Future<Map<Object?, Object?>> Function(Map<String, Object?> request);

/// Invokes one Servers V1 message callable by name. The test seam for the
/// reaction, media and author-delete callables, which share one shape.
typedef ServerMessageCallableInvoker =
    Future<Map<Object?, Object?>> Function(
      String name,
      Map<String, Object?> request,
    );

class ClubChatService {
  ClubChatService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    ClubMessageModerationInvoker? moderationInvoker,
    ClubMessageSendInvoker? messageSendInvoker,
    ServerMessageCallableInvoker? serverMessageInvoker,
    ServerMediaUploader? mediaUploader,
    FirebaseStorage? storage,
    DateTime Function()? clock,
    String Function()? requestIdFactory,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions,
       _moderationInvoker = moderationInvoker,
       _messageSendInvoker = messageSendInvoker,
       _serverMessageInvoker = serverMessageInvoker,
       _mediaUploaderOverride = mediaUploader,
       _storageOverride = storage,
       _clock = clock ?? DateTime.now,
       _requestIdFactory = requestIdFactory ?? _newRequestId;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;
  final ClubMessageModerationInvoker? _moderationInvoker;
  final ClubMessageSendInvoker? _messageSendInvoker;
  final ServerMessageCallableInvoker? _serverMessageInvoker;
  final ServerMediaUploader? _mediaUploaderOverride;
  final FirebaseStorage? _storageOverride;
  final DateTime Function() _clock;
  final String Function() _requestIdFactory;

  /// Grants live only in memory and only until they expire. Keyed by
  /// server/channel/message, dropped ten seconds before expiry so a render
  /// never uses a URL that dies mid-request.
  final Map<String, ServerMediaGrant> _mediaGrants = {};

  /// Ids the server reported unavailable (removed, non-media, or an object
  /// that is gone). Remembered briefly so a thread does not ask again on
  /// every rebuild.
  final Map<String, DateTime> _mediaUnavailableUntil = {};
  final Map<String, _ServerMediaGrantBatch> _pendingMediaGrants = {};

  static const _mediaGrantSafety = Duration(seconds: 10);
  static const _mediaUnavailableMemory = Duration(seconds: 30);
  static const _mediaGrantBatch = 20;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  static String _newRequestId() {
    final random = Random.secure();
    final randomPart = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-'
        '$randomPart';
  }

  User get _user {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to use club chat.');
    }
    return user;
  }

  CollectionReference<Map<String, dynamic>> _messages({
    required String clubId,
    required String channelId,
  }) {
    return _firestore
        .collection('clubs')
        .doc(clubId)
        .collection('channels')
        .doc(channelId)
        .collection('messages');
  }

  Stream<List<ClubMessage>> watchMessages({
    required String clubId,
    required String channelId,
  }) {
    return _messages(clubId: clubId, channelId: channelId)
        .orderBy('sentAt', descending: true)
        .limit(250)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (document) => ClubMessage.fromFirestore(
                  clubId: clubId,
                  channelId: channelId,
                  document: document,
                ),
              )
              .toList(growable: false),
        );
  }

  /// The single newest message in a channel, or null when the channel has
  /// never been used.
  ///
  /// **Currently unused — no caller in `lib/` or `test/`.** It was written
  /// for `DesktopConversations`, the desktop Conversations hub decided in
  /// ADR-036. That module was dropped from desktop Home by the ADR-043
  /// board rebuild (`98f477d`) and its file deleted in `409c7ee`. Home now
  /// previews DM-only `RecentChats` per ADR-048, reading
  /// `MessageService.watchConversations`, which never touches club chat.
  ///
  /// Kept, rather than deleted, because the constraint that motivated it is
  /// unchanged: club chat has no denormalised "last message" on the club
  /// document, so a club preview line has to come from the messages
  /// themselves, and [watchMessages] would pull up to 250 documents per
  /// club to render one. This is the same collection and the same ordering,
  /// limited to one. Delete it if club previews are ruled out for good,
  /// rather than merely unbuilt.
  Stream<ClubMessage?> watchLatestMessage({
    required String clubId,
    required String channelId,
  }) {
    return _messages(
      clubId: clubId,
      channelId: channelId,
    ).orderBy('sentAt', descending: true).limit(1).snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return ClubMessage.fromFirestore(
        clubId: clubId,
        channelId: channelId,
        document: snapshot.docs.first,
      );
    });
  }

  Future<void> sendTextMessage({
    required String clubId,
    required String channelId,
    required String text,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    if (normalized.length > 2000) {
      throw ArgumentError('A club message cannot exceed 2000 characters.');
    }

    final payload = <String, Object?>{
      'clubId': clubId,
      'channelId': channelId,
      'requestId': _requestIdFactory(),
      'text': normalized,
    };
    if (_messageSendInvoker != null) {
      await _messageSendInvoker(payload);
      return;
    }
    await _functions.httpsCallable('sendClubMessage').call(payload);
  }

  Future<Map<Object?, Object?>> _callServerMessage(
    String name,
    Map<String, Object?> payload,
  ) async {
    final invoker = _serverMessageInvoker;
    if (invoker != null) return invoker(name, payload);
    final response = await _functions
        .httpsCallable(name)
        .call<Map<Object?, Object?>>(payload);
    return response.data;
  }

  /// Toggles the viewer's reaction on a Servers V1 channel message, exactly
  /// as `MessageService.toggleReaction` does for a direct message: one
  /// reaction per person, and choosing the current one again removes it.
  ///
  /// Callable-only. `firestore.rules` keeps V1 message updates closed to
  /// every client, so there is deliberately no direct-write fallback: the
  /// `setServerChannelMessageReactionV1` callable is the only writer of the
  /// map and decides who may react (members, including in announcement and
  /// rules channels; never guests).
  Future<void> toggleServerReaction({
    required String serverId,
    required String channelId,
    required String messageId,
    required String emoji,
  }) async {
    final user = _user;
    // Decided against the stored map rather than the rendered tile, the way
    // the direct-message toggle reads its document first.
    final snapshot = await _messages(
      clubId: serverId,
      channelId: channelId,
    ).doc(messageId).get();
    final stored = snapshot.data()?['reactions'];
    final current = stored is Map ? stored[user.uid] : null;
    await _callServerMessage('setServerChannelMessageReactionV1', {
      'serverId': serverId,
      'channelId': channelId,
      'messageId': messageId,
      'emoji': current == emoji ? null : emoji,
      'requestId': _requestIdFactory(),
    });
  }

  // ------------------------------------------------- channel photos/videos

  /// Sends one photo or video to a Servers V1 text channel:
  /// reserve -> upload the exact reserved object -> finalize.
  ///
  /// The client never chooses the path, the id or the metadata: all three come
  /// from the reservation, and `storage.rules` accepts the upload only while
  /// that reservation is live. A retry reuses the same reservation (the same
  /// `requestId`), so a lost response can never leave a second object or a
  /// second message. Returns the message id the channel will show.
  Future<String> sendServerMediaMessage({
    required String serverId,
    required String channelId,
    required String type,
    required String contentType,
    required Uint8List bytes,
    int? durationSeconds,
    void Function(double progress)? onProgress,
  }) async {
    final user = _user;
    if (type != 'image' && type != 'video') {
      throw ArgumentError.value(type, 'type', 'Unsupported media type.');
    }
    final reserveRequestId = _requestIdFactory();
    final reserved =
        await _callServerMessage('reserveServerChannelMessageMediaV1', {
          'serverId': serverId,
          'channelId': channelId,
          'type': type,
          'contentType': contentType,
          'size': bytes.lengthInBytes,
          'durationSeconds': durationSeconds,
          'requestId': reserveRequestId,
        });
    final messageId = reserved['messageId'];
    final media = reserved['media'];
    if (messageId is! String || messageId.isEmpty || media is! Map) {
      throw StateError('The upload could not be prepared. Try again.');
    }
    final storagePath = media['storagePath'];
    final metadata = media['uploadMetadata'];
    final expected =
        'server_message_media/$serverId/$channelId/${user.uid}/$messageId.';
    if (storagePath is! String ||
        !storagePath.startsWith(expected) ||
        metadata is! Map) {
      throw StateError('The upload could not be prepared. Try again.');
    }
    final customMetadata = <String, String>{
      for (final entry in metadata.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
    if (customMetadata.length != metadata.length) {
      throw StateError('The upload could not be prepared. Try again.');
    }
    final generation = await (_mediaUploaderOverride ?? _uploadWithStorage)(
      storagePath: storagePath,
      bytes: bytes,
      contentType: contentType,
      customMetadata: customMetadata,
      onProgress: onProgress,
    );
    final finalize = <String, Object?>{
      'serverId': serverId,
      'channelId': channelId,
      'messageId': messageId,
      'objectGeneration': generation,
      'requestId': _requestIdFactory(),
    };
    try {
      await _callServerMessage('finalizeServerChannelMessageMediaV1', finalize);
    } on FirebaseFunctionsException catch (error) {
      // One retry of the SAME operation for a lost or transient answer; the
      // ledger makes the second call a replay, never a second message.
      if (error.code != 'unavailable' &&
          error.code != 'deadline-exceeded' &&
          error.code != 'internal' &&
          error.code != 'aborted') {
        rethrow;
      }
      await _callServerMessage('finalizeServerChannelMessageMediaV1', finalize);
    }
    return messageId;
  }

  Future<String> _uploadWithStorage({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
    void Function(double progress)? onProgress,
  }) async {
    final reference = (_storageOverride ?? FirebaseStorage.instance).ref(
      storagePath,
    );
    final settable = SettableMetadata(
      contentType: contentType,
      customMetadata: customMetadata,
    );
    try {
      final task = reference.putData(bytes, settable);
      final progress = task.snapshotEvents.listen(
        (snapshot) {
          if (snapshot.totalBytes > 0) {
            onProgress?.call(snapshot.bytesTransferred / snapshot.totalBytes);
          }
        },
        onError: (_) {
          // Progress is cosmetic; the upload's own future owns the outcome.
        },
      );
      try {
        final snapshot = await task;
        final generation = snapshot.metadata?.generation;
        if (generation != null && generation.isNotEmpty) return generation;
      } finally {
        await progress.cancel();
      }
    } catch (_) {
      // The object may have committed before the response was lost. The
      // uploader may read its own object back while the reservation is live,
      // so ask Storage instead of reserving a second path.
    }
    final stored = await reference.getMetadata();
    final generation = stored.generation;
    if (generation == null ||
        generation.isEmpty ||
        stored.size != bytes.lengthInBytes) {
      throw StateError('The upload did not complete. Try again.');
    }
    return generation;
  }

  /// A short-lived read grant for one media message, or null when the server
  /// reports it unavailable (removed, not media, or its object is gone).
  ///
  /// Requests made in the same frame are coalesced into batches of twenty, so
  /// a thread of media bubbles costs one callable per twenty visible tiles,
  /// and each grant is cached until shortly before it expires.
  Future<ServerMediaGrant?> serverMediaGrant({
    required String serverId,
    required String channelId,
    required String messageId,
    bool refresh = false,
  }) {
    final key = '$serverId/$channelId/$messageId';
    final now = _clock();
    if (!refresh) {
      final cached = _mediaGrants[key];
      if (cached != null &&
          cached.expiresAt.isAfter(now.add(_mediaGrantSafety))) {
        return Future<ServerMediaGrant?>.value(cached);
      }
      final blocked = _mediaUnavailableUntil[key];
      if (blocked != null && blocked.isAfter(now)) {
        return Future<ServerMediaGrant?>.value(null);
      }
    }
    _mediaGrants.remove(key);
    final batchKey = '$serverId/$channelId';
    final batch = _pendingMediaGrants.putIfAbsent(batchKey, () {
      Timer.run(() => _flushServerMediaGrants(batchKey));
      return _ServerMediaGrantBatch(serverId, channelId);
    });
    return batch.waiting
        .putIfAbsent(messageId, Completer<ServerMediaGrant?>.new)
        .future;
  }

  /// Drops any cached grant for [messageId] — after a retraction or a
  /// moderator removal, the next render must ask again.
  void forgetServerMediaGrant({
    required String serverId,
    required String channelId,
    required String messageId,
  }) {
    final key = '$serverId/$channelId/$messageId';
    _mediaGrants.remove(key);
    _mediaUnavailableUntil.remove(key);
  }

  Future<void> _flushServerMediaGrants(String batchKey) async {
    final batch = _pendingMediaGrants.remove(batchKey);
    if (batch == null) return;
    final ids = batch.waiting.keys.toList(growable: false);
    for (var start = 0; start < ids.length; start += _mediaGrantBatch) {
      final chunk = ids.sublist(
        start,
        min(start + _mediaGrantBatch, ids.length),
      );
      try {
        final response =
            await _callServerMessage('getServerChannelMessageMediaAccessV1', {
              'serverId': batch.serverId,
              'channelId': batch.channelId,
              'messageIds': chunk,
            });
        final grants = _parseServerMediaGrants(response);
        final now = _clock();
        for (final messageId in chunk) {
          final key = '${batch.serverId}/${batch.channelId}/$messageId';
          final grant = grants[messageId];
          if (grant != null) {
            _mediaGrants[key] = grant;
            _mediaUnavailableUntil.remove(key);
          } else {
            _mediaUnavailableUntil[key] = now.add(_mediaUnavailableMemory);
          }
          batch.waiting[messageId]?.complete(grant);
        }
      } catch (error, stack) {
        for (final messageId in chunk) {
          batch.waiting[messageId]?.completeError(error, stack);
        }
      }
    }
  }

  Map<String, ServerMediaGrant> _parseServerMediaGrants(
    Map<Object?, Object?> response,
  ) {
    final expiresAtMillis = response['expiresAtMillis'];
    final rows = response['grants'];
    if (expiresAtMillis is! int || rows is! List) {
      throw StateError('The media could not be loaded. Try again.');
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      expiresAtMillis,
      isUtc: true,
    ).toLocal();
    final grants = <String, ServerMediaGrant>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final messageId = row['messageId'];
      final url = row['url'];
      final type = row['type'];
      final contentType = row['contentType'];
      final size = row['size'];
      final duration = row['durationSeconds'];
      if (messageId is! String ||
          url is! String ||
          type is! String ||
          contentType is! String ||
          size is! num) {
        continue;
      }
      final parsed = Uri.tryParse(url);
      // Only the signing host this backend uses, and only over HTTPS: a
      // grant is a bearer capability and must never point anywhere else.
      if (parsed == null ||
          parsed.scheme != 'https' ||
          parsed.host != 'storage.googleapis.com' ||
          parsed.userInfo.isNotEmpty) {
        continue;
      }
      grants[messageId] = ServerMediaGrant(
        messageId: messageId,
        url: parsed,
        type: type,
        contentType: contentType,
        size: size.toInt(),
        durationSeconds: duration is num ? duration.toInt() : null,
        expiresAt: expiresAt,
      );
    }
    return grants;
  }

  /// The author takes their own Servers V1 message back. Rules keep every V1
  /// message update closed to clients, so this is callable-only; it tombstones
  /// the message and enqueues the private object's deletion.
  Future<void> deleteOwnServerMessage({
    required String serverId,
    required String channelId,
    required String messageId,
  }) async {
    await _callServerMessage('deleteServerChannelMessageV1', {
      'serverId': serverId,
      'channelId': channelId,
      'messageId': messageId,
      'requestId': _requestIdFactory(),
    });
    forgetServerMediaGrant(
      serverId: serverId,
      channelId: channelId,
      messageId: messageId,
    );
  }

  /// The viewer's removal authority in [clubId], kept live.
  ///
  /// Two documents decide it — the viewer's own membership row for their
  /// role, and the club document for `ownerId` — and both have to be
  /// watched rather than read once: a demotion has to take the affordance
  /// away, and an ownership transfer has to move the protected messages.
  /// They are merged here rather than in the screen so the UI gate and
  /// [deleteMessage] provably consult the same two fields.
  ///
  /// The stream emits on the first snapshot of either document; until
  /// then, and whenever a read fails, the authority withholds moderator
  /// power and permits only self-retraction — the same behaviour the
  /// screen had before moderation existed.
  Stream<ClubChatAuthority> watchAuthority(String clubId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return Stream<ClubChatAuthority>.value(
        const ClubChatAuthority.signedOut(),
      );
    }

    ClubRole? role;
    String? ownerId;
    var muted = false;
    // Flips on the first membership snapshot (or its failure), never back.
    var membershipResolved = false;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? memberSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? clubSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? restrictionSub;
    late final StreamController<ClubChatAuthority> controller;

    void emit() {
      // `onCancel` awaits the subscription cancellations, so an event
      // already in flight can land after the screen is gone. Dropping it
      // is correct; adding it would not be.
      if (controller.isClosed || !controller.hasListener) return;
      controller.add(
        ClubChatAuthority(
          viewerId: uid,
          role: role,
          clubOwnerId: ownerId,
          // Read from the cached User rather than a token refresh. A
          // stale `false` only withholds the affordance; a stale `true`
          // is not reachable, because the flag never goes back.
          viewerEmailVerified: _auth.currentUser?.emailVerified ?? false,
          viewerIsCommunicationMuted: muted,
          membershipResolved: membershipResolved,
        ),
      );
    }

    controller = StreamController<ClubChatAuthority>(
      onListen: () {
        memberSub = _firestore
            .collection('clubs')
            .doc(clubId)
            .collection('members')
            .doc(uid)
            .snapshots()
            .listen(
              (snapshot) {
                role = snapshot.exists
                    ? ClubRole.fromValue(snapshot.data()?['role'])
                    : null;
                membershipResolved = true;
                emit();
              },
              onError: (_) {
                role = null;
                membershipResolved = true;
                emit();
              },
            );
        clubSub = _firestore
            .collection('clubs')
            .doc(clubId)
            .snapshots()
            .listen(
              (snapshot) {
                ownerId = _readOwnerId(snapshot.data());
                emit();
              },
              onError: (_) {
                ownerId = null;
                emit();
              },
            );
        restrictionSub = _firestore
            .collection('restrictions')
            .doc(uid)
            .snapshots()
            .listen(
              (snapshot) {
                muted = _readCommunicationMute(snapshot.data());
                emit();
              },
              onError: (_) {
                // Unreadable restrictions must not silently grant
                // moderation, but they must not take away a member's
                // ability to retract their own words either — which is
                // why this flag is consulted on the moderator path only.
                muted = true;
                emit();
              },
            );
      },
      onCancel: () async {
        await memberSub?.cancel();
        await clubSub?.cancel();
        await restrictionSub?.cancel();
      },
    );

    return controller.stream;
  }

  /// Soft-removes a message, in the one shape `firestore.rules` accepts.
  ///
  /// ONE SHAPE, NOT TWO. The rules permit `deletedBy`/`deletedAt` on the
  /// author branch as well as requiring them on the moderator branch, so
  /// a single write is legal either way — and that matters beyond tidiness.
  /// A two-shape client has to decide which branch it believes it is on
  /// and then send the matching payload; guess wrong and the write is
  /// refused for a reason the user cannot act on. With one shape the
  /// client never chooses a branch at all — the rules do, from the
  /// document. It also means every removal in the collection carries the
  /// same attribution fields, so the audit trigger and the UI read
  /// `deletedBy` directly instead of inferring an actor from an absence.
  /// Distinguishing a retraction from a moderator removal then becomes
  /// `deletedBy != senderId`, which is exactly what
  /// `functions/moderation/global_chat.js` already keys on.
  ///
  /// `editedAt` stays in the payload: the rules require it to equal
  /// `request.time`, not merely permit it.
  Future<void> deleteMessage({
    required String clubId,
    required String channelId,
    required ClubMessage message,
  }) async {
    final user = _user;
    final memberSnapshot = await _firestore
        .collection('clubs')
        .doc(clubId)
        .collection('members')
        .doc(user.uid)
        .get();
    if (!memberSnapshot.exists) {
      throw StateError('You are not a member of this club.');
    }
    final role = ClubRole.fromValue(memberSnapshot.data()?['role']);

    // Authority is decided against the SERVER's copy of the message, not
    // the rendered one. The rules pick the author branch or the moderator
    // branch from the STORED `senderId` and accept only a live -> removed
    // transition, so letting a tile that may be seconds stale choose the
    // branch is how an offered action turns into a bare denial. Re-reading
    // also means a message another moderator removed a moment ago gets
    // copy that says exactly that.
    final messageRef = _messages(
      clubId: clubId,
      channelId: channelId,
    ).doc(message.id);
    final current = await messageRef.get();
    if (!current.exists) {
      throw StateError('This message no longer exists.');
    }
    final live = ClubMessage.fromFirestore(
      clubId: clubId,
      channelId: channelId,
      document: current,
    );

    // The club document is only needed to protect the owner's messages
    // from moderators, and an author retracting their own message is
    // decided before ownership is ever consulted (see
    // ClubChatAuthority.removalRefusal), so the extra read is skipped on
    // the self-retraction path.
    final isAuthor = live.senderId == user.uid;
    final authority = ClubChatAuthority(
      viewerId: user.uid,
      role: role,
      clubOwnerId: isAuthor ? null : await _clubOwnerId(clubId),
      viewerEmailVerified: user.emailVerified,
      viewerIsCommunicationMuted: isAuthor
          ? false
          : await _isCommunicationMuted(user.uid),
    );
    final refusal = authority.removalRefusal(live);
    if (refusal != null) throw StateError(refusal);

    if (!isAuthor) {
      final payload = <String, Object?>{
        'clubId': clubId,
        'channelId': channelId,
        'messageId': live.id,
      };
      final response = _moderationInvoker != null
          ? await _moderationInvoker(payload)
          : (await _functions
                    .httpsCallable('moderateClubMessage')
                    .call<Map<Object?, Object?>>(payload))
                .data;
      if (response['outcome'] != 'redacted' || response['redacted'] != true) {
        throw StateError('The server did not confirm message removal.');
      }
      return;
    }

    await messageRef.update({
      'content': '',
      if (current.data()?.containsKey('gif') ?? false) 'gif': null,
      'isDeleted': true,
      'editedAt': FieldValue.serverTimestamp(),
      'deletedBy': user.uid,
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Mirrors the rules' `isCommunicationMuted()`: a live restriction of
  /// the right type with no expiry, or one that has not passed yet.
  Future<bool> _isCommunicationMuted(String uid) async {
    final snapshot = await _firestore.collection('restrictions').doc(uid).get();
    return _readCommunicationMute(snapshot.data());
  }

  static bool _readCommunicationMute(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['type'] != 'communicationMute') return false;
    final expiresAt = data['expiresAt'];
    if (expiresAt == null) return true;
    if (expiresAt is! Timestamp) return true;
    // Evaluated against the device clock where the rules use
    // `request.time`. A mute that lapses mid-session therefore keeps the
    // affordance withheld until something re-emits, which is the
    // harmless direction of the discrepancy.
    return DateTime.now().isBefore(expiresAt.toDate());
  }

  Future<String?> _clubOwnerId(String clubId) async {
    final snapshot = await _firestore.collection('clubs').doc(clubId).get();
    return _readOwnerId(snapshot.data());
  }

  /// Read exactly as the rule compares it — no trimming or coercion, so
  /// the client's idea of the owner cannot differ from the server's.
  static String? _readOwnerId(Map<String, dynamic>? data) {
    final value = data?['ownerId'];
    return value is String && value.isNotEmpty ? value : null;
  }
}
