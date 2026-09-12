import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_friend_tile.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

/// The friends rail's content mark.
///
/// The contract under test is the honesty rule the package set: a ring and a
/// badge mean "a friend has something new you can hear", presence means
/// something else entirely, and neither may be inferred from the other. A
/// Reel never produces a mark at all — the backend exposes no friends scope
/// for reels, so a badge would be an invention.
void main() {
  VoiceMoment moment({
    required String id,
    required String authorId,
    int durationSeconds = 45,
    bool withMedia = true,
    DateTime? expiresAt,
    DateTime? createdAt,
  }) => VoiceMoment(
    id: id,
    authorId: authorId,
    authorName: 'Maja',
    authorPhotoUrl: null,
    caption: '',
    audioUrl: withMedia ? 'https://example.test/$id.m4a' : null,
    durationSeconds: durationSeconds,
    likeCount: 0,
    commentCount: 0,
    isPublished: true,
    createdAt: createdAt ?? DateTime(2026, 9, 12, 10),
    expiresAt: expiresAt ?? DateTime(2026, 9, 13, 10),
  );

  Widget host(Widget child, {Locale locale = const Locale('pl')}) => MaterialApp(
    locale: locale,
    localizationsDelegates: _delegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppTheme.darkTheme,
    home: Scaffold(body: Center(child: child)),
  );

  group('homeFriendVoiceByAuthor', () {
    final now = DateTime(2026, 9, 12, 12);

    test('a friend with playable, unexpired, unheard media gets an entry', () {
      final result = homeFriendVoiceByAuthor(
        page: [moment(id: 'm1', authorId: 'maja')],
        friendIds: const {'maja'},
        viewedMomentIds: const {},
        now: now,
      );
      expect(result.keys, ['maja']);
      expect(result['maja']!.durationSeconds, 45);
      expect(result['maja']!.chain, hasLength(1));
    });

    test('an author who is followed but NOT a friend gets nothing', () {
      final result = homeFriendVoiceByAuthor(
        page: [moment(id: 'm1', authorId: 'creator')],
        friendIds: const {'maja'},
        viewedMomentIds: const {},
        now: now,
      );
      expect(result, isEmpty);
    });

    test('a friend absent from the loaded page gets nothing', () {
      final result = homeFriendVoiceByAuthor(
        page: const [],
        friendIds: const {'maja'},
        viewedMomentIds: const {},
        now: now,
      );
      expect(result, isEmpty);
    });

    test('a Moment with no media reference never marks a tile', () {
      final result = homeFriendVoiceByAuthor(
        page: [moment(id: 'm1', authorId: 'maja', withMedia: false)],
        friendIds: const {'maja'},
        viewedMomentIds: const {},
        now: now,
      );
      expect(result, isEmpty);
    });

    test('a fully heard chain drops the mark', () {
      final result = homeFriendVoiceByAuthor(
        page: [moment(id: 'm1', authorId: 'maja')],
        friendIds: const {'maja'},
        viewedMomentIds: const {'m1'},
        now: now,
      );
      expect(result, isEmpty);
    });

    test('one unheard link in a chain keeps the mark, newest first', () {
      final result = homeFriendVoiceByAuthor(
        page: [
          moment(
            id: 'old',
            authorId: 'maja',
            durationSeconds: 10,
            createdAt: DateTime(2026, 9, 12, 9),
          ),
          moment(
            id: 'new',
            authorId: 'maja',
            durationSeconds: 62,
            createdAt: DateTime(2026, 9, 12, 11),
          ),
        ],
        friendIds: const {'maja'},
        viewedMomentIds: const {'old'},
        now: now,
      );
      expect(result['maja']!.chain.map((m) => m.id), ['old', 'new']);
      expect(result['maja']!.durationLabel, '1:02');
    });

    test('an expired Moment never marks a tile', () {
      final result = homeFriendVoiceByAuthor(
        page: [
          moment(
            id: 'm1',
            authorId: 'maja',
            expiresAt: DateTime(2026, 9, 12, 11),
          ),
        ],
        friendIds: const {'maja'},
        viewedMomentIds: const {},
        now: now,
      );
      expect(result, isEmpty);
    });
  });

  testWidgets('content draws the ring, the badge and the Voice label while '
      'presence stays a separate dot', (tester) async {
    await tester.pumpWidget(
      host(
        HomeFriendTile(
          displayName: 'Maja',
          userId: 'maja',
          status: PeopleStatus.online,
          voice: HomeFriendVoice(
            chain: [moment(id: 'm1', authorId: 'maja')],
            newest: moment(id: 'm1', authorId: 'maja'),
          ),
          onOpenVoice: (_) {},
          onOpenProfile: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Maja'), findsOneWidget);
    expect(find.text('Voice 0:45'), findsOneWidget);
    // The badge glyph is the waveform; a Reel play badge must never appear.
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    expect(find.text('Reel 0:45'), findsNothing);
  });

  testWidgets('no content: presence word only, no ring and no badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const HomeFriendTile(
          displayName: 'Bartek',
          userId: 'bartek',
          status: PeopleStatus.online,
          onOpenProfile: _noop,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Dostępny'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);
  });

  testWidgets('tap opens the chain, long-press opens the profile', (
    tester,
  ) async {
    var chains = 0;
    var profiles = 0;
    await tester.pumpWidget(
      host(
        HomeFriendTile(
          displayName: 'Maja',
          userId: 'maja',
          status: PeopleStatus.online,
          voice: HomeFriendVoice(
            chain: [moment(id: 'm1', authorId: 'maja')],
            newest: moment(id: 'm1', authorId: 'maja'),
          ),
          onOpenVoice: (_) => chains++,
          onOpenProfile: () => profiles++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(HomeFriendTile));
    await tester.pump();
    expect(chains, 1);
    expect(profiles, 0);

    await tester.longPress(find.byType(HomeFriendTile));
    await tester.pump();
    expect(profiles, 1);
    expect(chains, 1);
  });

  testWidgets('without content the tap is the profile preview', (tester) async {
    var chains = 0;
    var profiles = 0;
    await tester.pumpWidget(
      host(
        HomeFriendTile(
          displayName: 'Bartek',
          userId: 'bartek',
          status: PeopleStatus.away,
          onOpenVoice: (_) => chains++,
          onOpenProfile: () => profiles++,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(HomeFriendTile));
    await tester.pump();
    expect(profiles, 1);
    expect(chains, 0);
  });

  testWidgets('a reader hears the name, the new Moment in spoken seconds and '
      'the presence, and can reach the profile without a long-press', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var profiles = 0;
    await tester.pumpWidget(
      host(
        HomeFriendTile(
          displayName: 'Maja',
          userId: 'maja',
          status: PeopleStatus.online,
          voice: HomeFriendVoice(
            chain: [moment(id: 'm1', authorId: 'maja')],
            newest: moment(id: 'm1', authorId: 'maja'),
          ),
          onOpenVoice: (_) {},
          onOpenProfile: () => profiles++,
        ),
      ),
    );
    await tester.pump();

    final node = tester.getSemantics(find.byType(HomeFriendTile));
    expect(node.label, 'Maja');
    expect(node.value, 'Nowy Voice Moment, 45 sekund. Dostępny');
    final action = node.getSemanticsData().customSemanticsActionIds ?? const [];
    expect(action, isNotEmpty);
    final profileAction = CustomSemanticsAction.getAction(action.first);
    expect(profileAction?.label, 'Otwórz profil');
    // The binding's own semantics owner is the one that holds this tree's
    // nodes; the root pipeline owner does not. Deprecated, and deliberately
    // used: there is no supported way to invoke a custom action otherwise.
    // ignore: deprecated_member_use
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.customAction,
      action.first,
    );
    await tester.pump();
    expect(profiles, 1);
    handle.dispose();
  });

  testWidgets('the disc keeps its size whether or not a ring is painted', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const HomeFriendTile(
          displayName: 'Bartek',
          userId: 'bartek',
          status: PeopleStatus.online,
          onOpenProfile: _noop,
        ),
      ),
    );
    await tester.pump();
    final without = tester.getSize(find.byType(HomeFriendTile)).width;

    await tester.pumpWidget(
      host(
        HomeFriendTile(
          displayName: 'Bartek',
          userId: 'bartek',
          status: PeopleStatus.online,
          voice: HomeFriendVoice(
            chain: [moment(id: 'm1', authorId: 'bartek')],
            newest: moment(id: 'm1', authorId: 'bartek'),
          ),
          onOpenVoice: (_) {},
          onOpenProfile: () {},
        ),
      ),
    );
    await tester.pump();
    expect(tester.getSize(find.byType(HomeFriendTile)).width, without);
  });

  testWidgets('a long Polish name ellipsises without overflowing at 200 % '
      'text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pl'),
        localizationsDelegates: _delegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.darkTheme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: Center(
              child: HomeFriendTile(
                displayName: 'Bartłomiej-Krzysztof Wojciechowski',
                userId: 'bartek',
                status: PeopleStatus.brb,
                onOpenProfile: _noop,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

const _delegates = <LocalizationsDelegate<Object>>[
  AppLocalizationsDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
