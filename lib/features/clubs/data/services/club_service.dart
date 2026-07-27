import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/models/club_channel.dart';
import 'package:yovoice/features/clubs/data/models/club_member.dart';

class ClubService {
  ClubService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

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
    String? avatarUrl,
    String? bannerUrl,
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
      'avatarUrl': _normalizeNullable(avatarUrl),
      'bannerUrl': _normalizeNullable(bannerUrl),
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
      'avatarUrl': _normalizeNullable(avatarUrl),
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
      'imageUrl': _normalizeNullable(avatarUrl),
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
    if (actor.role.power <= target.role.power) {
      throw StateError(
        'You cannot manage a member with an equal or higher role.',
      );
    }
    if (role == ClubRole.owner) {
      throw StateError('Club ownership transfer is not available yet.');
    }
    if (actor.role != ClubRole.owner && role.power >= actor.role.power) {
      throw StateError('You cannot assign a role equal to or above your own.');
    }

    await memberRef.update({
      'role': role.name,
      'roleUpdatedAt': FieldValue.serverTimestamp(),
      'roleUpdatedBy': _user.uid,
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
      if (actor.role.power <= target.role.power) {
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

  static String? _normalizeNullable(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
