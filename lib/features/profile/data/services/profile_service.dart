import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_image_rules.dart';

export 'package:yovoice/features/profile/data/services/profile_image_rules.dart'
    show
        ProfileImageException,
        ProfileImageFormat,
        ProfileImageKind,
        ProfileImageRules;

class ProfileService {
  ProfileService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    ImagePicker? picker,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _storageOverride = storage,
       _picker = picker ?? ImagePicker();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage? _storageOverride;
  final ImagePicker _picker;

  // Resolved lazily rather than in the constructor: FirebaseStorage.instance
  // throws without an initialised Firebase app, which would make every
  // Firestore-only code path (and every test of it) require full Firebase
  // setup just to construct the service.
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    return user.uid;
  }

  DocumentReference<Map<String, dynamic>> get _document =>
      _firestore.collection('users').doc(_uid);

  /// One shared, reactive view of the signed-in user's profile.
  ///
  /// Every screen that shows the current user's avatar, banner, name or
  /// account type reads this — Home, Profile, Settings, Creator Studio and
  /// Edit profile — so there is a single source of truth and they cannot
  /// disagree. Callers construct `ProfileService()` freely; the underlying
  /// Firestore listener is cached per uid and shared, and replays the last
  /// snapshot to late subscribers so a screen opened after the first
  /// emission renders immediately instead of flashing a placeholder.
  ///
  /// Do NOT mix this with `FirebaseAuth.currentUser.photoURL`. That is a
  /// different, staler store (null for email/password accounts, the Google
  /// avatar for Google ones) and blending the two is what made a freshly
  /// saved avatar appear on one screen but not another.
  Stream<UserProfile> watchCurrentProfile() {
    final uid = _uid;
    return _sharedProfileStreams.putIfAbsent(
      uid,
      () => _buildSharedProfileStream(uid),
    );
  }

  static final Map<String, Stream<UserProfile>> _sharedProfileStreams = {};

  Stream<UserProfile> _buildSharedProfileStream(String uid) {
    final controller = StreamController<UserProfile>.broadcast();
    UserProfile? latest;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? subscription;

    controller.onListen = () {
      subscription = _firestore
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen(
            (snapshot) {
              final profile = UserProfile.fromFirestore(snapshot);
              latest = profile;
              if (!controller.isClosed) controller.add(profile);
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!controller.isClosed) {
                controller.addError(error, stackTrace);
              }
            },
          );
    };
    controller.onCancel = () async {
      await subscription?.cancel();
      subscription = null;
    };

    return Stream<UserProfile>.multi((subscriber) {
      final cached = latest;
      if (cached != null) subscriber.add(cached);
      final inner = controller.stream.listen(
        subscriber.add,
        onError: subscriber.addError,
        onDone: subscriber.close,
      );
      subscriber.onCancel = inner.cancel;
    });
  }

  /// Drops the cached profile stream(s). Call on sign-out so the next
  /// account does not inherit the previous one's cached snapshot.
  static void resetCurrentProfileCache() {
    _sharedProfileStreams.clear();
  }

  Stream<UserProfile> watchProfile(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map(UserProfile.fromFirestore);
  }

  Future<void> ensureProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final existing = await _document.get();
    final data = existing.data();

    // Keyed off displayName, not document existence: other services
    // (friend_service's ensureUserDocument, presence) legitimately create
    // this document with only presence fields, and an `exists` check let
    // those races leave a brand-new account permanently un-bootstrapped.
    final alreadySeeded =
        (data?['displayName'] as String?)?.trim().isNotEmpty == true;
    if (alreadySeeded) return;

    final displayName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (user.email?.split('@').first ?? 'YO Voice user');

    final seed = <String, Object?>{
      'uid': user.uid,
      'email': user.email ?? '',
      'displayName': displayName,
      'username': displayName,
      'profileUpdatedAt': FieldValue.serverTimestamp(),
    };

    // Seed the avatar from the Auth account (Google sign-in supplies one)
    // ONLY when the profile has none. photoUrl belongs to this service
    // once set, and FirebaseAuth's copy is a separate, staler source.
    final hasProfilePhoto =
        (data?['photoUrl'] as String?)?.trim().isNotEmpty == true;
    if (!hasProfilePhoto && user.photoURL?.trim().isNotEmpty == true) {
      seed['photoUrl'] = user.photoURL;
    }

    // Counters are only safe to write on true first creation — rewriting
    // them would stomp progress friend_service/follow_service already
    // incremented.
    if (!existing.exists) {
      seed.addAll(_initialCounters());
    }

    await _document.set(seed, SetOptions(merge: true));
  }

  Map<String, Object?> _initialCounters() {
    return {
      'bio': '',
      'country': '',
      'nativeLanguage': '',
      'spokenLanguages': <String>[],
      'learningLanguages': <String>[],
      'website': '',
      'accountType': AccountType.personal.name,
      'friendCount': 0,
      'followerCount': 0,
      'followingCount': 0,
      'roomCount': 0,
      'communityCount': 0,
      'voiceMinutes': 0,
      'messageCount': 0,
      'activeDays': 0,
      'momentCount': 0,
      'reactionCount': 0,
      'hostMinutes': 0,
      'unlockedTitleIds': <String>[],
      'unlockedTitleTimestamps': <String, Object?>{},
    };
  }

  Future<void> updateProfile({
    required String displayName,
    required String username,
    required String bio,
    required String country,
    required String nativeLanguage,
    required List<String> spokenLanguages,
    required List<String> learningLanguages,
    required String website,
    required AccountType accountType,
    String statusMessage = '',
  }) async {
    final cleanDisplayName = displayName.trim();
    final cleanUsername = username.trim();

    if (cleanDisplayName.length < 2) {
      throw ArgumentError('Display name must contain at least 2 characters.');
    }
    if (cleanUsername.length < 2) {
      throw ArgumentError('Username must contain at least 2 characters.');
    }

    await _document.set({
      'displayName': cleanDisplayName,
      'username': cleanUsername,
      'bio': bio.trim(),
      'country': country.trim(),
      'nativeLanguage': nativeLanguage.trim(),
      'spokenLanguages': spokenLanguages,
      'learningLanguages': learningLanguages,
      'statusMessage': statusMessage.trim(),
      'website': website.trim(),
      'accountType': accountType.name,
      'profileUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _auth.currentUser?.updateDisplayName(cleanDisplayName);
  }

  /// Opens the gallery and returns validated bytes for [kind], or null when
  /// the user cancels the picker.
  ///
  /// Nothing is uploaded here. Edit profile holds the result as a pending
  /// change and commits it on Save, so backing out of the screen cannot
  /// leave a changed remote avatar or an orphaned Storage object behind.
  ///
  /// Throws [ProfileImageException] with a user-facing message when the file
  /// is too large or is not a format every supported platform can decode.
  /// Structured diagnostics for the save pipeline. Deliberately plain
  /// debugPrint so the stages are visible in a production web console
  /// while the persistence bug is being chased in the field. Logs paths,
  /// sizes and MIME types — never tokens, credentials or full download
  /// URLs.
  static void _logStage(String stage, [Map<String, Object?>? data]) {
    debugPrint('[PROFILE] $stage${data == null ? '' : ' $data'}');
  }

  Future<PickedProfileImage?> pickProfileImage(ProfileImageKind kind) async {
    final rules = ProfileImageRules.of(kind);

    // maxWidth keeps a 50MP camera original from being read into memory at
    // full size on the way in. image_picker ignores it on Web, which is why
    // the byte-size check below is the real guard. Twice the output edge so
    // the crop editor can zoom to 2x before the final render has to upscale.
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: (rules.maxOutputEdge * 2).toDouble(),
    );

    if (image == null) {
      _logStage('PROFILE_MEDIA_PICKER_CANCELLED', {'kind': kind.name});
      return null;
    }

    final bytes = await image.readAsBytes();
    _logStage('PROFILE_MEDIA_SELECTED', {
      'kind': kind.name,
      'bytes': bytes.lengthInBytes,
      'pickerName': image.name,
    });
    rules.validateSource(bytes);

    final format = ProfileImageRules.detectFormat(bytes)!;
    _logStage('PROFILE_MEDIA_VALIDATED', {
      'kind': kind.name,
      'format': format.mimeType,
    });

    return PickedProfileImage(kind: kind, bytes: bytes, format: format);
  }

  /// Uploads an already-validated image and persists its URL.
  Future<String> uploadProfileImage(PickedProfileImage image) {
    final kind = image.kind;
    final filename =
        '${kind.name}_${DateTime.now().millisecondsSinceEpoch}'
        '.${image.format.extension}';

    return _uploadBytes(
      bytes: image.bytes,
      path: 'users/$_uid/profile/$filename',
      contentType: image.format.mimeType,
      field: kind == ProfileImageKind.avatar ? 'photoUrl' : 'bannerUrl',
      updateAuthPhoto: kind == ProfileImageKind.avatar,
    );
  }

  /// Kept for callers that still want the old one-shot behaviour.
  Future<String?> pickAndUploadImage(ProfileImageKind kind) async {
    final picked = await pickProfileImage(kind);
    if (picked == null) return null;
    return uploadProfileImage(picked);
  }

  Future<String> _uploadBytes({
    required Uint8List bytes,
    required String path,
    required String contentType,
    required String field,
    required bool updateAuthPhoto,
  }) async {
    // Read the outgoing URL before anything changes so the replaced
    // object can be cleaned up afterwards.
    final previousUrl = (await _document.get()).data()?[field] as String?;

    _logStage('${field.toUpperCase()}_UPLOAD_STARTED', {
      'path': path,
      'bytes': bytes.lengthInBytes,
      'contentType': contentType,
    });

    final reference = _storage.ref().child(path);
    final uploadTask = reference.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        cacheControl: 'public,max-age=3600',
      ),
    );
    final snapshot = await uploadTask;

    if (snapshot.state != TaskState.success) {
      _logStage('${field.toUpperCase()}_UPLOAD_FAILED', {
        'state': snapshot.state.name,
      });
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'upload-failed',
        message: 'The image upload did not finish successfully.',
      );
    }

    _logStage('${field.toUpperCase()}_UPLOAD_COMPLETE', {
      'path': snapshot.ref.fullPath,
    });

    // Use the exact reference returned by the completed upload task. This
    // avoids asking Storage for a stale or differently-normalized path.
    final url = await snapshot.ref.getDownloadURL();
    _logStage('${field.toUpperCase()}_URL_RECEIVED', {
      'host': Uri.tryParse(url)?.host,
    });

    // Consistency contract (Storage and Firestore cannot share a real
    // transaction): the Firestore field is the source of truth, so the
    // upload happens FIRST and the pointer flips second. If the pointer
    // write fails, the just-uploaded object is deleted again (best
    // effort) and the error propagates — the profile keeps pointing at
    // the old image and nothing is orphaned. Only after the pointer has
    // flipped is the OLD object deleted, also best effort: a leaked file
    // is preferable to a profile pointing at nothing.
    _logStage('PROFILE_FIRESTORE_UPDATE_STARTED', {'field': field});
    try {
      await _document.set({
        field: url,
        'profileUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      _logStage('PROFILE_FIRESTORE_UPDATE_FAILED', {
        'field': field,
        'error': error.runtimeType.toString(),
      });
      await snapshot.ref.delete().then((_) {}, onError: (_) {});
      rethrow;
    }
    _logStage('PROFILE_FIRESTORE_UPDATE_COMPLETE', {'field': field});

    if (updateAuthPhoto) {
      await _auth.currentUser?.updatePhotoURL(url);
    }

    await _deleteReplacedImage(previousUrl, replacedBy: url);
    _logStage('PROFILE_STATE_REFRESHED', {'field': field});

    return url;
  }

  /// Best-effort removal of the object a profile image field used to
  /// point at. Every upload uses a fresh timestamped filename (that's the
  /// cache-busting strategy — a genuinely new URL, not a query-string
  /// hack), so without this each change would leave the prior file behind
  /// forever. Only deletes objects inside this user's own profile folder;
  /// anything else (external seed URLs, a Google avatar) is left alone.
  Future<void> _deleteReplacedImage(
    String? previousUrl, {
    required String replacedBy,
  }) async {
    final url = previousUrl?.trim();
    if (url == null || url.isEmpty || url == replacedBy) return;
    if (!url.contains('/users%2F$_uid%2Fprofile%2F') &&
        !url.contains('/users/$_uid/profile/')) {
      return;
    }
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {
      // Missing object, revoked token, offline — none of these should
      // fail the save that already succeeded.
    }
  }
}

/// An image chosen by the user and validated, but not yet uploaded.
class PickedProfileImage {
  const PickedProfileImage({
    required this.kind,
    required this.bytes,
    required this.format,
  });

  final ProfileImageKind kind;
  final Uint8List bytes;
  final ProfileImageFormat format;
}
