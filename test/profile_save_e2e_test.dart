import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';

/// END-TO-END proof of the profile media save pipeline.
///
/// Drives the REAL EditProfileScreen — real buttons, real
/// ProfileService.pickProfileImage/uploadProfileImage/updateProfile — with
/// deterministic generated test images ("YO TEST AVATAR" 800x800,
/// "YO TEST BANNER" 1600x600). Only the backends are mocks
/// (fake_cloud_firestore / firebase_auth_mocks / firebase_storage_mocks)
/// and the OS file dialog is a fake ImagePicker returning the test bytes —
/// everything between "user taps Change avatar" and "profile stream emits
/// the new URL" is production code.
///
/// What this proves: the pipeline (select → validate → pending preview →
/// Save → Storage putData → getDownloadURL → Firestore pointer →
/// shared-stream emission) is correct end to end IN CODE. What it cannot
/// prove: production-environment failures (deployed rules, App Check,
/// network) — those need the live run documented in the session report.
const String _uid = 'e2e-user';

class _ProfileReservation {
  const _ProfileReservation({
    required this.kind,
    required this.path,
    required this.contentType,
    required this.size,
  });

  final String kind;
  final String path;
  final String contentType;
  final int size;
}

/// Deterministic callable boundary for the real private-media client flow.
/// The production Functions implementation owns these transitions; this
/// test double models only its contract while MockFirebaseStorage verifies
/// the bytes and crop dimensions written by Flutter.
class _FakeProfileMediaBackend {
  _FakeProfileMediaBackend(this.storage);

  final MockFirebaseStorage storage;
  final Map<String, _ProfileReservation> reservations = {};
  final Map<String, _ProfileReservation> active = {};
  final Map<String, String> generations = {};

  Future<Map<Object?, Object?>> call(
    String callable,
    Map<String, Object?> request,
  ) async {
    switch (callable) {
      case 'reserveProfileMediaUpload':
        final kind = request['kind']! as String;
        final uploadId = request['uploadId']! as String;
        final contentType = request['contentType']! as String;
        final size = request['size']! as int;
        final extension = contentType == 'image/jpeg'
            ? 'jpg'
            : contentType == 'image/png'
            ? 'png'
            : 'webp';
        final reservation = _ProfileReservation(
          kind: kind,
          path: 'users/$_uid/profile/${kind}_$uploadId.$extension',
          contentType: contentType,
          size: size,
        );
        reservations[uploadId] = reservation;
        return {
          'schemaVersion': 1,
          'uploadId': uploadId,
          'storagePath': reservation.path,
          'expiresAtMillis': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
        };
      case 'finalizeProfileMediaUpload':
        final uploadId = request['uploadId']! as String;
        final generation = request['objectGeneration']! as String;
        final reservation = reservations[uploadId]!;
        final previous = active[reservation.kind];
        if (previous != null && previous.path != reservation.path) {
          await storage.ref(previous.path).delete();
        }
        active[reservation.kind] = reservation;
        generations[reservation.kind] = generation;
        return {
          'schemaVersion': 1,
          'userId': _uid,
          'kind': reservation.kind,
          'generation': generation,
          'contentType': reservation.contentType,
          'size': reservation.size,
        };
      case 'getProfileMediaAccess':
        final kind = request['kind']! as String;
        final current = active[kind];
        final generation = generations[kind];
        return {
          'schemaVersion': 1,
          'available': current != null,
          'expiresAtMillis': DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 80))
              .millisecondsSinceEpoch,
          if (current != null) ...{
            'url':
                'https://storage.googleapis.com/yovoice-private/'
                '${Uri.encodeComponent(current.path)}?generation=$generation',
            'generation': generation,
            'contentType': current.contentType,
            'size': current.size,
          },
        };
      default:
        throw StateError('Unexpected callable: $callable');
    }
  }
}

// ignore: must_be_immutable
class _RecordingPhotoUser extends MockUser {
  _RecordingPhotoUser({required super.uid, required super.email});

  final List<String?> photoUpdates = [];

