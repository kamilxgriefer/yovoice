import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'package:yovoice/core/localization/firebase_auth_language_sync.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/features/auth/data/action_code_settings.dart';
import 'package:yovoice/features/auth/data/auth_profile_identity.dart';
import 'package:yovoice/features/auth/data/totp_mfa_service.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/moments/data/services/offline_voice_moment_service.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/shared/models/app_user.dart';
import 'package:yovoice/services/firestore_service.dart';

enum AppleSignInAvailability {
  available,
  notConfigured,
  temporarilyUnavailable,
}

typedef AppleProviderProbe = Future<AppleSignInAvailability> Function();

/// Calls `secureFederatedSignInV1` and returns its result map. Injectable so
/// the post-sign-in takeover check can be asserted without Cloud Functions.
typedef FederatedSignInSecurityCheck = Future<Map<String, dynamic>> Function();

/// Removes this device's FCM token registration. Injectable so the
/// sign-out ordering can be asserted without a live Firebase Messaging.
typedef DeviceTokenUnregister = Future<void> Function();

typedef ActiveVoiceSessionReader =
    ({String? directCallId, bool isActive, bool isRoomSession, String? roomId})
    Function();
typedef ActiveVoiceDisconnect = Future<void> Function();
typedef ActiveRoomLeave = Future<void> Function(String roomId);
typedef ActiveDirectCallEnd = Future<void> Function(String callId);
typedef LocalSensitiveDataClear = Future<void> Function(String userId);
typedef EphemeralMediaAccessClear = void Function();

