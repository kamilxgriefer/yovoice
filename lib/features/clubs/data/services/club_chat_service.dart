import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/clubs/data/models/club_chat_authority.dart';
import 'package:yovoice/features/clubs/data/models/club_member.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';

class ClubChatService {
  ClubChatService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

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
  /// Club chat has no denormalised "last message" on the club document —
  /// previews have to come from the messages themselves. [watchMessages]
  /// would pull 250 documents per club to render one preview line, so
  /// conversation-list surfaces (the desktop Conversations hub) use this
  /// instead: the same collection and the same ordering, limited to one.
  Stream<ClubMessage?> watchLatestMessage({
    required String clubId,
    required String channelId,
  }) {
    return _messages(clubId: clubId, channelId: channelId)
        .orderBy('sentAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
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
    final user = _user;
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    if (normalized.length > 2000) {
      throw ArgumentError('A club message cannot exceed 2000 characters.');
    }

    final member = await _firestore
        .collection('clubs')
        .doc(clubId)
        .collection('members')
        .doc(user.uid)
        .get();
    if (!member.exists) throw StateError('You are not a member of this club.');

    final memberData = member.data() ?? const <String, dynamic>{};
    final role = ClubRole.fromValue(memberData['role']);
    if (!role.canWriteChat) {
      throw StateError('Guests cannot send messages in club chat.');
    }
    final displayName = (memberData['displayName'] as String?)?.trim();
    final photoUrl = memberData['photoUrl'] as String?;
    final messageRef = _messages(clubId: clubId, channelId: channelId).doc();
    final now = Timestamp.now();

    await messageRef.set({
      'clubId': clubId,
      'channelId': channelId,
      'senderId': user.uid,
      'senderName': displayName?.isNotEmpty == true
          ? displayName
          : _resolveUserName(user),
      'senderPhotoUrl': photoUrl?.trim().isNotEmpty == true
          ? photoUrl!.trim()
          : user.photoURL,
      'content': normalized,
      'sentAt': now,
      'editedAt': null,
      'isDeleted': false,
    });
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
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? memberSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? clubSub;
    late final StreamController<ClubChatAuthority> controller;

    void emit() {
      // `onCancel` awaits two subscription cancellations, so an event
      // already in flight can land after the screen is gone. Dropping it
      // is correct; adding it would not be.
      if (controller.isClosed || !controller.hasListener) return;
      controller.add(
        ClubChatAuthority(viewerId: uid, role: role, clubOwnerId: ownerId),
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
                emit();
              },
              onError: (_) {
                role = null;
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
      },
      onCancel: () async {
        await memberSub?.cancel();
        await clubSub?.cancel();
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
    );
    final refusal = authority.removalRefusal(live);
    if (refusal != null) throw StateError(refusal);

    await messageRef.update({
      'content': '',
      'isDeleted': true,
      'editedAt': FieldValue.serverTimestamp(),
      'deletedBy': user.uid,
      'deletedAt': FieldValue.serverTimestamp(),
    });
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

  static String _resolveUserName(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'YO Voice user';
  }
}
