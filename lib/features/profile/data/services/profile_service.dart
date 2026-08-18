import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

typedef DisplayNameMutationInvoker =
    Future<DisplayNameChangeResult> Function(String displayName);

class ProfileUnavailableException implements Exception {
  const ProfileUnavailableException();

  @override
  String toString() => 'This profile is not available.';
}

enum DisplayNameChangeFailure {
  cooldown,
  authSyncPending,
  authAccountMissingAfterSave,
  emailVerificationRequired,
  invalidName,
  signedOut,
  inactiveAccount,
  missingProfile,
  tooManyAttempts,
  unavailable,
}

class DisplayNameChangeException implements Exception {
  const DisplayNameChangeException(
    this.failure,
    this.message, {
    this.nextDisplayNameChangeAt,
    this.canonicalDisplayName,
    this.displayNameChangedAt,
  });

  final DisplayNameChangeFailure failure;
  final String message;
  final DateTime? nextDisplayNameChangeAt;
  final String? canonicalDisplayName;
  final DateTime? displayNameChangedAt;

  @override
  String toString() => message;
}

class DisplayNameChangeResult {
  const DisplayNameChangeResult({
    required this.displayName,
    required this.changed,
    required this.canChange,
    required this.displayNameChangedAt,
    required this.nextDisplayNameChangeAt,
  });

  final String displayName;
  final bool changed;
  final bool canChange;
  final DateTime? displayNameChangedAt;
  final DateTime? nextDisplayNameChangeAt;
}

class ProfileService {
  ProfileService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    ImagePicker? picker,
    FirebaseFunctions? functions,
    DisplayNameMutationInvoker? displayNameMutationInvoker,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _storageOverride = storage,
       _picker = picker ?? ImagePicker(),
       _functionsOverride = functions,
       _displayNameMutationInvoker = displayNameMutationInvoker;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage? _storageOverride;
  final ImagePicker _picker;
  final FirebaseFunctions? _functionsOverride;
  final DisplayNameMutationInvoker? _displayNameMutationInvoker;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

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
    // The complete users/{uid} document is private account state. Only the
    // signed-in account watches its source record; every other profile comes
    // from the exact server-owned public projection (no email, preferences,
    // presence, staff/ban or achievement internals).
    final collection = userId == _uid ? 'users' : 'publicProfiles';
    return _firestore.collection(collection).doc(userId).snapshots().map((
      document,
    ) {
      if (userId != _uid && !document.exists) {
        throw const ProfileUnavailableException();
      }
      return UserProfile.fromFirestore(document);
    });
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
    final cleanUsername = username.trim();

    if (cleanUsername.length < 2) {
      throw ArgumentError('Username must contain at least 2 characters.');
    }

