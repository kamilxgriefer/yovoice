import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:yovoice/core/security/ephemeral_media_access_registry.dart';
import 'package:yovoice/features/rooms/data/models/room_message.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/data/models/room_metadata.dart';
import 'package:yovoice/features/rooms/data/models/room_voice_access.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';

typedef RoomCoverAccessInvoker =
    Future<Map<Object?, Object?>> Function(Map<String, Object?> request);
typedef RoomCoverFinalizeInvoker =
    Future<Map<Object?, Object?>> Function(Map<String, Object?> request);
typedef RoomMessageSendInvoker =
    Future<Map<Object?, Object?>> Function(Map<String, Object?> request);
typedef RoomCreateInvoker =
    Future<Map<Object?, Object?>> Function(Map<String, Object?> request);
typedef RoomVoiceStartInvoker =
    Future<Map<Object?, Object?>> Function(Map<String, Object?> request);

class RoomService {
  RoomService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    RoomCoverAccessInvoker? coverAccessInvoker,
    RoomCoverFinalizeInvoker? coverFinalizeInvoker,
    RoomMessageSendInvoker? roomMessageSendInvoker,
    RoomCreateInvoker? roomCreateInvoker,
    RoomVoiceStartInvoker? roomVoiceStartInvoker,
    String Function()? requestIdFactory,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions,
       _coverAccessInvoker = coverAccessInvoker,
       _coverFinalizeInvoker = coverFinalizeInvoker,
       _roomMessageSendInvoker = roomMessageSendInvoker,
       _roomCreateInvoker = roomCreateInvoker,
       _roomVoiceStartInvoker = roomVoiceStartInvoker,
       _requestIdFactory = requestIdFactory ?? _newRequestId {
    EphemeralMediaAccessRegistry.register(
      'room-cover',
      clearAllCoverAccessCaches,
    );
  }

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;
  final RoomCoverAccessInvoker? _coverAccessInvoker;
  final RoomCoverFinalizeInvoker? _coverFinalizeInvoker;
  final RoomMessageSendInvoker? _roomMessageSendInvoker;
  final RoomCreateInvoker? _roomCreateInvoker;
  final RoomVoiceStartInvoker? _roomVoiceStartInvoker;
  final String Function() _requestIdFactory;
  static final Map<String, _CachedRoomCoverAccess> _coverAccessCache = {};
  static int _coverAccessCacheEpoch = 0;

  /// In-flight cover grants, shared by every instance like the cache they
  /// feed. The entry screen's coordinator and the room screen it opens hold
  /// different `RoomService` instances; keyed by account, room and cover
  /// generation, one callable in flight serves both instead of each paying
  /// for its own.
  static final Map<String, Future<Uri>> _pendingCoverAccess = {};
  final Map<String, _PendingRoomVoiceStart> _pendingRoomVoiceStarts = {};
  _PrivateProfileRead? _privateProfileMemo;

  /// Client-side deadline for `startRoomVoice`. The plugin default is 60 s;
  /// a stalled or cold instance should become an actionable failure well
  /// before that. Safe to retry: the request and session ids are kept in
  /// [_pendingRoomVoiceStarts] and the server ledger replays them.
  static const Duration startRoomVoiceTimeout = Duration(seconds: 15);

  /// Client-side deadline for `getRoomCoverMediaAccess`. A missing cover is
  /// already tolerated (`_resolveRoomCoverSafely`), so a slow grant should
  /// degrade to the gradient state rather than hold a screen.
  static const Duration coverAccessTimeout = Duration(seconds: 10);

  /// Client-side deadline for `setOwnRoomParticipantMute`; see [setMuted].
  static const Duration setMutedDefaultTimeout = Duration(seconds: 15);

  /// How long one read of the caller's own `users/{uid}` document is reused
  /// between [resolveVoiceStartAuthority] and [joinRoom] on the dormant-room
  /// path. Both need the same document; the memo turns two reads into one.
  /// A rename inside this window fails the rules' byte-for-byte displayName
  /// binding at commit and surfaces as the existing "The room changed while
  /// you were joining" retry — the same failure class as today's
  /// millisecond gap, just a wider one.
  static const Duration privateProfileMemoTtl = Duration(seconds: 10);

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

  CollectionReference<Map<String, dynamic>> get _rooms =>
      _firestore.collection('rooms');

  User get _user {
    final user = _auth.currentUser;
    if (user == null) throw StateError('You must be signed in to use rooms.');
    return user;
  }

  /// The signed-in account id, or '' when signed out.
  ///
  /// The room screens used to read `FirebaseAuth.instance` directly, which
  /// tied every one of their render paths to a live Firebase app and left the
  /// voice lifecycle untestable at the widget level. Routing identity through
  /// the same injected service the rest of the screen already uses is what
  /// makes "did this screen ask for a token?" an answerable question.
  String get currentUserId => _auth.currentUser?.uid ?? '';

