import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:yovoice/features/rooms/data/models/room_message.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/data/models/room_metadata.dart';
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
      'autoMuteNewUsers': true,
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
      if (existing.exists) return;

      final count = (data['participantCount'] as num?)?.toInt() ?? 0;
      final max = (data['maxParticipants'] as num?)?.toInt();
      if (max != null && count >= max) throw StateError('This room is full.');

      transaction.set(participant, {
        'userId': user.uid,
        'displayName': identity.displayName,
        'photoUrl': identity.photoUrl,
        'role': data['hostId'] == user.uid ? 'host' : 'listener',
        'isMuted': data['hostId'] == user.uid
            ? false
            : (data['autoMuteNewUsers'] as bool? ?? true),
        'isSpeaker': data['hostId'] == user.uid,
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

  Future<void> startCommunityVoice(String roomId) async {
    final room = await _rooms.doc(roomId).get();
    final data = room.data();
    if (!room.exists || data == null) throw StateError('Room not found.');
    final canStart =
        data['hostId'] == _user.uid ||
        (data['membersCanStartVoice'] == true &&
            await _isMember(roomId, _user.uid));
    if (!canStart) throw StateError('You cannot start voice in this room.');
    if (RoomStatus.fromValue(data['status']) != RoomStatus.active) {
      throw StateError('Open the room before starting voice.');
    }
    await _rooms.doc(roomId).update({
      'isLive': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'endedAt': FieldValue.delete(),
    });
    await joinRoom(roomId);
  }

  Future<void> endCommunityVoice(String roomId) async {
    final callable = _functions.httpsCallable('endRoomVoiceSelf');
    await callable.call<Map<Object?, Object?>>({'roomId': roomId});
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

    if (!room.isLive) {
      await clubLoungeReference(clubId).update({
        'isLive': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'endedAt': FieldValue.delete(),
      });
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
    if (currentData != null &&
        currentData['hostId'] == user.uid &&
        RoomType.fromValue(currentData['roomType']) == RoomType.temporary) {
      await endCommunityVoice(roomId);
      return;
    }
    final callable = _functions.httpsCallable('leaveRoomSelf');
    await callable.call<Map<Object?, Object?>>({'roomId': roomId});
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

  Future<void> _requireHost(String roomId) async {
    final room = await _rooms.doc(roomId).get();
    if (!room.exists || room.data()?['hostId'] != _user.uid) {
      throw StateError('Only the room owner can do this.');
    }
  }
}
