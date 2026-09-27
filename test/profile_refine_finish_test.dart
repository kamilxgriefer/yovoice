// Refine-look batch B8 (spec §8.5 and the §10 profile_header handoff): the
// profile's finish — one CTA lift, R7 neutral secondaries, R2 blocks with the
// stats band, the R14 pinned bead that lights only while it plays, the wide
// measure, the brand avatar, high contrast and the error state.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/achievements/data/services/achievement_service.dart';
import 'package:yovoice/features/creator/data/models/creator_pinned_post.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/creator/presentation/widgets/creator_pinned_moment_card.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_journey_card.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_layout.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_vibe_headline.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import 'voice_moment_test_doubles.dart';

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

ProfileMediaService _media(MockFirebaseAuth auth) => ProfileMediaService(
  auth: auth,
  invoker: (_, _) async => {
    'schemaVersion': 1,
    'available': false,
    'expiresAtMillis': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch,
  },
);

UserProfile _profile({AccountType accountType = AccountType.creator}) =>
    UserProfile(
      uid: 'me',
      email: 'maja@yovoice.app',
      displayName: 'Maja Kowalska',
      username: 'maja.kowalska',
      bio: 'Poranne Momenty.',
      statusMessage: 'Muzyka + nocne rozmowy',
      country: 'Polska',
      nativeLanguage: 'polski',
      spokenLanguages: const ['angielski'],
      learningLanguages: const [],
      photoUrl: null,
      bannerUrl: null,
      website: '',
      accountType: accountType,
      creatorAudienceVisible: true,
      friendCount: 148,
      followerCount: 1840,
      followingCount: 212,
      roomCount: 1,
      communityCount: 3,
      voiceMinutes: 1265,
      messageCount: 842,
      activeDays: 64,
      momentCount: 27,
      reactionCount: 310,
      hostMinutes: 420,
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
];

class _FakeAudioPlayer implements audio.AudioPlayer {
  int playCount = 0;
  int pauseCount = 0;

  @override
  Stream<void> get onPlayerComplete => const Stream<void>.empty();

  @override
  Future<void> play(
    audio.Source source, {
    double? volume,
    double? balance,
    audio.AudioContext? ctx,
    Duration? position,
    audio.PlayerMode? mode,
  }) async => playCount += 1;

  @override
  Future<void> pause() async => pauseCount += 1;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<CreatorPinnedPostService> _pinned(
  FakeFirebaseFirestore db,
  MockFirebaseAuth auth,
) async {
  final createdAt = DateTime.now().subtract(const Duration(hours: 3));
  await db.collection('voiceMoments').doc('pinned-me').set({
    'id': 'pinned-me',
    'schemaVersion': 2,
    'status': 'published',
    'isDeleted': false,
    'authorId': 'me',
    'authorName': 'Maja',
    'authorPhotoUrl': null,
    'caption': 'Poranek nad Wisłą',
    'mediaGeneration': '1700000000000001',
    'mediaContentType': 'audio/mp4',
    'mediaSize': 4096,
    'durationSeconds': 42,
    'likeCount': 18,
    'commentCount': 4,
    'isPublished': true,
    'createdAt': Timestamp.fromDate(createdAt),
    'expiresAt': Timestamp.fromDate(createdAt.add(const Duration(hours: 24))),
  });
  await db.collection('creatorPinnedPosts').doc('me').set({
    'schemaVersion': 1,
    'creatorId': 'me',
    'momentId': 'pinned-me',
    'pinnedAt': Timestamp.fromDate(DateTime.now()),
    'updatedAt': Timestamp.fromDate(DateTime.now()),
  });
  return CreatorPinnedPostService(
    firestore: db,
    auth: auth,
    mutationInvoker: (_) async => const {},
    voiceMomentReadService: VoiceMomentReadService(
      viewInvoker: fakeVoiceMomentViewInvoker(firestore: db, viewerUid: 'me'),
    ),
  );
}

Widget _app(
  Widget home, {
  ThemeData? theme,
  bool highContrast = false,
  bool disableAnimations = true,
  bool accessibleNavigation = false,
  TextScaler? textScaler,
}) => RepaintBoundary(
  key: _shot,
  child: MaterialApp(
    theme: theme ?? AppTheme.darkTheme,
    locale: const Locale('pl'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: disableAnimations,
        accessibleNavigation: accessibleNavigation,
        highContrast: highContrast,
        textScaler: textScaler,
      ),
      child: child!,
    ),
    home: home,
  ),
);

/// Wraps every pumped app, so a test can read the pixels it painted.
final _shot = GlobalKey();

/// One pixel of the last painted frame (the app is at the origin, 1 dpr).
Future<Color> _pixel(WidgetTester tester, Offset at) async {
  late Color color;
  await tester.runAsync(() async {
    final boundary =
        _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final data = (await image.toByteData())!;
      final index = (at.dy.floor() * image.width + at.dx.floor()) * 4;
      color = Color.fromARGB(
        data.getUint8(index + 3),
        data.getUint8(index),
        data.getUint8(index + 1),
        data.getUint8(index + 2),
      );
    } finally {
      image.dispose();
    }
  });
  return color;
}

