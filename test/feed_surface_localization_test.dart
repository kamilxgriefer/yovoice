import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_feed_surface_release.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_moments_strip.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_status.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

const _capture = bool.fromEnvironment('YO_CAPTURE_FEED_LOCALIZATION');
final _now = DateTime.utc(2026, 9, 11, 14);

// Independent expected strings: never computed through the production catalog.
const _expected = <String, Map<String, String>>{
  'en': {
    'likes0': 'Likes: 0',
    'likes1': 'Likes: 1',
    'likes2': 'Likes: 2',
    'likes5': 'Likes: 5',
    'comments0': 'Comments: 0',
    'comments1': 'Comments: 1',
    'comments2': 'Comments: 2',
    'comments5': 'Comments: 5',
    'like': 'Like',
    'comments': 'Comments',
    'play': 'Play',
    'pause': 'Pause',
    'share': 'Share',
    'soundOn': 'Turn sound on',
    'soundOff': 'Turn sound off',
    'shareReel': 'Share Reel',
    'viewAll': 'View all',
    'error': 'Moments could not load',
  },
  'pl': {
    'likes0': 'Polubienia: 0',
    'likes1': 'Polubienia: 1',
    'likes2': 'Polubienia: 2',
    'likes5': 'Polubienia: 5',
    'comments0': 'Komentarze: 0',
    'comments1': 'Komentarze: 1',
    'comments2': 'Komentarze: 2',
    'comments5': 'Komentarze: 5',
    'like': 'Lubię to',
    'comments': 'Komentarze',
    'play': 'Odtwórz',
    'pause': 'Pauza',
    'share': 'Udostępnij',
    'soundOn': 'Włącz dźwięk',
    'soundOff': 'Wyłącz dźwięk',
    'shareReel': 'Udostępnij Reel',
    'viewAll': 'Zobacz wszystkie',
    'error': 'Nie udało się wczytać Momentów',
  },
  'de': {
    'likes0': 'Gefällt mir: 0',
    'likes1': 'Gefällt mir: 1',
    'likes2': 'Gefällt mir: 2',
    'likes5': 'Gefällt mir: 5',
    'comments0': 'Kommentare: 0',
    'comments1': 'Kommentare: 1',
    'comments2': 'Kommentare: 2',
    'comments5': 'Kommentare: 5',
    'like': 'Gefällt mir',
    'comments': 'Kommentare',
    'play': 'Abspielen',
    'pause': 'Pausieren',
    'share': 'Teilen',
    'soundOn': 'Ton einschalten',
    'soundOff': 'Ton ausschalten',
    'shareReel': 'Reel teilen',
    'viewAll': 'Alle anzeigen',
    'error': 'Momente konnten nicht geladen werden',
  },
  'nl': {
    'likes0': 'Vind-ik-leuks: 0',
    'likes1': 'Vind-ik-leuks: 1',
    'likes2': 'Vind-ik-leuks: 2',
    'likes5': 'Vind-ik-leuks: 5',
    'comments0': 'Reacties: 0',
    'comments1': 'Reacties: 1',
    'comments2': 'Reacties: 2',
    'comments5': 'Reacties: 5',
    'like': 'Vind ik leuk',
    'comments': 'Reacties',
    'play': 'Afspelen',
    'pause': 'Pauzeren',
    'share': 'Delen',
    'soundOn': 'Geluid aanzetten',
    'soundOff': 'Geluid uitzetten',
    'shareReel': 'Reel delen',
    'viewAll': 'Alles bekijken',
    'error': 'Momenten konden niet worden geladen',
  },
  'ar': {
    'likes0': 'الإعجابات: 0',
    'likes1': 'الإعجابات: 1',
    'likes2': 'الإعجابات: 2',
    'likes5': 'الإعجابات: 5',
    'comments0': 'التعليقات: 0',
    'comments1': 'التعليقات: 1',
    'comments2': 'التعليقات: 2',
    'comments5': 'التعليقات: 5',
    'like': 'إعجاب',
    'comments': 'التعليقات',
    'play': 'تشغيل',
    'pause': 'إيقاف مؤقت',
    'share': 'مشاركة',
    'soundOn': 'تشغيل الصوت',
    'soundOff': 'إيقاف الصوت',
    'shareReel': 'مشاركة Reel',
    'viewAll': 'عرض الكل',
    'error': 'تعذّر تحميل اللحظات',
  },
};

