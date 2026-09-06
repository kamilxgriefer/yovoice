// The compact, Instagram-style Voice Moments story tile and its
// seen/unseen ring.
//
// The ring is the whole point of the rework: a brand gradient while this
// account still has something unheard in the chain, a flat quiet line and
// a dimmed avatar once every link was heard. Both facts come from the
// caller's own `users/{uid}/momentViews` docs — there is no global "seen"
// counter in the schema, so unknown viewed state must render as UNHEARD
// rather than greying out something nobody played.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home_sections.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

const _me = 'me';
final DateTime _anchor = DateTime.now();

VoiceMoment _moment(
  String id, {
  String authorId = 'ola',
  String authorName = 'Ola',
  Duration age = const Duration(minutes: 5),
}) {
  final createdAt = _anchor.subtract(age);
  return VoiceMoment(
    id: id,
    authorId: authorId,
    authorName: authorName,
    authorPhotoUrl: null,
    caption: '',
    audioUrl: 'https://cdn.example/$id.m4a',
    durationSeconds: 12,
    likeCount: 0,
    commentCount: 0,
    isPublished: true,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(hours: 12)),
    schemaVersion: 2,
    status: 'published',
  );
}

UserProfile _profile() => UserProfile(
  uid: _me,
  email: 'me@example.com',
  displayName: 'Kamil',
  username: 'kamil',
  bio: '',
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
  createdAt: _anchor,
);

Widget _host(
  Widget child, {
  ThemeData? theme,
  double textScale = 1,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  theme: theme ?? AppTheme.darkTheme,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, inner) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: inner!,
  ),
  home: Scaffold(body: child),
);

/// The ring stops actually painted under [tileKey].
List<Color> _ringColors(WidgetTester tester, Key tileKey) {
  final ring = tester.widget<Container>(
    find.descendant(
      of: find.byKey(tileKey),
      matching: find.byKey(MomentStoryTile.ringKey),
    ),
  );
  final gradient = (ring.decoration! as BoxDecoration).gradient!;
  return gradient.colors;
}

/// How hard the avatar under [tileKey] is dimmed.
double _avatarOpacity(WidgetTester tester, Key tileKey) => tester
    .widget<Opacity>(
      find
          .descendant(of: find.byKey(tileKey), matching: find.byType(Opacity))
          .first,
    )
    .opacity;

