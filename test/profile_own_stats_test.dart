import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'voice_moment_test_doubles.dart';

/// The own profile's stats row counts the person's real, current servers
/// (the same `watchMyServers()` list the page renders), never the
/// achievement engine's ever-growing `communityCount`, and it shows no
/// Moments counter until a live count exists (`momentCount` never falls).
MockFirebaseAuth _auth() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: 'me', email: 'me@yovoice.app', isEmailVerified: true),
);

PublicIdentityRepository _identity() => PublicIdentityRepository(
  auth: _auth(),
  fetchOverride: (uids) async => {
    for (final uid in uids) uid: const {'role': 'user'},
  },
  flushDelay: const Duration(milliseconds: 1),
);

UserProfile _profile() => UserProfile(
  uid: 'me',
  email: 'maja@yovoice.app',
  displayName: 'Maja Kowalska',
  username: 'maja.kowalska',
  bio: '',
  country: '',
  nativeLanguage: '',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  website: '',
  accountType: AccountType.personal,
  friendCount: 5,
  followerCount: 0,
  followingCount: 0,
  roomCount: 0,
  // Deliberately out of step with the real list below.
  communityCount: 7,
  voiceMinutes: 0,
  messageCount: 0,
  activeDays: 0,
  momentCount: 27,
  reactionCount: 0,
  hostMinutes: 0,
  selectedTitleId: null,
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: DateTime(2026),
);

const _servers = <Server>[
  Server(
    id: 's1',
    name: 'Nocne Rozmowy',
    description: '',
    ownerId: 'me',
    type: ServerType.podcast,
    privacy: ServerPrivacy.public,
    memberCount: 128,
  ),
  Server(
    id: 's2',
    name: 'Ekipa z liceum',
    description: '',
    ownerId: 'ola',
    type: ServerType.friends,
    privacy: ServerPrivacy.private,
    memberCount: 9,
  ),
  Server(
    id: 's3',
    name: 'Kraków Muzycznie',
    description: '',
    ownerId: 'kuba',
    type: ServerType.community,
    privacy: ServerPrivacy.public,
    memberCount: 2140,
  ),
];

void main() {
  late PublicIdentityRepository originalIdentity;
  const audioChannels = <MethodChannel>[
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
    MethodChannel('xyz.luan/audioplayers.global/events'),
  ];

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in audioChannels) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in audioChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = _identity();
    ProfileMediaService.clearAllMediaAccessCaches();
  });

  tearDown(() => PublicIdentityRepository.instance = originalIdentity);

  Future<void> pump(
    WidgetTester tester,
    Size size, {
    bool loading = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _auth();
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: const Locale('pl'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ProfileScreenView(
          profile: _profile(),
          servers: loading ? const [] : _servers,
          serversLoading: loading,
          onEdit: () {},
          onAchievements: () {},
          onOpenServer: (_) {},
          showSuperAdminActivation: false,
          isActivatingSuperAdmin: false,
          currentRole: 'user',
          onActivateSuperAdmin: () async {},
          onLogout: () async {},
          identityRepository: _identity(),
          mediaService: ProfileMediaService(
            auth: auth,
            invoker: (_, _) async => {
              'schemaVersion': 1,
              'available': false,
              'expiresAtMillis': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .millisecondsSinceEpoch,
            },
          ),
          creatorPinnedPostService: CreatorPinnedPostService(
            firestore: db,
            auth: auth,
            mutationInvoker: (_) async => const {},
            voiceMomentReadService: VoiceMomentReadService(
              viewInvoker: fakeVoiceMomentViewInvoker(
                firestore: db,
                viewerUid: 'me',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final serversStat = find.byKey(const ValueKey('profile-stat-servers'));

  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    testWidgets('${size.width.toInt()} px: Serwery counts the real server '
        'list, and no Moments counter is shown', (tester) async {
      await pump(tester, size);
      expect(serversStat, findsOneWidget);
      expect(
        find.descendant(of: serversStat, matching: find.text('3')),
        findsOneWidget,
        reason: 'the page lists 3 servers',
      );
      expect(
        find.descendant(of: serversStat, matching: find.text('7')),
        findsNothing,
        reason: 'communityCount is an achievement counter, not the list',
      );
      expect(find.byKey(const ValueKey('profile-stat-moments')), findsNothing);
      expect(
        find.byKey(const ValueKey('profile-stat-friends')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('while the server list loads, no made-up Serwery 0 is shown', (
    tester,
  ) async {
    await pump(tester, const Size(390, 844), loading: true);
    expect(serversStat, findsNothing);
    expect(find.byKey(const ValueKey('profile-stat-friends')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