const _footerExpected = <String, Map<String, String>>{
  "en": {
    "following": "Following",
    "only": "That is the only live Moment right now.",
    "loaded0": "0 live Moments loaded.",
    "loaded1": "1 live Moment loaded.",
    "loaded2": "2 live Moments loaded.",
    "loaded5": "5 live Moments loaded.",
    "all2": "That is all 2 live Moments right now.",
    "all3": "That is all 3 live Moments right now.",
    "all5": "That is all 5 live Moments right now.",
    "all6": "That is all 6 live Moments right now.",
    "retry": "Try again",
  },
  "pl": {
    "following": "Obserwowani",
    "only": "To jedyny aktywny Moment w tej chwili.",
    "loaded0": "Wczytano aktywne Momenty: 0.",
    "loaded1": "Wczytano aktywne Momenty: 1.",
    "loaded2": "Wczytano aktywne Momenty: 2.",
    "loaded5": "Wczytano aktywne Momenty: 5.",
    "all2": "To wszystkie aktywne Momenty w tej chwili: 2.",
    "all3": "To wszystkie aktywne Momenty w tej chwili: 3.",
    "all5": "To wszystkie aktywne Momenty w tej chwili: 5.",
    "all6": "To wszystkie aktywne Momenty w tej chwili: 6.",
    "retry": "Spróbuj ponownie",
  },
  "de": {
    "following": "Gefolgt",
    "only": "Das ist derzeit der einzige aktive Moment.",
    "loaded0": "Geladene aktive Momente: 0.",
    "loaded1": "Geladene aktive Momente: 1.",
    "loaded2": "Geladene aktive Momente: 2.",
    "loaded5": "Geladene aktive Momente: 5.",
    "all2": "Alle derzeit aktiven Momente: 2.",
    "all3": "Alle derzeit aktiven Momente: 3.",
    "all5": "Alle derzeit aktiven Momente: 5.",
    "all6": "Alle derzeit aktiven Momente: 6.",
    "retry": "Erneut versuchen",
  },
  "nl": {
    "following": "Volgend",
    "only": "Dit is momenteel het enige actieve Moment.",
    "loaded0": "Geladen actieve Momenten: 0.",
    "loaded1": "Geladen actieve Momenten: 1.",
    "loaded2": "Geladen actieve Momenten: 2.",
    "loaded5": "Geladen actieve Momenten: 5.",
    "all2": "Alle momenteel actieve Momenten: 2.",
    "all3": "Alle momenteel actieve Momenten: 3.",
    "all5": "Alle momenteel actieve Momenten: 5.",
    "all6": "Alle momenteel actieve Momenten: 6.",
    "retry": "Opnieuw proberen",
  },
  "ar": {
    "following": "المتابَعون",
    "only": "هذه هي اللحظة النشطة الوحيدة الآن.",
    "loaded0": "اللحظات النشطة المحمّلة: 0.",
    "loaded1": "اللحظات النشطة المحمّلة: 1.",
    "loaded2": "اللحظات النشطة المحمّلة: 2.",
    "loaded5": "اللحظات النشطة المحمّلة: 5.",
    "all2": "كل اللحظات النشطة الآن: 2.",
    "all3": "كل اللحظات النشطة الآن: 3.",
    "all5": "كل اللحظات النشطة الآن: 5.",
    "all6": "كل اللحظات النشطة الآن: 6.",
    "retry": "حاول مرة أخرى",
  },
};

class _PagingDiscovery implements MomentDiscoveryService {
  _PagingDiscovery(this.count, this.moreExists);
  final int count;
  final bool moreExists;
  final requests = <Completer<MomentDiscoveryFeed>>[];

