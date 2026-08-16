import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/models/club_channel.dart';
import 'package:yovoice/features/clubs/data/models/club_invite.dart';
import 'package:yovoice/features/clubs/data/models/club_member.dart';
import 'package:yovoice/features/clubs/data/models/family_check_in.dart';
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
       _functionsOverride = functions;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  /// Resolved on first use, not in the constructor. Community creation and
  /// ownership transfer call Cloud Functions, but
  /// `FirebaseFunctions.instance` throws whenever no Firebase app is
  /// initialised — which made the whole service unconstructible in widget
  /// tests that only ever read clubs (the desktop Conversations hub).
  /// There is no fake for cloud_functions, and lazy resolution keeps
  /// production calls must target the functions' europe-west1 region.
  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  CollectionReference<Map<String, dynamic>> get _clubs =>
      _firestore.collection('clubs');

  User get _user {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to use clubs.');
    }
    return user;
  }

  /// Allocates the idempotency key used by community Club creation. The
  /// create screen keeps this value across submit retries, so a lost callable
  /// response can only recover the same server transaction, never create a
  /// second Club.
  String newClubDocumentId() => _clubs.doc().id;

  /// Creates the caller's Family Room: the same club document, members,
  /// roles, invites, channels and lounge, with `type: family` — which is
  /// what `firestore.rules` keys the private read boundary off.
  ///
  /// The id is deterministic (`family_{uid}`) and that is deliberate: it
  /// is the one-per-account limit, enforced server-side. Creating a
  /// second one has nowhere to go, so this surfaces the existing room
  /// instead of failing with a permission error.
  Future<Club> createFamilyRoom({
    required String name,
    required String description,
    String defaultLanguage = 'English',
    XFile? avatarFile,
  }) async {
    final existing = await _clubs.doc(Club.familyRoomIdFor(_user.uid)).get();
    if (existing.exists) return Club.fromFirestore(existing);

    return createClub(
      name: name,
      description: description,
      // Invite-only is the only privacy a family space may have; there
      // is no public variant of it to choose.
      privacy: ClubPrivacy.inviteOnly,
      defaultLanguage: defaultLanguage,
      avatarFile: avatarFile,
      type: ClubType.family,
      documentId: Club.familyRoomIdFor(_user.uid),
    );
  }

  Future<Club> createClub({
    required String name,
    required String description,
    required ClubPrivacy privacy,
    required String defaultLanguage,
    XFile? avatarFile,
    XFile? bannerFile,
    ClubType type = ClubType.community,
    String? documentId,
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

    final clubRef = documentId == null ? _clubs.doc() : _clubs.doc(documentId);
    String? avatarUrl;
    String? bannerUrl;
    final uploadedReferences = <Reference>[];
    var cleanupUploadsOnFailure = true;

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

      // Community Club creation is privileged server work: the callable
      // verifies the trusted entitlement, serializes concurrent sessions per
      // owner, counts canonical Club roots (including legacy documents) and
      // atomically writes the same Club/member/channels/lounge shape below.
      // Family Rooms remain on the direct, free deterministic-id path.
      if (type == ClubType.community) {
        final callable = _functions.httpsCallable('createCommunityClub');
        // Once the request leaves the device, a transport timeout is
        // ambiguous: the server transaction may already have committed. Do
        // not delete images that a committed Club now references. First
        // recover idempotently through the same locally generated Club id;
        // clean up only for explicit server rejections that happen before a
        // commit (quota/entitlement/input/auth).
        cleanupUploadsOnFailure = false;
        try {
          await callable.call<Map<Object?, Object?>>({
            'clubId': clubRef.id,
            'name': normalizedName,
            'description': normalizedDescription,
            'privacy': privacy.name,
            'defaultLanguage': normalizedLanguage,
            'avatarUrl': avatarUrl,
            'bannerUrl': bannerUrl,
          });
        } on FirebaseFunctionsException catch (error) {
          try {
            final recovered = await clubRef.get();
            if (recovered.exists && recovered.data()?['ownerId'] == user.uid) {
              return Club.fromFirestore(recovered);
            }
          } catch (_) {
            // The read is inconclusive too; preserve the uploads because the
            // callable can still have committed.
          }
          cleanupUploadsOnFailure = const {
            'already-exists',
            'failed-precondition',
            'invalid-argument',
            'permission-denied',
            'resource-exhausted',
            'unauthenticated',
          }.contains(error.code);
          rethrow;
        }
        final snapshot = await clubRef.get();
        if (!snapshot.exists) {
          throw StateError('The Club was not created. Please try again.');
        }
        return Club.fromFirestore(snapshot);
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
        'type': type.name,
        'status': 'active',
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
        'name': type == ClubType.family ? 'Family Lounge' : 'Club Lounge',
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
      await batch.commit();
      final snapshot = await clubRef.get();
      return Club.fromFirestore(snapshot);
    } catch (_) {
      if (cleanupUploadsOnFailure) {
        for (final reference in uploadedReferences) {
          try {
            await reference.delete();
          } catch (_) {
            // Best-effort cleanup only.
          }
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
    // The object name is deterministic for a Club/idempotency key. Retrying a
    // timed-out creation overwrites the same two objects instead of leaking a
    // new timestamped upload on every tap. Content type remains explicit, so
    // an extension is not needed for serving the object.
    final reference = _storage.ref().child('clubs/${_user.uid}/$clubId/$kind');
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

    final callable = _functions.httpsCallable('removeClubMemberSelf');
    await callable.call<Map<Object?, Object?>>({
      'clubId': clubId,
      'memberId': memberId,
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

    try {
      await _functions.httpsCallable('sendClubInvite').call({
        'clubId': clubId,
        'inviteeId': friendId,
      });
    } on FirebaseFunctionsException catch (error) {
      throw StateError(error.message ?? 'The invitation could not be sent.');
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

  // ------------------------------------------------ family check-ins

  /// The family's recent check-ins, newest first.
  ///
  /// Readable only by members — enforced in `firestore.rules`, not here.
  /// A non-member's listener simply errors, which is the correct
  /// behaviour: the client is not the thing keeping this private.
  Stream<List<FamilyCheckIn>> watchCheckIns(String clubId, {int limit = 20}) {
    return _clubs
        .doc(clubId)
        .collection('checkIns')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(FamilyCheckIn.fromFirestore)
              // A value this build does not recognise is dropped rather
              // than rendered as something it might not be.
              .where((checkIn) => checkIn.status != null)
              .toList(growable: false),
        );
  }

  /// Posts a check-in as the signed-in account.
  ///
  /// `userId` is the caller's own uid and the timestamp is the server's —
  /// rules reject anything else, so a check-in can never be attributed to
  /// someone who did not send it, or back-dated.
  Future<void> postCheckIn({
    required String clubId,
    required FamilyCheckInStatus status,
  }) async {
    final user = _user;
    await _clubs.doc(clubId).collection('checkIns').add({
      'userId': user.uid,
      'clubId': clubId,
      'displayName': _resolveUserName(user),
      'photoUrl': user.photoURL,
      'status': status.value,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a check-in. Rules allow this for its author and for an
  /// organizer, matching how the rest of the club surfaces treat
  /// member-authored content.
  Future<void> deleteCheckIn({
    required String clubId,
    required String checkInId,
  }) async {
    await _clubs.doc(clubId).collection('checkIns').doc(checkInId).delete();
  }

  static String _resolveUserName(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'YO Voice user';
  }
}

class _UploadedClubImage {
  const _UploadedClubImage({required this.reference, required this.url});
  final Reference reference;
  final String url;
}
