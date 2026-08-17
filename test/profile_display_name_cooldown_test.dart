import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';

const _uid = 'display-name-user';

UserProfile _profile({
  DateTime? displayNameChangedAt,
  String displayName = 'Current Name',
}) => UserProfile(
  uid: _uid,
  email: 'verified@yovoice.app',
  displayName: displayName,
  username: 'current',
  bio: 'Old bio',
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
  createdAt: DateTime.utc(2026),
  displayNameChangedAt: displayNameChangedAt,
);

Future<({FakeFirebaseFirestore db, MockFirebaseAuth auth})> _backend() async {
  final db = FakeFirebaseFirestore();
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      uid: _uid,
      email: 'verified@yovoice.app',
      displayName: 'Current Name',
      isEmailVerified: true,
    ),
  );
  await db.collection('users').doc(_uid).set({
    'uid': _uid,
    'displayName': 'Current Name',
    'username': 'current',
    'bio': 'Old bio',
  });
  return (db: db, auth: auth);
}

Widget _app({
  required UserProfile profile,
  required ProfileService service,
  required EntitlementService entitlements,
  required DateTime now,
  double textScale = 1,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: EditProfileScreen(
      profile: profile,
      service: service,
      entitlements: entitlements,
      clock: () => now,
    ),
  );
}

