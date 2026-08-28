import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:yovoice/features/rooms/data/models/room_message.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/data/models/room_metadata.dart';
import 'package:yovoice/features/rooms/data/models/room_voice_access.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';

class RoomService {
  RoomService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  bool get _shouldIncrementLegacyRoomCount {
    final users = Firebase.apps;
    return users.isEmpty;
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
  /// be stale after a rename. The avatar keeps its legacy fallback because
  /// this security boundary concerns the canonical display name.
  Future<({String displayName, String? photoUrl})> _identity() async {
    final user = _user;
    final snapshot = await _firestore.collection('users').doc(user.uid).get();
    final data = snapshot.data();
    final name = data?['displayName'];
    if (name is! String || name.trim().isEmpty) {
      throw StateError('Your profile does not have a display name.');
    }
    final photo = (data?['photoUrl'] as String?)?.trim();
    return (
      // Preserve exact stored bytes for the byte-for-byte Rules binding.
      displayName: name,
      photoUrl: photo?.isNotEmpty == true ? photo : user.photoURL,
    );
  }

  Future<VoiceRoom> createRoom({
    required String name,
    required String description,
    required String category,
    required String visibility,
    required String language,
    required int? maxParticipants,
    required RoomType roomType,
    String? imageUrl,
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
  }) async {
    final user = _user;
    final normalizedName = name.trim();
    if (normalizedName.length < 3) {
      throw ArgumentError('Room name must contain at least 3 characters.');
    }

    final room = _rooms.doc();
    final identity = await _identity();
    final hostName = identity.displayName;
    final batch = _firestore.batch();
    final isCommunity = roomType == RoomType.community;

    batch.set(room, {
      'hostId': user.uid,
      'hostName': hostName,
      'hostPhotoUrl': identity.photoUrl,
      'name': normalizedName,
      'description': description.trim(),
      'category': category,
      'visibility': visibility,
      'language': language,
      'maxParticipants': maxParticipants,
      'participantCount': isCommunity ? 0 : 1,
      'memberCount': isCommunity ? 1 : 0,
      'isLive': !isCommunity,
      'roomType': roomType.name,
      'status': RoomStatus.active.name,
      'imageUrl': imageUrl,
      // Descriptive metadata. Written type-scoped on purpose: a community
      // room never carries showFormat and a broadcast room never carries
      // conversationStyle, so neither can present itself as the other.
      // firestore.rules refuses the cross-type write independently.
      'targetAudience': targetAudience.value,
      'topicTags': RoomMetadataLimits.normalizeTags(topicTags),
      'roomGuidelines': roomGuidelines.trim().substring(
        0,
        roomGuidelines.trim().length > RoomMetadataLimits.maxGuidelinesLength
            ? RoomMetadataLimits.maxGuidelinesLength
            : roomGuidelines.trim().length,
      ),
      if (conversationStyle != null)
        'conversationStyle': conversationStyle.value,
      if (newcomerFriendly) 'newcomerFriendly': true,
      if (showFormat != null) 'showFormat': showFormat.value,
      // The room type is authorization-relevant while metadata is being
      // validated. Persist it in the SAME atomic create as showFormat or
      // conversationStyle; a later configure update is too late for rules to
      // decide which type-scoped fields the initial document may contain.
      'experience': experience.firestoreValue,
      'topic': topic.trim(),
      'audienceCanSpeak': audienceCanSpeak,
      'handRaisingEnabled': handRaisingEnabled,
      'stageLimit': experience == RoomExperience.broadcast ? 8 : null,
      'approvalRequired': false,
      'slowModeSeconds': 0,
      // Community is a Discord-like open conversation: joining it grants a
      // normal microphone immediately. Broadcast keeps its audience muted
      // until the host promotes somebody.
      'autoMuteNewUsers': experience == RoomExperience.broadcast,
      'membersCanStartVoice': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (isCommunity) {
      batch.set(room.collection('roomMembers').doc(user.uid), {
        'userId': user.uid,
        'displayName': hostName,
        'photoUrl': identity.photoUrl,
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });
    } else {
      batch.set(room.collection('participants').doc(user.uid), {
        'userId': user.uid,
        'displayName': hostName,
        'photoUrl': identity.photoUrl,
        'role': 'host',
        'isMuted': false,
        'isSpeaker': true,
        'isHandRaised': false,
        'joinedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    if (_shouldIncrementLegacyRoomCount && isCommunity) {
      await _firestore.collection('users').doc(user.uid).set({
        'roomCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    }

    return VoiceRoom.fromFirestore(await room.get());
  }

  Stream<List<VoiceRoom>> watchLivePublicRooms() {
    return _rooms
        .where('isLive', isEqualTo: true)
        .where('visibility', isEqualTo: 'public')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(VoiceRoom.fromFirestore)
              .where((room) => room.isActive)
              .toList(growable: false),
        );
  }

  Stream<List<VoiceRoom>> watchPublicRooms() {
    return _rooms.where('visibility', isEqualTo: 'public').snapshots().map((
      snapshot,
    ) {
      final rooms = snapshot.docs
          .map(VoiceRoom.fromFirestore)
          .where((room) => room.isActive)
          .toList();
      rooms.sort(
        (a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(1970)).compareTo(
          a.updatedAt ?? a.createdAt ?? DateTime(1970),
        ),
      );
      return rooms;
    });
  }

  Stream<List<VoiceRoom>> watchOwnedRooms() {
    return _rooms.where('hostId', isEqualTo: _user.uid).snapshots().map((
      snapshot,
    ) {
      final rooms = snapshot.docs.map(VoiceRoom.fromFirestore).toList();
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

          final rooms = documents
              .where((document) => document.exists)
              .map(VoiceRoom.fromFirestore)
              .where(
                (room) => room.roomType == RoomType.community && room.isActive,
              )
              .toList();

          rooms.sort(
            (a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(1970)).compareTo(
              a.updatedAt ?? a.createdAt ?? DateTime(1970),
            ),
          );
          return rooms;
        });
  }

  Stream<VoiceRoom> watchRoom(String roomId) {
    return _rooms.doc(roomId).snapshots().map((document) {
      if (!document.exists) throw StateError('The room no longer exists.');
      return VoiceRoom.fromFirestore(document);
    });
  }

  Future<VoiceRoom> getRoom(String roomId) async {
    final document = await _rooms.doc(roomId).get();
    if (!document.exists) {
      throw StateError('The room no longer exists.');
    }
    return VoiceRoom.fromFirestore(document);
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
    await _requireHost(roomId);
    final normalizedName = name.trim();
    if (normalizedName.length < 3) {
      throw ArgumentError('Room name must contain at least 3 characters.');
    }
    await _rooms.doc(roomId).update({
      'name': normalizedName,
      'description': description.trim(),
      'category': category,
      'visibility': visibility,
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

  Future<void> updateImageUrl({
    required String roomId,
    required String imageUrl,
  }) async {
    await _requireHost(roomId);
    await _rooms.doc(roomId).update({
      'imageUrl': imageUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setRoomStatus(String roomId, RoomStatus status) async {
    final callable = _functions.httpsCallable('setRoomStatusSelf');
    await callable.call<Map<Object?, Object?>>({
      'roomId': roomId,
      'status': status.name,
    });
  }

  Future<VoiceRoom> joinRoom(String roomId) async {
    final user = _user;
    final identity = await _identity();
    final room = _rooms.doc(roomId);
    final participant = room.collection('participants').doc(user.uid);

    await _firestore.runTransaction((transaction) async {
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

      final existing = await transaction.get(participant);
      if (existing.exists) {
        // RE-ENTRY, NOT A FRESH JOIN. The row survives a tab close, a crash
        // and any leave that did not complete, so this is the ordinary path
        // back into a room — not an edge case.
        //
        // The stored self-mute must not outlive the session it belonged to.
        // `VoiceCallService.join()` opens the microphone on connect, so a row
        // still carrying `isMuted: true` from a previous visit would describe
        // a person as muted while they are audibly speaking, and every other
        // participant would render a mute badge on their avatar that nothing
        // could clear.
        //
        // Only the caller's OWN flag is touched. `hostMuted` and `serverMuted`
        // are left exactly as they are — the rules pin both on this update,
        // and the token honours them independently, so a moderator mute
        // survives re-entry the way it must.
        if ((existing.data() ?? const <String, dynamic>{})['isMuted'] == true) {
          transaction.update(participant, {
            'isMuted': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
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
        'isMuted': data['hostId'] == user.uid
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
    });
    return VoiceRoom.fromFirestore(await room.get());
  }

  Future<void> joinCommunity(String roomId) async {
    final user = _user;
    final identity = await _identity();
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

  /// Performs the liveness transition and nothing else.
  ///
  /// The write shape is load-bearing: both `roomVoiceStartAllowed()` and
  /// `hostRoomUpdateAllowed()`'s start branch require
  /// `affectedKeys().hasOnly(['isLive', 'endedAt', 'updatedAt'])` and
  /// `updatedAt == request.time`. Anything else riding along — a counter, a
  /// visibility flip, a denormalized name — turns an authorized start into a
  /// permission-denied.
  ///
  /// Both rules also require `resource.data.isLive == false`, so a room that
  /// is ALREADY live must not be written at all; re-asserting `isLive: true`
  /// is refused by the server. Callers must check first, which
  /// [RoomVoiceEntryCoordinator] does.
  Future<void> startRoomVoice(String roomId) async {
    await _rooms.doc(roomId).update({
      'isLive': true,
      'updatedAt': FieldValue.serverTimestamp(),
      // Clearing the closing marker is part of the same permitted key set.
      // On a room that never ended this is a no-op and contributes no key.
      'endedAt': FieldValue.delete(),
    });
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
    return clubLoungeReference(clubId).snapshots().map((document) {
      if (!document.exists) return null;
      return VoiceRoom.fromFirestore(document);
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
        'hostPhotoUrl': ownerPhotoUrl,
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
    final user = _user;
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    if (normalized.length > 500) {
      throw ArgumentError('A room message can contain up to 500 characters.');
    }
    final identity = await _identity();
    await _rooms.doc(roomId).collection('messages').add({
      'senderId': user.uid,
      'senderName': identity.displayName,
      'senderPhotoUrl': identity.photoUrl,
      'text': normalized,
      'createdAt': FieldValue.serverTimestamp(),
      'reactions': <String, List<String>>{},
    });
    await _touchRoomActivity(roomId);
  }

  /// Advances the room root's `updatedAt`, which is the field
  /// [watchPublicRooms] and [watchMyCommunities] sort the Home feeds on.
  ///
  /// This is a DENORMALIZED ORDERING HINT, not part of sending. By the time
  /// it runs the message has already committed, so its failure must never be
  /// reported as "your message didn't send" — that was the live defect: the
  /// non-host branch of the room-root update rule accepted no bare
  /// `updatedAt`, so every non-host message landed and then raised
  /// permission-denied, which the chat sheet surfaced as a send failure and
  /// which left the composer uncleared, inviting a duplicate send.
  ///
  /// Deliberately NOT batched with the message. Fusing them would make chat
  /// hostage to a recency rule: a refused bump would roll the message back,
  /// turning a cosmetic ordering defect into message loss. Separate writes
  /// mean the worst case is a room that sorts stale.
  ///
  /// firestore.rules now permits this for anyone the message create rule
  /// permits to post, so the swallow below should no longer fire in normal
  /// use. It stays because the conditions that can still refuse it — a room
  /// frozen or torn down between the two writes, a suspension landing
  /// mid-send — are all cases where the message is already sent and the user
  /// has nothing to act on.
  Future<void> _touchRoomActivity(String roomId) async {
    try {
      await _rooms.doc(roomId).update({
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      debugPrint(
        'Room recency bump skipped for $roomId: ${error.code}. '
        'The message itself was already committed.',
      );
    }
  }

  Future<void> setMuted({required String roomId, required bool isMuted}) async {
    final callable = _functions.httpsCallable('setOwnRoomParticipantMute');
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
      final data = (await _firestore.collection('users').doc(userId).get())
          .data();
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

  Future<void> _requireHost(String roomId) async {
    final room = await _rooms.doc(roomId).get();
    if (!room.exists || room.data()?['hostId'] != _user.uid) {
      throw StateError('Only the room owner can do this.');
    }
  }
}