  MomentDiscoveryFeed _snapshot(int count, bool moreExists) =>
      MomentDiscoveryFeed(
        moments: [
          for (var index = 0; index < count; index++)
            _moment(0, id: 'loaded-$index'),
        ],
        // An excluded item proves the footer uses the visible total,
        // not the fetched count or the opaque continuation token.
        fetchedCount: count + 1,
        drops: const {'filtered-id': MomentDropReason.blockedAuthor},
        seed: 1,
        poolExhausted: moreExists,
        nextCursor: moreExists ? 'opaque/continuation:server-owned' : null,
        loadMore: moreExists
            ? () {
                final pending = Completer<MomentDiscoveryFeed>();
                requests.add(pending);
                return pending.future;
              }
            : null,
      );

  void completePage() => requests.last.complete(_snapshot(count + 1, false));

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = 60,
    int? seed,
  }) async => _snapshot(count, moreExists);
  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({int poolSize = 60}) =>
      const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Discovery implements MomentDiscoveryService {
  _Discovery(this.moment);
  final VoiceMoment moment;
  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = 60,
    int? seed,
  }) async => MomentDiscoveryFeed(
    moments: [moment],
    fetchedCount: 1,
    drops: const {},
    seed: 1,
    poolExhausted: false,
  );
  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({int poolSize = 60}) =>
      const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Feed implements HomeFeedService {
  bool fail = false;
  int reads = 0;
  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) {
    reads++;
    return fail
        ? Stream.error(StateError('PRIVATE_TEST_ERROR'))
        : Stream.value(const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Moments implements MomentService {
  final requested = <String>[];
  @override
  Stream<List<VoiceMoment>> watchMyMoments() => Stream.value(const []);
  @override
  Stream<List<MomentComment>> watchComments(
    String momentId, {
    int limit = 80,
  }) => Stream.value(const []);
  @override
  Future<Uri> resolveMediaUri({
    required String momentId,
    String? commentId,
  }) async {
    requested.add(momentId);
    return Uri.parse('https://example.invalid/voice.m4a');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Following implements FollowService {
  @override
  Stream<List<FollowUser>> watchFollowing(String userId) =>
      Stream.value(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Friends implements FriendService {
  @override
  Stream<List<FriendUser>> watchFriends() => Stream.value(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Views implements MomentViewsService {
  @override
  Stream<Set<String>> watchViewedMomentIds() => Stream.value(const {});
  @override
  Future<void> markViewed(String momentId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Audio implements audio.AudioPlayer {
  int plays = 0;
  @override
  Stream<Duration> get onPositionChanged => const Stream.empty();
  @override
  Stream<Duration> get onDurationChanged => const Stream.empty();
  @override
  Stream<void> get onPlayerComplete => const Stream.empty();
  @override
  Future<void> play(
    audio.Source source, {
    double? volume,
    double? balance,
    audio.AudioContext? ctx,
    Duration? position,
    audio.PlayerMode? mode,
  }) async {
    plays++;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Video implements ReelVideoPlayback {
  @override
  bool isPlaying = false;
  @override
  Duration position = Duration.zero;
  @override
  Future<void> play() async {
    isPlaying = true;
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
  }

  @override
  Future<void> seek(Duration value) async {
    position = value;
  }

  @override
  Future<void> setVolume(double value) async {}
}

VoiceMoment _moment(int count, {String id = 'localized'}) => VoiceMoment(
  id: id,
  authorId: 'creator',
  authorName: 'Ada',
  authorPhotoUrl: null,
  caption: 'Voice caption {count} stays unchanged.',
  audioUrl: null,
  durationSeconds: 20,
  likeCount: count,
  commentCount: count,
  isPublished: true,
  createdAt: _now.subtract(const Duration(hours: 1)),
  expiresAt: _now.add(const Duration(hours: 1)),
  schemaVersion: 2,
  status: 'published',
  hasAuthorizedMedia: true,
);

Reel _reel() => Reel.fromV2Wire({
  'id': 'localized-reel',
  'authorId': 'creator',
  'authorName': 'Ada',
  'media': {
    'kind': 'video',
    'contentType': 'video/mp4',
    'size': 1024,
    'generation': '1',
    'durationMs': 15000,
  },
  'backingAudio': null,
  'composition': const ReelComposition(
    trimEndMs: 15000,
    caption: 'Authored caption stays unchanged.',
  ).toWire(),
  'publishedAtMillis': _now.millisecondsSinceEpoch,
  'sortKey': '${_now.millisecondsSinceEpoch}_localized-reel',
  'availability': {
    'schemaVersion': 1,
    'availabilityHours': 'permanent',
    'expiresAtMillis': null,
  },
  'likeCount': 2,
  'commentCount': 5,
  'callerLiked': false,
});

Future<void> _mount(
  WidgetTester tester,
  Widget child,
  String locale, {
  Size size = const Size(390, 1000),
  double scale = 1,
  GlobalKey? boundary,
  bool light = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        navigatorObservers: [appRouteObserver],
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  if (!_capture) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(
        'test/.screenshots/feed-localization-2026-09-11',
      )..createSync(recursive: true);
      File(
        '${directory.path}/$name.png',
      ).writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

File _materialIconsFont() {
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null) {
    final configured = File(
      '$configuredRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (configured.existsSync()) return configured;
  }
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final font = File(
      '${directory.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (font.existsSync()) return font;
    directory = directory.parent;
  }
  throw StateError('Could not locate the current Flutter SDK material font.');
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(_materialIconsFont().readAsBytesSync()),
          ),
        ))
        .load();
    // Real glyphs from a family already listed by AppTypography. The widget
    // test engine otherwise substitutes its test font for system fallback.
    final unicode = File(
      Platform.environment['YO_TEST_UNICODE_FONT'] ??
          '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    );
    if (unicode.existsSync()) {
      await (FontLoader('Arial Unicode MS')..addFont(
            Future.value(ByteData.sublistView(unicode.readAsBytesSync())),
          ))
          .load();
    } else if (_capture) {
      throw StateError('Set YO_TEST_UNICODE_FONT for Arabic render evidence.');
    }
  });
  late PublicIdentityRepository previousIdentity;
  setUp(() {
    previousIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'viewer')),
      fetchOverride: (uids) async => {
        for (final uid in uids) uid: {'uid': uid, 'role': 'user', 'vip': false},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });
  tearDown(() => PublicIdentityRepository.instance = previousIdentity);

  test(
    'all 14 exact keys have explicit nonempty translations in all 41 catalogs',
    () {
      const keys = {
        'Moments could not load',
        'No rooms are live right now — start one and your community will hear it.',
        'Play',
        'Pause',
        'Like',
        'Likes: {count}',
        'Comments: {count}',
        'Turn sound off',
        'Turn sound on',
        'View all',
        'Share',
        'Good morning,',
        'Good afternoon,',
        'Good evening,',
      };
      final locales = selectableAppLanguages
          .where((l) => !['en', 'pl'].contains(l.localeKey))
          .map((l) => l.localeKey)
          .toSet();
      expect(locales, hasLength(41));
      expect(feedSurfaceReleaseTranslationKeys, hasLength(14));
      expect(feedSurfaceReleaseTranslationKeys.toSet(), keys);
      expect(feedSurfaceReleaseTranslations.keys.toSet(), locales);
      final token = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');
      for (final locale in locales) {
        expect(feedSurfaceReleaseTranslations[locale]!.keys.toSet(), keys);
        for (final key in keys) {
          final value = appTranslations[locale]![key];
          expect(value, isNotNull, reason: '$locale / $key');
          expect(value!.trim(), isNotEmpty, reason: '$locale / $key');
          expect(
            value,
            isNot(key),
            reason: 'No English fallback: $locale / $key',
          );
          expect(
            token.allMatches(value).map((m) => m.group(0)).toList(),
            token.allMatches(key).map((m) => m.group(0)).toList(),
          );
        }
      }
    },
  );

  for (final locale in _expected.keys) {
    final expected = _expected[locale]!;
    test(
      '$locale actual AppLocalizations resolves 0,1,2,5 without plural sentences',
      () {
        final copy = AppLocalizations(Locale(locale));
        for (final count in [0, 1, 2, 5]) {
          expect(
            copy.template(
              'Likes: {count}',
              'Polubienia: {count}',
              values: {'count': count},
            ),
            expected['likes$count'],
          );
          expect(
            copy.template(
              'Comments: {count}',
              'Komentarze: {count}',
              values: {'count': count},
            ),
            expected['comments$count'],
          );
        }
        expect(copy.text('Play', 'Odtwórz'), expected['play']);
        expect(copy.text('Pause', 'Pauza'), expected['pause']);
        expect(copy.text('Like', 'Lubię to'), expected['like']);
        expect(copy.text('Share', 'Udostępnij'), expected['share']);
        expect(copy.text('View all', 'Zobacz wszystkie'), expected['viewAll']);
        expect(
          copy.text('Moments could not load', 'Nie udało się wczytać Momentów'),
          expected['error'],
        );
      },
    );
    for (final count in [0, 1, 2, 5]) {
      testWidgets(
        '$locale Voice card keeps exact count $count and localized play/pause',
        (tester) async {
          final auth = MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
          );
          final service = _Moments();
          final player = _Audio();
          final boundary = GlobalKey();
          await _mount(
            tester,
            MomentsFeedView(
              discoveryService: _Discovery(_moment(count)),
              feedService: _Feed(),
              momentService: service,
              viewsService: _Views(),
              auth: auth,
              expiryClock: () => _now,
              playerFactory: () => player,
              onRecord: () {},
              onOpenDetail: (_) {},
            ),
            locale,
            boundary: boundary,
          );
          final like = find.byKey(const ValueKey('moment-row-like-localized'));
          final comments = find.byKey(
            const ValueKey('moment-row-comments-localized'),
          );
          expect(
            find.descendant(
              of: like,
              matching: find.text(
                expected[count == 0 ? 'like' : 'likes$count']!,
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: comments,
              matching: find.text(
                expected[count == 0 ? 'comments' : 'comments$count']!,
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.text('Voice caption {count} stays unchanged.'),
            findsOneWidget,
          );
          expect(find.text(expected['share']!), findsOneWidget);
          final play = find.byKey(const ValueKey('moment-row-play-localized'));
          expect(tester.widget<IconButton>(play).tooltip, expected['play']);
          expect(
            Directionality.of(tester.element(play)),
            locale == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          );
          await tester.ensureVisible(play);
          await tester.tap(play);
          await tester.pumpAndSettle();
          expect(service.requested, ['localized']);
          expect(player.plays, 1);
          expect(tester.widget<IconButton>(play).tooltip, expected['pause']);
          expect(tester.takeException(), isNull);
          if (count == 2 && ['de', 'nl', 'ar'].contains(locale)) {
            await _shot(tester, boundary, 'voice-$locale-390-dark');
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  for (final locale in _footerExpected.keys) {
    final expected = _footerExpected[locale]!;
    for (final count in [0, 1, 2, 5]) {
      for (final moreExists in [true, false]) {
        if (count == 0 && !moreExists) {
          continue; // This is an empty state, not a footer.
        }
        testWidgets(
          '$locale footer total$count more$moreExists keeps real paging at200percent',
          (tester) async {
            final discovery = _PagingDiscovery(count, moreExists);
            final boundary = GlobalKey();
            await _mount(
              tester,
              MomentsFeedView(
                discoveryService: discovery,
                feedService: _Feed(),
                momentService: _Moments(),
                viewsService: _Views(),
                auth: MockFirebaseAuth(
                  signedIn: true,
                  mockUser: MockUser(uid: 'viewer'),
                ),
                expiryClock: () => _now,
                playerFactory: () => _Audio(),
                onRecord: () {},
                onOpenDetail: (_) {},
              ),
              locale,
              size: const Size(320, 1000),
              scale: 2,
              boundary: boundary,
            );
            final following = find.byKey(
              const ValueKey('moments-filter-following'),
            );
            expect(
              find.descendant(
                of: following,
                matching: find.text(expected['following']!),
              ),
              findsOneWidget,
            );
            final summary = moreExists
                ? expected['loaded$count']!
                : count == 1
                ? expected['only']!
                : expected['all$count']!;
            final scroll = find.descendant(
              of: find.byKey(const ValueKey('moments-feed-scroll')),
              matching: find.byType(Scrollable),
            );
            await tester.scrollUntilVisible(
              find.text(summary),
              450,
              scrollable: scroll,
            );
            await tester.pumpAndSettle();
            expect(find.text(summary), findsOneWidget);
            expect(tester.takeException(), isNull);
            final more = find.byKey(const ValueKey('moments-load-more'));
            if (moreExists) {
              await tester.ensureVisible(more);
              await tester.tap(more);
              await tester.pump();
              expect(discovery.requests, hasLength(1));
              expect(tester.widget<OutlinedButton>(more).onPressed, isNull);
              expect(find.text(summary), findsOneWidget);
              discovery.completePage();
              await tester.pumpAndSettle();
              final completed = count == 0
                  ? expected['only']!
                  : expected['all${count + 1}']!;
              await tester.scrollUntilVisible(
                find.text(completed),
                450,
                scrollable: scroll,
              );
              await tester.pumpAndSettle();
              expect(find.text(completed), findsOneWidget);
              expect(more, findsNothing);
              expect(discovery.requests, hasLength(1));
            } else {
              expect(more, findsNothing);
              expect(discovery.requests, isEmpty);
            }
            expect(tester.takeException(), isNull);
            if (count == 1 &&
                !moreExists &&
                ['de', 'nl', 'ar'].contains(locale)) {
              await _shot(tester, boundary, 'voice-footer-$locale-320-2x-dark');
            }
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
          },
        );
      }
    }

    if (['de', 'nl', 'ar'].contains(locale)) {
      testWidgets('$locale footer retry preserves the measured visible total', (
        tester,
      ) async {
        final discovery = _PagingDiscovery(1, true);
        await _mount(
          tester,
          MomentsFeedView(
            discoveryService: discovery,
            feedService: _Feed(),
            momentService: _Moments(),
            viewsService: _Views(),
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'viewer'),
            ),
            expiryClock: () => _now,
            playerFactory: () => _Audio(),
            onRecord: () {},
            onOpenDetail: (_) {},
          ),
          locale,
          size: const Size(320, 1000),
          scale: 2,
        );
        final more = find.byKey(const ValueKey('moments-load-more'));
        final scroll = find.descendant(
          of: find.byKey(const ValueKey('moments-feed-scroll')),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(more, 450, scrollable: scroll);
        await tester.tap(more);
        await tester.pump();
        discovery.requests.single.completeError(
          StateError('PRIVATE_PAGE_FAILURE'),
        );
        await tester.pumpAndSettle();
        expect(find.text(expected['loaded1']!), findsOneWidget);
        expect(find.textContaining('PRIVATE_PAGE_FAILURE'), findsNothing);
        expect(
          find.descendant(of: more, matching: find.text(expected['retry']!)),
          findsOneWidget,
        );
        await tester.ensureVisible(more);
        await tester.tap(more);
        await tester.pump();
        expect(discovery.requests, hasLength(2));
        discovery.completePage();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(expected['all2']!),
          450,
          scrollable: scroll,
        );
        expect(find.text(expected['all2']!), findsOneWidget);
        expect(more, findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }

  for (final locale in ['de', 'nl', 'ar']) {
    final expected = _expected[locale]!;
    testWidgets(
      '$locale actual Reel rail has localized counts, share and sound actions',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final sound = ValueNotifier(false);
          addTearDown(sound.dispose);
          final service = ReelService(
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
            ),
            callableInvoker: (name, payload) async {
              if (name == 'getReelMediaAccessV2') {
                return {
                  'schemaVersion': 2,
                  'url':
                      'https://storage.googleapis.com/demo-yovoice/fixture.mp4',
                  'expiresAtMillis': _now
                      .add(const Duration(minutes: 5))
                      .millisecondsSinceEpoch,
                  'generation': '1',
                  'availabilityHours': 'permanent',
                  'contentExpiresAtMillis': null,
                };
              }
              if (name == 'recordReelViewedV2') return {'schemaVersion': 2};
              throw StateError('Unexpected test callable: $name');
            },
          );
          var shares = 0;
          final boundary = GlobalKey();
          await _mount(
            tester,
            ReelCard(
              reel: _reel(),
              service: service,
              now: () => _now,
              soundOn: sound,
              videoBuilder: (_, _, _) =>
                  const ColoredBox(color: Color(0xFF596F68)),
              videoPlaybackFactory: (_, _) => _Video(),
              onShare: () async {
                shares++;
              },
              onLike: () {},
              onComments: () {},
              onOpenAuthor: (_) {},
            ),
            locale,
            size: const Size(390, 844),
            boundary: boundary,
          );
          expect(find.byTooltip(expected['soundOn']!), findsOneWidget);
          expect(find.byTooltip(expected['shareReel']!), findsOneWidget);
          expect(
            find.bySemanticsLabel('${expected['like']}. ${expected['likes2']}'),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(
              RegExp(RegExp.escape(expected['comments5']!)),
            ),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('reel-share-action')));
          expect(shares, 1);
          await tester.tap(find.byKey(const ValueKey('reel-sound-toggle')));
          await tester.pumpAndSettle();
          expect(sound.value, isTrue);
          expect(find.byTooltip(expected['soundOff']!), findsOneWidget);
          await tester.longPress(
            find.byKey(const ValueKey('reel-sound-toggle')),
          );
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text(expected['soundOff']!), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _shot(tester, boundary, 'reels-$locale-390-dark-tooltip');
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '$locale real Home error and header reflow at 320px 200 percent',
      (tester) async {
        final feed = _Feed()..fail = true;
        final boundary = GlobalKey();
        var viewAll = 0;
        var created = 0;
        await _mount(
          tester,
          HomeErrorAnnouncementScope(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HomeConversationInvitation(
                    actions: HomeQuickActions(
                      onCreateRoom: () => created++,
                      onFriends: () {},
                    ),
                  ),
                  HomeSectionHeader(
                    title: 'Moments',
                    onSeeAll: () => viewAll++,
                  ),
                  DesktopMomentsStrip(
                    currentUserId: 'viewer',
                    feedService: feed,
                    followService: _Following(),
                    friendService: _Friends(),
                    viewsService: _Views(),
                    avatarOnly: true,
                    showOwnTile: false,
                    onOpenMoment: (_) {},
                    onCreateMoment: () {},
                    onSeeAll: () {},
                  ),
                ],
              ),
            ),
          ),
          locale,
          size: const Size(320, 1200),
          scale: 2,
          light: true,
          boundary: boundary,
        );
        expect(find.text(expected['viewAll']!), findsOneWidget);
        expect(find.text(expected['error']!), findsOneWidget);
        expect(find.textContaining('PRIVATE_TEST_ERROR'), findsNothing);
        expect(
          find.text(
            'No rooms are live right now — start one and your community will hear it.',
          ),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('home-quick-create-room')));
        expect(created, 1);
        await tester.ensureVisible(find.text(expected['viewAll']!));
        await tester.tap(find.text(expected['viewAll']!));
        expect(viewAll, 1);
        expect(tester.takeException(), isNull);
        await _shot(tester, boundary, 'home-$locale-320-2x-pearl');
        final error = find.byKey(const ValueKey('home-moments-error'));
        final retry = find.descendant(
          of: error,
          matching: find.byWidgetPredicate(
            (widget) => widget is OutlinedButton,
          ),
        );
        expect(retry, findsOneWidget);
        feed.fail = false;
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(feed.reads, 2);
        expect(error, findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