class AuthService {
  AuthService({
    FirebaseAuth? firebaseAuth,
    FirestoreService? firestoreService,
    @visibleForTesting bool? appleSignInFeatureEnabled,
    @visibleForTesting bool? appleUseWebPopup,
    @visibleForTesting AppleProviderProbe? appleProviderProbe,
    @visibleForTesting
    FederatedSignInSecurityCheck? federatedSignInSecurityCheck,
    @visibleForTesting Duration? federatedSignInSecurityCheckWait,
    @visibleForTesting PresenceService? presenceService,
    @visibleForTesting DeviceTokenUnregister? unregisterDeviceToken,
    @visibleForTesting ActiveVoiceSessionReader? activeVoiceSessionReader,
    @visibleForTesting ActiveVoiceDisconnect? disconnectActiveVoice,
    @visibleForTesting ActiveRoomLeave? leaveActiveRoom,
    @visibleForTesting ActiveDirectCallEnd? endActiveDirectCall,
    @visibleForTesting LocalSensitiveDataClear? clearLocalSensitiveData,
    @visibleForTesting EphemeralMediaAccessClear? clearEphemeralMediaAccess,
    @visibleForTesting Future<void> Function()? waitForAuthLanguage,
    @visibleForTesting
    Duration bestEffortCleanupTimeout = const Duration(seconds: 10),
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestoreService = firestoreService ?? FirestoreService(),
       _injectedPresenceService = presenceService,
       _injectedUnregisterDeviceToken = unregisterDeviceToken,
       _injectedActiveVoiceSessionReader = activeVoiceSessionReader,
       _injectedDisconnectActiveVoice = disconnectActiveVoice,
       _injectedLeaveActiveRoom = leaveActiveRoom,
       _injectedEndActiveDirectCall = endActiveDirectCall,
       _injectedClearLocalSensitiveData = clearLocalSensitiveData,
       _injectedClearEphemeralMediaAccess = clearEphemeralMediaAccess,
       _waitForAuthLanguage =
           waitForAuthLanguage ??
           (() => FirebaseAuthLanguageSync.instance.ready),
       _bestEffortCleanupTimeout = bestEffortCleanupTimeout,
       _appleSignInFeatureEnabled =
           appleSignInFeatureEnabled ??
           const bool.fromEnvironment(
             'YOVOICE_APPLE_SIGN_IN_ENABLED',
             defaultValue: true,
           ),
       _appleUseWebPopup = appleUseWebPopup,
       _appleProviderProbe = appleProviderProbe,
       _injectedFederatedSignInSecurityCheck = federatedSignInSecurityCheck,
       _federatedSignInSecurityCheckWait =
           federatedSignInSecurityCheckWait ??
           AuthService.federatedSignInSecurityCheckTimeout;

  final FirebaseAuth _firebaseAuth;
  final FirestoreService _firestoreService;
  final bool _appleSignInFeatureEnabled;
  final bool? _appleUseWebPopup;
  final AppleProviderProbe? _appleProviderProbe;
  final FederatedSignInSecurityCheck? _injectedFederatedSignInSecurityCheck;
  final Duration _federatedSignInSecurityCheckWait;

  /// How long a returning Google/Apple sign-in waits for the post-sign-in
  /// takeover check before it proceeds. Past it the sign-in continues and the
  /// call keeps running: a late "remediated" still signs this device out and
  /// is announced on [federatedSessionSecuredLater]. The server sweep is the
  /// backstop when no answer arrives at all.
  static const Duration federatedSignInSecurityCheckTimeout = Duration(
    seconds: 8,
  );

  // Never closed: a pending `.first` on a closed stream would throw.
  final StreamController<void> _federatedSessionSecuredLater =
      StreamController<void>.broadcast(sync: true);

  /// Emits when the post-sign-in check answered "remediated" AFTER the
  /// sign-in had already returned (a brand-new account, which is checked in
  /// the background, or a returning one whose check outlasted
  /// [federatedSignInSecurityCheckTimeout]). This device has been signed out
  /// by then; the listener only tells the owner why.
  Stream<void> get federatedSessionSecuredLater =>
      _federatedSessionSecuredLater.stream;

  // Resolved lazily, inside signOut() only. Building the production
  // PresenceService or touching PushNotificationService.instance eagerly in
  // the constructor would reach FirebaseAuth/Firestore/Messaging singletons
  // every time an AuthService is constructed — including in widget tests
  // that never sign out.
  final PresenceService? _injectedPresenceService;
  final DeviceTokenUnregister? _injectedUnregisterDeviceToken;
  final ActiveVoiceSessionReader? _injectedActiveVoiceSessionReader;
  final ActiveVoiceDisconnect? _injectedDisconnectActiveVoice;
  final ActiveRoomLeave? _injectedLeaveActiveRoom;
  final ActiveDirectCallEnd? _injectedEndActiveDirectCall;
  final LocalSensitiveDataClear? _injectedClearLocalSensitiveData;
  final EphemeralMediaAccessClear? _injectedClearEphemeralMediaAccess;
  final Future<void> Function() _waitForAuthLanguage;
  final Duration _bestEffortCleanupTimeout;

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static Future<void>? _signOutInFlight;

  Future<void>? _googleSignInInitialization;
  Future<AppleSignInAvailability>? _appleSignInAvailability;

  User? get currentUser => _firebaseAuth.currentUser;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  TotpSignInChallenge createTotpSignInChallenge(
    FirebaseAuthMultiFactorException exception,
  ) => TotpSignInChallenge(exception.resolver);

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _waitForAuthLanguage();
      return await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      throw const AuthServiceException(
        'An unexpected error occurred while signing in.',
      );
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      await _waitForAuthLanguage();
      UserCredential credential;

      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();

        googleProvider.setCustomParameters({'prompt': 'select_account'});

        credential = await _firebaseAuth.signInWithPopup(googleProvider);
      } else {
        await _initializeGoogleSignIn();

        if (!_googleSignIn.supportsAuthenticate()) {
          throw const AuthServiceException(
            'Google Sign-In is not supported on this platform.',
          );
        }

        final googleUser = await _googleSignIn.authenticate();
        final googleAuthentication = googleUser.authentication;
        final idToken = googleAuthentication.idToken;

        if (idToken == null || idToken.isEmpty) {
          throw const AuthServiceException(
            'Google did not return a valid authentication token.',
          );
        }

        final googleCredential = GoogleAuthProvider.credential(
          idToken: idToken,
        );

        credential = await _firebaseAuth.signInWithCredential(googleCredential);
      }

      await _createSocialUserProfileIfNeeded(
        credential,
        providerName: 'Google',
      );
      await _secureReturningFederatedSignIn(credential);

      return credential;
    } on GoogleSignInException catch (error) {
      switch (error.code) {
        case GoogleSignInExceptionCode.canceled:
          throw const AuthServiceException('Google Sign-In was cancelled.');

        case GoogleSignInExceptionCode.interrupted:
          throw const AuthServiceException(
            'Google Sign-In was interrupted. Please try again.',
          );

        case GoogleSignInExceptionCode.clientConfigurationError:
          throw const AuthServiceException(
            'Google Sign-In is not configured correctly.',
          );

        case GoogleSignInExceptionCode.providerConfigurationError:
          throw const AuthServiceException(
            'Google authentication provider is unavailable.',
          );

        case GoogleSignInExceptionCode.uiUnavailable:
          throw const AuthServiceException(
            'Google Sign-In window could not be opened.',
          );

        default:
          throw const AuthServiceException(
            'An unexpected Google Sign-In error occurred.',
          );
      }
    } on FirebaseAuthException {
      rethrow;
    } on AuthServiceException {
      rethrow;
    } catch (_) {
      throw const AuthServiceException(
        'An unexpected error occurred during Google Sign-In.',
      );
    }
  }

  /// Returns whether Firebase's production configuration can start an Apple
  /// OAuth flow. The build flag is intentionally necessary as well: enabling
  /// the provider in the Firebase console before the Apple Service ID,
  /// signing capability and release profile are ready must not expose a
  /// half-configured button to users. Every shipped target is configured and
  /// therefore defaults on; an unconfigured build must explicitly set the
  /// compile-time flag to false.
  Future<AppleSignInAvailability> getAppleSignInAvailability() async {
    if (!_appleSignInFeatureEnabled) {
      return AppleSignInAvailability.notConfigured;
    }

    final probe = _appleSignInAvailability ??= _probeAppleProvider();

    try {
      final availability = await probe;
      if (availability == AppleSignInAvailability.temporarilyUnavailable &&
          identical(_appleSignInAvailability, probe)) {
        // A timeout/offline result is not configuration state. Do not make a
        // transient network failure disable Apple until the screen is rebuilt;
        // the next tap can probe again and continue immediately.
        _appleSignInAvailability = null;
      }
      return availability;
    } catch (_) {
      if (identical(_appleSignInAvailability, probe)) {
        _appleSignInAvailability = null;
      }
      rethrow;
    }
  }

  Future<UserCredential> signInWithApple() async {
    await _waitForAuthLanguage();
    final availability = await getAppleSignInAvailability();
    if (availability != AppleSignInAvailability.available) {
      throw const AuthServiceException(
        'Apple Sign-In is not available right now.',
      );
    }

    try {
      final appleProvider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');

      final useWebPopup = _appleUseWebPopup ?? kIsWeb;
      final credential = useWebPopup
          ? await _firebaseAuth.signInWithPopup(appleProvider)
          : await _firebaseAuth.signInWithProvider(appleProvider);

      await _createSocialUserProfileIfNeeded(credential, providerName: 'Apple');
      await _secureReturningFederatedSignIn(credential);

      return credential;
    } on FirebaseAuthException {
      rethrow;
    } on AuthServiceException {
      rethrow;
    } catch (_) {
      throw const AuthServiceException(
        'An unexpected error occurred during Apple Sign-In.',
      );
    }
  }

  Future<UserCredential> register({
    required String email,
    required String password,
    required String username,
  }) async {
    UserCredential? credential;

    try {
      await _waitForAuthLanguage();
      credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        throw const AuthServiceException(
          'Unable to create a new user account.',
        );
      }

      await user.updateDisplayName(username.trim());

      final appUser = AppUser(
        uid: user.uid,
        email: email.trim(),
        username: username.trim(),
        createdAt: DateTime.now(),
      );

      await _firestoreService.createUserProfile(appUser);

      try {
        await user.sendEmailVerification(verifyEmailActionCodeSettings());
      } catch (_) {
        // The account and profile already exist at this point — a failed
        // verification send shouldn't undo registration. The verify-email
        // screen's resend button covers this case.
      }

      return credential;
    } on FirebaseAuthException {
      rethrow;
    } catch (error) {
      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {
          // The account may already have been removed or the session expired.
        }
      }

      if (error is AuthServiceException) {
        rethrow;
      }

      throw const AuthServiceException('Unable to create the user profile.');
    }
  }

  Future<void> resendVerificationEmail() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw const AuthServiceException('You must be signed in to do that.');
    }

    try {
      await _waitForAuthLanguage();
      await user.sendEmailVerification(verifyEmailActionCodeSettings());
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      throw const AuthServiceException(
        'Unable to send the verification email.',
      );
    }
  }

  /// Forces a fresh emailVerified read from Firebase. The cached [User]
  /// object never updates emailVerified on its own — reload() is the only
  /// way to learn a link opened elsewhere (another tab, another device)
  /// was actually applied.
  Future<bool> reloadCurrentUser() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _firebaseAuth.currentUser?.emailVerified ?? false;
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _waitForAuthLanguage();
      await _firebaseAuth.sendPasswordResetEmail(
        email: email.trim(),
        actionCodeSettings: resetPasswordActionCodeSettings(),
      );
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      throw const AuthServiceException(
        'Unable to send the password reset email.',
      );
    }
  }

  /// The single sign-out choke point for the whole app.
  ///
  /// Settings, Profile, the device-sessions screen, the 2FA
  /// expired-session path and [AuthController] all route through here, on
  /// purpose: signing out has to mean the same thing everywhere. Three pieces
  /// of cleanup are only *permitted* while the session is still live, so
  /// they run before [FirebaseAuth.signOut] rather than in reaction to it:
  ///
  ///  * **Presence.** `firestore.rules` gates `users/{uid}` updates on
  ///    `isSignedIn() && isOwner(uid)`. An offline write issued after the
  ///    session is cleared is denied, `socialPresence/{uid}` keeps
  ///    mirroring `isOnline: true`, and the account shows as Online to its
  ///    friends in DMs indefinitely.
  ///  * **This device's FCM token.** Deleting `fcmTokens/{token}` needs
  ///    `isOwner(uid)` for the same reason. A token left behind means the
  ///    previous account keeps receiving push on a shared device.
  ///  * **Active voice.** The process-wide LiveKit service intentionally
  ///    survives room-screen disposal for the mini player. Logout therefore
  ///    disconnects it centrally and, for a room session, leaves the server
  ///    roster while Auth can still authorize that mutation.
  ///
  ///  * **Local pending messages.** Text drafts and photo/voice payloads are
  ///    durable for offline retry, but must be purged before another account
  ///    can use the same device.
  ///
  /// All are best-effort. A cleanup failure is reported and swallowed — it
  /// must never trap someone in a session they asked to leave.
  ///
  /// This covers sign-out, not process death: an app that is force-quit or
  /// whose refresh token is revoked server-side never reaches this code, and
  /// nothing on the client can write for a session that no longer exists.
  /// Expiring stale presence in that case needs a server-side sweeper over
  /// `presenceUpdatedAt`, which does not exist yet.
  Future<void> signOut() {
    final existing = _signOutInFlight;
    if (existing != null) return existing;

    final operation = _performSignOut();
    late final Future<void> tracked;
    tracked = operation.whenComplete(() {
      if (identical(_signOutInFlight, tracked)) _signOutInFlight = null;
    });
    _signOutInFlight = tracked;
    return tracked;
  }

  Future<void> _performSignOut() async {
    final userId = _firebaseAuth.currentUser?.uid;

    // Signed Voice Moment URLs are short-lived bearer grants. Invalidate the
    // process-wide cache (including in-flight resolutions) before any async
    // cleanup yields so an account switch cannot retain a usable grant.
    try {
      (_injectedClearEphemeralMediaAccess ??
          MomentService.clearAllMediaAccessCaches)();
      ReelService.clearAllMediaAccessCaches();
    } catch (error) {
      debugPrint(
        'AuthService.signOut: ephemeral media-grant cleanup failed '
        '(${error.runtimeType}). Sign-out will continue.',
      );
    }

    final cleanup = <Future<void>>[
      _clearActiveVoiceSessionBestEffort(canLeaveRoom: userId != null),
    ];
    if (userId != null) {
      cleanup.addAll([
        _unregisterDeviceTokenBestEffort(),
        _setOfflineBestEffort(userId),
        _clearLocalSensitiveDataBestEffort(userId),
      ]);
    }
    await Future.wait<void>(cleanup);

    try {
      if (!kIsWeb) {
        try {
          await _initializeGoogleSignIn();
          await _googleSignIn.signOut();
        } catch (_) {
          // Firebase must still be signed out even when Google sign-out fails.
        }
      }
    } finally {
      await _firebaseAuth.signOut();
      // Friends fanouts replay public identity and presence across otherwise
      // independent screens. Retire them only after Firebase confirms the
      // boundary: if sign-out itself fails, the still-authenticated screens
      // must keep their live streams. This remains synchronous before the
      // sign-out future completes, so a subsequent account cannot inherit the
      // prior generation.
      try {
        FriendService.clearSharedReadCaches();
      } catch (error) {
        debugPrint(
          'AuthService.signOut: friend read-cache cleanup failed '
          '(${error.runtimeType}). Sign-out will continue.',
        );
      }
      // Drop the cached current-profile/entitlement streams so the next
      // account never inherits the previous user's replayed snapshots.
      ProfileService.resetCurrentProfileCache();
      EntitlementService.resetCache();
    }
  }

  Future<void> _clearActiveVoiceSessionBestEffort({
    required bool canLeaveRoom,
  }) async {
    try {
      final voice = VoiceCallService.instance;
      final session =
          _injectedActiveVoiceSessionReader?.call() ??
          (
            directCallId: voice.directCallId,
            isActive:
                voice.roomId != null ||
                voice.status != VoiceCallStatus.disconnected,
            isRoomSession: voice.isRoomSession,
            roomId: voice.roomId,
          );
      if (!session.isActive) return;

      // VoiceCallService.disconnect clears its local room, microphone and
      // identity fields synchronously before awaiting LiveKit disposal. Start
      // it first so even a stalled network teardown cannot leave audio alive
      // while the remaining account cleanup runs.
      final disconnect =
          _injectedDisconnectActiveVoice ??
          () => voice.disconnect(playSound: false);
      final pending = <Future<void>>[
        disconnect().timeout(_bestEffortCleanupTimeout),
      ];

      final roomId = canLeaveRoom && session.isRoomSession
          ? session.roomId
          : null;
      if (roomId != null && roomId.isNotEmpty) {
        final leave =
            _injectedLeaveActiveRoom ??
            (roomId) => RoomService().leaveRoom(roomId);
        pending.add(leave(roomId).timeout(_bestEffortCleanupTimeout));
      }
      final directCallId = canLeaveRoom ? session.directCallId : null;
      if (directCallId != null && directCallId.isNotEmpty) {
        final endCall =
            _injectedEndActiveDirectCall ??
            (callId) => DirectCallService(auth: _firebaseAuth).end(callId);
        pending.add(endCall(directCallId).timeout(_bestEffortCleanupTimeout));
      }

      await Future.wait(pending);
    } on TimeoutException {
      debugPrint(
        'AuthService.signOut: active voice cleanup exceeded the bounded '
        'window. Local audio was disconnected and sign-out will continue.',
      );
    } catch (error) {
      debugPrint(
        'AuthService.signOut: active voice cleanup failed '
        '(${error.runtimeType}). Sign-out will continue.',
      );
    }
  }

  Future<void> _unregisterDeviceTokenBestEffort() async {
    try {
      // Resolved inside the guard on purpose: reaching
      // PushNotificationService.instance builds the singleton, which touches
      // the FirebaseAuth and Messaging singletons.
      final unregister =
          _injectedUnregisterDeviceToken ??
          PushNotificationService.instance.unregisterCurrentDevice;
      await unregister().timeout(_bestEffortCleanupTimeout);
    } on TimeoutException {
      debugPrint(
        'AuthService.signOut: device-token cleanup exceeded the bounded '
        'window. Sign-out will continue; push identity remains epoch-blocked '
        'and the next binding must rotate its token.',
      );
    } catch (error) {
      debugPrint(
        'AuthService.signOut: could not unregister this device for push '
        '(${error.runtimeType}). The previous account may keep receiving '
        'push notifications here until the token is refreshed or '
        'invalidated.',
      );
    }
  }

  Future<void> _setOfflineBestEffort(String userId) async {
    try {
      await (_injectedPresenceService ?? PresenceService())
          .setOfflineForUser(userId)
          .timeout(_bestEffortCleanupTimeout);
    } on TimeoutException {
      debugPrint(
        'AuthService.signOut: presence cleanup exceeded the bounded window. '
        'Sign-out will continue; presence will converge on the next session.',
      );
    } catch (error) {
      debugPrint(
        'AuthService.signOut: could not mark the account offline '
        '(${error.runtimeType}). Friends may still see it as Online until '
        'the next sign-in sets presence again.',
      );
    }
  }

  Future<void> _clearLocalSensitiveDataBestEffort(String userId) async {
    try {
      final clear = _injectedClearLocalSensitiveData ?? _clearLocalUserData;
      await clear(userId).timeout(_bestEffortCleanupTimeout);
    } on TimeoutException {
      debugPrint(
        'AuthService.signOut: local private-data cleanup exceeded the '
        'bounded window. Sign-out will continue.',
      );
    } catch (error) {
      debugPrint(
        'AuthService.signOut: local private-data cleanup failed '
        '(${error.runtimeType}). Sign-out will continue.',
      );
    }
  }

  Future<void> _clearLocalUserData(String userId) => Future.wait<void>([
    MessageService.live.clearLocalSensitiveStateForUser(userId),
    OfflineVoiceMomentService.instance.clearForUser(userId),
  ]);

  Future<void> _initializeGoogleSignIn() async {
    final existingInitialization = _googleSignInInitialization;

    if (existingInitialization != null) {
      await existingInitialization;
      return;
    }

    final initialization = _googleSignIn.initialize();
    _googleSignInInitialization = initialization;

    try {
      await initialization;
    } catch (_) {
      _googleSignInInitialization = null;
      rethrow;
    }
  }

  /// Closes a pre-registered account takeover from the owner's side.
  ///
  /// Anyone can register a stranger's address with a password. When the
  /// owner then signs in with Google or Apple, Firebase gives the owner that
  /// same account — and the pre-registrant's session survives. Right after a
  /// Google/Apple sign-in, the owner's client is the one party the
  /// pre-registrant cannot silence, so it asks the server to check the
  /// account (`secureFederatedSignInV1`, functions/auth/federated_takeover.js).
  ///
  /// A RETURNING sign-in waits for the answer, up to
  /// [federatedSignInSecurityCheckTimeout]. A BRAND-NEW account is checked
  /// too, in the background: the server answers "clean" for a genuinely new
  /// account, and whether Firebase reports a takeover as new is not something
  /// the app relies on. Neither path blocks an ordinary sign-in.
  ///
  /// When the server remediates, it has revoked every refresh token of the
  /// account — this device's too — and its session epoch refuses this
  /// session's ID token for push registration. The app therefore signs out
  /// and asks the owner to sign in once more; that new session is after the
  /// epoch and nothing further happens. An answer that arrives after the
  /// sign-in returned does the same and emits on
  /// [federatedSessionSecuredLater]. No device token is passed: this device
  /// registers push only after the shell opens and rotates its token on every
  /// identity change, so there is none to keep yet.
  Future<void> _secureReturningFederatedSignIn(
    UserCredential credential,
  ) async {
    final uid = credential.user?.uid;
    if (uid == null) return;

    final check =
        _injectedFederatedSignInSecurityCheck ?? _callSecureFederatedSignIn;
    final inFlight = Future<Map<String, dynamic>>.sync(check);

    final isNewUser = credential.additionalUserInfo?.isNewUser ?? false;
    if (isNewUser) {
      unawaited(_honourLateSecurityAnswer(inFlight, uid));
      return;
    }

    final Map<String, dynamic> result;
    try {
      result = await inFlight.timeout(_federatedSignInSecurityCheckWait);
    } on TimeoutException {
      debugPrint(
        'AuthService: the post-sign-in account check is slow. Sign-in '
        'continues; a late answer is still honoured.',
      );
      unawaited(_honourLateSecurityAnswer(inFlight, uid));
      return;
    } catch (error) {
      debugPrint(
        'AuthService: the post-sign-in account check did not complete '
        '(${error.runtimeType}). Sign-in continues; the server sweep covers '
        'this account.',
      );
      return;
    }

    if (result['status'] != 'remediated') return;

    await _signOutAfterSecuredSession();
    throw const FederatedSessionSecuredException();
  }

  /// Waits for a check the sign-in no longer waits for. A "remediated"
  /// answer signs this device out — only while the same account is still
  /// signed in here — and is announced on [federatedSessionSecuredLater].
  Future<void> _honourLateSecurityAnswer(
    Future<Map<String, dynamic>> inFlight,
    String uid,
  ) async {
    final Map<String, dynamic> result;
    try {
      result = await inFlight;
    } catch (error) {
      debugPrint(
        'AuthService: the background account check did not complete '
        '(${error.runtimeType}); the server sweep covers this account.',
      );
      return;
    }
    if (result['status'] != 'remediated') return;
    if (_firebaseAuth.currentUser?.uid != uid) return;

    await _signOutAfterSecuredSession();
    _federatedSessionSecuredLater.add(null);
  }

  Future<void> _signOutAfterSecuredSession() async {
    try {
      await signOut();
    } catch (error) {
      debugPrint(
        'AuthService: sign-out after the account was secured failed '
        '(${error.runtimeType}).',
      );
    }
  }

  Future<Map<String, dynamic>> _callSecureFederatedSignIn() async {
    final response = await FirebaseFunctions.instanceFor(
      region: 'europe-west1',
    ).httpsCallable('secureFederatedSignInV1').call<Object?>();
    final data = response.data;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<void> _createSocialUserProfileIfNeeded(
    UserCredential credential, {
    required String providerName,
  }) async {
    final isNewUser = credential.additionalUserInfo?.isNewUser ?? false;

    if (!isNewUser) {
      return;
    }

    final user = credential.user;

    if (user == null) {
      throw AuthServiceException(
        'Unable to retrieve the signed-in $providerName user.',
      );
    }

    final email = user.email?.trim();

    if (email == null || email.isEmpty) {
      throw AuthServiceException(
        '$providerName did not provide an email address.',
      );
    }

    final username = _resolveUsername(user);

    final appUser = AppUser(
      uid: user.uid,
      email: email,
      username: username,
      createdAt: DateTime.now(),
    );

    try {
      await _firestoreService.createUserProfile(appUser);
    } catch (error) {
      // Firebase publishes the authenticated user before this method returns.
      // A transient Firestore failure must therefore never roll a valid
      // Google/Apple session back to signed-out: that produced the visible
      // "login for one second, then back to Login" failure for both providers.
      // AuthGate owns the idempotent, retried profile bootstrap and does not
      // reveal MainShell until it succeeds.
      debugPrint(
        'AuthService: $providerName authentication succeeded; deferred '
        'profile bootstrap after ${error.runtimeType}.',
      );
    }
  }

  Future<AppleSignInAvailability> _probeAppleProvider() async {
    final injectedProbe = _appleProviderProbe;
    if (injectedProbe != null) {
      return injectedProbe();
    }

    try {
      final apiKey = Firebase.app().options.apiKey;
      if (apiKey.isEmpty) {
        return AppleSignInAvailability.temporarilyUnavailable;
      }

      final uri = Uri.https(
        'identitytoolkit.googleapis.com',
        '/v1/accounts:createAuthUri',
        {'key': apiKey},
      );
      final continueUri = kIsWeb && Uri.base.hasScheme
          ? Uri.base.origin
          : 'https://auth.yovoice.app';
      final response = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'providerId': AppleAuthProvider.PROVIDER_ID,
              'continueUri': continueUri,
            }),
          )
          .timeout(const Duration(seconds: 6));

      return parseAppleProviderProbeResponse(
        response.statusCode,
        response.body,
      );
    } catch (_) {
      // Availability is a fail-closed UI gate. Network and malformed-response
      // failures must never turn the sign-in button on optimistically.
      return AppleSignInAvailability.temporarilyUnavailable;
    }
  }

  String _resolveUsername(User user) {
    return resolveAuthProfileName(
      displayName: user.displayName,
      email: user.email,
    );
  }

  String getErrorMessage(Object error) {
    if (error is AuthServiceException) {
      return error.message;
    }

    if (error is! FirebaseAuthException) {
      return 'An unexpected error occurred.';
    }

    switch (error.code) {
      case 'invalid-email':
        return 'The email address is invalid.';

      case 'user-disabled':
        return 'This account has been disabled.';

      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';

      case 'email-already-in-use':
        return 'An account with this email already exists.';

      case 'weak-password':
        return 'The password is too weak.';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';

      case 'network-request-failed':
        return 'No internet connection.';

      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';

      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using another sign-in method.';

      case 'popup-blocked':
        return 'The browser blocked the sign-in window. Allow pop-ups and try again.';

      case 'canceled':
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Sign-in was cancelled.';

      case 'unauthorized-domain':
        return 'This website is not authorized for sign-in.';

      default:
        return 'Authentication could not be completed. Try again.';
    }
  }
}

