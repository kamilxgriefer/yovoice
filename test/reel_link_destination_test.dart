import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reel_link_destination_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';

class _Auth extends MockFirebaseAuth {
  User? _user = MockUser(uid: 'viewer-a', isEmailVerified: true);
  final _changes = StreamController<User?>.broadcast(sync: true);
  @override
  User? get currentUser => _user;
  @override
  Stream<User?> userChanges() => _changes.stream;
  void change(String? uid) {
    _user = uid == null ? null : MockUser(uid: uid, isEmailVerified: true);
    _changes.add(_user);
  }

  void fail() => _changes.addError(StateError('Synthetic identity failure'));

  Future<void> close() => _changes.close();
}

class _Service extends ReelService {
  _Service({required super.auth, required super.callableInvoker});
  int viewed = 0;
  @override
  Future<void> recordViewed(Reel reel) async {
    viewed++;
  }
}

class _Video implements ReelVideoPlayback {
  @override
  bool isPlaying = false;
  @override
  Duration position = Duration.zero;
  double volume = -1;
  @override
  Future<void> pause() async {
    isPlaying = false;
  }

  @override
  Future<void> play() async {
    isPlaying = true;
  }

  @override
  Future<void> seek(Duration value) async {
    position = value;
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }
}

Map<Object?, Object?> _view({
  String id = 'reel_1',
  String authorId = 'private-author',
  String commentAuthorId = 'private-author',
  DateTime? expiry,
  String caption = 'Synthetic studio fixture',
  bool withComment = false,
}) => {
  'schemaVersion': 2,
  'reel': {
    'id': id,
    'authorId': authorId,
    'authorName': 'PRIVATE AUTHOR',
    'media': {
      'kind': 'video',
      'contentType': 'video/mp4',
      'size': 4096,
      'generation': '7',
      'durationMs': 10000,
    },
    'backingAudio': null,
    'composition': ReelComposition(
      trimStartMs: 0,
      trimEndMs: 10000,
      caption: caption,
    ).toWire(),
    'publishedAtMillis': 1725000000000,
    'sortKey': '1725000000000_$id',
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
        'commentId': 'comment_one',
        'type': 'text',
        'authorId': commentAuthorId,
        'authorName': 'PRIVATE COMMENTER',
        'authorPhotoUrl': null,
        'text': 'PRIVATE THREAD TEXT',
        'durationSeconds': null,
        'createdAtMillis': 1725000000000,
      },
  ],
  'commentsTruncated': false,
  'nextCommentCursor': null,
};

Map<Object?, Object?> _grant({DateTime? expiry}) => {
  'schemaVersion': 2,
  'url':
      'https://storage.googleapis.com/synthetic-test/reel.mp4?token=PRIVATE_MEDIA_GRANT',
  'expiresAtMillis': DateTime.now()
      .add(const Duration(minutes: 5))
      .millisecondsSinceEpoch,
  'generation': '7',
  'availabilityHours': expiry == null ? 'permanent' : 24,
  'contentExpiresAtMillis': expiry?.millisecondsSinceEpoch,
};

