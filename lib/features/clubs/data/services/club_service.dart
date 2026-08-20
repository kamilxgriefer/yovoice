import 'dart:typed_data';

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

enum _ClubImageFormat {
  jpeg('image/jpeg'),
  png('image/png'),
  webp('image/webp');

  const _ClubImageFormat(this.mimeType);

  final String mimeType;
}

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

  /// The signed-in account id, or '' when signed out.
  ///
  /// Mirrors `RoomService.currentUserId`: presentation compares this against
  /// `Club.ownerId` to decide whether to OFFER owner-only controls (the
  /// lounge delete flow), without reaching for `FirebaseAuth.instance` and
  /// tying its render path to a live Firebase app. Authorization itself stays
  /// server-side — `deleteClubSelf` re-checks the same ownerId.
  String get currentUserId => _auth.currentUser?.uid ?? '';

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
    XFile? bannerFile,
  }) async {
    if (avatarFile != null || bannerFile != null) {
      throw ArgumentError(
        'Family Room images are not supported until private authenticated media is available.',
      );
    }
    final user = _user;
    final familyRef = _clubs.doc(Club.familyRoomIdFor(user.uid));
    final existing = await _readOwnedFamilyRoom(familyRef, user.uid);
    if (existing != null) {
      return existing;
    }

    return createClub(
      name: name,
      description: description,
      // Invite-only is the only privacy a family space may have; there
      // is no public variant of it to choose.
      privacy: ClubPrivacy.inviteOnly,
      defaultLanguage: defaultLanguage,
      avatarFile: null,
      bannerFile: null,
      type: ClubType.family,
      documentId: familyRef.id,
    );
  }

  Future<Club?> _readOwnedFamilyRoom(
    DocumentReference<Map<String, dynamic>> reference,
    String ownerId,
  ) async {
    late final DocumentSnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await reference.get();
    } on FirebaseException catch (error) {
      // The first shipping Family ruleset evaluated resource.data while this
      // deterministic document was still missing. Rules turn that null
      // dereference into permission-denied, before the create batch even has
      // a chance to run. Current rules explicitly allow this one missing-doc
      // probe, but older deployed rules and cached clients can overlap during
      // rollout. Treat only this inconclusive PRE-READ as "not found" and let
      // the atomic create rules remain the authority. If a document actually
      // exists or the caller is unauthorized, the subsequent create is an
      // update and still fails closed.
      if (error.code == 'permission-denied') return null;
      rethrow;
    }
    if (!snapshot.exists) return null;
    final club = Club.fromFirestore(snapshot);
    if (club.ownerId != ownerId || club.type != ClubType.family) {
      throw StateError('The canonical Family Room id contains invalid data.');
    }
    return club;
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
    // Validate and canonicalize media before creating anything, but do not
    // upload yet. Storage authorizes Club media from a real active root and
    // membership; uploading to arbitrary pre-root ids creates an unbounded
    // orphan-object surface.
    final preparedAvatar = avatarFile == null
        ? null
        : await _prepareClubImage(avatarFile);
    final preparedBanner = bannerFile == null
        ? null
        : await _prepareClubImage(bannerFile);

    try {
      // Community Club creation is privileged server work: the callable
      // verifies the trusted entitlement, serializes concurrent sessions per
      // owner, counts canonical Club roots (including legacy documents) and
      // atomically writes the same Club/member/channels/lounge shape below.
      // Family Rooms remain on the direct, free deterministic-id path.
      if (type == ClubType.community) {
        final callable = _functions.httpsCallable('createCommunityClub');
        try {
          await callable.call<Map<Object?, Object?>>({
            'clubId': clubRef.id,
            'name': normalizedName,
            'description': normalizedDescription,
            'privacy': privacy.name,
            'defaultLanguage': normalizedLanguage,
            // Media is attached only after the callable has established the
            // Premium/quota-bound root and owner membership.
            'avatarUrl': null,
            'bannerUrl': null,
          });
        } on FirebaseFunctionsException catch (_) {
          try {
            final recovered = await clubRef.get();
            if (recovered.exists && recovered.data()?['ownerId'] == user.uid) {
              return _attachClubMedia(
                clubRef: clubRef,
                avatar: preparedAvatar,
                banner: preparedBanner,
              );
            }
          } catch (_) {
            // The read is inconclusive too; preserve the original callable
            // error. No media exists yet, so there is nothing to orphan.
          }
          rethrow;
        }
        final snapshot = await clubRef.get();
        if (!snapshot.exists) {
          throw StateError('The Club was not created. Please try again.');
        }
        return _attachClubMedia(
          clubRef: clubRef,
          avatar: preparedAvatar,
          banner: preparedBanner,
        );
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
      // Family creation is the remaining client-owned Club bootstrap. Its
      // root, owner roster row and lounge all carry identity snapshots, so
      // read the canonical private profile once and use the exact stored
      // value across the atomic graph. Firebase Auth is only a mirror and may
      // be stale after a rename.
      final ownerName = await _canonicalDisplayName(user);

      final batch = _firestore.batch();
      batch.set(clubRef, {
        'name': normalizedName,
        'description': normalizedDescription,
        'ownerId': user.uid,
        'ownerName': ownerName,
        'avatarUrl': null,
        'bannerUrl': null,
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
        'avatarUrl': null,
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
        'imageUrl': null,
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
      return _attachClubMedia(
        clubRef: clubRef,
        avatar: preparedAvatar,
        banner: preparedBanner,
      );
    } catch (error, stackTrace) {
      // Two devices can both observe the deterministic Family Room id as
      // missing, then race the same atomic create. One batch wins; the other
      // is rejected because its root write is now an update. Recover the
      // winner instead of surfacing a false error. Family media is disabled,
      // so this recovery never uploads or attaches a bearer-token URL.
      if (type == ClubType.family &&
          clubRef.id == Club.familyRoomIdFor(user.uid)) {
        try {
          final recovered = await _readOwnedFamilyRoom(clubRef, user.uid);
          if (recovered != null) {
            return recovered;
          }
        } catch (_) {
          // Preserve the original creation failure when recovery is
          // inconclusive or the canonical document is malformed.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<_PreparedClubImage> _prepareClubImage(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length < 128) {
      throw StateError('The selected image is empty or damaged.');
    }
    if (bytes.length > 8 * 1024 * 1024) {
      throw StateError('The selected image must be smaller than 8 MB.');
    }

    // Pickers do not provide a trustworthy MIME on every platform. Web can
    // report image/jpg, image/x-png or application/octet-stream for perfectly
    // valid images, while a renamed HEIC may claim image/jpeg. Storage rules
    // intentionally accept only formats every supported client renders, so
    // sniff the bytes and send one canonical MIME instead of trusting the
    // declaration. This prevents a valid JPG/PNG/WebP from being rejected as
    // `storage/unauthorized` and gives unsupported files a useful local error.
    final format = _detectClubImageFormat(bytes);
    if (format == null) {
      throw StateError(
        'That file type is not supported. Use a JPG, PNG or WebP image.',
      );
    }
    return _PreparedClubImage(bytes: bytes, format: format);
  }

  Future<_UploadedClubImage> _uploadClubImage({
    required String clubId,
    required _PreparedClubImage image,
    required String kind,
  }) async {
    // The object name is deterministic for a Club/idempotency key. Retrying a
    // timed-out creation overwrites the same two objects instead of leaking a
    // new timestamped upload on every tap. Content type remains explicit, so
    // an extension is not needed for serving the object.
    final reference = _storage.ref().child('clubs/${_user.uid}/$clubId/$kind');
    final metadata = SettableMetadata(
      contentType: image.format.mimeType,
      cacheControl: 'public,max-age=31536000',
    );
    final snapshot = await reference.putData(image.bytes, metadata);
    final generation = snapshot.metadata?.generation?.trim().isNotEmpty == true
        ? snapshot.metadata!.generation!.trim()
        : (await reference.getMetadata()).generation?.trim();
    if (generation == null || generation.isEmpty) {
      throw StateError('The uploaded image could not be verified.');
    }
    return _UploadedClubImage(reference: reference, generation: generation);
  }

  Future<Club> _attachClubMedia({
    required DocumentReference<Map<String, dynamic>> clubRef,
    required _PreparedClubImage? avatar,
    required _PreparedClubImage? banner,
  }) async {
    if (avatar == null && banner == null) {
      return Club.fromFirestore(await clubRef.get());
    }

    final initialSnapshot = await clubRef.get();
    final initial = initialSnapshot.data();
    if (initial == null || initial['ownerId'] != _user.uid) {
      throw StateError('Only the Club owner can attach creation media.');
    }
    // Defense in depth for non-UI callers. Family roots must never gain a
    // bearer-token media URL: those URLs bypass Storage Rules after leaking.
    if (initial['type'] == ClubType.family.name) {
      throw StateError(
        'Family Room images are not available yet. Create the room without an image.',
      );
    }

    final pendingAvatar =
        initial['avatarUrl'] is String &&
            (initial['avatarUrl'] as String).isNotEmpty &&
            initial['avatarGeneration'] is String
        ? null
        : avatar;
    final pendingBanner =
        initial['bannerUrl'] is String &&
            (initial['bannerUrl'] as String).isNotEmpty &&
            initial['bannerGeneration'] is String
        ? null
        : banner;
    if (pendingAvatar == null && pendingBanner == null) {
      return Club.fromFirestore(initialSnapshot);
    }

    final uploaded = <_UploadedClubImage>[];
    var finalizeAttempted = false;
    try {
      final avatarUpload = pendingAvatar == null
          ? null
          : await _uploadClubImage(
              clubId: clubRef.id,
              image: pendingAvatar,
              kind: 'avatar',
            );
      if (avatarUpload != null) uploaded.add(avatarUpload);
      final bannerUpload = pendingBanner == null
          ? null
          : await _uploadClubImage(
              clubId: clubRef.id,
              image: pendingBanner,
              kind: 'banner',
            );
      if (bannerUpload != null) uploaded.add(bannerUpload);

      final callable = _functions.httpsCallable('finalizeClubMedia');
      finalizeAttempted = true;
      await callable.call<Map<Object?, Object?>>({
        'clubId': clubRef.id,
        'avatar': avatarUpload?.callableDescriptor,
        'banner': bannerUpload?.callableDescriptor,
      });
      return Club.fromFirestore(await clubRef.get());
    } catch (error, stackTrace) {
      // A callable response can be lost after its transaction commits. Bind
      // recovery to the exact object generations; a URL/path comparison alone
      // would accept a stale replay after an overwrite.
      try {
        final recovered = await clubRef.get();
        final data = recovered.data();
        final committed =
            data != null &&
            uploaded.every((image) {
              final kind = image.reference.name;
              return data['${kind}Generation'] == image.generation;
            });
        if (committed) return Club.fromFirestore(recovered);
      } catch (_) {
        // Preserve the original finalize error and perform best-effort cleanup.
      }
      final explicitPreCommitRejection =
          error is FirebaseFunctionsException &&
          const {
            'invalid-argument',
            'failed-precondition',
            'permission-denied',
            'unauthenticated',
            'data-loss',
          }.contains(error.code);
      // Never delete after an ambiguous callable failure: its Admin
      // transaction may have committed even when this client could not read
      // the generation mirror yet. Deterministic names bound orphan growth to
      // at most avatar+banner per canonical Club and a later retry can safely
      // recover them.
      if (!finalizeAttempted || explicitPreCommitRejection) {
        for (final image in uploaded) {
          try {
            await image.reference.delete();
          } catch (_) {
            // The Club remains valid without media; cleanup is best effort.
          }
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static _ClubImageFormat? _detectClubImageFormat(Uint8List bytes) {
    if (bytes.length < 12) return null;
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return _ClubImageFormat.jpeg;
    }
    const png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    var isPng = true;
    for (var index = 0; index < png.length; index++) {
      if (bytes[index] != png[index]) {
        isPng = false;
        break;
      }
    }
    if (isPng) return _ClubImageFormat.png;
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return _ClubImageFormat.webp;
    }
    return null;
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

  /// Permanently deletes a whole Club — the club document tree, its lounge
  /// room tree, the LiveKit room and media — through the owner-only
  /// `deleteClubSelf` callable ({ clubId } → { success: true, clubId }).
  ///
  /// This is the ONE deletion path for a Club and therefore for its lounge:
  /// `deleteRoomSelf` deliberately refuses `club_lounge_*` rooms, so the
  /// room delete flow routes club lounges here instead. The callable
  /// authorizes by checking the caller IS the club's current owner and
  /// answers `permission-denied` otherwise; the client only decides whether
  /// to OFFER the control.
  ///
  /// After an ambiguous failure (timeout, unavailable) this deliberately
  /// does NOT probe the club document and claim success: a non-owner's read
  /// of a half-deleted tree is inconclusive under rules, and a false
  /// "deleted" over a Club that still exists is the worse error. The caller
  /// keeps the server's own refusal and may simply retry — the callable is
  /// idempotent on the server side per the contract.
  Future<void> deleteClub(String clubId) async {
    final normalized = clubId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('A Club id is required to delete a Club.');
    }
    final callable = _functions.httpsCallable('deleteClubSelf');
    final result = await callable.call<Map<Object?, Object?>>({
      'clubId': normalized,
    });
    // The contract's success shape is { success: true, clubId }. Anything
    // else is not proof of deletion, and this path refuses to fall back
    // after an ambiguous answer — see _attachClubMedia for the same stance.
    if (result.data['success'] != true) {
      throw StateError(
        'The Club deletion could not be confirmed. Please try again.',
      );
    }
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
    final displayName = userData['displayName'];
    final photoUrl = userData['photoUrl'] as String? ?? _user.photoURL;
    if (displayName is! String || displayName.trim().isEmpty) {
      throw StateError('Your profile does not have a display name.');
    }

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
        // Preserve the exact canonical bytes. Rules compare the membership
        // snapshot directly with users/{uid}.displayName.
        'displayName': displayName,
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
    final displayName = await _canonicalDisplayName(user);
    await _clubs.doc(clubId).collection('checkIns').add({
      'userId': user.uid,
      'clubId': clubId,
      'displayName': displayName,
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

  Future<String> _canonicalDisplayName(User user) async {
    final snapshot = await _firestore.collection('users').doc(user.uid).get();
    final displayName = snapshot.data()?['displayName'];
    if (displayName is String && displayName.trim().isNotEmpty) {
      return displayName;
    }
    throw StateError('Your profile does not have a display name.');
  }
}

class _UploadedClubImage {
  const _UploadedClubImage({required this.reference, required this.generation});
  final Reference reference;
  final String generation;

  Map<String, Object> get callableDescriptor => {
    'path': reference.fullPath,
    'generation': generation,
  };
}

class _PreparedClubImage {
  const _PreparedClubImage({required this.bytes, required this.format});

  final Uint8List bytes;
  final _ClubImageFormat format;
}