    await _document.set({
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
  }

  /// Changes the signed-in member's display name through the canonical,
  /// server-authoritative 30-day policy.
  ///
  /// There is deliberately no direct Firestore/Auth fallback here: a network
  /// or deployment failure must fail closed instead of bypassing the limit.
  Future<DisplayNameChangeResult> updateDisplayName(String displayName) async {
    final override = _displayNameMutationInvoker;
    if (override != null) return override(displayName);

    try {
      final response = await _functions
          .httpsCallable('updateMyDisplayName')
          .call<Map<String, dynamic>>({'displayName': displayName});
      return _parseDisplayNameResult(response.data);
    } on FirebaseFunctionsException catch (error) {
      throw _displayNameExceptionFor(error);
    } on DisplayNameChangeException {
      rethrow;
    } catch (_) {
      throw const DisplayNameChangeException(
        DisplayNameChangeFailure.unavailable,
        "We couldn't update your display name. Check your connection and try again.",
      );
    }
  }

  static DisplayNameChangeResult _parseDisplayNameResult(
    Map<String, dynamic> data,
  ) {
    const expectedKeys = <String>{
      'displayName',
      'changed',
      'canChange',
      'displayNameChangedAtMs',
      'nextDisplayNameChangeAtMs',
    };
    if (data.keys.toSet().length != expectedKeys.length ||
        !data.keys.toSet().containsAll(expectedKeys)) {
      throw const DisplayNameChangeException(
        DisplayNameChangeFailure.unavailable,
        'The server returned an unexpected display-name update.',
      );
    }
    final displayName = data['displayName'];
    final changed = data['changed'];
    final canChange = data['canChange'];
    if (displayName is! String ||
        !_isCanonicalDisplayName(displayName) ||
        changed is! bool ||
        canChange is! bool) {
      throw const DisplayNameChangeException(
        DisplayNameChangeFailure.unavailable,
        'The server returned an incomplete display-name update.',
      );
    }

    DateTime? readMillis(String key) {
      final value = data[key];
      if (value == null) return null;
      if (value is! int || value < 0) {
        throw const DisplayNameChangeException(
          DisplayNameChangeFailure.unavailable,
          'The server returned an invalid display-name timestamp.',
        );
      }
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }

    final changedAt = readMillis('displayNameChangedAtMs');
    final nextChange = readMillis('nextDisplayNameChangeAtMs');
    final timestampsArePaired = (changedAt == null) == (nextChange == null);
    final exactWindow =
        changedAt == null ||
        nextChange!.difference(changedAt) == const Duration(days: 30);
    final legacyShape =
        changedAt == null && !changed && canChange && nextChange == null;
    if (!timestampsArePaired ||
        !exactWindow ||
        (changed && (changedAt == null || canChange)) ||
        (changedAt == null && !legacyShape)) {
      throw const DisplayNameChangeException(
        DisplayNameChangeFailure.unavailable,
        'The server returned an incomplete display-name update.',
      );
    }

    return DisplayNameChangeResult(
      displayName: displayName,
      changed: changed,
      canChange: canChange,
      displayNameChangedAt: changedAt,
      nextDisplayNameChangeAt: nextChange,
    );
  }

  @visibleForTesting
  static DisplayNameChangeResult parseDisplayNameResultForTesting(
    Map<String, dynamic> data,
  ) => _parseDisplayNameResult(data);

  static DisplayNameChangeException _displayNameExceptionFor(
    FirebaseFunctionsException error,
  ) {
    final details = error.details;
    DateTime? nextChange;
    DateTime? changedAt;
    String? canonicalDisplayName;
    String? reason;
    int? retryAfterSeconds;
    Set<String> detailKeys = const {};
    if (details is Map) {
      detailKeys = details.keys.whereType<String>().toSet();
      final rawReason = details['reason'];
      if (rawReason is String) reason = rawReason;
      final rawDisplayName = details['displayName'];
      if (rawDisplayName is String) canonicalDisplayName = rawDisplayName;
      final millis = details['nextDisplayNameChangeAtMs'];
      if (millis is int && millis >= 0) {
        nextChange = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
      }
      final changedAtMillis = details['displayNameChangedAtMs'];
      if (changedAtMillis is int && changedAtMillis >= 0) {
        changedAt = DateTime.fromMillisecondsSinceEpoch(
          changedAtMillis,
          isUtc: true,
        );
      }
      final rawRetryAfterSeconds = details['retryAfterSeconds'];
      if (rawRetryAfterSeconds is int && rawRetryAfterSeconds >= 0) {
        retryAfterSeconds = rawRetryAfterSeconds;
      }
    }

    if (error.code == 'unavailable' &&
        reason == 'auth-display-name-sync-pending' &&
        detailKeys.length == 4 &&
        detailKeys.containsAll(const {
          'reason',
          'displayName',
          'displayNameChangedAtMs',
          'nextDisplayNameChangeAtMs',
        }) &&
        canonicalDisplayName != null &&
        _isCanonicalDisplayName(canonicalDisplayName) &&
        changedAt != null &&
        nextChange != null &&
        nextChange.difference(changedAt) == const Duration(days: 30)) {
      return DisplayNameChangeException(
        DisplayNameChangeFailure.authSyncPending,
        'Your display name was saved, but account sync is still finishing. Press Save to retry.',
        nextDisplayNameChangeAt: nextChange,
        canonicalDisplayName: canonicalDisplayName,
        displayNameChangedAt: changedAt,
      );
    }

    if (error.code == 'failed-precondition' &&
        reason == 'email-verification-required') {
      return const DisplayNameChangeException(
        DisplayNameChangeFailure.emailVerificationRequired,
        'Verify your email address before changing your display name.',
      );
    }

    if (error.code == 'failed-precondition' &&
        reason == 'auth-account-missing' &&
        detailKeys.length == 4 &&
        detailKeys.containsAll(const {
          'reason',
          'displayName',
          'displayNameChangedAtMs',
          'nextDisplayNameChangeAtMs',
        }) &&
        canonicalDisplayName != null &&
        _isCanonicalDisplayName(canonicalDisplayName) &&
        changedAt != null &&
        nextChange != null &&
        nextChange.difference(changedAt) == const Duration(days: 30)) {
      return DisplayNameChangeException(
        DisplayNameChangeFailure.authAccountMissingAfterSave,
        'Your profile name was saved, but the sign-in account could not be found. Please sign in again.',
        nextDisplayNameChangeAt: nextChange,
        canonicalDisplayName: canonicalDisplayName,
        displayNameChangedAt: changedAt,
      );
    }

    return switch (error.code) {
      'failed-precondition'
          when reason == 'display-name-cooldown' &&
              detailKeys.length == 3 &&
              detailKeys.containsAll(const {
                'reason',
                'nextDisplayNameChangeAtMs',
                'retryAfterSeconds',
              }) &&
              nextChange != null &&
              retryAfterSeconds != null =>
        DisplayNameChangeException(
          DisplayNameChangeFailure.cooldown,
          'Your display name can only be changed once every 30 days.',
          nextDisplayNameChangeAt: nextChange,
        ),
      'failed-precondition' => const DisplayNameChangeException(
        DisplayNameChangeFailure.unavailable,
        "We couldn't verify your display-name state. Reopen your profile and try again.",
      ),
      'invalid-argument' => const DisplayNameChangeException(
        DisplayNameChangeFailure.invalidName,
        'Use 2–120 characters and remove line breaks or control characters.',
      ),
      'unauthenticated' => const DisplayNameChangeException(
        DisplayNameChangeFailure.signedOut,
        'Please sign in again before changing your display name.',
      ),
      'permission-denied' => const DisplayNameChangeException(
        DisplayNameChangeFailure.inactiveAccount,
        'This account cannot change its display name right now.',
      ),
      'not-found' => const DisplayNameChangeException(
        DisplayNameChangeFailure.missingProfile,
        'Your profile could not be found. Please reopen the app and try again.',
      ),
      'resource-exhausted' => const DisplayNameChangeException(
        DisplayNameChangeFailure.tooManyAttempts,
        'Too many display-name attempts. Wait a minute and try again.',
      ),
      _ => const DisplayNameChangeException(
        DisplayNameChangeFailure.unavailable,
        "We couldn't update your display name. Check your connection and try again.",
      ),
    };
  }

  @visibleForTesting
  static DisplayNameChangeException displayNameExceptionForTesting(
    FirebaseFunctionsException error,
  ) => _displayNameExceptionFor(error);

  static bool _isCanonicalDisplayName(String value) {
    final runes = value.runes.toList(growable: false);
    return value == value.trim() &&
        runes.length >= 2 &&
        runes.length <= 120 &&
        !runes.any(_isForbiddenDisplayNameRune);
  }

  static bool _isForbiddenDisplayNameRune(int value) {
    return value <= 0x1F ||
        (value >= 0x7F && value <= 0x9F) ||
        value == 0x00AD ||
        (value >= 0x0600 && value <= 0x0605) ||
        value == 0x061C ||
        value == 0x06DD ||
        value == 0x070F ||
        (value >= 0x0890 && value <= 0x0891) ||
        value == 0x08E2 ||
        value == 0x180E ||
        (value >= 0x200B && value <= 0x200F) ||
        (value >= 0x2028 && value <= 0x202E) ||
        (value >= 0x2060 && value <= 0x206F) ||
        value == 0xFEFF ||
        (value >= 0xFFF9 && value <= 0xFFFB) ||
        value == 0x110BD ||
        value == 0x110CD ||
        (value >= 0x13430 && value <= 0x1343F) ||
        (value >= 0x1BCA0 && value <= 0x1BCA3) ||
        (value >= 0x1D173 && value <= 0x1D17A) ||
        value == 0xE0001 ||
        (value >= 0xE0020 && value <= 0xE007F);
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