Future<void> _pump(
  WidgetTester tester, {
  required ReelService service,
  String id = 'reel_1',
  Size size = const Size(390, 844),
  ThemeData? theme,
  Locale locale = const Locale('en'),
  double textScale = 1,
  DateTime Function()? now,
  ReelVideoPlaybackFactory? video,
  GlobalKey<NavigatorState>? navigator,
  GlobalKey? captureKey,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigator,
        navigatorObservers: [appRouteObserver],
        theme: theme ?? AppTheme.darkTheme,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ReelLinkDestinationScreen(
          reelId: id,
          service: service,
          now: now,
          videoPlaybackFactory: video,
          videoBuilder: (_, _, _) => const DecoratedBox(
            key: ValueKey('synthetic-reel-media'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xff183e64),
                  Color(0xff6d2d93),
                  Color(0xff101828),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUpAll(() async {
    if (Platform.environment['REEL_LINK_CAPTURE_DIR'] == null) return;
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    var directory = File(Platform.resolvedExecutable).parent;
    while (directory.parent.path != directory.path) {
      final icons = File(
        '${directory.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.sublistView(icons.readAsBytesSync())),
            ))
            .load();
        break;
      }
      directory = directory.parent;
    }
    final unicode = File(
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    );
    if (unicode.existsSync()) {
      await (FontLoader('Arial Unicode MS')..addFont(
            Future.value(ByteData.sublistView(unicode.readAsBytesSync())),
          ))
          .load();
    }
  });
  setUp(ReelService.clearAllMediaAccessCaches);

  testWidgets(
    'only an authorized exact view can construct a player or expose metadata',
    (tester) async {
      final auth = _Auth();
      final view = Completer<Map<Object?, Object?>>();
      final calls = <String>[];
      final service = _Service(
        auth: auth,
        callableInvoker: (name, payload) {
          calls.add(name);
          if (name == 'getReelViewV2') {
            expect(payload['reelId'], 'reel_1');
            expect(payload['commentLimit'], 1);
            return view.future;
          }
          if (name == 'getReelMediaAccessV2') return Future.value(_grant());
          throw StateError('Unexpected $name');
        },
      );
      await _pump(tester, service: service);
      expect(find.byType(ReelCard), findsNothing);
      expect(find.text('PRIVATE AUTHOR'), findsNothing);
      expect(calls, ['getReelViewV2']);
      view.complete(_view());
      await tester.pumpAndSettle();
      expect(find.byType(ReelCard), findsOneWidget);
      expect(find.text('PRIVATE AUTHOR'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('synthetic-reel-media')),
        findsOneWidget,
      );
      expect(calls, ['getReelViewV2', 'getReelMediaAccessV2']);
      expect(
        service.viewed,
        0,
        reason: 'Resolving a link is not a genuine watch.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    },
  );

  testWidgets(
    'denied, missing, mismatched, expired and malformed views never request media',
    (tester) async {
      final failures = <Object>[
        FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'PRIVATE AUTHOR',
        ),
        FirebaseFunctionsException(
          code: 'not-found',
          message: 'PRIVATE CAPTION',
        ),
        _view(id: 'other'),
        _view(expiry: DateTime.now().subtract(const Duration(seconds: 1))),
        <Object?, Object?>{'schemaVersion': 99, 'reel': 'PRIVATE AUTHOR'},
      ];
      for (final failure in failures) {
        final auth = _Auth();
        final calls = <String>[];
        final service = _Service(
          auth: auth,
          callableInvoker: (name, _) async {
            calls.add(name);
            if (failure is Map<Object?, Object?>) return failure;
            throw failure;
          },
        );
        await _pump(tester, service: service);
        await tester.pumpAndSettle();
        expect(find.byType(ReelCard), findsNothing);
        expect(find.text('PRIVATE AUTHOR'), findsNothing);
        expect(
          find.text('This Reel is unavailable right now.'),
          findsOneWidget,
        );
        expect(calls, ['getReelViewV2']);
        expect(service.viewed, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await auth.close();
      }
    },
  );

  testWidgets(
    'signed-out and unsafe-ID destinations perform no network reads',
    (tester) async {
      for (final id in ['../room/private', 'reel_1']) {
        final auth = _Auth();
        if (id == 'reel_1') auth.change(null);
        var calls = 0;
        final service = _Service(
          auth: auth,
          callableInvoker: (_, _) async {
            calls++;
            return _view();
          },
        );
        await _pump(tester, service: service, id: id);
        await tester.pumpAndSettle();
        expect(calls, 0);
        expect(find.byType(ReelCard), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await auth.close();
      }
    },
  );

  testWidgets('pending view A→B and ABA never installs an old snapshot', (
    tester,
  ) async {
    for (final changes in [
      <String?>['viewer-b'],
      <String?>[null, 'viewer-a'],
    ]) {
      final auth = _Auth();
      final pending = Completer<Map<Object?, Object?>>();
      final calls = <String>[];
      final service = _Service(
        auth: auth,
        callableInvoker: (name, _) {
          calls.add(name);
          return pending.future;
        },
      );
      await _pump(tester, service: service);
      for (final uid in changes) {
        auth.change(uid);
      }
      pending.complete(_view());
      await tester.pumpAndSettle();
      expect(find.byType(ReelCard), findsNothing);
      expect(find.text('PRIVATE AUTHOR'), findsNothing);
      expect(find.text('Sign in to open this Reel.'), findsOneWidget);
      expect(calls, ['getReelViewV2']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    }
  });

  testWidgets(
    'account exit removes loaded metadata and stops the old player immediately',
    (tester) async {
      final auth = _Auth();
      final video = _Video();
      final service = _Service(
        auth: auth,
        callableInvoker: (name, _) async =>
            name == 'getReelViewV2' ? _view() : _grant(),
      );
      await _pump(tester, service: service, video: (_, _) => video);
      await tester.pump(const Duration(milliseconds: 500));
      expect(video.isPlaying, isTrue);
      expect(video.volume, 0, reason: 'An opened link autoplays silently.');
      auth.change('viewer-b');
      await tester.pump();
      expect(find.byType(ReelCard), findsNothing);
      expect(find.text('PRIVATE AUTHOR'), findsNothing);
      expect(video.isPlaying, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    },
  );

  testWidgets(
    'cover/pop and background/resume reauthorize without recreating the same player',
    (tester) async {
      final auth = _Auth();
      final navigator = GlobalKey<NavigatorState>();
      final video = _Video();
      var decoderCreates = 0;
      var reads = 0;
      Completer<Map<Object?, Object?>>? nextRead;
      final service = _Service(
        auth: auth,
        callableInvoker: (name, _) {
          if (name == 'getReelViewV2') {
            reads++;
            return nextRead?.future ?? Future.value(_view());
          }
          return Future.value(_grant());
        },
      );
      await _pump(
        tester,
        service: service,
        navigator: navigator,
        video: (_, _) {
          decoderCreates++;
          return video;
        },
      );
      await tester.pump(const Duration(milliseconds: 500));
      final element = tester.element(find.byType(ReelCard));
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Other route')),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(video.isPlaying, isFalse);
      expect(find.text('PRIVATE AUTHOR'), findsNothing);
      nextRead = Completer<Map<Object?, Object?>>();
      navigator.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 350));
      expect(video.isPlaying, isFalse);
      expect(find.text('PRIVATE AUTHOR'), findsNothing);
      nextRead.complete(_view());
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('PRIVATE AUTHOR'), findsOneWidget);
      expect(tester.element(find.byType(ReelCard)), same(element));
      expect(decoderCreates, 1);
      nextRead = Completer<Map<Object?, Object?>>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(video.isPlaying, isFalse);
      expect(find.text('PRIVATE AUTHOR'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('PRIVATE AUTHOR'), findsNothing);
      nextRead.completeError(
        FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'blocked',
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('PRIVATE AUTHOR'), findsNothing);
      expect(find.byType(ReelCard), findsNothing);
      expect(reads, 3);
      expect(decoderCreates, 1);
      expect(video.isPlaying, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    },
  );

  testWidgets(
    'share and comments retain seek and hand-pause through revalidation and resume',
    (tester) async {
      for (final handPaused in [false, true]) {
        for (final action in ['share', 'comments']) {
          final auth = _Auth();
          final navigator = GlobalKey<NavigatorState>();
          final video = _Video();
          var decoderCreates = 0;
          Completer<Map<Object?, Object?>>? nextView;
          final service = _Service(
            auth: auth,
            callableInvoker: (name, _) => name == 'getReelViewV2'
                ? nextView?.future ?? Future.value(_view())
                : Future.value(_grant()),
          );
          await _pump(
            tester,
            service: service,
            navigator: navigator,
            video: (_, _) {
              decoderCreates++;
              return video;
            },
          );
          await tester.pumpAndSettle();
          final element = tester.element(find.byType(ReelCard));
          expect(video.isPlaying, isTrue);
          video.position = const Duration(seconds: 4);
          if (handPaused) {
            await tester.tap(
              find.byKey(const ValueKey('reel-video-playback-surface')),
            );
            await tester.pumpAndSettle();
            expect(video.isPlaying, isFalse);
          }
          await tester.tap(
            find.byKey(
              ValueKey(
                action == 'share' ? 'reel-link-share' : 'reel-comments-action',
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(video.isPlaying, isFalse);
          expect(video.position, const Duration(seconds: 4));
          nextView = Completer<Map<Object?, Object?>>();
          navigator.currentState!.pop();
          await tester.pump(const Duration(milliseconds: 350));
          expect(video.isPlaying, isFalse);
          expect(video.position, const Duration(seconds: 4));
          expect(find.text('PRIVATE AUTHOR'), findsNothing);
          nextView.complete(_view());
          await tester.pumpAndSettle();
          expect(video.isPlaying, !handPaused);
          expect(video.position, const Duration(seconds: 4));
          expect(tester.element(find.byType(ReelCard)), same(element));
          nextView = Completer<Map<Object?, Object?>>();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.scheduleForcedFrame();
          await tester.pump();
          expect(video.isPlaying, isFalse);
          expect(video.position, const Duration(seconds: 4));
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          expect(video.isPlaying, isFalse);
          expect(find.text('PRIVATE AUTHOR'), findsNothing);
          nextView.complete(_view());
          await tester.pumpAndSettle();
          expect(video.isPlaying, !handPaused);
          expect(video.position, const Duration(seconds: 4));
          expect(tester.element(find.byType(ReelCard)), same(element));
          expect(decoderCreates, 1);
          expect(tester.takeException(), isNull, reason: '$action $handPaused');
          await tester.pumpWidget(const SizedBox.shrink());
          await auth.close();
        }
      }
    },
  );

  testWidgets(
    'content deadline removes author and player, not just the media grant',
    (tester) async {
      final auth = _Auth();
      var now = DateTime.now().toUtc();
      final expiry = now.add(const Duration(seconds: 3));
      final service = _Service(
        auth: auth,
        callableInvoker: (name, _) async =>
            name == 'getReelViewV2' ? _view(expiry: expiry) : _grant(),
      );
      await _pump(tester, service: service, now: () => now);
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE AUTHOR'), findsOneWidget);
      now = expiry;
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(ReelCard), findsNothing);
      expect(find.text('PRIVATE AUTHOR'), findsNothing);
      expect(find.text('This Reel is unavailable right now.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    },
  );

  testWidgets('comments preflight cannot install a previous-account thread', (
    tester,
  ) async {
    final auth = _Auth();
    final pending = Completer<Map<Object?, Object?>>();
    var reads = 0;
    final service = _Service(
      auth: auth,
      callableInvoker: (name, _) {
        if (name != 'getReelViewV2') return Future.value(_grant());
        reads++;
        return reads == 1 ? Future.value(_view()) : pending.future;
      },
    );
    await _pump(tester, service: service);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reel-comments-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ReelCommentsView), findsNothing);
    expect(find.text('This Reel is unavailable right now.'), findsNothing);
    auth.change('viewer-b');
    pending.complete(_view(withComment: true));
    await tester.pumpAndSettle();
    expect(find.byType(ReelCommentsView), findsNothing);
    expect(find.text('PRIVATE THREAD TEXT'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('reel-link-comments-host')),
        matching: find.text('Sign in to open this Reel.'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await auth.close();
  });

  testWidgets(
    'expiry disposes modal comments without popping a foreign route',
    (tester) async {
      final auth = _Auth();
      final navigator = GlobalKey<NavigatorState>();
      var now = DateTime.now().toUtc();
      final expiry = now.add(const Duration(seconds: 3));
      final service = _Service(
        auth: auth,
        callableInvoker: (name, _) async => name == 'getReelViewV2'
            ? _view(expiry: expiry, withComment: true)
            : _grant(),
      );
      await _pump(
        tester,
        service: service,
        now: () => now,
        navigator: navigator,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reel-comments-action')));
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE THREAD TEXT'), findsOneWidget);
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Unrelated route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      now = expiry;
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Unrelated route'), findsOneWidget);
      expect(find.byType(ReelCommentsView, skipOffstage: false), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reel-link-comments-host')),
        findsOneWidget,
      );
      expect(find.text('PRIVATE THREAD TEXT'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('reel-link-comments-host')),
          matching: find.text('This Reel is unavailable right now.'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    },
  );

  testWidgets(
    'backgrounded comments stay hidden until current access is rechecked',
    (tester) async {
      final auth = _Auth();
      var available = true;
      var reads = 0;
      final service = _Service(
        auth: auth,
        callableInvoker: (name, _) async {
          if (name != 'getReelViewV2') return _grant();
          reads++;
          if (!available) {
            throw FirebaseFunctionsException(
              code: 'permission-denied',
              message: 'PRIVATE reason',
            );
          }
          return _view(withComment: true);
        },
      );
      await _pump(tester, service: service);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reel-comments-action')));
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE THREAD TEXT'), findsOneWidget);
      final before = reads;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      // A paused binding suppresses frames. Force one to inspect the guarded
      // subtree, rather than mistaking the last painted frame for new state.
      tester.binding.scheduleForcedFrame();
      await tester.pump();
      expect(find.byType(ReelCommentsView), findsNothing);
      expect(find.text('PRIVATE THREAD TEXT'), findsNothing);
      available = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(reads, before + 1);
      expect(find.byType(ReelCommentsView), findsNothing);
      expect(find.text('PRIVATE THREAD TEXT'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('reel-link-comments-host')),
          matching: find.text('This Reel is unavailable right now.'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    },
  );

  testWidgets(
    'expiry clears a nested report quote without popping a foreign route',
    (tester) async {
      final auth = _Auth();
      final navigator = GlobalKey<NavigatorState>();
      var now = DateTime.now().toUtc();
      final expiry = now.add(const Duration(seconds: 3));
      final service = _Service(
        auth: auth,
        callableInvoker: (name, _) async => name == 'getReelViewV2'
            ? _view(expiry: expiry, withComment: true)
            : _grant(),
      );
      await _pump(
        tester,
        service: service,
        now: () => now,
        navigator: navigator,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reel-comments-action')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('reel-comment-report-comment_one')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reel-comment-report-target')),
        findsOneWidget,
      );
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Unrelated route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      now = expiry;
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Unrelated route'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('reel-comment-report-target'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      tester
          .widget<TextButton>(
            find.byKey(
              const ValueKey('reel-link-comment-overlay-close'),
              skipOffstage: false,
            ),
          )
          .onPressed!();
      await tester.pump();
      expect(find.text('Unrelated route'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE THREAD TEXT'), findsNothing);
      expect(find.text('PRIVATE COMMENTER'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    },
  );

  for (final action in ['report', 'remove', 'delete']) {
    testWidgets('guarded $action overlay retires on every privacy exit', (
      tester,
    ) async {
      for (final exit in ['expiry', 'logout ABA', 'auth error', 'background']) {
        final auth = _Auth();
        var now = DateTime.now().toUtc();
        final expiry = now.add(const Duration(seconds: 3));
        final calls = <String>[];
        final service = _Service(
          auth: auth,
          callableInvoker: (name, _) async {
            calls.add(name);
            return name == 'getReelViewV2'
                ? _view(
                    authorId: action == 'remove'
                        ? 'viewer-a'
                        : 'private-author',
                    commentAuthorId: action == 'delete'
                        ? 'viewer-a'
                        : 'private-author',
                    expiry: expiry,
                    withComment: true,
                  )
                : _grant();
          },
        );
        Future<void> openAction() async {
          if (action == 'remove') {
            await tester.tap(
              find.byKey(const ValueKey('reel-comment-actions-comment_one')),
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(
            find.byKey(ValueKey('reel-comment-$action-comment_one')),
          );
          await tester.pumpAndSettle();
        }

        final privateKey = ValueKey(
          action == 'report'
              ? 'reel-comment-report-target'
              : 'reel-comment-$action-confirm',
        );
        await _pump(tester, service: service, now: () => now);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('reel-comments-action')));
        await tester.pumpAndSettle();
        await openAction();
        expect(find.byKey(privateKey), findsOneWidget, reason: '$action $exit');
        switch (exit) {
          case 'expiry':
            now = expiry;
            await tester.pump(const Duration(seconds: 3));
          case 'logout ABA':
            auth.change(null);
            auth.change('viewer-a');
            await tester.pumpAndSettle();
          case 'auth error':
            auth.fail();
            await tester.pumpAndSettle();
          case 'background':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            tester.binding.scheduleForcedFrame();
            await tester.pump();
            expect(find.byKey(privateKey), findsNothing);
            expect(
              find.text('PRIVATE THREAD TEXT', skipOffstage: false),
              findsNothing,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pumpAndSettle();
        }
        expect(
          find.byKey(privateKey, skipOffstage: false),
          findsNothing,
          reason: '$action $exit',
        );
        if (exit != 'background') {
          expect(
            find.textContaining('PRIVATE COMMENTER', skipOffstage: false),
            findsNothing,
            reason: '$action $exit',
          );
          expect(
            find.text('PRIVATE THREAD TEXT', skipOffstage: false),
            findsNothing,
            reason: '$action $exit',
          );
        }
        expect(
          find.byKey(const ValueKey('reel-link-comment-overlay-unavailable')),
          findsOneWidget,
        );
        if (exit == 'background') {
          // A fresh host is authorized again, but the original overlay never
          // restores its old quote or draft. A deliberate new action can.
          await tester.tap(
            find.byKey(const ValueKey('reel-link-comment-overlay-close')),
          );
          await tester.pumpAndSettle();
          await openAction();
          expect(find.byKey(privateKey), findsOneWidget);
        }
        expect(
          calls.where(
            (name) => [
              'createReelCommentReport',
              'removeReelComment',
              'deleteReelComment',
            ].contains(name),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull, reason: '$action $exit');
        await tester.pumpWidget(const SizedBox.shrink());
        await auth.close();
      }
    });
  }

  testWidgets('a retired comment menu cannot open a new private confirmation', (
    tester,
  ) async {
    final auth = _Auth();
    var now = DateTime.now().toUtc();
    final expiry = now.add(const Duration(seconds: 3));
    final service = _Service(
      auth: auth,
      callableInvoker: (name, _) async => name == 'getReelViewV2'
          ? _view(authorId: 'viewer-a', expiry: expiry, withComment: true)
          : _grant(),
    );
    await _pump(tester, service: service, now: () => now);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reel-comments-action')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('reel-comment-actions-comment_one')),
    );
    await tester.pumpAndSettle();
    now = expiry;
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(ReelCommentsView, skipOffstage: false), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('reel-comment-remove-comment_one')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('reel-comment-remove-confirm')),
      findsNothing,
    );
    expect(find.textContaining('PRIVATE COMMENTER'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await auth.close();
  });

  testWidgets(
    'single-Reel destination fits 200% text in Polish/RTL and can render review fixtures',
    (tester) async {
      for (final locale in const [Locale('pl'), Locale('ar')]) {
        for (final size in const [
          Size(320, 568),
          Size(768, 1024),
          Size(1440, 900),
        ]) {
          final auth = _Auth();
          final captureKey = GlobalKey();
          var now = DateTime.now().toUtc();
          final expiry = now.add(const Duration(hours: 1));
          final service = _Service(
            auth: auth,
            callableInvoker: (name, _) async => name == 'getReelViewV2'
                ? _view(
                    expiry: expiry,
                    withComment: true,
                    caption:
                        'To tylko syntetyczny opis służący do lokalnego przeglądu układu interfejsu. ' *
                        3,
                  )
                : _grant(expiry: expiry),
          );
          await _pump(
            tester,
            service: service,
            size: size,
            locale: locale,
            textScale: 2,
            theme: locale.languageCode == 'pl'
                ? AppTheme.lightTheme
                : AppTheme.darkTheme,
            captureKey: captureKey,
            now: () => now,
          );
          await tester.pumpAndSettle();
          expect(find.byType(ReelCard), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$locale $size');
          final output = Platform.environment['REEL_LINK_CAPTURE_DIR'];
          if (output != null) {
            Future<void> capture(String prefix) async {
              await tester.runAsync(() async {
                final boundary =
                    captureKey.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final picture = await boundary.toImage(pixelRatio: 1);
                try {
                  final bytes = await picture.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  await File(
                    '$output/$prefix-${locale.languageCode}-${size.width.toInt()}.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                } finally {
                  picture.dispose();
                }
              });
            }

            await capture('reel-link');
            await tester.tap(find.byKey(const ValueKey('reel-link-share')));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('reel-share-copy')),
              findsOneWidget,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: 'Share $locale $size',
            );
            await capture('reel-share');
            await tester.tap(find.byKey(const ValueKey('modal-sheet-close')));
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('reel-comments-action')),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('reel-comment-report-comment_one')),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('reel-comment-report-target')),
              findsOneWidget,
            );
            now = expiry;
            await tester.pump(const Duration(hours: 1));
            expect(
              find.byKey(const ValueKey('reel-comment-report-target')),
              findsNothing,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: 'Expired overlay $locale $size',
            );
            await capture('reel-overlay-expired');
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await auth.close();
        }
      }
    },
  );
}