void main() {
  late PublicIdentityRepository originalIdentity;

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  group('the story ring', () {
    for (final (mode, theme) in [
      ('dark', AppTheme.darkTheme),
      ('pearl', AppTheme.lightTheme),
    ]) {
      testWidgets('$mode: unheard paints the brand gradient, heard paints one '
          'flat quiet line and dims the avatar', (tester) async {
        const unheardKey = ValueKey('tile-unheard');
        const heardKey = ValueKey('tile-heard');
        await tester.pumpWidget(
          _host(
            theme: theme,
            Row(
              children: [
                MomentStoryTile(
                  key: unheardKey,
                  name: 'Ola',
                  seen: false,
                  semanticLabel: 'Play Voice Moment from Ola',
                  onTap: () {},
                ),
                MomentStoryTile(
                  key: heardKey,
                  name: 'Marek',
                  seen: true,
                  semanticLabel: 'Play Voice Moment from Marek',
                  onTap: () {},
                ),
              ],
            ),
          ),
        );

        expect(_ringColors(tester, unheardKey), [
          AppColors.primary,
          AppColors.secondary,
        ]);

        final quiet =
            AppPalette.of(tester.element(find.byKey(heardKey))).border;
        expect(
          _ringColors(tester, heardKey),
          [quiet, quiet],
          reason: 'heard is a flat, low-contrast line — never the gradient',
        );

        expect(_avatarOpacity(tester, unheardKey), 1);
        expect(
          _avatarOpacity(tester, heardKey),
          lessThan(1),
          reason: 'the heard avatar is dimmed as well as unringed',
        );
      });
    }

    testWidgets('the heard/unheard state rides on the semantic label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Row(
            children: [
              MomentStoryTile(
                name: 'Ola',
                seen: false,
                semanticLabel: 'Play Voice Moment from Ola',
                onTap: () {},
              ),
              MomentStoryTile(
                name: 'Marek',
                seen: true,
                semanticLabel: 'Play Voice Moment from Marek',
                onTap: () {},
              ),
            ],
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('Play Voice Moment from Ola, not heard yet'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Play Voice Moment from Marek, already heard'),
        findsOneWidget,
      );
    });

    testWidgets('Polish gets the state too', (tester) async {
      await tester.pumpWidget(
        _host(
          locale: const Locale('pl'),
          MomentStoryTile(
            name: 'Ola',
            seen: true,
            semanticLabel: 'Odtwórz Voice Moment użytkownika Ola',
            onTap: () {},
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(
          'Odtwórz Voice Moment użytkownika Ola, odsłuchane',
        ),
        findsOneWidget,
      );
    });
  });

  group('viewed state flows from momentViews', () {
    testWidgets('marking a Moment viewed flips the chain ring from gradient '
        'to quiet', (tester) async {
      final db = FakeFirebaseFirestore();
      final views = MomentViewsService(
        firestore: db,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      );
      final chain = MomentChain(moments: [_moment('ola-1')]);
      const tileKey = ValueKey('moments-chain-ola');

      await tester.pumpWidget(
        _host(
          MomentViewedIds(
            service: views,
            builder: (context, viewedIds) => MomentStoryStrip(
              chains: [chain],
              viewedIds: viewedIds,
              onOpenChain: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(_ringColors(tester, tileKey), [
        AppColors.primary,
        AppColors.secondary,
      ]);

      await views.markViewed('ola-1');
      await tester.pump();
      await tester.pump();

      final quiet = AppPalette.of(tester.element(find.byKey(tileKey))).border;
      expect(
        _ringColors(tester, tileKey),
        [quiet, quiet],
        reason: 'the caller\'s own momentViews doc greys the ring out',
      );
    });

    testWidgets('a chain with ANY unheard link stays gradient', (tester) async {
      final db = FakeFirebaseFirestore();
      final views = MomentViewsService(
        firestore: db,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      );
      final chain = MomentChain(
        moments: [
          _moment('ola-1', age: const Duration(minutes: 30)),
          _moment('ola-2', age: const Duration(minutes: 5)),
        ],
      );
      await views.markViewed('ola-1');

      await tester.pumpWidget(
        _host(
          MomentViewedIds(
            service: views,
            builder: (context, viewedIds) => MomentStoryStrip(
              chains: [chain],
              viewedIds: viewedIds,
              onOpenChain: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(_ringColors(tester, const ValueKey('moments-chain-ola')), [
        AppColors.primary,
        AppColors.secondary,
      ], reason: 'one heard link does not make the whole chain heard');
    });

    testWidgets('a services failure fails OPEN — every ring stays unheard', (
      tester,
    ) async {
      // No Firebase app has been initialised in this suite, so the default
      // MomentViewsService construction throws inside MomentViewedIds.
      await tester.pumpWidget(
        _host(
          MomentViewedIds(
            builder: (context, viewedIds) => MomentStoryStrip(
              chains: [
                MomentChain(moments: [_moment('ola-1')]),
              ],
              viewedIds: viewedIds,
              onOpenChain: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_ringColors(tester, const ValueKey('moments-chain-ola')), [
        AppColors.primary,
        AppColors.secondary,
      ]);
    });
  });

  group('compact geometry', () {
    for (final (label, surface, expected) in [
      ('an ordinary phone', Size(390, 844), 60.0),
      ('a 320pt viewport', Size(320, 640), 56.0),
    ]) {
      testWidgets('the disc is clearly smaller than the 66pt discs it '
          'replaced — $label', (tester) async {
        tester.view.physicalSize = surface;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _host(
            MomentStoryTile(
              name: 'Ola',
              seen: false,
              semanticLabel: 'Play Voice Moment from Ola',
              onTap: () {},
            ),
          ),
        );
        await tester.pump();

        expect(
          tester.getSize(find.byKey(MomentStoryTile.ringKey)).width,
          expected,
        );
        expect(
          expected,
          lessThan(66),
          reason: 'the rails this replaces all drew a 66pt disc',
        );
      });
    }

    testWidgets('every tap target stays at least 44pt at 320px and 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          textScale: 2,
          MobileMomentsStrip(
            moments: [
              _moment('mine-1', authorId: _me, authorName: 'Kamil'),
              _moment('ola-1'),
            ],
            profile: _profile(),
            currentUserId: _me,
            viewedIds: const <String>{},
            onOpenMoment: (_) {},
            onCreateMoment: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byKey(const ValueKey('home-your-moment'))),
        ).scale(10),
        20,
        reason: 'the regression must exercise 200% text, not the default',
      );

      for (final key in const [
        ValueKey('home-your-moment'),
        ValueKey('home-moment-ola-1'),
        ValueKey('home-record-moment'),
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.width, greaterThanOrEqualTo(44), reason: '$key width');
        expect(size.height, greaterThanOrEqualTo(44), reason: '$key height');
      }

      // The rail scrolls instead of overflowing at this size.
      expect(tester.takeException(), isNull);
    });

    testWidgets('the feed strip reserves exactly the height its tiles need', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          MomentStoryStrip(
            chains: [
              MomentChain(moments: [_moment('ola-1')]),
              MomentChain(
                moments: [_moment('mk-1', authorId: 'mk', authorName: 'Marek')],
              ),
            ],
            viewedIds: const <String>{},
            onOpenChain: (_) {},
          ),
        ),
      );
      await tester.pump();

      final strip = tester.getSize(find.byType(MomentStoryStrip));
      expect(
        strip.height,
        lessThan(108),
        reason: 'the old chain strip reserved 108pt for every row',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the rails still open the same destinations', () {
    testWidgets('a heard chain on mobile Home still opens the whole chain', (
      tester,
    ) async {
      List<VoiceMoment>? opened;
      final older = _moment('ola-older', age: const Duration(minutes: 30));
      final newer = _moment('ola-newer');

      await tester.pumpWidget(
        _host(
          MobileMomentsStrip(
            moments: [newer, older],
            profile: _profile(),
            currentUserId: _me,
            // Both links heard: the tile greys out and keeps working.
            viewedIds: const {'ola-older', 'ola-newer'},
            onOpenMoment: (_) {},
            onOpenChain: (chain) => opened = chain,
            onCreateMoment: () {},
          ),
        ),
      );
      await tester.pump();

      const tileKey = ValueKey('home-moment-ola-newer');
      final quiet = AppPalette.of(tester.element(find.byKey(tileKey))).border;
      expect(_ringColors(tester, tileKey), [quiet, quiet]);

      await tester.tap(find.byKey(tileKey));
      await tester.pump();
      expect(
        opened?.map((moment) => moment.id).toList(),
        ['ola-older', 'ola-newer'],
        reason: 'oldest → newest, exactly as before the rework',
      );
    });

    testWidgets('the own tile keeps its separate record target', (
      tester,
    ) async {
      var records = 0;
      List<VoiceMoment>? played;

      await tester.pumpWidget(
        _host(
          MobileMomentsStrip(
            moments: [_moment('mine-1', authorId: _me, authorName: 'Kamil')],
            profile: _profile(),
            currentUserId: _me,
            viewedIds: const <String>{},
            onOpenMoment: (_) {},
            onOpenChain: (chain) => played = chain,
            onCreateMoment: () => records++,
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSize(find.byKey(const ValueKey('home-record-moment'))),
        const Size(44, 44),
      );
      await tester.tap(find.byKey(const ValueKey('home-record-moment')));
      await tester.pump();
      expect(records, 1);
      expect(played, isNull);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('home-your-moment')),
          matching: find.byType(Opacity),
        ),
      );
      await tester.pump();
      expect(played?.single.id, 'mine-1');
      expect(records, 1);
    });

    testWidgets('a chain badge shows a real count and only above one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          MomentStoryStrip(
            chains: [
              MomentChain(
                moments: [
                  _moment('ola-1', age: const Duration(minutes: 30)),
                  _moment('ola-2'),
                ],
              ),
              MomentChain(
                moments: [_moment('mk-1', authorId: 'mk', authorName: 'Marek')],
              ),
            ],
            viewedIds: const <String>{},
            onOpenChain: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('moments-chain-ola')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('moments-chain-mk')),
          matching: find.text('1'),
        ),
        findsNothing,
        reason: 'a single Moment carries no count badge',
      );
    });
  });
}