@visibleForTesting
AppleSignInAvailability parseAppleProviderProbeResponse(
  int statusCode,
  String responseBody,
) {
  try {
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      return AppleSignInAvailability.temporarilyUnavailable;
    }

    if (statusCode == 200) {
      final authUri = Uri.tryParse(decoded['authUri'] as String? ?? '');
      final providerId = decoded['providerId'];
      final isAppleAuthorization =
          authUri != null &&
          authUri.scheme == 'https' &&
          authUri.host == 'appleid.apple.com' &&
          providerId == AppleAuthProvider.PROVIDER_ID;

      return isAppleAuthorization
          ? AppleSignInAvailability.available
          : AppleSignInAvailability.temporarilyUnavailable;
    }

    final error = decoded['error'];
    final message = error is Map<String, dynamic>
        ? error['message'] as String? ?? ''
        : '';
    if (statusCode == 400 && message.startsWith('OPERATION_NOT_ALLOWED')) {
      return AppleSignInAvailability.notConfigured;
    }
  } catch (_) {
    // Parsed below as unavailable.
  }

  return AppleSignInAvailability.temporarilyUnavailable;
}

class AuthServiceException implements Exception {
  const AuthServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The server found that this Google/Apple sign-in inherited a password
/// account its holder never verified, ended every earlier session (this
/// device's included) and removed that password. The owner signs in once
/// more and continues normally.
class FederatedSessionSecuredException extends AuthServiceException {
  const FederatedSessionSecuredException()
    : super(
        'We secured your account and ended every earlier session, including '
        'a password sign-in that was never verified. Sign in again to '
        'continue.',
      );
}