/// Whether [color] is (antialias-free) the same as [expected].
Matcher _samePixel(Color expected) => predicate<Color>(
  (color) =>
      ((color.r - expected.r).abs() * 255) <= 2 &&
      ((color.g - expected.g).abs() * 255) <= 2 &&
      ((color.b - expected.b).abs() * 255) <= 2,
  'the pixel $expected',
);

/// Keyboard focus on the focusable control that owns [target], shown the
/// way a Tab press shows it.
Future<void> _focus(WidgetTester tester, Finder target) async {
  final manager = tester.binding.focusManager;
  manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  addTearDown(
    () => manager.highlightStrategy = FocusHighlightStrategy.automatic,
  );
  Focus.of(tester.element(target)).requestFocus();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// A pinned-post service that serves exactly the pins a test pushes.
class _ControlledPinService extends CreatorPinnedPostService {
  _ControlledPinService({required super.firestore, required super.auth});

  final StreamController<PinnedVoiceMoment?> pins =
      StreamController<PinnedVoiceMoment?>.broadcast();

  @override
  Stream<PinnedVoiceMoment?> watchPinnedPostForCreator(String creatorId) =>
      pins.stream;
}

PinnedVoiceMoment _pin(String id, {bool media = true}) {
  final createdAt = DateTime.now().subtract(const Duration(hours: 3));
  return PinnedVoiceMoment(
    pin: CreatorPinnedPost(creatorId: 'me', momentId: id, pinnedAt: createdAt),
    moment: VoiceMoment(
      id: id,
      authorId: 'me',
      authorName: 'Maja',
      authorPhotoUrl: null,
      caption: 'Poranek nad Wisłą',
      // A legacy Moment with no media reference cannot be played.
      audioUrl: null,
      durationSeconds: 42,
      likeCount: 18,
      commentCount: 4,
      isPublished: true,
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(hours: 24)),
      schemaVersion: 2,
      status: 'published',
      hasAuthorizedMedia: media,
    ),
  );
}

/// A player whose first [failures] plays throw, like a revoked grant.
class _FlakyAudioPlayer extends _FakeAudioPlayer {
  int failures = 1;

  @override
  Future<void> play(
    audio.Source source, {
    double? volume,
    double? balance,
    audio.AudioContext? ctx,
    Duration? position,
    audio.PlayerMode? mode,
  }) async {
    if (failures > 0) {
      failures -= 1;
      throw StateError('playback failed');
    }
    playCount += 1;
  }
}

/// The signed-in profile stream as Firestore behaves: the first listener
/// errors and stays dead; asking again (after the cache is dropped) serves
/// a live one.
class _FlakyProfileService extends ProfileService {
  _FlakyProfileService({
    required this.profile,
    required super.firestore,
    required super.auth,
  });

  final UserProfile profile;
  int watches = 0;

  @override
  Stream<UserProfile> watchCurrentProfile() {
    watches += 1;
    return watches == 1
        ? Stream<UserProfile>.error(StateError('permission-denied'))
        : Stream<UserProfile>.value(profile);
  }

  @override
  Future<void> ensureProfile() async {}
}

class _QuietAchievements extends AchievementService {
  _QuietAchievements({required super.firestore, required super.auth});

  @override
  Future<void> refreshUnlockedTitles() async {}
}

class _Servers implements ServerRepository {
  int watches = 0;

