// Independent boundary tests. Only explicit service/platform seams are fake;
// parsers, intent coordinator, sharing and nested destination UI are real.
// This is not OS-share, deployed-login, device-media or backend Rules proof.
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
// The installed url_launcher plugin owns this locked test-only platform seam.
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/reel_links.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/navigation/reel_link_coordinator.dart';
import 'package:yovoice/features/reels/presentation/screens/reel_link_destination_screen.dart';
import 'package:yovoice/features/reels/presentation/sharing/reel_share.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

const _uid = 'independent-viewer-A';
const _author = 'independent-publisher';
const _caption = 'QA_PRIVATE_CAPTION';
const _quote = 'QA_PRIVATE_COMMENT_QUOTE';
const _draft = 'QA_PRIVATE_REPORT_DRAFT';
const _commentId = 'qa_comment';
int _sequence = 0;

class _Auth extends MockFirebaseAuth {
  User? _principal = MockUser(uid: _uid, isEmailVerified: true);
  final _events = StreamController<User?>.broadcast(sync: true);

  @override
  User? get currentUser => _principal;
  @override
  Stream<User?> userChanges() => _events.stream;

  void change(String? uid) {
    _principal = uid == null ? null : MockUser(uid: uid, isEmailVerified: true);
    _events.add(_principal);
  }

  void fail() => _events.addError(StateError('QA_PRIVATE_AUTH_FAILURE'));
  Future<void> close() => _events.close();
}

class _Video implements ReelVideoPlayback {
  @override
  bool isPlaying = false;
  @override
  Duration position = Duration.zero;
  double volume = -1;

  @override
  Future<void> pause() async => isPlaying = false;
  @override
  Future<void> play() async => isPlaying = true;
  @override
  Future<void> seek(Duration value) async => position = value;
  @override
  Future<void> setVolume(double value) async => volume = value;
}

class _LinkLauncher extends UrlLauncherPlatform {
  final launches = <({String url, LaunchOptions options})>[];

  @override
  Null get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches.add((url: url, options: options));
    return true;
  }
}

class _Fixture {
  _Fixture() : id = 'independent_link_${++_sequence}' {
    service = ReelService(auth: auth, callableInvoker: _call);
  }

  final String id;
  final auth = _Auth();
  late final ReelService service;
  final calls = <({String name, Map<String, Object?> payload})>[];
  final videos = <_Video>[];
  DateTime now = DateTime.now().toUtc();
  DateTime? expiry;
  String? replyId;
  String authorId = _author;
  String commentAuthorId = _author;
  bool denied = false;
  bool withComment = false;
  bool withLinks = false;
  Future<Map<Object?, Object?>> Function(int read)? viewReply;
  int _reads = 0;

  Map<Object?, Object?> view() => {
    'schemaVersion': 2,
    'reel': {
      'id': replyId ?? id,
      'authorId': authorId,
      'authorName': 'QA_PRIVATE_AUTHOR',
      'media': {
        'kind': 'video',
        'contentType': 'video/mp4',
        'size': 4096,
        'generation': '5',
        'durationMs': 20000,
      },
      'backingAudio': null,
      'composition': ReelComposition(
        trimEndMs: 20000,
        caption: _caption,
        linkOverlays: withLinks
            ? List.generate(
                4,
                (index) => ReelLinkOverlay(
                  id: 'metadata_$index',
                  label: 'QA_PRIVATE_LINK_$index',
                  uri: Uri.parse('https://example.com/qa-link-$index'),
                  x: .5,
                  y: index / 3,
                ),
              )
            : const [],
      ).toWire(),
      'publishedAtMillis': 1725000000000,
      'sortKey': '1725000000000_${replyId ?? id}',
      'availability': {
        'schemaVersion': expiry == null ? 1 : 2,
        'availabilityHours': expiry == null ? 'permanent' : 24,
        'expiresAtMillis': expiry?.millisecondsSinceEpoch,
      },
      'likeCount': 1,
      'commentCount': withComment ? 1 : 0,
      'callerLiked': false,
    },
    'comments': <Object?>[
      if (withComment)
        {
          'schemaVersion': 1,
          'commentId': _commentId,
          'type': 'text',
          'authorId': commentAuthorId,
          'authorName': 'QA_PRIVATE_COMMENTER',
          'authorPhotoUrl': null,
          'text': _quote,
          'durationSeconds': null,
          'createdAtMillis': 1725000000000,
        },
    ],
    'commentsTruncated': false,
    'nextCommentCursor': null,
  };