  Future<Uri> resolveCoverUri(VoiceRoom room) {
    final uid = _auth.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      throw StateError('You must be signed in to view this room cover.');
    }
    final path = room.coverStoragePath;
    final generation = room.coverGeneration;
    if (!room.hasCanonicalCover ||
        path == null ||
        generation == null ||
        room.id.isEmpty ||
        room.id.contains('/')) {
      throw const FormatException('The room cover identity is invalid.');
    }
    final epoch = _coverAccessCacheEpoch;
    final cacheKey = '$uid:${room.id}:$generation';
    final now = DateTime.now().toUtc();
    final cached = _coverAccessCache[cacheKey];
    if (cached != null &&
        cached.expiresAt.isAfter(now.add(const Duration(seconds: 15)))) {
      return Future<Uri>.value(cached.uri);
    }
    final inFlight = _pendingCoverAccess[cacheKey];
    if (inFlight != null) return inFlight;
    // DELIBERATELY NOT `putIfAbsent`. The grant body can fail before its first
    // suspension — `FirebaseFunctions.instanceFor` throws when there is no
    // Firebase app — and a `finally` that removes the key would then run
    // BEFORE `putIfAbsent` inserted it, leaving a failed future in a
    // process-wide map for the life of the isolate. Build the future, insert
    // it, and remove it from a completion callback that cannot run before the
    // insert.
    final pending = _requestCoverAccess(
      room: room,
      uid: uid,
      path: path,
      generation: generation,
      cacheKey: cacheKey,
      epoch: epoch,
    );
    _pendingCoverAccess[cacheKey] = pending;
    unawaited(
      pending.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        // Only ever retire OUR entry; a newer request for the same key owns
        // itself.
        if (identical(_pendingCoverAccess[cacheKey], pending)) {
          _pendingCoverAccess.remove(cacheKey);
        }
      }),
    );
    return pending;
  }

  Future<Uri> _requestCoverAccess({
    required VoiceRoom room,
    required String uid,
    required String path,
    required String generation,
    required String cacheKey,
    required int epoch,
  }) async {
    final payload = <String, Object?>{'roomId': room.id};
    final response = _coverAccessInvoker != null
        ? await _coverAccessInvoker(payload)
        : (await _functions
                  .httpsCallable(
                    'getRoomCoverMediaAccess',
                    options: HttpsCallableOptions(timeout: coverAccessTimeout),
                  )
                  .call<Map<Object?, Object?>>(payload))
              .data;
    if (_auth.currentUser?.uid != uid || epoch != _coverAccessCacheEpoch) {
      throw StateError('Room cover access was cleared. Try again.');
    }
    final rawUrl = response['url'];
    final rawExpiry = response['expiresAtMillis'];
    final responseGeneration = response['coverGeneration'];
    final responseType = response['coverContentType'];
    final responseSize = response['coverSize'];
    if (response['schemaVersion'] != 1 ||
        rawUrl is! String ||
        rawUrl.length > 4096 ||
        rawExpiry is! int ||
        responseGeneration != generation ||
        responseType != room.coverContentType ||
        responseSize != room.coverSize) {
      throw const FormatException('Malformed room-cover grant.');
    }
    final uri = Uri.tryParse(rawUrl);
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      rawExpiry,
      isUtc: true,
    );
    final objectPath = uri == null || uri.pathSegments.length < 2
        ? ''
        : uri.pathSegments.skip(1).join('/');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'storage.googleapis.com' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        objectPath != path ||
        uri.queryParameters['generation'] != generation ||
        !expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const FormatException('Unsafe room-cover grant.');
    }
    _coverAccessCache[cacheKey] = _CachedRoomCoverAccess(
      uri: uri,
      expiresAt: expiresAt,
    );
    return uri;
  }

  Future<VoiceRoom> _resolveRoomCoverSafely(VoiceRoom room) async {
    if (!room.hasCanonicalCover) return room;
    try {
      return room.withResolvedImageUrl(
        (await resolveCoverUri(room)).toString(),
      );
    } catch (error) {
      debugPrint('Room cover unavailable for ${room.id}: $error');
      return room.withResolvedImageUrl(null);
    }
  }

  /// Starts resolving [room]'s cover grant without waiting for it.
  ///
  /// The entry path reads a room to decide whether it may be joined; the
  /// cover is not part of that decision, so the grant callable — a cold
  /// start on its own — should not sit in the await chain. Warming it here
  /// means the room screen's first `watchRoom` emission finds the grant in
  /// [_coverAccessCache], or joins the same in-flight future. Failures are
  /// logged and swallowed exactly as [_resolveRoomCoverSafely] does.
  void _warmCoverAccess(VoiceRoom room) {
    if (!room.hasCanonicalCover) return;
    try {
      unawaited(
        resolveCoverUri(room).then<void>(
          (_) {},
          onError: (Object error) {
            debugPrint('Room cover warm-up failed for ${room.id}: $error');
          },
        ),
      );
    } catch (error) {
      debugPrint('Room cover warm-up failed for ${room.id}: $error');
    }
  }

  /// [room] with its cover grant applied, or [room] unchanged with the grant
  /// warming in the background.
  ///
  /// Resolving costs a callable round trip. A surface that paints the cover
  /// pays it; the entry path, which only decides whether the room may be
  /// joined, does not — it warms the same cache instead so the room screen's
  /// first `watchRoom` emission finds the grant already there.
  Future<VoiceRoom> _withCover(VoiceRoom room, {required bool resolve}) {
    if (resolve) return _resolveRoomCoverSafely(room);
    _warmCoverAccess(room);
    return Future<VoiceRoom>.value(room);
  }

  static void clearAllCoverAccessCaches() {
    _coverAccessCacheEpoch += 1;
    _coverAccessCache.clear();
    // In-flight grants belong to the session that started them. The epoch
    // check already makes them fail closed; dropping them keeps the shared
    // map from carrying one account's request into the next account's reads.
    _pendingCoverAccess.clear();
  }

  /// A display label for the live-audio session. The LiveKit participant name
  /// is re-derived server-side from the canonical profile
  /// (`buildParticipantName` in functions/livekit/token.js), so this is a
  /// presentation fallback, never an identity claim.
  String get currentUserLabel {
    final user = _auth.currentUser;
    if (user == null) return 'YO Voice user';
    final name = user.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user.email?.split('@').first.trim();
    if (email != null && email.isNotEmpty) return email;
    return 'YO Voice user';
  }

  /// Canonical identity for everything this service writes (rosters,
  /// members, messages): the private profile document. Display name never
  /// falls back to Firebase Auth because Auth is a retryable mirror and may
  /// be stale after a rename. Avatar renderers resolve the uid through the
  /// viewer-authorized profile-media service instead of copying Auth URLs.
  Future<({String displayName, String? photoUrl})> _identity() async {
    final user = _user;
    final data = await _readPrivateProfile(user.uid);
    final name = data?['displayName'];
    if (name is! String || name.trim().isEmpty) {
      throw StateError('Your profile does not have a display name.');
    }
    return (
      // Preserve exact stored bytes for the byte-for-byte Rules binding.
      displayName: name,
      photoUrl: null,
    );
  }

  /// One read of `users/{uid}` shared by [_identity] and [_isActiveAccount],
  /// reused for [privateProfileMemoTtl]. Only a read that succeeded is kept,
  /// only for the account it was read for, and only until the next account
  /// boundary — [clearAllCoverAccessCaches] bumps the same epoch on sign-out,
  /// so a memo can never outlive the session that produced it.
  Future<Map<String, dynamic>?> _readPrivateProfile(String uid) async {
    final epoch = _coverAccessCacheEpoch;
    final memo = _privateProfileMemo;
    if (memo != null &&
        memo.uid == uid &&
        memo.epoch == epoch &&
        DateTime.now().difference(memo.readAt) <= privateProfileMemoTtl) {
      return memo.data;
    }
    final data = (await _firestore.collection('users').doc(uid).get()).data();
    if (_coverAccessCacheEpoch == epoch) {
      _privateProfileMemo = _PrivateProfileRead(
        uid: uid,
        data: data,
        readAt: DateTime.now(),
        epoch: epoch,
      );
    }
    return data;
  }

  Future<VoiceRoom> createRoom({
    required String name,
    required String description,
    required String category,
    required String visibility,
    required String language,
    required int? maxParticipants,
    required RoomType roomType,
    TargetAudience targetAudience = TargetAudience.everyone,
    List<String> topicTags = const <String>[],
    String roomGuidelines = '',
    ConversationStyle? conversationStyle,
    bool newcomerFriendly = false,
    ShowFormat? showFormat,
    RoomExperience experience = RoomExperience.community,
    String topic = '',
    bool audienceCanSpeak = true,
    bool handRaisingEnabled = false,
    String? requestId,
  }) async {
    final user = _user;
    final normalizedName = name.trim();
    if (normalizedName.length < 3) {
      throw ArgumentError('Room name must contain at least 3 characters.');
    }
    if (normalizedName.length > 100) {
      throw ArgumentError('Room name cannot exceed 100 characters.');
    }
    final normalizedDescription = description.trim();
    if (normalizedDescription.length > 1000) {
      throw ArgumentError('Room description cannot exceed 1000 characters.');
    }
    final normalizedGuidelines = roomGuidelines.trim();
    if (normalizedGuidelines.length > RoomMetadataLimits.maxGuidelinesLength) {
      throw ArgumentError(
        'Room guidelines cannot exceed '
        '${RoomMetadataLimits.maxGuidelinesLength} characters.',
      );
    }
    final normalizedTopic = topic.trim();
    final creationRequestId = requestId ?? _requestIdFactory();
    if (!RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(creationRequestId)) {
      throw ArgumentError('The room creation request id is invalid.');
    }

    final payload = <String, Object?>{
      'requestId': creationRequestId,
      'name': normalizedName,
      'description': normalizedDescription,
      'category': category,
      'visibility': visibility,
      'language': language,
      'maxParticipants': maxParticipants,
      'roomType': roomType.name,
      'targetAudience': targetAudience.value,
      'topicTags': RoomMetadataLimits.normalizeTags(topicTags),
      'roomGuidelines': normalizedGuidelines,
      'conversationStyle': conversationStyle?.value,
      'newcomerFriendly': newcomerFriendly,
      'showFormat': showFormat?.value,
      'experience': experience.firestoreValue,
      'topic': normalizedTopic,
      'audienceCanSpeak': audienceCanSpeak,
      'handRaisingEnabled': handRaisingEnabled,
    };
    final response = _roomCreateInvoker != null
        ? await _roomCreateInvoker(payload)
        : (await _functions
                  .httpsCallable('createRoom')
                  .call<Map<Object?, Object?>>(payload))
              .data;
    final roomId = response['roomId'];
    if (response['schemaVersion'] != 1 ||
        roomId is! String ||
        !RegExp(r'^r_[a-f0-9]{40}$').hasMatch(roomId)) {
      throw const FormatException('The room creation response is malformed.');
    } else {
      final room = await getRoom(roomId);
      if (room.hostId != user.uid || room.clubId != null) {
        throw const FormatException('The created room identity is invalid.');
      }
      return room;
    }
  }

  /// Generates one retry-safe key for a creation flow. The screen retains it
  /// after an inconclusive callable failure, so another tap recovers the same
  /// server transaction rather than creating a second room.
  String newRoomCreationRequestId() => _requestIdFactory();

  Stream<List<VoiceRoom>> watchLivePublicRooms() {
    return _rooms
        .where('isLive', isEqualTo: true)
        .where('visibility', isEqualTo: 'public')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final rooms = snapshot.docs
              .map(VoiceRoom.fromFirestore)
              .where((room) => room.isActive);
          return Future.wait(rooms.map(_resolveRoomCoverSafely));
        });
  }

  Stream<List<VoiceRoom>> watchPublicRooms() {
    return _rooms.where('visibility', isEqualTo: 'public').snapshots().asyncMap(
      (snapshot) async {
        final rooms = await Future.wait(
          snapshot.docs
              .map(VoiceRoom.fromFirestore)
              .where((room) => room.isActive)
              .map(_resolveRoomCoverSafely),
        );
        rooms.sort(
          (a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(1970)).compareTo(
            a.updatedAt ?? a.createdAt ?? DateTime(1970),
          ),
        );
        return rooms;
      },
    );
  }

  Stream<List<VoiceRoom>> watchOwnedRooms() {
    return _rooms.where('hostId', isEqualTo: _user.uid).snapshots().asyncMap((
      snapshot,
    ) async {
      final rooms = await Future.wait(
        snapshot.docs.map(VoiceRoom.fromFirestore).map(_resolveRoomCoverSafely),
      );
      rooms.sort(
        (a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(1970)).compareTo(
          a.updatedAt ?? a.createdAt ?? DateTime(1970),
        ),
      );
      return rooms;
    });
  }

  Stream<List<VoiceRoom>> watchMyCommunities() {
    return _firestore
        .collectionGroup('roomMembers')
        .where('userId', isEqualTo: _user.uid)
        .snapshots()
        .asyncMap((snapshot) async {
          final roomIds = snapshot.docs
              .map((document) => document.reference.parent.parent?.id)
              .whereType<String>()
              .toSet();

          if (roomIds.isEmpty) return <VoiceRoom>[];

          final documents = await Future.wait(
            roomIds.map((roomId) => _rooms.doc(roomId).get()),
          );

          final parsedRooms = documents
              .where((document) => document.exists)
              .map(VoiceRoom.fromFirestore)
              .where(
                (room) => room.roomType == RoomType.community && room.isActive,
              );
          final rooms = await Future.wait(
            parsedRooms.map(_resolveRoomCoverSafely),
          );

          rooms.sort(
            (a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(1970)).compareTo(
              a.updatedAt ?? a.createdAt ?? DateTime(1970),
            ),
          );
          return rooms;
        });
  }

  Stream<VoiceRoom> watchRoom(String roomId) {
    return _rooms.doc(roomId).snapshots().asyncMap((document) async {
      if (!document.exists) throw StateError('The room no longer exists.');
      return _resolveRoomCoverSafely(VoiceRoom.fromFirestore(document));
    });
  }

  /// Reads one room.
  ///
  /// [resolveCover] defaults to true so every existing caller keeps painting
  /// the cover it always painted. Pass false on a path that only needs the
  /// room's STATE — the entry coordinator's refresh, for instance — and the
  /// `getRoomCoverMediaAccess` callable leaves the await chain entirely; the
  /// grant is still fetched, just concurrently.
  Future<VoiceRoom> getRoom(String roomId, {bool resolveCover = true}) async {
    final document = await _rooms.doc(roomId).get();
    if (!document.exists) {
      throw StateError('The room no longer exists.');
    }
    return _withCover(VoiceRoom.fromFirestore(document), resolve: resolveCover);
  }

  /// Authoritative read for destructive recovery decisions. A normal get may
  /// fall back to a stale cache while the network is unhealthy; that is useful
  /// for UI, but it must never be used as proof that a lost-ACK write did not
  /// commit before deleting its Storage object.
  Future<VoiceRoom> getRoomFromServer(String roomId) async {
    final document = await _rooms
        .doc(roomId)
        .get(const GetOptions(source: Source.server));
    if (document.metadata.isFromCache || document.metadata.hasPendingWrites) {
      throw StateError('The room state is not yet confirmed by the server.');
    }
    if (!document.exists) {
      throw StateError('The room no longer exists.');
    }
    return _resolveRoomCoverSafely(VoiceRoom.fromFirestore(document));
  }

  Stream<bool> watchIsParticipant(String roomId) {
    return _rooms
        .doc(roomId)
        .collection('participants')
        .doc(_user.uid)
        .snapshots()
        .map((document) => document.exists);
  }

  Stream<List<RoomParticipant>> watchParticipants(String roomId) {
    return _rooms.doc(roomId).collection('participants').snapshots().map((
      snapshot,
    ) {
      final participants = snapshot.docs
          .map(RoomParticipant.fromFirestore)
          .toList();
      participants.sort((a, b) {
        if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
        if (a.isSpeaker != b.isSpeaker) return a.isSpeaker ? -1 : 1;
        return a.displayName.compareTo(b.displayName);
      });
      return participants;
    });
  }

  /// Authoritative check that [userId] really is gone from [roomId]'s
  /// roster, asked of the SERVER.
  ///
  /// `watchParticipants` is a `snapshots()` stream, which also emits
  /// CACHE-sourced snapshots (listener re-establishment after a network
  /// blip, cold-cache re-targeting). A transient snapshot that happens
  /// not to contain the caller's own participant document is
  /// indistinguishable, at the stream level, from "a moderator removed
  /// me" — and the room screens ejected the user to the ended state on
  /// that basis. Observed once in production: a host was ejected ~80s
  /// after creating a room, with no moderation action and the room
  /// still live (docs/Bugs.md).
  ///
  /// Returns true only when the server confirms the document is absent.
  /// On any error it returns FALSE (still present): a failed check must
  /// never eject someone from a room they are legitimately in.
  Future<bool> isParticipantRemovedOnServer({
    required String roomId,
    required String userId,
  }) async {
    try {
      final snapshot = await _rooms
          .doc(roomId)
          .collection('participants')
          .doc(userId)
          .get(const GetOptions(source: Source.server));
      return !snapshot.exists;
    } catch (_) {
      return false;
    }
  }

  /// The newest chat message alone, for the mini player's collapsed
  /// preview. `limit(1)` on the same single-field `createdAt` ordering the
  /// full history uses, so a surface that only ever shows one line never
  /// pays for a hundred documents. Emits null while the room has no
  /// messages (or the latest was deleted and none remain).
  Stream<RoomMessage?> watchLatestRoomMessage(String roomId) {
    return _rooms
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.isEmpty
              ? null
              : RoomMessage.fromFirestore(snapshot.docs.first),
        );
  }

  Stream<List<RoomMessage>> watchRoomMessages(String roomId) {
    return _rooms
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(RoomMessage.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<void> updateRoomSettings({
    required String roomId,
    required String name,
    required String description,
    required String category,
    required String visibility,
    required String language,
    required int? maxParticipants,
    required bool approvalRequired,
    required int slowModeSeconds,
    required bool autoMuteNewUsers,
    required bool membersCanStartVoice,
    String? topic,
    ShowFormat? showFormat,
    String? roomGuidelines,
    bool? handRaisingEnabled,
  }) async {
    final currentRoom = await _requireHost(roomId);
    final normalizedName = name.trim();
    if (normalizedName.length < 3) {
      throw ArgumentError('Room name must contain at least 3 characters.');
    }
    if (currentRoom['visibility'] != visibility) {
      await _functions.httpsCallable('setRoomVisibilitySelf').call<void>({
        'roomId': roomId,
        'visibility': visibility,
      });
    }
    await _rooms.doc(roomId).update({
      'name': normalizedName,
      'description': description.trim(),
      'category': category,
      'language': language,
      'maxParticipants': maxParticipants,
      'approvalRequired': approvalRequired,
      'slowModeSeconds': slowModeSeconds,
      'autoMuteNewUsers': autoMuteNewUsers,
      'membersCanStartVoice': membersCanStartVoice,
      if (topic != null) 'topic': topic.trim(),
      if (showFormat != null) 'showFormat': showFormat.value,
      if (roomGuidelines != null)
        'roomGuidelines': roomGuidelines.trim().substring(
          0,
          roomGuidelines.trim().length > RoomMetadataLimits.maxGuidelinesLength
              ? RoomMetadataLimits.maxGuidelinesLength
              : roomGuidelines.trim().length,
        ),
      'handRaisingEnabled': ?handRaisingEnabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> finalizeRoomCoverUpload({
    required String roomId,
    required String objectGeneration,
    required String reservationId,
    required String storagePath,
  }) async {
    final request = <String, Object?>{
      'roomId': roomId,
      'objectGeneration': objectGeneration,
      'reservationId': reservationId,
    };
    final response = _coverFinalizeInvoker != null
        ? await _coverFinalizeInvoker(request)
        : (await _functions
                  .httpsCallable('finalizeRoomCoverUpload')
                  .call<Map<Object?, Object?>>(request))
              .data;
    if (response['updated'] != true ||
        response['coverStoragePath'] != storagePath ||
        response['coverGeneration'] != objectGeneration) {
      throw StateError('The room cover service returned an invalid result.');
    }
    clearAllCoverAccessCaches();
  }

  @Deprecated('Use finalizeRoomCoverUpload with canonical Storage identity.')
  Future<void> updateImageUrl({
    required String roomId,
    required String imageUrl,
  }) {
    throw UnsupportedError(
      'Durable room-cover download URLs are no longer accepted.',
    );
  }

  Future<void> setRoomStatus(String roomId, RoomStatus status) async {
    final callable = _functions.httpsCallable('setRoomStatusSelf');
    await callable.call<Map<Object?, Object?>>({
      'roomId': roomId,
      'status': status.name,
    });
  }

  Future<VoiceRoom> joinRoom(
    String roomId, {
    bool startMuted = false,
    bool resolveCover = true,
  }) async {
    final user = _user;
    // ISSUED NOW, AWAITED INSIDE THE TRANSACTION. The profile read and the
    // transaction's room read touch different documents and neither depends on
    // the other, so serialising them only added a round trip to every join.
    // The read is still awaited before anything is written, so a profile
    // without a display name still refuses the join exactly as it did.
    final identityRead = _identity();
    // A failure here must surface through the transaction below, not as an
    // unhandled asynchronous error when a room check throws first.
    unawaited(identityRead.then<void>((_) {}, onError: (Object _) {}));
    final room = _rooms.doc(roomId);
    final participant = room.collection('participants').doc(user.uid);

    // The document as the transaction committed it. Returning this instead of
    // re-reading the room afterwards removes the last round trip of the join:
    // the only field the write moves is the roster count.
    VoiceRoom? joined;
    await _firestore.runTransaction((transaction) async {
      // A transaction body can run more than once; never carry a previous
      // attempt's result forward.
      joined = null;
      final snapshot = await transaction.get(room);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw StateError('The requested room does not exist.');
      }
      if (RoomStatus.fromValue(data['status']) != RoomStatus.active) {
        throw StateError('This room is currently unavailable.');
      }
      if (data['isLive'] != true) {
        throw StateError('Voice is not live in this room.');
      }
      final identity = await identityRead;
      final captured = VoiceRoom.fromFirestore(snapshot);

      final existing = await transaction.get(participant);
      if (existing.exists) {
        // RE-ENTRY, NOT A FRESH JOIN. The row survives a tab close, a crash
        // and any leave that did not complete, so this is the ordinary path
        // back into a room — not an edge case.
        //
        // The roster and LiveKit join must agree on the initial microphone
        // state. Normal entry starts open; a confirmed external deep link
        // starts muted. Never leave a previous session's value behind.
        //
        // Only the caller's OWN flag is touched. `hostMuted` and `serverMuted`
        // are left exactly as they are — the rules pin both on this update,
        // and the token honours them independently, so a moderator mute
        // survives re-entry the way it must.
        if ((existing.data() ?? const <String, dynamic>{})['isMuted'] !=
            startMuted) {
          transaction.update(participant, {
            'isMuted': startMuted,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        // Re-entry adds nobody to the roster, so the captured count already
        // describes the room the caller is about to see.
        joined = captured;
        return;
      }

      final count = (data['participantCount'] as num?)?.toInt() ?? 0;
      final max = (data['maxParticipants'] as num?)?.toInt();
      if (max != null && count >= max) throw StateError('This room is full.');

      final experience = RoomExperience.fromValue(data['experience']);
      final everyoneSpeaks = experience == RoomExperience.community;
      transaction.set(participant, {
        'userId': user.uid,
        'displayName': identity.displayName,
        'photoUrl': identity.photoUrl,
        'role': data['hostId'] == user.uid
            ? 'host'
            : everyoneSpeaks
            ? 'speaker'
            : 'listener',
        'isMuted': startMuted
            ? true
            : data['hostId'] == user.uid
            ? false
            : everyoneSpeaks
            ? false
            : (data['autoMuteNewUsers'] as bool? ?? true),
        'isSpeaker': data['hostId'] == user.uid || everyoneSpeaks,
        'isHandRaised': false,
        'joinedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(room, {
        'participantCount': count + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      joined = captured.withParticipantCount(count + 1);
    });
    // The fallback covers a transaction implementation that could commit
    // without running the body to completion; it costs a read only when the
    // captured value is genuinely missing.
    final result = joined ?? VoiceRoom.fromFirestore(await room.get());
    return _withCover(result, resolve: resolveCover);
  }

  Future<void> joinCommunity(String roomId) async {
    final user = _user;
    // Same overlap as [joinRoom]: an independent document read has no reason
    // to sit in front of the transaction that needs it.
    final identityRead = _identity();
    unawaited(identityRead.then<void>((_) {}, onError: (Object _) {}));
    final room = _rooms.doc(roomId);
    final member = room.collection('roomMembers').doc(user.uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(room);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) throw StateError('Room not found.');
      if (RoomType.fromValue(data['roomType']) != RoomType.community) {
        throw StateError('Only community rooms have members.');
      }
      if (RoomStatus.fromValue(data['status']) != RoomStatus.active) {
        throw StateError('This community is currently unavailable.');
      }
      final identity = await identityRead;
      final existing = await transaction.get(member);
      if (existing.exists) return;
      if (data['approvalRequired'] == true) {
        throw StateError('This community requires owner approval.');
      }
      final count = (data['memberCount'] as num?)?.toInt() ?? 0;
      transaction.set(member, {
        'userId': user.uid,
        'displayName': identity.displayName,
        'photoUrl': identity.photoUrl,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(room, {
        'memberCount': count + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Resolves whether THIS account may flip [room]'s `isLive` false -> true,
  /// mirroring the deployed `firestore.rules` branch for branch.
  ///
  /// The client asks this BEFORE offering a start control, because the app
  /// must never present an affordance the server will refuse. It is a mirror,
  /// not the authority: the rules and `createLiveKitToken` still decide.
  ///
  /// Legacy tolerance is deliberate and matches the rules' own
  /// `.get(field, default)` reads. Production holds rooms with no
  /// `membersCanStartVoice`, no `roomType` and no `experience`; every one of
  /// them resolves here exactly as the server would resolve it, which for a
  /// bare document means "the host, and nobody else".
  Future<RoomVoiceStartAuthority> resolveVoiceStartAuthority(
    VoiceRoom room,
  ) async {
    // A closed, archived, suspended or half-deleted room has no voice
    // session to start. `hostRoomUpdateAllowed()`'s start branch does not
    // read `deletionInProgress`, so this refusal is stricter than the rules
    // on purpose: a room whose teardown has begun must never be restarted
    // from the client while the server is still dismantling it.
    if (!room.isActive || room.deletionInProgress) {
      return RoomVoiceStartAuthority.none;
    }

    final uid = _user.uid;

    // ACCOUNT STATUS IS PART OF EVERY BRANCH, not a separate concern.
    // `hostRoomUpdateAllowed()` opens with `isActiveAccount()`, and both
    // `isRoomMember()` and `isActiveClubRoomMember()` call it too, so a
    // banned or disabled account satisfies none of the three. Without this
    // read the app offers such an account a "Start voice" control and the
    // server answers with a denial — the precise mismatch this mirror
    // exists to prevent. Mirrors accountIsActive(): the profile must exist
    // and carry neither flag.
    if (!await _isActiveAccount(uid)) return RoomVoiceStartAuthority.none;

    if (room.hostId.isNotEmpty && room.hostId == uid) {
      return RoomVoiceStartAuthority.host;
    }

    // Club lounges (including Family Rooms) derive start authority from
    // canonical Club membership, never from a roomMembers row — lounge
    // members never get one. Mirrors isActiveClubRoomMember().
    //
    // This branch RETURNS rather than falling through, which is marginally
    // stricter than `roomVoiceStartAllowed()`: that rule is a disjunction, so
    // a Club room that also set `membersCanStartVoice` would additionally
    // accept a roomMembers holder. No such document can exist — a lounge is
    // written `visibility: 'private'` and the self-join roomMembers rule
    // requires a public room, while `ensureClubLounge` writes no membership
    // rows at all — and erring toward the Club's own membership on a private
    // Club room is the safe direction. Anything that starts minting lounge
    // roomMembers rows must revisit this.
    //
    // `storedClubId`, NOT `clubId`: the rule reads the document FIELD
    // (`resource.data.get('clubId','')`), so a lounge identified only by its
    // `club_lounge_` id prefix cannot satisfy the Club branch on the server
    // no matter who the caller is. Resolving from the prefix-derived getter
    // would offer a Start control and then eat a permission-denied.
    final clubId = room.storedClubId;
    if (clubId != null && clubId.isNotEmpty) {
      return await _isActiveClubMember(clubId, uid)
          ? RoomVoiceStartAuthority.clubMember
          : RoomVoiceStartAuthority.none;
    }

    // A fieldless lounge falls THROUGH rather than returning none, because
    // `roomVoiceStartAllowed()` is a disjunction: its second branch is still
    // open to a roomMembers holder if the host set membersCanStartVoice.
    // Lounges carry neither, so in practice this resolves to host-only —
    // which is exactly what the server would decide for the same document.
    if (room.membersCanStartVoice && await _isMember(room.id, uid)) {
      return RoomVoiceStartAuthority.roomMember;
    }
    return RoomVoiceStartAuthority.none;
  }

  /// Starts one server-authorized voice session.
  ///
  /// The request and session ids remain stable after an ambiguous network
  /// failure. Retrying therefore recovers the original atomic transition;
  /// it cannot create another follower-notification fanout. Firestore Rules
  /// deliberately reject every direct false -> true write.
  Future<void> startRoomVoice(String roomId) async {
    final pending = _pendingRoomVoiceStarts.putIfAbsent(
      roomId,
      () => _PendingRoomVoiceStart(
        requestId: _requestIdFactory(),
        sessionId: _requestIdFactory(),
      ),
    );
    final payload = <String, Object?>{
      'requestId': pending.requestId,
      'roomId': roomId,
      'sessionId': pending.sessionId,
    };
    final response = _roomVoiceStartInvoker != null
        ? await _roomVoiceStartInvoker(payload)
        : (await _functions
                  .httpsCallable(
                    'startRoomVoice',
                    options: HttpsCallableOptions(
                      timeout: startRoomVoiceTimeout,
                    ),
                  )
                  .call<Map<Object?, Object?>>(payload))
              .data;
    if (response['schemaVersion'] != 1 ||
        response['started'] != true ||
        response['roomId'] != roomId ||
        response['sessionId'] != pending.sessionId) {
      throw const FormatException(
        'The room voice-start response is malformed.',
      );
    }
    _pendingRoomVoiceStarts.remove(roomId);
  }

  /// Turns a dormant room live and puts the caller on its roster.
  ///
  /// This is the ONE path that makes a room joinable by voice, shared by
  /// every room type — Community, Broadcast, Club Lounge and Family Room.
  /// It is ordered on purpose: liveness first, roster second, and only then
  /// may a LiveKit token be requested. `joinRoom` itself refuses a room whose
  /// `isLive` is not true, and `createLiveKitToken` refuses both a dormant
  /// room and a caller with no participant row, so any other order is a
  /// guaranteed failure.
  ///
  /// Kept under its original name because it is public API; it now serves
  /// every experience rather than only non-club community rooms, and it
  /// resolves authority through [resolveVoiceStartAuthority] instead of the
  /// partial host/`membersCanStartVoice` test it used to carry (which had no
  /// Club branch at all, so a Club Lounge member — including a Family Room
  /// member — was always refused).
  Future<void> startCommunityVoice(String roomId) async {
    final room = await getRoom(roomId);
    if (!room.isActive || room.deletionInProgress) {
      throw StateError('Open the room before starting voice.');
    }
    if (!room.isLive) {
      final authority = await resolveVoiceStartAuthority(room);
      if (!authority.canStart) {
        throw StateError('You cannot start voice in this room.');
      }
      await startRoomVoice(roomId);
    }
    await joinRoom(roomId);
  }

  /// Ends the voice session for everyone in the room.
  ///
  /// [onlyIfEmpty] is the difference between the two callers. A host pressing
  /// "End room" MEANS "end it for the people in it", so the default stays
  /// false and that control is unchanged. The leave path passes true, and the
  /// server then re-reads the ROSTER inside its own transaction and writes
  /// nothing if anyone else is present — returning success, not an error,
  /// because a leave must never surface as a failure. Without the flag a
  /// leave decided on the denormalised `participantCount` could disconnect
  /// people who were still talking.
  Future<void> endCommunityVoice(
    String roomId, {
    bool onlyIfEmpty = false,
  }) async {
    final callable = _functions.httpsCallable('endRoomVoiceSelf');
    await callable.call<Map<Object?, Object?>>({
      'roomId': roomId,
      if (onlyIfEmpty) 'onlyIfEmpty': true,
    });
  }

  DocumentReference<Map<String, dynamic>> clubLoungeReference(String clubId) {
    return _rooms.doc('club_lounge_$clubId');
  }

  Stream<VoiceRoom?> watchClubLounge(String clubId) {
    return clubLoungeReference(clubId).snapshots().asyncMap((document) async {
      if (!document.exists) return null;
      return _resolveRoomCoverSafely(VoiceRoom.fromFirestore(document));
    });
  }

  Future<VoiceRoom> ensureClubLounge({
    required String clubId,
    required String clubName,
    required String clubDescription,
    required String language,
    required String ownerId,
    required String ownerName,
    String? ownerPhotoUrl,
    String? imageUrl,
  }) async {
    final reference = clubLoungeReference(clubId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (snapshot.exists) return;

      transaction.set(reference, {
        'hostId': ownerId,
        'hostName': ownerName,
        'hostPhotoUrl': null,
        'name': '$clubName Lounge',
        'description': clubDescription.trim().isEmpty
            ? 'Private voice lounge for $clubName members.'
            : clubDescription.trim(),
        'category': 'club',
        'visibility': 'private',
        'language': language.trim().isEmpty ? 'English' : language.trim(),
        'maxParticipants': null,
        'participantCount': 0,
        'memberCount': 0,
        'isLive': false,
        'roomType': RoomType.community.name,
        'status': RoomStatus.active.name,
        'imageUrl': imageUrl,
        'approvalRequired': false,
        'slowModeSeconds': 0,
        'autoMuteNewUsers': false,
        'membersCanStartVoice': true,
        'experience': 'community',
        'clubId': clubId,
        'roomKind': 'clubLounge',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    return getRoom(reference.id);
  }

  /// Resolves a member's Club Lounge for a passive prejoin preview.
  ///
  /// This intentionally performs no voice-start write and creates no roster
  /// row. `RoomEntryScreen` owns that consent boundary through the shared
  /// entry coordinator, just like every other room surface.
  Future<VoiceRoom> prepareClubLounge({
    required String clubId,
    required String clubName,
    required String clubDescription,
    required String language,
    required String ownerId,
    required String ownerName,
    String? ownerPhotoUrl,
    String? imageUrl,
  }) async {
    final member = await _firestore
        .collection('clubs')
        .doc(clubId)
        .collection('members')
        .doc(_user.uid)
        .get();
    if (!member.exists) {
      throw StateError('Only club members can enter the Club Lounge.');
    }

    final room = await ensureClubLounge(
      clubId: clubId,
      clubName: clubName,
      clubDescription: clubDescription,
      language: language,
      ownerId: ownerId,
      ownerName: ownerName,
      ownerPhotoUrl: ownerPhotoUrl,
      imageUrl: imageUrl,
    );

    if (!room.isActive || room.deletionInProgress) {
      throw StateError('This lounge is not available right now.');
    }

    return room;
  }

  /// Legacy programmatic entry retained for non-UI callers.
  ///
  /// Product navigation uses [prepareClubLounge] and lets RoomEntryScreen
  /// perform the actual start/join only after explicit consent.
  Future<VoiceRoom> enterClubLounge({
    required String clubId,
    required String clubName,
    required String clubDescription,
    required String language,
    required String ownerId,
    required String ownerName,
    String? ownerPhotoUrl,
    String? imageUrl,
  }) async {
    final room = await prepareClubLounge(
      clubId: clubId,
      clubName: clubName,
      clubDescription: clubDescription,
      language: language,
      ownerId: ownerId,
      ownerName: ownerName,
      ownerPhotoUrl: ownerPhotoUrl,
      imageUrl: imageUrl,
    );

    if (!room.isLive) {
      // Same single-purpose write every other room type uses, so the shape
      // the rules accept lives in exactly one place.
      await startRoomVoice(room.id);
    }

    return joinRoom(room.id);
  }

  Future<void> leaveClubLounge(String clubId) async {
    final roomId = clubLoungeReference(clubId).id;
    await leaveRoom(roomId);
  }

  /// Toggles the caller's [emoji] reaction on a room message. The rules
  /// only permit touching the reactions map, never the message body.
  Future<void> toggleRoomMessageReaction({
    required String roomId,
    required String messageId,
    required String emoji,
  }) async {
    final uid = _user.uid;
    final reference = _rooms.doc(roomId).collection('messages').doc(messageId);
    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(reference);
      if (!snapshot.exists) return;
      final raw = snapshot.data()?['reactions'];
      final current = <String, List<String>>{
        if (raw is Map)
          for (final entry in raw.entries)
            '${entry.key}': [
              if (entry.value is List)
                for (final id in entry.value as List) '$id',
            ],
      };
      final users = current[emoji] ?? <String>[];
      users.contains(uid) ? users.remove(uid) : users.add(uid);
      users.isEmpty ? current.remove(emoji) : current[emoji] = users;
      tx.update(reference, {'reactions': current});
    });
  }

  /// Host moderation: removes a message from the room chat.
  Future<void> deleteRoomMessage({
    required String roomId,
    required String messageId,
  }) async {
    await _requireHost(roomId);
    await _rooms.doc(roomId).collection('messages').doc(messageId).delete();
  }

  Future<void> sendRoomMessage({
    required String roomId,
    required String text,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    if (normalized.length > 500) {
      throw ArgumentError('A room message can contain up to 500 characters.');
    }
    final payload = <String, Object?>{
      'requestId': _requestIdFactory(),
      'roomId': roomId,
      'text': normalized,
    };
    if (_roomMessageSendInvoker != null) {
      await _roomMessageSendInvoker(payload);
      return;
    }
    await _functions.httpsCallable('sendRoomMessage').call(payload);
  }

  /// Writes the caller's own roster mute flag.
  ///
  /// Bounded on purpose. Unmute is server-first (ADR-149): the microphone is
  /// not enabled until this write resolves, so the plugin's 60 s default left
  /// a stalled or cold instance holding the control for a full minute with no
  /// way out. At [setMutedDefaultTimeout] the callable raises
  /// `deadline-exceeded`, which `RoomMuteCoordinator` already maps to
  /// [RoomMuteOutcome.failed] — an honest, retryable failure. The signature is
  /// unchanged so every existing caller and test double still matches.
  Future<void> setMuted({required String roomId, required bool isMuted}) async {
    final callable = _functions.httpsCallable(
      'setOwnRoomParticipantMute',
      options: HttpsCallableOptions(timeout: setMutedDefaultTimeout),
    );
    await callable.call<Map<Object?, Object?>>({
      'roomId': roomId,
      'isMuted': isMuted,
    });
  }

  Future<void> setHandRaised({
    required String roomId,
    required bool isRaised,
  }) async {
    await _rooms.doc(roomId).collection('participants').doc(_user.uid).update({
      'isHandRaised': isRaised,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Host declining a raise-hand request: lowers the participant's hand
  /// without promoting them. Accepting is setParticipantSpeakerStatus
  /// (which clears the hand as part of the promotion).
  Future<void> moderateHandLowered({
    required String roomId,
    required String participantId,
  }) async {
    await _moderateParticipant(
      roomId: roomId,
      participantId: participantId,
      lowerHand: true,
    );
  }

  Future<void> moderateParticipantMute({
    required String roomId,
    required String participantId,
    required bool isMuted,
  }) async {
    await _moderateParticipant(
      roomId: roomId,
      participantId: participantId,
      isMuted: isMuted,
    );
  }

  Future<void> setParticipantSpeakerStatus({
    required String roomId,
    required String participantId,
    required bool isSpeaker,
  }) async {
    await _moderateParticipant(
      roomId: roomId,
      participantId: participantId,
      isSpeaker: isSpeaker,
    );
  }

  Future<void> removeParticipant({
    required String roomId,
    required String participantId,
  }) async {
    final callable = _functions.httpsCallable('removeRoomParticipantSelf');
    await callable.call<Map<Object?, Object?>>({
      'roomId': roomId,
      'participantId': participantId,
    });
  }

  Future<void> leaveRoom(String roomId) async {
    final user = _user;
    final room = _rooms.doc(roomId);
    final currentRoom = await room.get();
    final currentData = currentRoom.data();
    // THE LITERAL FIELD, not RoomType.fromValue.
    //
    // `fromValue` answers `temporary` for ANYTHING that is not the string
    // 'community' — including a room with no `roomType` field at all, which
    // is 24 of the 45 rooms in production. Routed through this branch, a host
    // merely backing out of such a room would end the voice session for
    // everyone still talking in it, because this call is unconditional: it
    // does not pass `onlyIfEmpty`, and it never reaches `leaveRoomSelf` at
    // all, so the caller's own participant row is left behind.
    //
    // A room that genuinely opted into `roomType: 'temporary'` still ends
    // when its host leaves — that is what temporary MEANS and the behaviour
    // is unchanged. A room that never declared one falls through to the
    // ordinary path instead, where `leaveRoomSelf` removes the row and the
    // server ends the session only once the ROSTER proves it is empty.
    if (currentData != null &&
        currentData['hostId'] == user.uid &&
        currentData['roomType'] == RoomType.temporary.name) {
      await endCommunityVoice(roomId);
      return;
    }
    // Cheap pre-check only. It decides whether closing the session is even
    // this caller's business; it does NOT decide that the room is empty.
    final mayCloseAfterLeaving =
        currentData != null && await shouldEndVoiceOnLeaving(roomId);

    // LEAVE FIRST, ALWAYS. `executeEndRoomVoice` re-checks nothing before it
    // sets `participantCount: 0`, ends the LiveKit room and recursive-deletes
    // every participant document, so calling it while still holding a
    // participant row — on a count that was only ever a denormalized hint —
    // evicts anyone who joined between the read and the call. Removing
    // ourselves through the ordinary path first means the count we then read
    // already reflects our own departure.
    final callable = _functions.httpsCallable('leaveRoomSelf');
    await callable.call<Map<Object?, Object?>>({'roomId': roomId});

    if (!mayCloseAfterLeaving) return;

    // A SELF-DISABLING FALLBACK, not a second writer.
    //
    // `executeLeaveRoom` now ends the voice session for the last person out
    // of any room, and it proves the room is empty by reading the ROSTER
    // inside its own transaction — strictly better evidence than the
    // denormalised counter this client can see. When that server build is
    // live, the call above has already dropped `isLive`, so the re-read below
    // finds `isLive != true` and this whole branch does nothing.
    //
    // It stays for the deploy window: the app and Cloud Functions ship
    // separately, and until the new `leaveRoomSelf` is deployed a host
    // leaving their own persistent room is the only thing that can close it.
    // Deploy Functions BEFORE the app and this is dead code on arrival.
    //
    // The re-read is what keeps it safe either way: it happens AFTER our own
    // removal committed and demands a genuine zero, so it cannot evict
    // someone who joined while we were leaving.
    if (!await canCloseEmptyRoom(roomId)) return;
    try {
      // `onlyIfEmpty` makes the SERVER re-prove emptiness from the roster.
      // Our own `canCloseEmptyRoom` check reads `participantCount`, which is
      // denormalised; if it is stale-low while someone is genuinely still in
      // the room, this flag is what stops a housekeeping close from becoming
      // an eviction.
      await endCommunityVoice(roomId, onlyIfEmpty: true);
    } catch (error) {
      // We have already left. A refused close is a housekeeping miss, never
      // a failed leave, and must not surface as one.
      debugPrint(
        'Empty-room voice close skipped for $roomId: $error. '
        'The leave itself already committed.',
      );
    }
  }

  /// True only when the caller hosts a live, non-lounge, persistent room and
  /// is the last participant still in it — the cheap gate asked BEFORE
  /// leaving.
  ///
  /// Club lounges are excluded deliberately: `leaveRoomSelf` already performs
  /// their teardown atomically with the participant delete, and duplicating
  /// it here would race the server for the same transition.
  Future<bool> shouldEndVoiceOnLeaving(String roomId) =>
      _closableByHost(roomId, maxRemaining: 1);

  /// True only when the same room is now genuinely EMPTY — asked after the
  /// caller's own participant row is gone, immediately before the host-only
  /// `endRoomVoiceSelf` callable.
  Future<bool> canCloseEmptyRoom(String roomId) =>
      _closableByHost(roomId, maxRemaining: 0);

  /// The participant count is read from the SERVER: the decision closes the
  /// session for everyone, and a cache-served snapshot taken while someone
  /// was joining would close a room that is not actually empty. A failed read
  /// answers false — a leave must never become an eviction because a count
  /// could not be confirmed.
  Future<bool> _closableByHost(
    String roomId, {
    required int maxRemaining,
  }) async {
    try {
      final snapshot = await _rooms
          .doc(roomId)
          .get(const GetOptions(source: Source.server));
      final data = snapshot.data();
      if (data == null) return false;
      if (data['hostId'] != _user.uid) return false;
      if (data['isLive'] != true) return false;
      if (data['deletionInProgress'] == true) return false;
      if (RoomStatus.fromValue(data['status']) != RoomStatus.active) {
        return false;
      }
      if (RoomType.fromValue(data['roomType']) != RoomType.community) {
        return false;
      }
      final clubId = data['clubId'];
      if (data['roomKind'] == 'clubLounge' ||
          (clubId is String && clubId.isNotEmpty) ||
          roomId.startsWith('club_lounge_')) {
        return false;
      }
      return ((data['participantCount'] as num?)?.toInt() ?? 0) <= maxRemaining;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteRoom(String roomId) async {
    final callable = _functions.httpsCallable('deleteRoomSelf');
    await callable.call<Map<Object?, Object?>>({'roomId': roomId});
  }

  Future<void> _moderateParticipant({
    required String roomId,
    required String participantId,
    bool? isMuted,
    bool? isSpeaker,
    bool lowerHand = false,
  }) async {
    final callable = _functions.httpsCallable('moderateRoomParticipantSelf');
    await callable.call<Map<Object?, Object?>>({
      'roomId': roomId,
      'participantId': participantId,
      'isMuted': ?isMuted,
      'isSpeaker': ?isSpeaker,
      if (lowerHand) 'lowerHand': true,
    });
  }

  Future<bool> _isMember(String roomId, String userId) async {
    return (await _rooms
            .doc(roomId)
            .collection('roomMembers')
            .doc(userId)
            .get())
        .exists;
  }

  /// Mirrors `accountIsActive()` in firestore.rules: the profile document
  /// must exist and carry neither `banned` nor `disabled`. A read failure
  /// answers FALSE — an account whose status cannot be confirmed is not
  /// offered authority it may not have.
  Future<bool> _isActiveAccount(String userId) async {
    try {
      // Shares [_readPrivateProfile]'s memo with [_identity]: the dormant-room
      // path asks this question and then joins, and both need the same
      // document. One read, not two.
      final data = await _readPrivateProfile(userId);
      if (data == null) return false;
      return data['banned'] != true && data['disabled'] != true;
    } catch (_) {
      return false;
    }
  }

  /// Mirrors `isActiveClubRoomMember()` in firestore.rules: the membership
  /// row must exist, be canonical, be unbanned, and belong to a Club that is
  /// itself active and not being deleted. A banned lounge member keeps the
  /// row; what they lose is the ability to use it.
  Future<bool> _isActiveClubMember(String clubId, String userId) async {
    final club = _firestore.collection('clubs').doc(clubId);
    final results = await Future.wait([
      club.get(),
      club.collection('members').doc(userId).get(),
    ]);
    final clubData = results[0].data();
    final memberData = results[1].data();
    if (clubData == null || memberData == null) return false;
    if (clubData['status'] != 'active') return false;
    if (clubData['deletionInProgress'] == true) return false;
    if (memberData['userId'] != userId) return false;
    return memberData['banned'] != true;
  }

  Future<Map<String, dynamic>> _requireHost(String roomId) async {
    final room = await _rooms.doc(roomId).get();
    final data = room.data();
    if (!room.exists || data?['hostId'] != _user.uid) {
      throw StateError('Only the room owner can do this.');
    }
    return data!;
  }
}

class _CachedRoomCoverAccess {
  const _CachedRoomCoverAccess({required this.uri, required this.expiresAt});

  final Uri uri;
  final DateTime expiresAt;
}

class _PendingRoomVoiceStart {
  const _PendingRoomVoiceStart({
    required this.requestId,
    required this.sessionId,
  });

  final String requestId;
  final String sessionId;
}

/// One remembered read of the caller's own private profile.
///
/// [epoch] is the cover-access cache epoch the read was taken under, which is
/// the process-wide "the signed-in account changed" signal
/// ([RoomService.clearAllCoverAccessCaches]); a memo taken before a boundary
/// is never reused after it.
class _PrivateProfileRead {
  const _PrivateProfileRead({
    required this.uid,
    required this.data,
    required this.readAt,
    required this.epoch,
  });

  final String uid;
  final Map<String, dynamic>? data;
  final DateTime readAt;
  final int epoch;
}