void main() {
  group('display-name callable contract', () {
    final changedAt = DateTime.utc(2026, 8, 17, 10);
    final changedAtMs = changedAt.millisecondsSinceEpoch;
    final nextMs = changedAt
        .add(const Duration(days: 30))
        .millisecondsSinceEpoch;

    Map<String, dynamic> success({Map<String, dynamic>? extra}) => {
      'displayName': 'Canonical Name',
      'changed': true,
      'canChange': false,
      'displayNameChangedAtMs': changedAtMs,
      'nextDisplayNameChangeAtMs': nextMs,
      ...?extra,
    };

    test('accepts only the exact, internally consistent success schema', () {
      final parsed = ProfileService.parseDisplayNameResultForTesting(success());
      expect(parsed.displayName, 'Canonical Name');
      expect(
        parsed.nextDisplayNameChangeAt,
        changedAt.add(const Duration(days: 30)),
      );

      for (final malformed in <Map<String, dynamic>>[
        success(extra: {'privateRole': 'owner'}),
        success(extra: {'nextDisplayNameChangeAtMs': nextMs + 1}),
        success(extra: {'displayName': '  Padded Name  '}),
        success(extra: {'displayNameChangedAtMs': changedAtMs + 0.5}),
      ]) {
        expect(
          () => ProfileService.parseDisplayNameResultForTesting(malformed),
          throwsA(isA<DisplayNameChangeException>()),
        );
      }
    });

    test('maps only the exact email-verification reason to email copy', () {
      final verified = ProfileService.displayNameExceptionForTesting(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'hidden',
          details: const {'reason': 'email-verification-required'},
        ),
      );
      final invalidState = ProfileService.displayNameExceptionForTesting(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'hidden',
          details: const {'reason': 'display-name-state-invalid'},
        ),
      );
      expect(
        verified.failure,
        DisplayNameChangeFailure.emailVerificationRequired,
      );
      expect(invalidState.failure, DisplayNameChangeFailure.unavailable);
      expect(invalidState.message, isNot(contains('Verify your email')));

      final missingAuth = ProfileService.displayNameExceptionForTesting(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'hidden',
          details: {
            'reason': 'auth-account-missing',
            'displayName': 'Saved Name',
            'displayNameChangedAtMs': changedAtMs,
            'nextDisplayNameChangeAtMs': nextMs,
          },
        ),
      );
      expect(
        missingAuth.failure,
        DisplayNameChangeFailure.authAccountMissingAfterSave,
      );
      expect(missingAuth.canonicalDisplayName, 'Saved Name');
      expect(missingAuth.message, contains('was saved'));

      final malformedCooldown = ProfileService.displayNameExceptionForTesting(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'hidden',
          details: {
            'reason': 'display-name-cooldown',
            'nextDisplayNameChangeAtMs': nextMs + 0.5,
            'retryAfterSeconds': 1.5,
          },
        ),
      );
      expect(malformedCooldown.failure, DisplayNameChangeFailure.unavailable);
    });
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ProfileService.resetCurrentProfileCache);
  tearDown(ProfileService.resetCurrentProfileCache);

  test(
    'ordinary profile writes cannot mutate the canonical display name',
    () async {
      final backend = await _backend();
      final service = ProfileService(firestore: backend.db, auth: backend.auth);

      await service.updateProfile(
        username: 'new-username',
        bio: 'Updated independently',
        country: 'NL',
        nativeLanguage: 'Polish',
        spokenLanguages: const ['Polish', 'English'],
        learningLanguages: const ['Dutch'],
        website: 'https://example.test',
        accountType: AccountType.personal,
      );

      final stored = await backend.db.collection('users').doc(_uid).get();
      expect(stored.data()!['displayName'], 'Current Name');
      expect(stored.data()!['username'], 'new-username');
      expect(backend.auth.currentUser!.displayName, 'Current Name');
    },
  );

  testWidgets('changed display name uses the callable before profile write', (
    tester,
  ) async {
    final backend = await _backend();
    final calls = <String>[];
    final changedAt = DateTime.utc(2026, 8, 17, 10);
    final next = changedAt.add(const Duration(days: 30));
    final service = ProfileService(
      firestore: backend.db,
      auth: backend.auth,
      displayNameMutationInvoker: (displayName) async {
        calls.add(displayName);
        await backend.db.collection('users').doc(_uid).update({
          'displayName': displayName.trim(),
        });
        return DisplayNameChangeResult(
          displayName: displayName.trim(),
          changed: true,
          canChange: false,
          displayNameChangedAt: changedAt,
          nextDisplayNameChangeAt: next,
        );
      },
    );

    await tester.pumpWidget(
      _app(
        profile: _profile(),
        service: service,
        entitlements: EntitlementService(
          firestore: backend.db,
          auth: backend.auth,
        ),
        now: DateTime.utc(2026, 8, 17, 9),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current Name'),
      '  New Voice  ',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(calls, ['New Voice']);
    final stored = await backend.db.collection('users').doc(_uid).get();
    expect(stored.data()!['displayName'], 'New Voice');
    expect(
      backend.auth.currentUser!.displayName,
      'Current Name',
      reason: 'the client must never mirror/bypass the server in Auth',
    );
  });

  testWidgets('legacy surrounding whitespace is canonicalized by the server', (
    tester,
  ) async {
    final backend = await _backend();
    await backend.db.collection('users').doc(_uid).update({
      'displayName': '  New Voice  ',
    });
    final calls = <String>[];
    final changedAt = DateTime.utc(2026, 8, 17);
    final service = ProfileService(
      firestore: backend.db,
      auth: backend.auth,
      displayNameMutationInvoker: (name) async {
        calls.add(name);
        await backend.db.collection('users').doc(_uid).update({
          'displayName': name,
        });
        return DisplayNameChangeResult(
          displayName: name,
          changed: true,
          canChange: false,
          displayNameChangedAt: changedAt,
          nextDisplayNameChangeAt: changedAt.add(const Duration(days: 30)),
        );
      },
    );
    await tester.pumpWidget(
      _app(
        profile: _profile(displayName: '  New Voice  '),
        service: service,
        entitlements: EntitlementService(
          firestore: backend.db,
          auth: backend.auth,
        ),
        now: DateTime.utc(2026, 8, 16),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(calls, ['New Voice']);
    final stored = await backend.db.collection('users').doc(_uid).get();
    expect(stored.data()!['displayName'], 'New Voice');
  });

  testWidgets(
    'active cooldown is read-only, announces exact retry time, and still '
    'allows other profile changes',
    (tester) async {
      final now = DateTime.utc(2026, 8, 17, 12);
      final changedAt = now.subtract(const Duration(days: 5));
      final backend = await _backend();
      var callableCount = 0;
      final service = ProfileService(
        firestore: backend.db,
        auth: backend.auth,
        displayNameMutationInvoker: (displayName) async {
          callableCount++;
          throw StateError('the unchanged locked name must not be submitted');
        },
      );

      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          profile: _profile(displayNameChangedAt: changedAt),
          service: service,
          entitlements: EntitlementService(
            firestore: backend.db,
            auth: backend.auth,
          ),
          now: now,
        ),
      );
      await tester.pumpAndSettle();

      final displayNameField = find.widgetWithText(
        TextFormField,
        'Current Name',
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: displayNameField,
                matching: find.byType(EditableText),
              ),
            )
            .readOnly,
        isTrue,
      );
      expect(find.textContaining('You can change this again on'), findsOne);
      expect(
        find.bySemanticsLabel(
          RegExp(r'Display name\. You can change this again on'),
        ),
        findsOneWidget,
      );

      final bio = find.widgetWithText(TextFormField, 'Old bio');
      await tester.scrollUntilVisible(
        bio,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(bio, 'New bio during cooldown');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(callableCount, 0);
      final stored = await backend.db.collection('users').doc(_uid).get();
      expect(stored.data()!['displayName'], 'Current Name');
      expect(stored.data()!['bio'], 'New bio during cooldown');
      semantics.dispose();
    },
  );

  testWidgets(
    'server cooldown overrides stale eligible UI with friendly copy',
    (tester) async {
      final backend = await _backend();
      final retryAt = DateTime.utc(2026, 9, 1, 8, 30);
      final service = ProfileService(
        firestore: backend.db,
        auth: backend.auth,
        displayNameMutationInvoker: (_) async =>
            throw DisplayNameChangeException(
              DisplayNameChangeFailure.cooldown,
              'Your display name can only be changed once every 30 days.',
              nextDisplayNameChangeAt: retryAt,
            ),
      );
      await tester.pumpWidget(
        _app(
          profile: _profile(),
          service: service,
          entitlements: EntitlementService(
            firestore: backend.db,
            auth: backend.auth,
          ),
          now: DateTime.utc(2026, 8, 17),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current Name'),
        'Another Name',
      );
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(
        find.text('Your display name can only be changed once every 30 days.'),
        findsOneWidget,
      );
      final canonicalField = find.widgetWithText(TextFormField, 'Current Name');
      expect(canonicalField, findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: canonicalField,
                matching: find.byType(EditableText),
              ),
            )
            .readOnly,
        isTrue,
      );

      final bio = find.widgetWithText(TextFormField, 'Bio');
      await tester.scrollUntilVisible(
        bio,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(bio, 'Bio saved after stale cooldown conflict');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final stored = await backend.db.collection('users').doc(_uid).get();
      expect(stored.data()!['bio'], 'Bio saved after stale cooldown conflict');
    },
  );

  testWidgets(
    'committed name with pending Auth sync retries idempotently without '
    'opening another edit window',
    (tester) async {
      final backend = await _backend();
      final changedAt = DateTime.utc(2026, 8, 17, 10);
      final next = changedAt.add(const Duration(days: 30));
      var calls = 0;
      final service = ProfileService(
        firestore: backend.db,
        auth: backend.auth,
        displayNameMutationInvoker: (name) async {
          calls++;
          if (calls == 1) {
            throw DisplayNameChangeException(
              DisplayNameChangeFailure.authSyncPending,
              'Your display name was saved, but account sync is still finishing. Press Save to retry.',
              canonicalDisplayName: 'New Voice',
              displayNameChangedAt: changedAt,
              nextDisplayNameChangeAt: next,
            );
          }
          return DisplayNameChangeResult(
            displayName: 'New Voice',
            changed: false,
            canChange: false,
            displayNameChangedAt: changedAt,
            nextDisplayNameChangeAt: next,
          );
        },
      );
      await tester.pumpWidget(
        _app(
          profile: _profile(),
          service: service,
          entitlements: EntitlementService(
            firestore: backend.db,
            auth: backend.auth,
          ),
          now: DateTime.utc(2026, 8, 17, 9),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current Name'),
        'New Voice',
      );
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(calls, 1);
      expect(
        find.text('Name saved. Press Save again to finish account sync.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('account sync is still finishing'),
        findsOneWidget,
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(calls, 2, reason: 'same-name retry must reach the server');
    },
  );

  testWidgets('committed name stays canonical when the Auth account is missing', (
    tester,
  ) async {
    final backend = await _backend();
    final changedAt = DateTime.utc(2026, 8, 17, 10);
    final next = changedAt.add(const Duration(days: 30));
    final service = ProfileService(
      firestore: backend.db,
      auth: backend.auth,
      displayNameMutationInvoker: (_) async => throw DisplayNameChangeException(
        DisplayNameChangeFailure.authAccountMissingAfterSave,
        'Your profile name was saved, but the sign-in account could not be found. Please sign in again.',
        canonicalDisplayName: 'Saved Canonical Name',
        displayNameChangedAt: changedAt,
        nextDisplayNameChangeAt: next,
      ),
    );
    await tester.pumpWidget(
      _app(
        profile: _profile(),
        service: service,
        entitlements: EntitlementService(
          firestore: backend.db,
          auth: backend.auth,
        ),
        now: DateTime.utc(2026, 8, 17, 9),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current Name'),
      'Saved Canonical Name',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.textContaining('profile name was saved'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'Saved Canonical Name'),
      findsOneWidget,
    );
    expect(
      find.text('Name saved. Press Save again to finish account sync.'),
      findsNothing,
    );
  });

  testWidgets('unverified-email rejection is actionable', (tester) async {
    final backend = await _backend();
    final service = ProfileService(
      firestore: backend.db,
      auth: backend.auth,
      displayNameMutationInvoker: (_) async =>
          throw const DisplayNameChangeException(
            DisplayNameChangeFailure.emailVerificationRequired,
            'Verify your email address before changing your display name.',
          ),
    );
    await tester.pumpWidget(
      _app(
        profile: _profile(),
        service: service,
        entitlements: EntitlementService(
          firestore: backend.db,
          auth: backend.auth,
        ),
        now: DateTime.utc(2026, 8, 17),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current Name'),
      'Verified Voice',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(
      find.text('Verify your email address before changing your display name.'),
      findsOneWidget,
    );
    final stored = await backend.db.collection('users').doc(_uid).get();
    expect(stored.data()!['displayName'], 'Current Name');
  });

  testWidgets('rate-limit rejection asks the member to wait', (tester) async {
    final backend = await _backend();
    final service = ProfileService(
      firestore: backend.db,
      auth: backend.auth,
      displayNameMutationInvoker: (_) async =>
          throw const DisplayNameChangeException(
            DisplayNameChangeFailure.tooManyAttempts,
            'Too many display-name attempts. Wait a minute and try again.',
          ),
    );
    await tester.pumpWidget(
      _app(
        profile: _profile(),
        service: service,
        entitlements: EntitlementService(
          firestore: backend.db,
          auth: backend.auth,
        ),
        now: DateTime.utc(2026, 8, 17),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current Name'),
      'Rate Limited Voice',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(
      find.text('Too many display-name attempts. Wait a minute and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('Unicode line separators are rejected before submission', (
    tester,
  ) async {
    final backend = await _backend();
    var calls = 0;
    final service = ProfileService(
      firestore: backend.db,
      auth: backend.auth,
      displayNameMutationInvoker: (_) async {
        calls++;
        throw StateError('invalid UI value must not be submitted');
      },
    );
    await tester.pumpWidget(
      _app(
        profile: _profile(),
        service: service,
        entitlements: EntitlementService(
          firestore: backend.db,
          auth: backend.auth,
        ),
        now: DateTime.utc(2026, 8, 17),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current Name'),
      'Bad\u2028Name',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Remove line breaks or control characters.'), findsOne);
    expect(calls, 0);
  });

  testWidgets('display-name editor stays responsive at product breakpoints', (
    tester,
  ) async {
    final backend = await _backend();
    final now = DateTime.utc(2026, 8, 17);
    final service = ProfileService(
      firestore: backend.db,
      auth: backend.auth,
      displayNameMutationInvoker: (_) async => throw StateError('unused'),
    );

    for (final width in <double>[320, 390, 768, 1100, 1440]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      await tester.pumpWidget(
        _app(
          profile: _profile(
            displayNameChangedAt: now.subtract(const Duration(days: 1)),
          ),
          service: service,
          entitlements: EntitlementService(
            firestore: backend.db,
            auth: backend.auth,
          ),
          now: now,
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit profile'), findsOneWidget, reason: 'width $width');
      expect(
        find.textContaining('You can change this again on'),
        findsOneWidget,
        reason: 'width $width',
      );
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.textContaining('You can change this again on'),
            )
            .didExceedMaxLines,
        isFalse,
        reason: 'cooldown date must not be clipped at width $width',
      );
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });
}
