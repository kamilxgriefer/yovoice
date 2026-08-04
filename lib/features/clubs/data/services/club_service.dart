import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/models/club_channel.dart';
import 'package:yovoice/features/clubs/data/models/club_invite.dart';
import 'package:yovoice/features/clubs/data/models/club_member.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

class ClubService {
  ClubService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
    NotificationService? notificationService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _notifications = notificationService ?? NotificationService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;
  final NotificationService _notifications;

  CollectionReference<Map<String, dynamic>> get _clubs =>
      _firestore.collection('clubs');

  User get _user {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to use clubs.');
    }
    return user;
  }

  Future<Club> createClub({
    required String name,
    required String description,
    required ClubPrivacy privacy,
    required String defaultLanguage,
    XFile? avatarFile,
    XFile? bannerFile,
  }) async {
    final user = _user;
    final normalizedName = name.trim();
    final normalizedDescription = description.trim();
    final normalizedLanguage = defaultLanguage.trim().isEmpty
        ? 'English'
        : defaultLanguage.trim();

    if (normalizedName.length < 3) {
      throw ArgumentError('Club name must contain at least 3 characters.');
    }
    if (normalizedName.length > 40) {
      throw ArgumentError('Club name cannot exceed 40 characters.');
    }
    if (normalizedDescription.length > 220) {
      throw ArgumentError('Club description cannot exceed 220 characters.');
    }

    final clubRef = _clubs.doc();
    String? avatarUrl;
    String? bannerUrl;
    final uploadedReferences = <Reference>[];

    try {
      if (avatarFile != null) {
        final result = await _uploadClubImage(
          clubId: clubRef.id,
          file: avatarFile,
          kind: 'avatar',
        );
        avatarUrl = result.url;
        uploadedReferences.add(result.reference);
      }
      if (bannerFile != null) {
        final result = await _uploadClubImage(
          clubId: clubRef.id,
          file: bannerFile,
          kind: 'banner',
        );
        bannerUrl = result.url;
        uploadedReferences.add(result.reference);
      }

      final generalRef = clubRef.collection('channels').doc();
      final announcementsRef = clubRef.collection('channels').doc();
      final loungeRef = clubRef.collection('channels').doc();
      final loungeRoomRef = _firestore
          .collection('rooms')
          .doc('club_lounge_${clubRef.id}');
      final memberRef = clubRef.collection('members').doc(user.uid);
      final userClubRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('clubs')
          .doc(clubRef.id);
      final userRef = _firestore.collection('users').doc(user.uid);
      final ownerName = _resolveUserName(user);

      final batch = _firestore.batch();
      batch.set(clubRef, {
        'name': normalizedName,
        'description': normalizedDescription,
        'ownerId': user.uid,
        'ownerName': ownerName,
        'avatarUrl': avatarUrl,
        'bannerUrl': bannerUrl,
        'privacy': privacy.name,
        'defaultLanguage': normalizedLanguage,
        'memberCount': 1,
        'onlineCount': 1,
        'defaultChatChannelId': generalRef.id,
        'defaultVoiceChannelId': loungeRef.id,
        'loungeRoomId': loungeRoomRef.id,
        'announcementChannelId': announcementsRef.id,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(memberRef, {
        'userId': user.uid,
        'displayName': ownerName,
        'photoUrl': user.photoURL,
        'role': ClubRole.owner.name,
        'isOnline': true,
        'joinedAt': FieldValue.serverTimestamp(),
        'invitedBy': null,
      });
      batch.set(userClubRef, {
        'clubId': clubRef.id,
        'name': normalizedName,
        'avatarUrl': avatarUrl,
        'role': ClubRole.owner.name,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      batch.set(generalRef, {
        'name': 'general',
        'type': ClubChannelType.chat.name,
        'position': 0,
        'isPrivate': false,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(announcementsRef, {
        'name': 'announcements',
        'type': ClubChannelType.announcement.name,
        'position': 1,
        'isPrivate': false,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(loungeRef, {
        'name': 'Club Lounge',
        'type': ClubChannelType.voice.name,
        'position': 2,
        'isPrivate': false,
        'createdBy': user.uid,
        'roomId': loungeRoomRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(loungeRoomRef, {
        'hostId': user.uid,
        'hostName': ownerName,
        'hostPhotoUrl': user.photoURL,
        'name': '$normalizedName Lounge',
        'description': normalizedDescription.isEmpty
            ? 'Private voice lounge for $normalizedName members.'
            : normalizedDescription,
        'category': 'club',
        'visibility': 'private',
        'language': normalizedLanguage,
        'maxParticipants': null,
        'participantCount': 0,
        'memberCount': 1,
        'isLive': false,
        'roomType': 'community',
        'status': 'active',
        'imageUrl': avatarUrl,
        'approvalRequired': false,
        'slowModeSeconds': 0,
        'autoMuteNewUsers': false,
        'membersCanStartVoice': true,
        'experience': 'community',
        'clubId': clubRef.id,
        'roomKind': 'clubLounge',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(userRef, {
        'clubCount': FieldValue.increment(1),
      }, SetOptions(merge: true));

      await batch.commit();
      final snapshot = await clubRef.get();
      return Club.fromFirestore(snapshot);
    } catch (_) {
      for (final reference in uploadedReferences) {
        try {
          await reference.delete();
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
      rethrow;
    }
  }

  Future<_UploadedClubImage> _uploadClubImage({
    required String clubId,
    required XFile file,
    required String kind,
  }) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw StateError('The selected image is empty.');
    if (bytes.length > 8 * 1024 * 1024) {
      throw StateError('The selected image must be smaller than 8 MB.');
    }

    final extension = _fileExtension(file.name);
    final reference = _storage.ref().child(
      'clubs/${_user.uid}/$clubId/${kind}_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    final metadata = SettableMetadata(
      contentType: file.mimeType ?? _contentTypeForExtension(extension),
      cacheControl: 'public,max-age=31536000',
    );
    await reference.putData(bytes, metadata);
    return _UploadedClubImage(
      reference: reference,
      url: await reference.getDownloadURL(),
    );
  }

  static String _fileExtension(String name) {
    final normalized = name.toLowerCase();
    final dot = normalized.lastIndexOf('.');
    if (dot == -1 || dot == normalized.length - 1) return 'jpg';
    final value = normalized.substring(dot + 1);
    return value == 'jpeg' ||
            value == 'jpg' ||
            value == 'png' ||
            value == 'webp'
        ? value
        : 'jpg';
  }

  static String _contentTypeForExtension(String extension) {
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }

  Stream<List<Club>> watchMyClubs() {
    final uid = _user.uid;
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('clubs')
        .orderBy('joinedAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          if (snapshot.docs.isEmpty) return const <Club>[];
          final clubs = await Future.wait(
            snapshot.docs.map((item) async {
              final clubId = item.data()['clubId'] as String? ?? item.id;
              final club = await _clubs.doc(clubId).get();
              return club.exists ? Club.fromFirestore(club) : null;
            }),
          );
          return clubs.whereType<Club>().toList(growable: false);
        });
  }

  Stream<Club> watchClub(String clubId) {
    return _clubs.doc(clubId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        throw StateError('The club no longer exists.');
      }
      return Club.fromFirestore(snapshot);
    });
  }

  Stream<List<ClubMember>> watchMembers(String clubId) {
    return _clubs.doc(clubId).collection('members').snapshots().map((snapshot) {
      final members = snapshot.docs.map(ClubMember.fromFirestore).toList();
      members.sort((a, b) {
        final roleComparison = b.role.power.compareTo(a.role.power);
        if (roleComparison != 0) return roleComparison;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
      return members;
    });
  }

  Stream<List<ClubChannel>> watchChannels(String clubId) {
    return _clubs
        .doc(clubId)
        .collection('channels')
        .orderBy('position')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (document) => ClubChannel.fromFirestore(
                  clubId: clubId,
                  document: document,
                ),
              )
              .toList(growable: false),
        );
  }

  Future<ClubMember?> getMyMembership(String clubId) async {
    final snapshot = await _clubs
        .doc(clubId)
        .collection('members')
        .doc(_user.uid)
        .get();
    return snapshot.exists ? ClubMember.fromFirestore(snapshot) : null;
  }

  Stream<ClubMember?> watchMyMembership(String clubId) {
    return _clubs
        .doc(clubId)
        .collection('members')
        .doc(_user.uid)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.exists ? ClubMember.fromFirestore(snapshot) : null,
        );
  }

  Future<void> updateMemberRole({
    required String clubId,
    required String memberId,
    required ClubRole role,
  }) async {
    final actor = await getMyMembership(clubId);
    if (actor == null) {
      throw StateError('You are not a member of this club.');
    }
    if (!actor.role.canManageRoles) {
      throw StateError('Your role cannot manage club roles.');
    }
    if (memberId == _user.uid) {
      throw StateError('You cannot change your own role.');
    }

    final memberRef = _clubs.doc(clubId).collection('members').doc(memberId);
    final targetSnapshot = await memberRef.get();
    if (!targetSnapshot.exists) {
      throw StateError('This member no longer exists.');
    }
    final target = ClubMember.fromFirestore(targetSnapshot);

    if (target.role == ClubRole.owner) {
      throw StateError('The owner role cannot be changed.');
    }
    if (!actor.role.canManageMemberRole(target.role)) {
      throw StateError(
        'You cannot manage a member with an equal or higher role.',
      );
    }
    if (role == ClubRole.owner) {
      throw StateError('Use transferOwnership() to hand off club ownership.');
    }
    if (!actor.role.canAssignRole(role)) {
      throw StateError('You cannot assign this role.');
    }

    await memberRef.update({
      'role': role.name,
      'roleUpdatedAt': FieldValue.serverTimestamp(),
      'roleUpdatedBy': _user.uid,
    });
  }

  /// Hands the club to another existing member, demoting the current owner
  /// to co-owner. firestore.rules deliberately blocks role:'owner'
  /// transitions from the normal updateMemberRole() write path, so this
  /// goes through the transferClubOwnershipSelf Cloud Function instead
  /// (Admin SDK, authorized by checking the caller IS the club's current
  /// owner — see functions/clubs/ownership.js).
  Future<void> transferOwnership({
    required String clubId,
    required String newOwnerId,
  }) async {
    if (newOwnerId == _user.uid) {
      throw StateError('You are already the owner of this club.');
    }
    final callable = _functions.httpsCallable('transferClubOwnershipSelf');
    await callable.call<Map<Object?, Object?>>({
      'clubId': clubId,
      'newOwnerId': newOwnerId,
    });
  }

  Future<void> removeMember({
    required String clubId,
    required String memberId,
  }) async {
    final actor = await getMyMembership(clubId);
    if (actor == null) {
      throw StateError('You are not a member of this club.');
    }
    if (!actor.role.canRemoveMembers) {
      throw StateError('Your role cannot remove club members.');
    }
    if (memberId == _user.uid) {
      throw StateError('Use Leave Club to remove your own membership.');
    }

    final clubRef = _clubs.doc(clubId);
    final memberRef = clubRef.collection('members').doc(memberId);
    final userClubRef = _firestore
        .collection('users')
        .doc(memberId)
        .collection('clubs')
        .doc(clubId);

    await _firestore.runTransaction((transaction) async {
      final clubSnapshot = await transaction.get(clubRef);
      final targetSnapshot = await transaction.get(memberRef);
      if (!clubSnapshot.exists || !targetSnapshot.exists) return;

      final target = ClubMember.fromFirestore(targetSnapshot);
      if (target.role == ClubRole.owner) {
        throw StateError('The club owner cannot be removed.');
      }
      if (!actor.role.canRemoveRole(target.role)) {
        throw StateError(
          'You cannot remove a member with an equal or higher role.',
        );
      }

      final data = clubSnapshot.data()!;
      final memberCount = (data['memberCount'] as num?)?.toInt() ?? 0;
      final onlineCount = (data['onlineCount'] as num?)?.toInt() ?? 0;
      transaction.delete(memberRef);
      transaction.delete(userClubRef);
      transaction.update(clubRef, {
        'memberCount': memberCount > 0 ? memberCount - 1 : 0,
        if (target.isOnline)
          'onlineCount': onlineCount > 0 ? onlineCount - 1 : 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<List<ClubInvite>> watchMyClubInvites() {
    return _firestore
        .collectionGroup('invites')
        .where('inviteeId', isEqualTo: _user.uid)
        .snapshots()
        .map((snapshot) {
          final invites = snapshot.docs
              .map(ClubInvite.fromFirestore)
              .toList(growable: false);
          invites.sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
          return invites;
        });
  }

  Stream<Set<String>> watchInvitedUserIds(String clubId) {
    return _clubs
        .doc(clubId)
        .collection('invites')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((document) => document.id).toSet(),
        );
  }

  Future<void> sendClubInvite({
    required String clubId,
    required String friendId,
  }) async {
    final actor = await getMyMembership(clubId);
    if (actor == null || !actor.role.canInvite) {
      throw StateError('Your role cannot invite club members.');
    }
    if (friendId == _user.uid) {
      throw StateError('You are already in this club.');
    }

    final clubRef = _clubs.doc(clubId);
    final memberRef = clubRef.collection('members').doc(friendId);
    final inviteRef = clubRef.collection('invites').doc(friendId);
    final inviterSnapshot = await _firestore
        .collection('users')
        .doc(_user.uid)
        .get();
    final inviterName = (inviterSnapshot.data()?['displayName'] as String?)
        ?.trim();

    String? clubName;
    await _firestore.runTransaction((transaction) async {
      final clubSnapshot = await transaction.get(clubRef);
      final memberSnapshot = await transaction.get(memberRef);
      final inviteSnapshot = await transaction.get(inviteRef);

      if (!clubSnapshot.exists) {
        throw StateError('The club no longer exists.');
      }
      if (memberSnapshot.exists) {
        throw StateError('This person is already a club member.');
      }
      if (inviteSnapshot.exists) {
        throw StateError('An invitation has already been sent.');
      }

      final club = Club.fromFirestore(clubSnapshot);
      clubName = club.name;
      transaction.set(inviteRef, {
        'clubId': clubId,
        'clubName': club.name,
        'clubAvatarUrl': club.avatarUrl,
        'inviteeId': friendId,
        'inviterId': _user.uid,
        'inviterName': inviterName?.isNotEmpty == true
            ? inviterName
            : _resolveUserName(_user),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    try {
      await _notifications.notify(
        recipientId: friendId,
        type: NotificationType.clubInvite,
        targetId: clubId,
        targetLabel: clubName,
        dedupeKey: 'clubInvite:$clubId:${_user.uid}',
      );
    } catch (_) {
      // Best-effort — the invite doc itself already succeeded above.
    }
  }

  Future<void> cancelClubInvite({
    required String clubId,
    required String inviteeId,
  }) async {
    final actor = await getMyMembership(clubId);
    if (actor == null || !actor.role.canInvite) {
      throw StateError('Your role cannot manage club invitations.');
    }
    await _clubs.doc(clubId).collection('invites').doc(inviteeId).delete();
  }

  Future<void> acceptClubInvite(ClubInvite invite) async {
    if (invite.inviteeId != _user.uid) {
      throw StateError('This invitation does not belong to you.');
    }

    final clubRef = _clubs.doc(invite.clubId);
    final inviteRef = clubRef.collection('invites').doc(_user.uid);
    final memberRef = clubRef.collection('members').doc(_user.uid);
    final userClubRef = _firestore
        .collection('users')
        .doc(_user.uid)
        .collection('clubs')
        .doc(invite.clubId);
    final userSnapshot = await _firestore
        .collection('users')
        .doc(_user.uid)
        .get();
    final userData = userSnapshot.data() ?? const <String, dynamic>{};
    final displayName = (userData['displayName'] as String?)?.trim();
    final photoUrl = userData['photoUrl'] as String? ?? _user.photoURL;

    await _firestore.runTransaction((transaction) async {
      final clubSnapshot = await transaction.get(clubRef);
      final invitationSnapshot = await transaction.get(inviteRef);
      final memberSnapshot = await transaction.get(memberRef);

      if (!clubSnapshot.exists) {
        throw StateError('The club no longer exists.');
      }
      if (!invitationSnapshot.exists) {
        throw StateError('This invitation is no longer available.');
      }
      if (memberSnapshot.exists) {
        transaction.delete(inviteRef);
        return;
      }

      final club = Club.fromFirestore(clubSnapshot);
      transaction.set(memberRef, {
        'userId': _user.uid,
        'displayName': displayName?.isNotEmpty == true
            ? displayName
            : _resolveUserName(_user),
        'photoUrl': photoUrl,
        'role': ClubRole.member.name,
        'isOnline': true,
        'joinedAt': FieldValue.serverTimestamp(),
        'invitedBy': invite.inviterId,
      });
      transaction.set(userClubRef, {
        'clubId': invite.clubId,
        'name': club.name,
        'avatarUrl': club.avatarUrl,
        'role': ClubRole.member.name,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(clubRef, {
        'memberCount': FieldValue.increment(1),
        'onlineCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.delete(inviteRef);
    });

    try {
      await _notifications.notify(
        recipientId: invite.inviterId,
        type: NotificationType.clubInviteAccepted,
        targetId: invite.clubId,
        targetLabel: invite.clubName,
      );
    } catch (_) {
      // Best-effort — membership itself already succeeded above.
    }
  }

  Future<void> declineClubInvite(ClubInvite invite) async {
    if (invite.inviteeId != _user.uid) {
      throw StateError('This invitation does not belong to you.');
    }
    await _clubs
        .doc(invite.clubId)
        .collection('invites')
        .doc(_user.uid)
        .delete();
  }

  Future<void> updateClubDetails({
    required String clubId,
    required String name,
    required String description,
    required String defaultLanguage,
    required ClubPrivacy privacy,
  }) async {
    final actor = await getMyMembership(clubId);
    if (actor == null || !actor.role.canEditClub) {
      throw StateError('Your role cannot edit this club.');
    }

    final normalizedName = name.trim();
    final normalizedDescription = description.trim();
    final normalizedLanguage = defaultLanguage.trim().isEmpty
        ? 'English'
        : defaultLanguage.trim();

    if (normalizedName.length < 3 || normalizedName.length > 40) {
      throw StateError('Club name must contain 3 to 40 characters.');
    }
    if (normalizedDescription.length > 220) {
      throw StateError('Club description cannot exceed 220 characters.');
    }

    await _clubs.doc(clubId).update({
      'name': normalizedName,
      'description': normalizedDescription,
      'defaultLanguage': normalizedLanguage,
      'privacy': privacy.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  String createInviteLink(String clubId) => 'https://yovoice.app/?club=$clubId';

  Future<bool> isMember(String clubId) async {
    final snapshot = await _clubs
        .doc(clubId)
        .collection('members')
        .doc(_user.uid)
        .get();
    return snapshot.exists;
  }

  static String _resolveUserName(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'YoVoice user';
  }
}

class _UploadedClubImage {
  const _UploadedClubImage({required this.reference, required this.url});
  final Reference reference;
  final String url;
}
