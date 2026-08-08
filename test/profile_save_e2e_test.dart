import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/profile/data/models/user_profile.dart';
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

  setUp(ProfileService.resetCurrentProfileCache);
  tearDown(ProfileService.resetCurrentProfileCache);

  testWidgets(
    'full save pipeline: pick avatar+banner, Save, Storage object exists, '
    'Firestore fields point at it, shared profile stream emits new URLs',
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
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _uid, email: 'e2e@yovoice.app'),
      );
      final storage = MockFirebaseStorage();
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
          builder: (_) =>
              EditProfileScreen(profile: _seedProfile(), service: service),
        ),
      );
      await tester.pumpAndSettle();

      // --- User flow: pick both images through the real buttons. ---
      await tester.tap(find.text('Change avatar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Avatar ready'),
        findsOneWidget,
        reason: 'pending avatar state must appear after picking',
      );

      await tester.tap(find.text('Change banner'));
      await tester.pumpAndSettle();
      expect(find.text('Banner ready'), findsOneWidget);

      // Edit the bio through the real field. It sits below the fold in
      // the lazily-built ListView, so scroll it into existence first.
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
        names.where((n) => n.startsWith('avatar_') && n.endsWith('.png')),
        hasLength(1),
        reason: 'exactly one uploaded avatar object, timestamped png: $names',
      );
      expect(
        names.where((n) => n.startsWith('banner_') && n.endsWith('.png')),
        hasLength(1),
      );

      final avatarRef = avatarList.items.firstWhere(
        (r) => r.name.startsWith('avatar_'),
      );
      final storedAvatar = await tester.runAsync(() => avatarRef.getData());
      expect(
        storedAvatar,
        avatarBytes,
        reason: 'stored bytes must be exactly the picked image',
      );

      // --- PROOF 2: Firestore contains the URLs in the canonical fields.
      final doc = (await tester.runAsync(
        () => db.collection('users').doc(_uid).get(),
      ))!;
      final data = doc.data()!;
      expect(data['photoUrl'], isNotNull);
      expect(data['photoUrl'], contains('avatar_'));
      expect(data['bannerUrl'], isNotNull);
      expect(data['bannerUrl'], contains('banner_'));
      expect(data['bio'], 'new e2e bio');

      // --- PROOF 3: FirebaseAuth mirror was updated deliberately. ---
      expect(auth.currentUser!.photoURL, data['photoUrl']);

      // --- PROOF 4: the shared stream every consumer (Home, Profile,
      // Settings, Creator Studio) watches emits the new values. ---
      final emitted = (await tester.runAsync(
        () => service.watchCurrentProfile().first,
      ))!;
      expect(emitted.photoUrl, data['photoUrl']);
      expect(emitted.bannerUrl, data['bannerUrl']);
      expect(emitted.bio, 'new e2e bio');

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replacing the avatar deletes the old Storage object and keeps exactly '
    'one current file (cache correctness: new name, new URL)',
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
      await db.collection('users').doc(_uid).set({'uid': _uid});

      final service = ProfileService(
        firestore: db,
        auth: auth,
        storage: storage,
        picker: _FakeImagePicker([]),
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
      expect(doc.data()!['photoUrl'], secondUpload);

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
        home: EditProfileScreen(profile: _seedProfile(), service: service),
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