  @override
  Future<void> updatePhotoURL(String? photoUrl) async {
    photoUpdates.add(photoUrl);
    photoURL = photoUrl;
  }
}

/// Stands in for the OS file dialog only. Everything downstream of the
/// picker is real production code.
class _FakeImagePicker extends ImagePicker {
  _FakeImagePicker(this.queue);

  final List<XFile> queue;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    if (queue.isEmpty) return null;
    return queue.removeAt(0);
  }
}

/// Renders a labeled test card and returns real encoded PNG bytes —
/// a deterministic stand-in for "an arbitrary image the user picked".
Future<Uint8List> _makeTestImage({
  required int width,
  required int height,
  required String label,
  required Color background,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = background,
  );
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 64,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width.toDouble());
  painter.paint(
    canvas,
    Offset((width - painter.width) / 2, (height - painter.height) / 2),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

UserProfile _seedProfile() => UserProfile(
  uid: _uid,
  email: 'e2e@yovoice.app',
  displayName: 'E2E Tester',
  username: 'e2e',
  bio: 'old bio',
  country: '',
  nativeLanguage: '',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  website: '',
  accountType: AccountType.personal,
  friendCount: 0,
  followerCount: 0,
  followingCount: 0,
  roomCount: 0,
  communityCount: 0,
  voiceMinutes: 0,
  messageCount: 0,
  activeDays: 0,
  momentCount: 0,
  reactionCount: 0,
  hostMinutes: 0,
  selectedTitleId: null,
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ProfileService.resetCurrentProfileCache();
    ProfileMediaService.clearAllMediaAccessCaches();
  });
  tearDown(() {
    ProfileService.resetCurrentProfileCache();
    ProfileMediaService.clearAllMediaAccessCaches();
  });

  testWidgets(
    'full save pipeline: pick avatar+banner, Save, private Storage objects '
    'exist and the shared profile emits a media revision without bearer URLs',
    (tester) async {
      // runAsync: dart:ui image encoding uses real async work that never
      // completes inside the fake-async test zone (this exact call pattern
      // hangs the suite without it).
      final avatarBytes = (await tester.runAsync(
        () => _makeTestImage(
          width: 800,
          height: 800,
          label: 'YO TEST AVATAR',
          background: const Color(0xFF7B2FF7),
        ),
      ))!;
      final bannerBytes = (await tester.runAsync(
        () => _makeTestImage(
          width: 1600,
          height: 600,
          label: 'YO TEST BANNER',
          background: const Color(0xFF53108C),
        ),
      ))!;

      final db = FakeFirebaseFirestore();
      final authUser = _RecordingPhotoUser(uid: _uid, email: 'e2e@yovoice.app');
      final auth = MockFirebaseAuth(signedIn: true, mockUser: authUser);
      final storage = MockFirebaseStorage();
      final mediaBackend = _FakeProfileMediaBackend(storage);
      var nextGeneration = 0;
      final picker = _FakeImagePicker([
        XFile.fromData(avatarBytes, name: 'test-avatar.png'),
        XFile.fromData(bannerBytes, name: 'test-banner.png'),
      ]);

      await db.collection('users').doc(_uid).set({
        'uid': _uid,
        'displayName': 'E2E Tester',
        'username': 'e2e',
        'bio': 'old bio',
      });

      final service = ProfileService(
        firestore: db,
        auth: auth,
        storage: storage,
        picker: picker,
        profileMediaService: ProfileMediaService(
          auth: auth,
          invoker: mediaBackend.call,
        ),
        profileMediaGenerationResolver: (_) async => '${++nextGeneration}',
      );

      // Pushed over a base route so Save's Navigator.pop has somewhere
      // to return to, exactly like production.
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => EditProfileScreen(
            profile: _seedProfile(),
            service: service,
            entitlements: EntitlementService(firestore: db, auth: auth),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // --- User flow: pick both images through the real buttons. Each
      // pick now routes through the REAL crop editor: picker resolves,
      // the bytes are decoded (real async codec work — hence the
      // runAsync windows), the editor opens, and "Use photo" renders the
      // final cropped JPEG. ---
      Future<void> pickThroughCropEditor(String buttonLabel) async {
        await tester.tap(find.text(buttonLabel));
        await tester.pump();
        // Let ImageCrop.decode finish on the real event loop.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Use photo'),
          findsOneWidget,
          reason: 'crop editor must open after picking ($buttonLabel)',
        );
        await tester.tap(find.text('Use photo'));
        await tester.pump();
        // Let renderCroppedJpeg finish on the real event loop.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)),
        );
        await tester.pumpAndSettle();
      }

      await pickThroughCropEditor('Change avatar');
      expect(
        find.text('Avatar ready'),
        findsOneWidget,
        reason: 'pending avatar state must appear after crop confirm',
      );

      await pickThroughCropEditor('Change banner');
      expect(find.text('Banner ready'), findsOneWidget);

      // Edit the bio through the real field. It sits below the fold in
      // the lazily-built ListView, so scroll it into existence first.
      final vibeField = find.widgetWithText(TextFormField, 'Vibe');
      await tester.scrollUntilVisible(
        vibeField,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        vibeField,
        'Linkin Park · In the End · on repeat tonight',
      );

      final bioField = find.widgetWithText(TextFormField, 'old bio');
      await tester.scrollUntilVisible(
        bioField,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(bioField, 'new e2e bio');

      // --- Save through the real button. ---
      await tester.tap(find.text('Save'));
      await tester.pump();
      // The storage mock resolves its upload future on the real event
      // loop; give it real time inside runAsync, then settle the UI.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pumpAndSettle();

      // --- PROOF 1: Storage objects physically exist. ---
      // NB: mock quirk — ref(path).listAll() works, ref().child(path)
      // .listAll() returns empty. Production code is unaffected (it never
      // lists); only these assertions read the listing.
      final avatarList = (await tester.runAsync(
        () => storage.ref('users/$_uid/profile').listAll(),
      ))!;
      final names = avatarList.items.map((r) => r.name).toList();
      expect(
        names.where((n) => n.startsWith('avatar_') && n.endsWith('.jpg')),
        hasLength(1),
        reason:
            'exactly one uploaded avatar object, timestamped jpg '
            '(the CROPPED render, not the original): $names',
      );
      expect(
        names.where((n) => n.startsWith('banner_') && n.endsWith('.jpg')),
        hasLength(1),
      );

      // The stored object is the crop editor's output: a JPEG at exactly
      // the product dimensions — 1:1 for the avatar, 16:9 for the banner.
      final avatarRef = avatarList.items.firstWhere(
        (r) => r.name.startsWith('avatar_'),
      );
      final storedAvatar = await tester.runAsync(() => avatarRef.getData());
      final decodedAvatar = img.decodeJpg(storedAvatar!)!;
      expect(decodedAvatar.width, 1024);
      expect(
        decodedAvatar.height,
        1024,
        reason: 'avatar crop output must remain exactly 1:1',
      );

      final bannerRef = avatarList.items.firstWhere(
        (r) => r.name.startsWith('banner_'),
      );
      final storedBanner = await tester.runAsync(() => bannerRef.getData());
      final decodedBanner = img.decodeJpg(storedBanner!)!;
      expect(decodedBanner.width, 1920);
      expect(
        decodedBanner.height,
        1080,
        reason: 'banner crop output must be the real 16:9 banner ratio',
      );

      // --- PROOF 2: no durable media bearer URL is copied to Firestore.
      final doc = (await tester.runAsync(
        () => db.collection('users').doc(_uid).get(),
      ))!;
      final data = doc.data()!;
      expect(data.containsKey('photoUrl'), isFalse);
      expect(data.containsKey('bannerUrl'), isFalse);
      expect(mediaBackend.active.keys, containsAll(['avatar', 'banner']));
      expect(
        data['statusMessage'],
        'Linkin Park · In the End · on repeat tonight',
      );
      expect(data['bio'], 'new e2e bio');

      // --- PROOF 3: FirebaseAuth is not used as an image bearer store. ---
      expect(authUser.photoUpdates, [null]);

      // --- PROOF 4: the shared stream every consumer (Home, Profile,
      // Settings, Creator Studio) watches emits the non-sensitive revision. ---
      final emitted = (await tester.runAsync(
        () => service.watchCurrentProfile().first,
      ))!;
      expect(emitted.photoUrl, isNull);
      expect(emitted.bannerUrl, isNull);
      expect(emitted.profileUpdatedAt, isNotNull);
      expect(
        emitted.statusMessage,
        'Linkin Park · In the End · on repeat tonight',
      );
      expect(emitted.bio, 'new e2e bio');

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replacing the avatar uses unique private grants and keeps one current '
    'Storage object',
    (tester) async {
      final first = (await tester.runAsync(
        () => _makeTestImage(
          width: 400,
          height: 400,
          label: 'FIRST',
          background: const Color(0xFF7B2FF7),
        ),
      ))!;
      final second = (await tester.runAsync(
        () => _makeTestImage(
          width: 400,
          height: 400,
          label: 'SECOND',
          background: const Color(0xFFC026FF),
        ),
      ))!;

      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _uid, email: 'e2e@yovoice.app'),
      );
      final storage = MockFirebaseStorage();
      final mediaBackend = _FakeProfileMediaBackend(storage);
      var nextGeneration = 0;
      await db.collection('users').doc(_uid).set({'uid': _uid});

      final service = ProfileService(
        firestore: db,
        auth: auth,
        storage: storage,
        picker: _FakeImagePicker([]),
        profileMediaService: ProfileMediaService(
          auth: auth,
          invoker: mediaBackend.call,
        ),
        profileMediaGenerationResolver: (_) async => '${++nextGeneration}',
      );

      final firstUpload = (await tester.runAsync(
        () => service.uploadProfileImage(
          PickedProfileImage(
            kind: ProfileImageKind.avatar,
            bytes: first,
            format: ProfileImageFormat.png,
          ),
        ),
      ))!;
      // Different millisecond timestamp for the second filename.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      final secondUpload = (await tester.runAsync(
        () => service.uploadProfileImage(
          PickedProfileImage(
            kind: ProfileImageKind.avatar,
            bytes: second,
            format: ProfileImageFormat.png,
          ),
        ),
      ))!;

      expect(
        secondUpload,
        isNot(firstUpload),
        reason:
            'every upload must mint a NEW URL — that is the '
            'cache-busting strategy',
      );

      final doc = (await tester.runAsync(
        () => db.collection('users').doc(_uid).get(),
      ))!;
      expect(doc.data()!.containsKey('photoUrl'), isFalse);

      final objects = (await tester.runAsync(
        () => storage.ref('users/$_uid/profile').listAll(),
      ))!;
      final avatars = objects.items
          .where((r) => r.name.startsWith('avatar_'))
          .toList();
      expect(
        avatars,
        hasLength(1),
        reason:
            'replaced object must be cleaned up, not orphaned: '
            '${objects.items.map((r) => r.name)}',
      );
      expect(await tester.runAsync(() => avatars.single.getData()), second);
    },
  );

  testWidgets('oversized avatar is rejected with the product error message', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _uid, email: 'e2e@yovoice.app'),
    );
    // 5MB + 1 byte of JPEG-looking data.
    final oversized = Uint8List(5 * 1024 * 1024 + 1);
    oversized[0] = 0xFF;
    oversized[1] = 0xD8;
    oversized[2] = 0xFF;

    final service = ProfileService(
      firestore: db,
      auth: auth,
      storage: MockFirebaseStorage(),
      picker: _FakeImagePicker([XFile.fromData(oversized, name: 'huge.jpg')]),
    );

    await db.collection('users').doc(_uid).set({'uid': _uid});
    await tester.pumpWidget(
      MaterialApp(
        home: EditProfileScreen(
          profile: _seedProfile(),
          service: service,
          entitlements: EntitlementService(firestore: db, auth: auth),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change avatar'));
    await tester.pumpAndSettle();

    expect(find.text('Image must be smaller than 5 MB.'), findsOneWidget);
    expect(
      find.text('Avatar ready'),
      findsNothing,
      reason: 'a rejected image must not become a pending change',
    );
  });
}