  @override
  Stream<List<Server>> watchMyServers() {
    watches += 1;
    return Stream<List<Server>>.value(_servers);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpOwn(
    WidgetTester tester,
    Size size, {
    ThemeData? theme,
    bool highContrast = false,
    bool disableAnimations = true,
    bool accessibleNavigation = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _auth();
    final db = FakeFirebaseFirestore();
    final pinned = await tester.runAsync(() => _pinned(db, auth));
    await tester.pumpWidget(
      _app(
        ProfileScreenView(
          profile: _profile(),
          servers: _servers,
          serversLoading: false,
          onEdit: () {},
          onAchievements: () {},
          onOpenServer: (_) {},
          showSuperAdminActivation: false,
          isActivatingSuperAdmin: false,
          currentRole: 'user',
          onActivateSuperAdmin: () async {},
          onLogout: () async {},
          identityRepository: _identity(),
          mediaService: _media(auth),
          creatorPinnedPostService: pinned,
          pinnedPlayerFactory: _FakeAudioPlayer.new,
        ),
        theme: theme,
        highContrast: highContrast,
        disableAnimations: disableAnimations,
        accessibleNavigation: accessibleNavigation,
      ),
    );
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);
  }

  group('own profile actions', () {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      testWidgets('${size.width.toInt()} px: Edytuj profil is the one lifted '
          'gradient CTA; Nagrody and More are neutral glass', (tester) async {
        await pumpOwn(tester, size);
        final palette = AppPalette.dark;

        final edit = find.byKey(const ValueKey('profile-edit-button'));
        expect(tester.widget(edit), isA<YoGradientFilledButton>());
        final cta = tester.widget<YoGradientFilledButton>(edit);
        expect(cta.emphasis, YoActionEmphasis.lifted);
        expect(cta.shape, ProfileActionBar.shape);
        // It is still a FilledButton inside, and the page has only one.
        expect(
          find.descendant(of: edit, matching: find.byType(FilledButton)),
          findsOneWidget,
        );
        expect(find.byType(YoGradientFilledButton), findsOneWidget);
        expect(tester.getSize(edit).height, ProfileActionBar.buttonHeight);

        final awards = tester.widget<OutlinedButton>(
          find.byKey(const ValueKey('profile-awards-button')),
        );
        expect(
          awards.style!.backgroundColor!.resolve(<WidgetState>{}),
          AppFinish.glass(palette),
        );
        expect(
          awards.style!.side!.resolve(<WidgetState>{})!.color,
          palette.hairlineControl,
        );
        final more = tester.widget<IconButton>(
          find.descendant(
            of: find.byKey(const ValueKey('profile-more-button')),
            matching: find.byType(IconButton),
          ),
        );
        expect(
          more.style!.backgroundColor!.resolve(<WidgetState>{}),
          AppFinish.glass(palette),
        );
        final moreSize = tester.getSize(
          find.byKey(const ValueKey('profile-more-button')),
        );
        expect(moreSize.width, greaterThanOrEqualTo(44));
        expect(moreSize.height, greaterThanOrEqualTo(44));
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('the stats band carries the block finish with 12 w600 labels '
      'that are never scaled down', (tester) async {
    await pumpOwn(tester, const Size(390, 844));
    final palette = AppPalette.dark;
    final band = find.byKey(const ValueKey('profile-header-stats'));
    final decoration = tester.widget<Container>(band).decoration!;
    expect(decoration, AppFinish.block(palette));
    expect(
      find.descendant(of: band, matching: find.byType(FittedBox)),
      findsNothing,
    );
    final label = tester.widget<Text>(
      find.descendant(of: band, matching: find.text('Obserwujący')),
    );
    expect(label.style!.fontSize, 12);
    expect(label.style!.fontWeight, FontWeight.w600);
    expect(tester.takeException(), isNull);
  });

  testWidgets('labels that would not fit fold four counters two per line, '
      'then stack, instead of shrinking', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const stats = [
      ProfileStat(value: 3, label: 'Serwery', keyName: 'a'),
      ProfileStat(value: 148, label: 'Znajomi', keyName: 'b'),
      ProfileStat(value: 1840, label: 'Obserwujący', keyName: 'c'),
      ProfileStat(value: 212, label: 'Obserwowani', keyName: 'd'),
    ];
    Rect rect(String name) =>
        tester.getRect(find.byKey(ValueKey('profile-stat-$name')));
    // The test font draws every glyph 12 px wide at 12 px, so an
    // 11-letter label needs 132 + 2 × 8 px of air: 148 px. The four
    // counters need 100 + 100 + 148 + 148 = 496 px on one line.
    for (final (width, perLine) in const [
      (1000.0, 4), // 964 px: one line, evenly spaced
      (340.0, 2), // 304 px: not one line, but 152 px halves hold 148
      (240.0, 1), // 102 px halves cannot: one per line
    ]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(18),
              child: ProfileStatsRow(stats: stats),
            ),
          ),
        ),
      );
      final a = rect('a'), b = rect('b'), c = rect('c'), d = rect('d');
      switch (perLine) {
        case 4:
          expect(d.top, a.top, reason: '$width one line');
          // Evenly spaced natural-width cells: equal gaps between them.
          final gap = b.left - a.right;
          expect(gap, greaterThan(0));
          expect(c.left - b.right, moreOrLessEquals(gap, epsilon: 1));
          expect(d.left - c.right, moreOrLessEquals(gap, epsilon: 1));
        case 2:
          expect(b.top, a.top, reason: '$width two per line');
          expect(c.top, greaterThan(a.bottom - 1), reason: '$width');
          expect(d.top, c.top, reason: '$width');
          expect(c.left, a.left, reason: '$width');
        default:
          expect(b.top, greaterThan(a.bottom - 1), reason: '$width stacked');
          expect(d.top, greaterThan(c.bottom - 1), reason: '$width stacked');
      }
      for (final r in [a, b, c, d]) {
        expect(r.height, greaterThanOrEqualTo(44), reason: '$width target');
      }
      expect(find.byType(FittedBox), findsNothing);
      expect(tester.takeException(), isNull, reason: '$width');
    }
  });