  Future<Map<Object?, Object?>> _call(
    String name,
    Map<String, Object?> payload,
  ) async {
    calls.add((name: name, payload: Map.of(payload)));
    if (name == 'getReelViewV2') {
      final read = ++_reads;
      if (denied) {
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'QA_PRIVATE_BACKEND_REASON',
        );
      }
      final reply = viewReply;
      if (reply != null) return reply(read);
      return view();
    }
    if (name == 'getReelMediaAccessV2') {
      return {
        'schemaVersion': 2,
        'url': 'https://storage.googleapis.com/local-qa/$id.mp4?token=PRIVATE',
        'expiresAtMillis': DateTime.now()
            .add(const Duration(seconds: 90))
            .millisecondsSinceEpoch,
        'generation': '5',
        'availabilityHours': expiry == null ? 'permanent' : 24,
        'contentExpiresAtMillis': expiry?.millisecondsSinceEpoch,
      };
    }
    if (name == 'recordReelViewedV2') return {'schemaVersion': 2};
    throw StateError('Unexpected independent QA operation: $name');
  }

  Iterable<String> get mutations => calls
      .map((call) => call.name)
      .where(
        (name) => !['getReelViewV2', 'getReelMediaAccessV2'].contains(name),
      );

  ReelVideoPlayback video(Uri _, Reel _) {
    final video = _Video();
    videos.add(video);
    return video;
  }
}

Widget _app(Widget home, {GlobalKey<NavigatorState>? navigator}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  navigatorKey: navigator,
  navigatorObservers: [appRouteObserver],
  theme: AppTheme.darkTheme,
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

Future<void> _settle(WidgetTester tester) async {
  // A deliberately pending authorization may display an endless spinner.
  // Flush route animations and microtasks without requiring it to disappear.
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _mount(
  WidgetTester tester,
  Widget home, {
  GlobalKey<NavigatorState>? navigator,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  await tester.pumpWidget(_app(home, navigator: navigator));
  await _settle(tester);
}

Future<void> _destination(
  WidgetTester tester,
  _Fixture f, {
  GlobalKey<NavigatorState>? navigator,
  String? id,
}) => _mount(
  tester,
  ReelLinkDestinationScreen(
    reelId: id ?? f.id,
    service: f.service,
    now: () => f.now,
    videoPlaybackFactory: f.video,
    videoBuilder: (_, _, _) => const ColoredBox(color: Colors.indigo),
  ),
  navigator: navigator,
);

Future<void> _sharing(
  WidgetTester tester,
  _Fixture f, {
  required ReelShareInvoker share,
  required ReelLinkClipboardWriter copy,
  String? secondId,
  GlobalKey<NavigatorState>? navigator,
}) async {
  await _mount(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          key: const ValueKey('qa-open-share'),
          onPressed: () {
            final flight = showReelShareSheet(
              context,
              reelId: f.id,
              service: f.service,
              shareInvoker: share,
              clipboardWriter: copy,
              now: () => f.now,
            );
            if (secondId != null) {
              final second = showReelShareSheet(
                context,
                reelId: secondId,
                service: f.service,
                shareInvoker: share,
                clipboardWriter: copy,
                now: () => f.now,
              );
              expect(identical(flight, second), isTrue);
            }
            unawaited(flight);
          },
          child: const Text('Open'),
        ),
      ),
    ),
    navigator: navigator,
  );
  await tester.tap(find.byKey(const ValueKey('qa-open-share')));
  await _settle(tester);
}