  testWidgets('the hero avatar takes the brand finish; the ring stays the '
      'borderStrong cut-out', (tester) async {
    await pumpOwn(tester, const Size(390, 844));
    final ring = find.byKey(const Key('profile-header-avatar'));
    final avatar = tester.widget<UserAvatar>(
      find.descendant(of: ring, matching: find.byType(UserAvatar)),
    );
    expect(avatar.finish, UserAvatarFinish.brand);
    expect(avatar.backgroundColor, UserAvatar.defaultFill);
    final ringDecoration =
        tester.widget<Container>(ring).decoration! as BoxDecoration;
    expect(
      (ringDecoration.border! as Border).top.color,
      AppPalette.dark.borderStrong,
    );
    expect(ringDecoration.gradient, isNull, reason: 'no decorative ring');
    expect(tester.takeException(), isNull);
  });

  group('wide measure', () {
    testWidgets('1440: body sections take the 640 measure, start-aligned '
        'under the header cluster', (tester) async {
      await pumpOwn(tester, const Size(1440, 2400));
      final stats = tester.getRect(
        find.byKey(const ValueKey('profile-header-stats')),
      );
      final journey = tester.getRect(
        find.byKey(const ValueKey('profile-journey-card')),
      );
      final identity = tester.getRect(find.byType(ProfileVoiceIdentityCard));
      expect(journey.width, ProfileLayout.wideMeasure);
      expect(identity.width, ProfileLayout.wideMeasure);
      expect(stats.width, ProfileLayout.wideMeasure);
      expect(journey.left, stats.left);
      expect(identity.left, stats.left);
      // The 640 card is past 560: the journey shows its four cells.
      expect(
        find.byKey(const ValueKey('profile-journey-cells')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('768: body sections join the header cluster\'s 640 measure '
        '(one rule with the friend profile, from 700)', (tester) async {
      await pumpOwn(tester, const Size(768, 2400));
      final stats = tester.getRect(
        find.byKey(const ValueKey('profile-header-stats')),
      );
      final actions = tester.getRect(
        find.byKey(const ValueKey('profile-actions')),
      );
      final journey = tester.getRect(
        find.byKey(const ValueKey('profile-journey-card')),
      );
      final identity = tester.getRect(find.byType(ProfileVoiceIdentityCard));
      // One right edge for the header cluster and every block (before, the
      // blocks ran to 768 - 36 under a 640 header cluster).
      for (final rect in [actions, journey, identity]) {
        expect(rect.left, stats.left);
        expect(rect.right, stats.right);
      }
      expect(journey.width, ProfileLayout.wideMeasure);
      expect(
        find.byKey(const ValueKey('profile-journey-cells')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('below 700 the blocks keep the whole column', (tester) async {
      await pumpOwn(tester, const Size(700, 2400));
      final journey = tester.getRect(
        find.byKey(const ValueKey('profile-journey-card')),
      );
      // 700 - 36 = 664 of content: under the 700 threshold.
      expect(journey.width, 700 - 36);
      expect(tester.takeException(), isNull);
    });

    testWidgets('390: the journey keeps its rows', (tester) async {
      await pumpOwn(tester, const Size(390, 2400));
      expect(find.byType(ProfileJourneyCard), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-journey-cells')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
    testWidgets('${theme.brightness.name}: high contrast flattens the blocks '
        'and brings borderStrong back', (tester) async {
      await pumpOwn(
        tester,
        const Size(390, 2400),
        theme: theme,
        highContrast: true,
      );
      final palette = theme.extension<AppPalette>()!;
      final band =
          tester
                  .widget<Container>(
                    find.byKey(const ValueKey('profile-header-stats')),
                  )
                  .decoration!
              as BoxDecoration;
      expect(band.gradient, isNull);
      expect(band.color, palette.surface);
      expect(band.boxShadow, isEmpty);
      expect((band.border! as Border).top.color, palette.borderStrong);
      final journeyBox = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(const ValueKey('profile-journey-card')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final journeyFill = journeyBox.decoration! as BoxDecoration;
      expect(journeyFill.gradient, isNull);
      expect(journeyFill.color, palette.surface);
      expect(
        ((journeyBox.foregroundDecoration! as BoxDecoration).border! as Border)
            .top
            .color,
        palette.borderStrong,
      );
      // The CTA keeps its gradient (it IS the control) but drops the lift.
      expect(find.byType(YoGradientFilledButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('pinned Moment bead', () {
    Future<_FakeAudioPlayer> pumpCard(
      WidgetTester tester, {
      bool compact = false,
    }) async {
      final auth = _auth();
      final db = FakeFirebaseFirestore();
      final pinned = await tester.runAsync(() => _pinned(db, auth));
      final player = _FakeAudioPlayer();
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: CreatorPinnedMomentCard(
              creatorId: 'me',
              service: pinned,
              compact: compact,
              momentService: MomentService(
                firestore: db,
                auth: auth,
                storage: MockFirebaseStorage(),
                mediaAccessInvoker: fakeMomentMediaAccessInvoker(),
              ),
              playerFactory: () => player,
              onOpen: (_) {},
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (find.byType(YoGradientDisc).evaluate().isNotEmpty) break;
      }
      return player;
    }

    YoGradientDisc disc(WidgetTester tester) =>
        tester.widget<YoGradientDisc>(find.byType(YoGradientDisc));

    testWidgets('rests on a block and lights only while it plays', (
      tester,
    ) async {
      final player = await pumpCard(tester);
      final card = tester.widget<YoCard>(find.byType(YoCard));
      expect(card.radius, AppRadius.block);
      expect(card.tint, isNull, reason: 'no card tint on Profile (budget)');

      expect(disc(tester).size, 52);
      expect(disc(tester).gloss, isTrue);
      expect(disc(tester).emphasis, YoDiscEmphasis.rest);
      expect(tester.getSize(find.byType(YoGradientDisc)), const Size(52, 52));

      await tester.tap(find.byType(YoGradientDisc));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(player.playCount, 1);
      expect(disc(tester).emphasis, YoDiscEmphasis.lit);
      expect(
        find.bySemanticsLabel('Wstrzymaj przypięty Voice Moment'),
        findsOneWidget,
      );

      await tester.tap(find.byType(YoGradientDisc));
      await tester.pump();
      await tester.pump();
      expect(player.pauseCount, 1);
      expect(disc(tester).emphasis, YoDiscEmphasis.rest);
      expect(
        find.bySemanticsLabel('Odtwórz przypięty Voice Moment'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('is 48 px in the compact card', (tester) async {
      await pumpCard(tester, compact: true);
      expect(disc(tester).size, 48);
      expect(tester.takeException(), isNull);
    });
  });

  group('error state', () {
    testWidgets('is the shared error state with Try again and Back', (
      tester,
    ) async {
      var retries = 0;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: Text('previous-route')),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ProfileErrorView(
            message: 'Your servers could not be loaded.',
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(YoErrorState), findsOneWidget);
      expect(find.text('Your servers could not be loaded.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('previous-route'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('keyboard focus on the gradient CTAs is visible', () {
    for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
      testWidgets('${theme.brightness.name}: Edytuj profil draws its 2 px '
          'onPrimary edge over the gradient', (tester) async {
        await pumpOwn(tester, const Size(390, 844), theme: theme);
        final edit = find.byKey(const ValueKey('profile-edit-button'));
        final rect = tester.getRect(edit);
        final edge = Offset(rect.left + 1, rect.center.dy);
        final inside = Offset(rect.left + 5, rect.center.dy);
        final onPrimary = theme.colorScheme.onPrimary;

        final restEdge = await _pixel(tester, edge);
        expect(restEdge, isNot(_samePixel(onPrimary)), reason: 'no ring');

        await _focus(
          tester,
          find.descendant(of: edit, matching: find.text('Edytuj profil')),
        );
        expect(await _pixel(tester, edge), _samePixel(onPrimary));
        // The edge is 2 px: the gradient shows right inside it.
        expect(
          await _pixel(tester, inside),
          isNot(_samePixel(onPrimary)),
          reason: 'only the edge turns onPrimary',
        );
        // No layout shift: the ring is paint only.
        expect(tester.getRect(edit), rect);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a friend\'s Zadzwoń draws the same edge; the neutral '
        'slots keep their own side', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: ProfileQuickActions(
                actions: [
                  ProfileQuickAction(
                    key: const ValueKey('call'),
                    icon: Icons.call_rounded,
                    label: 'Zadzwoń',
                    semanticLabel: 'Zadzwoń do Oli',
                    emphasis: ProfileQuickActionEmphasis.primary,
                    onPressed: () {},
                  ),
                  ProfileQuickAction(
                    key: const ValueKey('video'),
                    icon: Icons.videocam_outlined,
                    label: 'Wideo',
                    semanticLabel: 'Połączenie wideo z Olą',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final call = find.byKey(const ValueKey('call'));
      final rect = tester.getRect(call);
      final edge = Offset(rect.left + 1, rect.center.dy);
      const white = Color(0xFFFFFFFF);
      expect(await _pixel(tester, edge), isNot(_samePixel(white)));
      await _focus(
        tester,
        find.descendant(of: call, matching: find.byType(Icon)),
      );
      expect(await _pixel(tester, edge), _samePixel(white));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('an account row shows R16\'s 2 px focus ring at radius 16', (
    tester,
  ) async {
    await pumpOwn(tester, const Size(390, 2400));
    final palette = AppPalette.dark;
    final logout = find.text('Wyloguj się');
    await tester.ensureVisible(logout);
    await tester.pump();
    final ring = find.ancestor(
      of: logout,
      matching: find.byType(ProfileFocusRing),
    );
    final rect = tester.getRect(ring);
    // The 2 px ring sits 4 px inside the row: sample its left stroke.
    final stroke = Offset(rect.left + 5, rect.center.dy);
    expect(await _pixel(tester, stroke), isNot(_samePixel(palette.focus)));
    await _focus(tester, logout);
    expect(await _pixel(tester, stroke), _samePixel(palette.focus));
    expect(tester.widget<ProfileFocusRing>(ring).borderRadius.topLeft.x, 16);
    expect(tester.getRect(ring), rect, reason: 'no layout shift');
    expect(tester.takeException(), isNull);
  });

  group('stats band fit at the band edge', () {
    // The test font draws every glyph as wide as its size: the counters
    // need 100 + 100 + 148 + 148 = 496 px on one line, and the widest is
    // 148 px. The band's 1 px edge leaves its width - 2 for the counters.
    const stats = [
      ProfileStat(value: 3, label: 'Serwery', keyName: 'a'),
      ProfileStat(value: 148, label: 'Znajomi', keyName: 'b'),
      ProfileStat(value: 1840, label: 'Obserwujący', keyName: 'c'),
      ProfileStat(value: 212, label: 'Obserwowani', keyName: 'd'),
    ];

    Future<void> pumpBand(WidgetTester tester, double width) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: const ProfileStatsRow(stats: stats),
              ),
            ),
          ),
        ),
      );
    }

    void expectWholeLabels(WidgetTester tester, String reason) {
      for (final label in const [
        'Serwery',
        'Znajomi',
        'Obserwujący',
        'Obserwowani',
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$reason $label');
      }
    }

    for (final (width, oneLine) in const [
      (496.0, false),
      (497.0, false),
      (498.0, true),
    ]) {
      testWidgets('band $width: ${oneLine ? 'one line' : 'folds'} without '
          'an overflow', (tester) async {
        await pumpBand(tester, width);
        final a = tester.getRect(find.byKey(const ValueKey('profile-stat-a')));
        final d = tester.getRect(find.byKey(const ValueKey('profile-stat-d')));
        expect(d.top == a.top, oneLine, reason: '$width');
        expectWholeLabels(tester, '$width');
        expect(tester.takeException(), isNull, reason: '$width');
      });
    }

    for (final (width, twoPerLine) in const [
      (296.0, false),
      (297.0, false),
      (298.0, true),
    ]) {
      testWidgets(
        'band $width: ${twoPerLine ? 'two per line' : 'one per '
                  'line'} and no label is cut',
        (tester) async {
          await pumpBand(tester, width);
          final a = tester.getRect(
            find.byKey(const ValueKey('profile-stat-a')),
          );
          final b = tester.getRect(
            find.byKey(const ValueKey('profile-stat-b')),
          );
          expect(b.top == a.top, twoPerLine, reason: '$width');
          expectWholeLabels(tester, '$width');
          expect(tester.takeException(), isNull, reason: '$width');
        },
      );
    }
  });

  group('pinned Moment bead states', () {
    Future<_ControlledPinService> pumpCard(
      WidgetTester tester,
      audio.AudioPlayer player, {
      PinnedVoiceMoment? pin,
    }) async {
      final auth = _auth();
      final db = FakeFirebaseFirestore();
      final service = _ControlledPinService(firestore: db, auth: auth);
      addTearDown(service.pins.close);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: CreatorPinnedMomentCard(
              creatorId: 'me',
              service: service,
              momentService: MomentService(
                firestore: db,
                auth: auth,
                storage: MockFirebaseStorage(),
                mediaAccessInvoker: fakeMomentMediaAccessInvoker(),
              ),
              playerFactory: () => player,
            ),
          ),
        ),
      );
      service.pins.add(pin ?? _pin('pin-a'));
      await tester.pump();
      await tester.pump();
      return service;
    }

    YoGradientDisc disc(WidgetTester tester) =>
        tester.widget<YoGradientDisc>(find.byType(YoGradientDisc));

    Future<void> tapBead(WidgetTester tester) async {
      await tester.tap(find.byType(YoGradientDisc));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    testWidgets('a failed play shows the refresh glyph and a message; the '
        'next try clears it', (tester) async {
      final player = _FlakyAudioPlayer();
      await pumpCard(tester, player);
      expect(disc(tester).status, YoDiscStatus.idle);

      await tapBead(tester);
      expect(disc(tester).status, YoDiscStatus.failed);
      expect(disc(tester).emphasis, YoDiscEmphasis.rest);
      expect(find.byKey(const ValueKey('yo-disc-failed')), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(player.playCount, 0);

      await tapBead(tester);
      expect(player.playCount, 1);
      expect(disc(tester).status, YoDiscStatus.idle);
      expect(disc(tester).emphasis, YoDiscEmphasis.lit);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new pin never inherits the previous pin\'s failure', (
      tester,
    ) async {
      final player = _FlakyAudioPlayer();
      final service = await pumpCard(tester, player);
      await tapBead(tester);
      expect(disc(tester).status, YoDiscStatus.failed);

      service.pins.add(_pin('pin-b'));
      await tester.pump();
      await tester.pump();
      expect(disc(tester).status, YoDiscStatus.idle);
      expect(find.byKey(const ValueKey('yo-disc-failed')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a Moment without media is a disabled bead that never '
        'plays', (tester) async {
      final semantics = tester.ensureSemantics();
      final player = _FakeAudioPlayer();
      await pumpCard(tester, player, pin: _pin('legacy', media: false));
      expect(disc(tester).status, YoDiscStatus.disabled);
      final node = tester.getSemantics(
        find.bySemanticsLabel('Odtwórz przypięty Voice Moment'),
      );
      expect(node.flagsCollection.isEnabled, ui.Tristate.isFalse);
      await tester.tap(find.byType(YoGradientDisc), warnIfMissed: false);
      await tester.pump();
      expect(player.playCount, 0);
      expect(disc(tester).status, YoDiscStatus.disabled);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });

    for (final (platform, haptic) in const [
      (TargetPlatform.iOS, true),
      (TargetPlatform.android, true),
      (TargetPlatform.macOS, false),
      (TargetPlatform.windows, false),
    ]) {
      testWidgets(
        '${platform.name}: ${haptic ? 'a light haptic' : 'no '
                  'haptic'} on play',
        (tester) async {
          final haptics = <Object?>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'HapticFeedback.vibrate') {
                haptics.add(call.arguments);
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          debugDefaultTargetPlatformOverride = platform;
          try {
            final player = _FakeAudioPlayer();
            await pumpCard(tester, player);
            await tapBead(tester);
            expect(player.playCount, 1);
            expect(
              haptics,
              haptic ? ['HapticFeedbackType.lightImpact'] : isEmpty,
            );
            // Pausing is not a play: no second haptic.
            await tapBead(tester);
            expect(haptics.length, haptic ? 1 : 0);
            expect(tester.takeException(), isNull);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  });

  testWidgets('Try again after the profile itself failed subscribes to a '
      'fresh profile stream and the page recovers', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _auth();
    final db = FakeFirebaseFirestore();
    final profile = _profile(accountType: AccountType.personal);
    final profiles = _FlakyProfileService(
      profile: profile,
      firestore: db,
      auth: auth,
    );
    final servers = _Servers();
    await tester.pumpWidget(
      _app(
        ProfileScreen(
          profileService: profiles,
          achievementService: _QuietAchievements(firestore: db, auth: auth),
          serverRepository: servers,
          auth: auth,
          identityRepository: _identity(),
          mediaService: _media(auth),
        ),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('profile-error')), findsOneWidget);
    expect(profiles.watches, 1);

    await tester.tap(find.text('Spróbuj ponownie'));
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await settle(tester);
    expect(profiles.watches, 2, reason: 'a fresh stream, not the dead one');
    expect(find.byKey(const ValueKey('profile-error')), findsNothing);
    expect(find.byType(ProfileScreenView), findsOneWidget);
    expect(find.text('Maja Kowalska'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the error and loading states keep the profile canvas', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: AppTheme.darkTheme,
        home: const ProfileErrorView(message: 'x'),
      ),
    );
    final background = tester.widget<YoPageBackground>(
      find.descendant(
        of: find.byKey(const ValueKey('profile-error')),
        matching: find.byType(YoPageBackground),
      ),
    );
    final decoration = background.decoration! as BoxDecoration;
    expect(
      decoration.gradient,
      AppPalette.dark.canvasGlow(AppTheme.darkTheme.colorScheme.primary),
    );
    expect(tester.takeException(), isNull);
  });

  group('achievement progress', () {
    FractionallySizedBox fill(WidgetTester tester) =>
        tester.widget<FractionallySizedBox>(
          find.descendant(
            of: find.byKey(const ValueKey('profile-achievement-progress')),
            matching: find.byType(FractionallySizedBox),
          ),
        );

    double target(WidgetTester tester) => tester
        .widget<TweenAnimationBuilder<double>>(
          find.descendant(
            of: find.byKey(const ValueKey('profile-achievement-progress')),
            matching: find.byType(TweenAnimationBuilder<double>),
          ),
        )
        .tween
        .end!;

    Duration growth(WidgetTester tester) => tester
        .widget<TweenAnimationBuilder<double>>(
          find.descendant(
            of: find.byKey(const ValueKey('profile-achievement-progress')),
            matching: find.byType(TweenAnimationBuilder<double>),
          ),
        )
        .duration;

    for (final (name, disableAnimations, accessibleNavigation, animated)
        in const [
          ('decorative motion allowed', false, false, true),
          ('Reduce Motion', true, false, false),
          ('accessible navigation', false, true, false),
        ]) {
      testWidgets('$name: ${animated ? 'grows' : 'no growth'}', (tester) async {
        await pumpOwn(
          tester,
          const Size(390, 2400),
          disableAnimations: disableAnimations,
          accessibleNavigation: accessibleNavigation,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('profile-achievement-progress')),
        );
        await tester.pumpAndSettle();
        expect(target(tester), greaterThan(0));
        expect(
          growth(tester),
          animated ? AppMotion.entrance : Duration.zero,
          reason: name,
        );
        expect(fill(tester).widthFactor, target(tester));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('grows once: scrolling away and back does not replay it', (
      tester,
    ) async {
      await pumpOwn(tester, const Size(390, 600), disableAnimations: false);
      final bar = find.byKey(const ValueKey('profile-achievement-progress'));
      await tester.scrollUntilVisible(
        bar,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final end = target(tester);
      expect(fill(tester).widthFactor, end);
      // Far past the card's cache extent, then back.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        bar,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(fill(tester).widthFactor, end, reason: 'no regrowth from 0');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('at 200 % text the image actions stack and keep whole labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _auth();
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(
      _app(
        EditProfileScreen(
          profile: _profile(),
          service: ProfileService(firestore: db, auth: auth),
          entitlements: EntitlementService(firestore: db, auth: auth),
          mediaService: _media(auth),
        ),
        textScaler: const TextScaler.linear(2),
      ),
    );
    await settle(tester);
    final avatar = tester.getRect(
      find.byKey(const ValueKey('edit-profile-avatar-action')),
    );
    final banner = tester.getRect(
      find.byKey(const ValueKey('edit-profile-banner-action')),
    );
    expect(banner.top, greaterThan(avatar.bottom), reason: 'stacked');
    expect(banner.width, avatar.width);
    for (final label in const ['Zmień awatar', 'Zmień baner']) {
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(label))
            .didExceedMaxLines,
        isFalse,
        reason: label,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 100 % text the image actions sit side by side', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _auth();
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(
      _app(
        EditProfileScreen(
          profile: _profile(),
          service: ProfileService(firestore: db, auth: auth),
          entitlements: EntitlementService(firestore: db, auth: auth),
          mediaService: _media(auth),
        ),
      ),
    );
    await settle(tester);
    final avatar = tester.getRect(
      find.byKey(const ValueKey('edit-profile-avatar-action')),
    );
    final banner = tester.getRect(
      find.byKey(const ValueKey('edit-profile-banner-action')),
    );
    expect(banner.top, avatar.top);
    expect(banner.left, greaterThan(avatar.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick-action tiles share one label size instead of shrinking '
      'one label', (tester) async {
    tester.view.physicalSize = const Size(480, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ProfileQuickAction slot(String key, String label, {bool primary = false}) =>
        ProfileQuickAction(
          key: ValueKey(key),
          icon: Icons.circle_outlined,
          label: label,
          semanticLabel: label,
          emphasis: primary
              ? ProfileQuickActionEmphasis.primary
              : ProfileQuickActionEmphasis.neutral,
          onPressed: () {},
        );
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ProfileQuickActions(
            actions: [
              slot('call', 'Zadzwoń', primary: true),
              slot('video', 'Wideo'),
              slot('message', 'Wiadomość'),
              slot('more', 'Więcej'),
            ],
          ),
        ),
      ),
    );
    // 480 px: four 114 px tiles with 98 px of room. The test font draws
    // "Wiadomość" 9 glyphs wide, so it needs 10.75 px glyphs to fit.
    final sizes = {
      for (final label in const ['Zadzwoń', 'Wideo', 'Wiadomość', 'Więcej'])
        tester.widget<Text>(find.text(label)).style!.fontSize,
    };
    expect(sizes, hasLength(1), reason: 'one shared size');
    expect(sizes.single, lessThan(ProfileQuickActions.tileLabelSize));
    for (final label in const ['Zadzwoń', 'Wideo', 'Wiadomość', 'Więcej']) {
      // Drawn at its own size: the FittedBox guard never scales it.
      expect(
        tester.getRect(find.text(label)).width,
        moreOrLessEquals(tester.getSize(find.text(label)).width),
        reason: label,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the preview sheet\'s compact vibe stays a neutral plate', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: ProfileVibeHeadline(
            vibe:
                'Nocne rozmowy https://open.spotify.com/track/7ouMYWpwJ422jRcDASZB7P',
            compact: true,
          ),
        ),
      ),
    );
    await tester.pump();
    final palette = AppPalette.dark;
    final scheme = AppTheme.darkTheme.colorScheme;
    final plate = tester.widget<Material>(
      find.byKey(const ValueKey('profile-vibe-surface')),
    );
    expect(plate.color, isNot(scheme.primary), reason: 'not the violet fill');
    expect(
      plate.color,
      Color.alphaBlend(
        scheme.primary.withValues(alpha: .13),
        palette.surfaceMuted,
      ),
    );
    expect(find.byKey(const ValueKey('profile-vibe-sweep')), findsNothing);
    expect(find.byKey(const ValueKey('profile-vibe-glint')), findsNothing);
    final label = tester.widget<Text>(
      find.byKey(const ValueKey('profile-vibe-label')),
    );
    expect(label.style!.color, palette.interactiveForeground);
    expect(tester.takeException(), isNull);
  });
}