Future<void> _openCommentAction(WidgetTester tester, String action) async {
  if (action == 'remove') {
    await tester.tap(
      find.byKey(const ValueKey('reel-comment-actions-$_commentId')),
    );
    await _settle(tester);
  }
  await tester.tap(find.byKey(ValueKey('reel-comment-$action-$_commentId')));
  await _settle(tester);
}

Future<void> _openReport(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('reel-comments-action')));
  await _settle(tester);
  await _openCommentAction(tester, 'report');
  expect(
    find.byKey(const ValueKey('reel-comment-report-target')),
    findsOneWidget,
  );
}

void _noPrivateText() {
  expect(find.textContaining('QA_PRIVATE_', skipOffstage: false), findsNothing);
}

void _noPrivateCommentState() {
  // The same-account destination deliberately retains an offstage player;
  // separate report/comment routes must discard their private model and draft.
  expect(find.textContaining('QA_PRIVATE_'), findsNothing);
  for (final text in [_quote, _draft, 'QA_PRIVATE_COMMENTER']) {
    expect(find.textContaining(text, skipOffstage: false), findsNothing);
  }
}

void main() {
  final fixtures = <_Fixture>[];
  late UrlLauncherPlatform originalLauncher;
  late _LinkLauncher linkLauncher;
  _Fixture fixture() {
    final value = _Fixture();
    fixtures.add(value);
    return value;
  }

  setUp(() {
    ReelService.clearAllMediaAccessCaches();
    originalLauncher = UrlLauncherPlatform.instance;
    linkLauncher = _LinkLauncher();
    UrlLauncherPlatform.instance = linkLauncher;
  });
  tearDown(() async {
    UrlLauncherPlatform.instance = originalLauncher;
    for (final f in fixtures) {
      await f.auth.close();
    }
    fixtures.clear();
  });

  test(
    'independent forged links never become redirects or bearer transports',
    () {
      final hostile = [
        'https://app.yovoice.app:444/?reel=x',
        'https://app.yovoice.app./?reel=x',
        'https://app.yovoice.app.evil.invalid/?reel=x',
        'https://app.yovoice.app%40evil.invalid/?reel=x',
        'https://evil.invalid@app.yovoice.app/?reel=x',
        'http://app.yovoice.app/?reel=x',
        '//app.yovoice.app/?reel=x',
        'https://app.yovoice.app/reel?reel=x',
        'https://app.yovoice.app/?reel=x&%72eel=y',
        'https://app.yovoice.app/?reel=x&returnUrl=https%3A%2F%2Fevil.invalid',
        'https://app.yovoice.app/?reel=x&X-Goog-Signature=private',
        'https://app.yovoice.app/?reel=x&authorName=private',
        'https://app.yovoice.app/?reel=x#',
        'https://app.yovoice.app/?reel=%252Fprivate',
        'https://app.yovoice.app/?reel=x%00',
        'https://app.yovoice.app/?reel=x%0D%0A',
        'https://app.yovoice.app/?reel=%E2%88%95private',
        'https://app.yovoice.app/?reel=${'z' * 129}',
      ];
      for (final value in hostile) {
        final uri = Uri.tryParse(value);
        expect(uri == null ? null : parseReelLink(uri), isNull, reason: value);
      }
      for (final id in ['A', 'a_B-19', 'z' * 128]) {
        final uri = buildReelLink(id);
        expect(parseReelLink(uri), id);
        expect(uri.queryParametersAll, {
          'reel': [id],
        });
        expect(uri.userInfo, isEmpty);
        expect(uri.hasFragment, isFalse);
      }
      // Dart canonicalizes explicit HTTPS :443 before this Uri API receives it.
      // It is the same authority, not permission to use a nonstandard port.
      expect(
        parseReelLink(Uri.parse('https://app.yovoice.app:443/?reel=x')),
        'x',
      );
    },
  );

  test(
    'independent intent drops every observed principal-exit epoch',
    () async {
      for (final sequence in <List<String?>>[
        [_uid, null, _uid],
        [_uid, 'B', _uid],
        [null, _uid, null, _uid],
      ]) {
        final intent = ReelLinkIntentController(
          initialUri: buildReelLink('target'),
        );
        for (final uid in sequence) {
          intent.handlePrincipal(uid);
        }
        expect(intent.consumeFor(_uid), isNull);
        await intent.initialVisitCompleted;
        intent.dispose();
      }
      final intent = ReelLinkIntentController(
        initialUri: buildReelLink('target'),
      );
      intent.handlePrincipal(null);
      intent.handleAuthError();
      intent.handlePrincipal(_uid);
      expect(intent.consumeFor(_uid), isNull);
      await intent.initialVisitCompleted;
      intent.dispose();
    },
  );

  testWidgets(
    'independent deferred entry cannot reopen after same-frame UID ABA',
    (tester) async {
      final intent = ReelLinkIntentController(
        initialUri: buildReelLink('target'),
      );
      final ready = ValueNotifier<bool>(false);
      final navigator = GlobalKey<NavigatorState>();
      var destinations = 0;
      addTearDown(intent.dispose);
      addTearDown(ready.dispose);
      intent.handlePrincipal(_uid);
      await _mount(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: ready,
          builder: (_, isReady, _) => isReady
              ? ReelLinkEntryCoordinator(
                  controller: intent,
                  userId: _uid,
                  destinationBuilder: (_, _) {
                    destinations++;
                    return const Scaffold(body: Text('Private destination'));
                  },
                  child: const Scaffold(body: Text('Ready shell')),
                )
              : const Scaffold(body: Text('Profile setup')),
        ),
        navigator: navigator,
      );
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Text('Foreign verification route')),
          ),
        ),
      );
      await _settle(tester);
      ready.value = true;
      await _settle(tester);
      expect(destinations, 0);
      intent.handlePrincipal(null);
      intent.handlePrincipal(_uid);
      navigator.currentState!.pop();
      await _settle(tester);
      expect(find.text('Ready shell'), findsOneWidget);
      expect(destinations, 0);
      await intent.initialVisitCompleted;
    },
  );

  testWidgets(
    'independent login readiness consumes once and never on another UID',
    (tester) async {
      final intent = ReelLinkIntentController(
        initialUri: buildReelLink('target'),
      );
      final ready = ValueNotifier<bool>(false);
      final navigator = GlobalKey<NavigatorState>();
      final targets = <String>[];
      addTearDown(intent.dispose);
      addTearDown(ready.dispose);
      intent.handlePrincipal(null);
      await _mount(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: ready,
          builder: (_, isReady, _) => isReady
              ? ReelLinkEntryCoordinator(
                  controller: intent,
                  userId: _uid,
                  destinationBuilder: (_, id) {
                    targets.add(id);
                    return const Scaffold(body: Text('Authorized destination'));
                  },
                  child: const Scaffold(body: Text('Shell')),
                )
              : const Scaffold(body: Text('Login')),
        ),
        navigator: navigator,
      );
      expect(targets, isEmpty);
      intent.handlePrincipal(_uid);
      expect(intent.consumeFor('foreign-principal'), isNull);
      await _settle(tester);
      expect(targets, isEmpty);
      ready.value = true;
      await _settle(tester);
      expect(targets, ['target']);
      navigator.currentState!.pop();
      await _settle(tester);
      await intent.initialVisitCompleted;
      intent.handlePrincipal(_uid);
      await _settle(tester);
      expect(targets, ['target']);
      expect(find.text('Shell'), findsOneWidget);
    },
  );

  testWidgets(
    'independent competing share requests preserve one authorized ID only',
    (tester) async {
      final f = fixture();
      final shared = <ShareParams>[];
      final copied = <String>[];
      await _sharing(
        tester,
        f,
        secondId: 'different_target',
        share: (params) async {
          shared.add(params);
          return const ShareResult('', ShareResultStatus.dismissed);
        },
        copy: (text) async => copied.add(text),
      );
      expect(f.calls.single.name, 'getReelViewV2');
      expect(f.calls.single.payload['reelId'], f.id);
      expect(find.byKey(const ValueKey('reel-share-sheet')), findsOneWidget);
      _noPrivateText();
      expect(shared, isEmpty);
      expect(copied, isEmpty);
      await tester.tap(find.byKey(const ValueKey('reel-share-platform')));
      await _settle(tester);
      final params = shared.single;
      expect(params.text, buildReelLink(f.id).toString());
      expect(params.uri, isNull);
      expect(params.files, isNull);
      expect(params.subject, isNull);
      expect(params.title, isNull);
      expect(params.downloadFallbackEnabled, isFalse);
      expect(params.mailToFallbackEnabled, isFalse);
      expect(
        params.sharePositionOrigin!.shortestSide,
        greaterThanOrEqualTo(44),
      );
      expect(copied, isEmpty);
      await tester.tap(find.byKey(const ValueKey('reel-share-copy')));
      await _settle(tester);
      expect(copied, [buildReelLink(f.id).toString()]);
      expect(f.calls, hasLength(1));
      expect(f.mutations, isEmpty);
    },
  );

  testWidgets(
    'independent unavailable share result is unknown not delivery or failure',
    (tester) async {
      final f = fixture();
      final completion = Completer<ShareResult>();
      var shared = 0;
      final copied = <String>[];
      await _sharing(
        tester,
        f,
        share: (_) {
          shared++;
          return completion.future;
        },
        copy: (text) async => copied.add(text),
      );
      await tester.tap(find.byKey(const ValueKey('reel-share-platform')));
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('reel-share-copy')),
            )
            .onPressed,
        isNull,
      );
      expect(shared, 1);
      completion.complete(const ShareResult('', ShareResultStatus.unavailable));
      await _settle(tester);
      expect(
        find.text('Sharing could not be confirmed. You can copy the link.'),
        findsOneWidget,
      );
      expect(
        find.text('Sharing is unavailable here. Copy the link instead.'),
        findsNothing,
      );
      expect(find.text('Reel link copied.'), findsNothing);
      expect(copied, isEmpty);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('reel-share-copy')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'independent stale authorized share callbacks are fenced after UID ABA',
    (tester) async {
      final f = fixture();
      var shares = 0;
      var copies = 0;
      await _sharing(
        tester,
        f,
        share: (_) async {
          shares++;
          return const ShareResult('', ShareResultStatus.success);
        },
        copy: (_) async {
          copies++;
        },
      );
      final share = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('reel-share-platform')),
          )
          .onPressed!;
      final copy = tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('reel-share-copy')))
          .onPressed!;
      f.auth.change(null);
      f.auth.change(_uid);
      share();
      copy();
      await _settle(tester);
      expect(shares, 0);
      expect(copies, 0);
      expect(find.byKey(const ValueKey('reel-share-platform')), findsNothing);
      expect(find.text('Sign in to open this Reel.'), findsOneWidget);
      _noPrivateText();
    },
  );

  testWidgets(
    'independent expiry is checked at action time before timer repaint',
    (tester) async {
      final f = fixture();
      f.expiry = f.now.add(const Duration(seconds: 10));
      var calls = 0;
      await _sharing(
        tester,
        f,
        share: (_) async {
          calls++;
          return const ShareResult('', ShareResultStatus.success);
        },
        copy: (_) async {
          calls++;
        },
      );
      final share = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('reel-share-platform')),
          )
          .onPressed!;
      final copy = tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('reel-share-copy')))
          .onPressed!;
      f.now = f.expiry!;
      share();
      copy();
      await tester.pump();
      expect(calls, 0);
      await tester.pump(const Duration(seconds: 10));
      expect(find.byKey(const ValueKey('reel-share-platform')), findsNothing);
      expect(find.byKey(const ValueKey('reel-share-copy')), findsNothing);
      expect(find.text('This Reel is unavailable right now.'), findsOneWidget);
    },
  );

  testWidgets(
    'independent pending share authorization cannot survive auth error',
    (tester) async {
      final f = fixture();
      final pending = Completer<Map<Object?, Object?>>();
      f.viewReply = (_) => pending.future;
      var effects = 0;
      await _sharing(
        tester,
        f,
        share: (_) async {
          effects++;
          return const ShareResult('', ShareResultStatus.success);
        },
        copy: (_) async {
          effects++;
        },
      );
      f.auth.fail();
      pending.complete(f.view());
      await _settle(tester);
      expect(find.byKey(const ValueKey('reel-share-platform')), findsNothing);
      expect(find.text('Sign in to open this Reel.'), findsOneWidget);
      expect(effects, 0);
      _noPrivateText();
    },
  );

  testWidgets(
    'independent invalid signed-out and mismatched destinations initialize no media',
    (tester) async {
      for (final mode in ['invalid', 'signed-out', 'mismatched']) {
        final f = fixture();
        if (mode == 'signed-out') f.auth.change(null);
        if (mode == 'mismatched') f.replyId = 'foreign_target';
        await _destination(
          tester,
          f,
          id: mode == 'invalid' ? '../private' : null,
        );
        expect(find.byType(ReelCard, skipOffstage: false), findsNothing);
        expect(f.videos, isEmpty);
        expect(
          f.calls.where((call) => call.name == 'getReelMediaAccessV2'),
          isEmpty,
        );
        expect(f.calls, hasLength(mode == 'mismatched' ? 1 : 0));
        _noPrivateText();
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'independent delayed destination response stays retired through UID ABA',
    (tester) async {
      final f = fixture();
      final pending = Completer<Map<Object?, Object?>>();
      f.viewReply = (_) => pending.future;
      await _destination(tester, f);
      f.auth.change(null);
      f.auth.change(_uid);
      pending.complete(f.view());
      await _settle(tester);
      expect(find.byType(ReelCard, skipOffstage: false), findsNothing);
      expect(f.videos, isEmpty);
      expect(
        f.calls.where((call) => call.name == 'getReelMediaAccessV2'),
        isEmpty,
      );
      expect(find.text('Sign in to open this Reel.'), findsOneWidget);
      _noPrivateText();
    },
  );

  testWidgets(
    'independent background reauthorization denial cannot resume retained player',
    (tester) async {
      final f = fixture();
      await _destination(tester, f);
      expect(f.videos.single.isPlaying, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.scheduleForcedFrame();
      await tester.pump();
      await tester.pump();
      expect(f.videos.every((video) => !video.isPlaying), isTrue);
      f.denied = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(
        f.calls.where((call) => call.name == 'getReelViewV2'),
        hasLength(2),
      );
      expect(find.byType(ReelCard, skipOffstage: false), findsNothing);
      expect(find.text('This Reel is unavailable right now.'), findsOneWidget);
      expect(f.videos.every((video) => !video.isPlaying), isTrue);
      _noPrivateText();
    },
  );

  testWidgets(
    'independent nested report expiry clears draft and never pops foreign route',
    (tester) async {
      final f = fixture()..withComment = true;
      f.expiry = f.now.add(const Duration(seconds: 20));
      final navigator = GlobalKey<NavigatorState>();
      await _destination(tester, f, navigator: navigator);
      await _openReport(tester);
      await tester.enterText(
        find.byKey(const ValueKey('reel-comment-report-note')),
        _draft,
      );
      await tester.pump();
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Text('Foreign route must survive')),
          ),
        ),
      );
      await _settle(tester);
      f.now = f.expiry!;
      await tester.pump(const Duration(seconds: 20));
      _noPrivateText();
      expect(find.byType(ReelCommentsView, skipOffstage: false), findsNothing);
      final close = tester
          .widget<TextButton>(
            find.byKey(
              const ValueKey('reel-link-comment-overlay-close'),
              skipOffstage: false,
            ),
          )
          .onPressed!;
      close();
      await tester.pump();
      expect(find.text('Foreign route must survive'), findsOneWidget);
      navigator.currentState!.pop();
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('reel-link-comment-overlay-unavailable')),
        findsOneWidget,
      );
      _noPrivateText();
      expect(f.mutations, isEmpty);
    },
  );

  testWidgets(
    'independent background retires report form permanently before fresh host access',
    (tester) async {
      final f = fixture()..withComment = true;
      await _destination(tester, f);
      await _openReport(tester);
      await tester.enterText(
        find.byKey(const ValueKey('reel-comment-report-note')),
        _draft,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.scheduleForcedFrame();
      await tester.pump();
      _noPrivateCommentState();
      f.denied = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(
        find.byKey(
          const ValueKey('reel-comment-report-note'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('reel-link-comment-overlay-unavailable')),
        findsOneWidget,
      );
      _noPrivateCommentState();
      await tester.tap(
        find.byKey(const ValueKey('reel-link-comment-overlay-close')),
      );
      await _settle(tester);
      f.denied = false;
      final host = find.byKey(const ValueKey('reel-link-comments-host'));
      await tester.tap(
        find.descendant(of: host, matching: find.text('Try again')),
      );
      await _settle(tester);
      await _openCommentAction(tester, 'report');
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('reel-comment-report-note')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(f.mutations, isEmpty);
    },
  );

  for (final action in ['remove', 'delete']) {
    testWidgets(
      'independent nested $action confirmation cannot survive same-frame UID ABA',
      (tester) async {
        final f = fixture()..withComment = true;
        if (action == 'remove') f.authorId = _uid;
        if (action == 'delete') f.commentAuthorId = _uid;
        await _destination(tester, f);
        await tester.tap(find.byKey(const ValueKey('reel-comments-action')));
        await _settle(tester);
        await _openCommentAction(tester, action);
        expect(
          find.byKey(ValueKey('reel-comment-$action-confirm')),
          findsOneWidget,
        );
        f.auth.change(null);
        f.auth.change(_uid);
        await _settle(tester);
        expect(
          find.byKey(
            ValueKey('reel-comment-$action-confirm'),
            skipOffstage: false,
          ),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('reel-link-comment-overlay-unavailable')),
          findsOneWidget,
        );
        _noPrivateText();
        expect(f.mutations, isEmpty);
      },
    );
  }

  testWidgets(
    'independent stale generic action menu cannot create a private dialog',
    (tester) async {
      final f = fixture()
        ..withComment = true
        ..authorId = _uid;
      await _destination(tester, f);
      await tester.tap(find.byKey(const ValueKey('reel-comments-action')));
      await _settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('reel-comment-actions-$_commentId')),
      );
      await _settle(tester);
      f.auth.fail();
      await _settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('reel-comment-remove-$_commentId')),
      );
      await _settle(tester);
      expect(
        find.byKey(
          const ValueKey('reel-comment-remove-confirm'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      _noPrivateText();
      expect(f.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final entry in ['more', 'caption']) {
    for (final exit in [
      'UID ABA',
      'auth error',
      'expiry',
      'background',
      'card removed',
      'source replaced',
    ]) {
      testWidgets(
        'independent $entry metadata and saved link retire on $exit without foreign pop',
        (tester) async {
          final f = fixture()..withLinks = true;
          f.expiry = f.now.add(const Duration(seconds: 20));
          final navigator = GlobalKey<NavigatorState>();
          final reel = Reel.fromV2Wire((f.view()['reel']));
          var showCard = true;
          var service = f.service;
          late StateSetter updateHost;
          await _mount(
            tester,
            Scaffold(
              body: StatefulBuilder(
                builder: (_, setState) {
                  updateHost = setState;
                  if (!showCard) return const Text('Card removed by its host');
                  return ReelCard(
                    key: ValueKey(f.id),
                    reel: reel,
                    service: service,
                    now: () => f.now,
                    videoPlaybackFactory: f.video,
                    videoBuilder: (_, _, _) =>
                        const ColoredBox(color: Colors.indigo),
                  );
                },
              ),
            ),
            navigator: navigator,
          );
          final control = entry == 'more'
              ? find.byKey(const ValueKey('reel-more-action'))
              : find.byWidgetPredicate(
                  (widget) =>
                      widget is AccessibleTapRegion &&
                      widget.semanticLabel == _caption,
                );
          expect(control.hitTestable(), findsOneWidget);
          await tester.tap(control);
          await _settle(tester);
          final modal = find.byType(BottomSheet, skipOffstage: false).last;
          expect(
            find.descendant(
              of: modal,
              matching: find.byWidgetPredicate(
                (widget) => widget is SelectableText && widget.data == _caption,
              ),
            ),
            findsOneWidget,
          );
          for (var index = 0; index < 4; index++) {
            final link = find.byKey(
              ValueKey('reel-details-link-metadata_$index'),
            );
            await tester.ensureVisible(link);
            await tester.pump();
            expect(tester.getSize(link).height, greaterThanOrEqualTo(44));
            expect(link.hitTestable(), findsOneWidget);
            await tester.tap(link);
            await _settle(tester);
          }
          expect(
            linkLauncher.launches.map((launch) => launch.url),
            List.generate(4, (index) => 'https://example.com/qa-link-$index'),
          );
          expect(
            linkLauncher.launches.every(
              (launch) =>
                  launch.options.mode ==
                  PreferredLaunchMode.externalApplication,
            ),
            isTrue,
          );
          final savedLink = tester
              .widget<ListTile>(
                find.byKey(const ValueKey('reel-details-link-metadata_0')),
              )
              .onTap!;
          unawaited(
            navigator.currentState!.push<void>(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Text('Foreign metadata route')),
              ),
            ),
          );
          await _settle(tester);
          switch (exit) {
            case 'UID ABA':
              f.auth.change(null);
              f.auth.change(_uid);
            case 'auth error':
              f.auth.fail();
            case 'expiry':
              f.now = f.expiry!;
              // The saved handler must check the clock even before repaint.
              savedLink();
              expect(linkLauncher.launches, hasLength(4));
              await tester.pump(const Duration(seconds: 20));
            case 'background':
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.paused,
              );
              tester.binding.scheduleForcedFrame();
              await tester.pump();
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.resumed,
              );
            case 'card removed':
              updateHost(() => showCard = false);
            case 'source replaced':
              updateHost(() {
                service = ReelService(auth: f.auth, callableInvoker: f._call);
              });
          }
          await _settle(tester);
          savedLink();
          await tester.pump();
          expect(linkLauncher.launches, hasLength(4));
          expect(
            find.descendant(
              of: modal,
              matching: find.textContaining('QA_PRIVATE_', skipOffstage: false),
              skipOffstage: false,
            ),
            findsNothing,
          );
          final close = tester
              .widget<TextButton>(
                find.byKey(
                  const ValueKey('reel-link-comment-overlay-close'),
                  skipOffstage: false,
                ),
              )
              .onPressed!;
          close();
          await tester.pump();
          expect(find.text('Foreign metadata route'), findsOneWidget);
          navigator.currentState!.pop();
          await _settle(tester);
          expect(
            find.byKey(const ValueKey('reel-link-comment-overlay-unavailable')),
            findsOneWidget,
          );
          expect(f.mutations, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'independent delayed comments page cannot reinstall retired private thread',
    (tester) async {
      final f = fixture()..withComment = true;
      final pending = Completer<Map<Object?, Object?>>();
      f.viewReply = (read) {
        if (read < 3) return Future.value(f.view());
        return pending.future;
      };
      await _destination(tester, f);
      await tester.tap(find.byKey(const ValueKey('reel-comments-action')));
      await _settle(tester);
      expect(
        f.calls.where((call) => call.name == 'getReelViewV2'),
        hasLength(3),
      );
      f.auth.change(null);
      f.auth.change(_uid);
      pending.complete(f.view());
      await _settle(tester);
      expect(find.byType(ReelCommentsView, skipOffstage: false), findsNothing);
      _noPrivateText();
      expect(f.mutations, isEmpty);
    },
  );
}
