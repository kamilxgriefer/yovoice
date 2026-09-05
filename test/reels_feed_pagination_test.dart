import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';

void main() {
  testWidgets('skips bounded empty pages before showing the empty state', (
    tester,
  ) async {
    var listCalls = 0;
    final service = _service((cursor) async {
      listCalls += 1;
      if (cursor == null) return _page(const <Object?>[], 'cursor_1');
      expect(cursor, 'cursor_1');
      return _page(<Object?>[_reelWire(1)], null);
    });

    await _pumpFeed(tester, service);

    expect(listCalls, 2);
    expect(find.text('No Reels yet'), findsNothing);
    expect(find.text('Creator 1'), findsOneWidget);
  });

  testWidgets(
    'load-more failure is visible and Retry resumes the same cursor',
    (tester) async {
      var listCalls = 0;
      final service = _service((cursor) async {
        listCalls += 1;
        if (cursor == null) {
          return _page(<Object?>[
            for (var index = 1; index <= 4; index++) _reelWire(index),
          ], 'cursor_more');
        }
        expect(cursor, 'cursor_more');
        if (listCalls == 2) throw StateError('temporary pagination failure');
        return _page(<Object?>[_reelWire(5)], null);
      });

      await _pumpFeed(tester, service);
      await tester.drag(find.byType(PageView), const Offset(0, -700));
      await tester.pumpAndSettle();

      expect(listCalls, 2);
      expect(
        find.byKey(const ValueKey<String>('reels-load-more-error')),
        findsOneWidget,
      );
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('reels-load-more-retry')),
      );
      await tester.pumpAndSettle();

      expect(listCalls, 3);
      expect(
        find.byKey(const ValueKey<String>('reels-load-more-error')),
        findsNothing,
      );
    },
  );

  testWidgets('host visibility deactivates the selected Reel player', (
    tester,
  ) async {
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);
    final service = _service((_) async => _page(<Object?>[_reelWire(1)], null));

    await _pumpFeed(tester, service, isVisible: visible);
    expect(tester.widget<ReelCard>(find.byType(ReelCard)).isActive, isTrue);

    visible.value = false;
    await tester.pump();
    expect(tester.widget<ReelCard>(find.byType(ReelCard)).isActive, isFalse);
  });

  testWidgets(
    'nearest expiry removes content exactly at deadline and disposes playback',
    (tester) async {
      var now = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().toUtc().millisecondsSinceEpoch,
        isUtc: true,
      );
      final deadline = now.add(const Duration(seconds: 5));
      final audio = _FakeAudioPlayback();
      late _FakeTimer expiryTimer;
      final grant = <Object?, Object?>{
        'schemaVersion': 2,
        'url': 'https://storage.googleapis.com/yovoice/reel.jpg?token=test',
        'expiresAtMillis': deadline.millisecondsSinceEpoch,
        'generation': '7',
        'availabilityHours': 24,
        'contentExpiresAtMillis': deadline.millisecondsSinceEpoch,
      };
      final service = _service(
        (_) async => _page(<Object?>[_timedPhotoWire(1, deadline)], null),
        mediaGrant: grant,
      );

      await _pumpFeed(
        tester,
        service,
        now: () => now,
        audioPlaybackFactory: () => audio,
        expiryTimerFactory: (duration, callback) {
          expect(duration, const Duration(seconds: 5));
          return expiryTimer = _FakeTimer(callback);
        },
      );
      final toggle = find.byKey(const ValueKey('reel-playback-toggle'));
      expect(toggle, findsOneWidget);
      await tester.ensureVisible(toggle);
      await tester.pump();
      final play = tester.widget<IconButton>(toggle).onPressed;
      expect(play, isNotNull);
      play!();
      await tester.pumpAndSettle();
      expect(audio.playCount, 1);

      now = deadline.subtract(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Creator 1'), findsOneWidget);

      now = deadline;
      expiryTimer.fire();
      await tester.pump();
      await tester.pump();

      expect(find.text('Creator 1'), findsNothing);
      expect(find.text('No Reels yet'), findsOneWidget);
      expect(audio.stopCount, 1);
      expect(audio.disposeCount, 1);
    },
  );

  testWidgets('route visibility revalidates an elapsed deadline', (
    tester,
  ) async {
    var now = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().toUtc().millisecondsSinceEpoch,
      isUtc: true,
    );
    final deadline = now.add(const Duration(minutes: 1));
    final visible = ValueNotifier<bool>(false);
    addTearDown(visible.dispose);
    final service = _service(
      (_) async => _page(<Object?>[_timedPhotoWire(2, deadline)], null),
    );

    await _pumpFeed(
      tester,
      service,
      isVisible: visible,
      now: () => now,
      expiryTimerFactory: (_, callback) => _FakeTimer(callback),
    );
    expect(find.text('Creator 2'), findsOneWidget);

    now = deadline;
    visible.value = true;
    await tester.pump();

    expect(find.text('Creator 2'), findsNothing);
    expect(find.text('No Reels yet'), findsOneWidget);
  });

  testWidgets('app resume revalidates an elapsed deadline', (tester) async {
    var now = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().toUtc().millisecondsSinceEpoch,
      isUtc: true,
    );
    final deadline = now.add(const Duration(minutes: 1));
    final service = _service(
      (_) async => _page(<Object?>[_timedPhotoWire(3, deadline)], null),
    );

    await _pumpFeed(
      tester,
      service,
      now: () => now,
      expiryTimerFactory: (_, callback) => _FakeTimer(callback),
    );
    expect(find.text('Creator 3'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    now = deadline;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('Creator 3'), findsNothing);
    expect(find.text('No Reels yet'), findsOneWidget);
  });

  testWidgets('30-day expiry is chunked at the real browser timer limit', (
    tester,
  ) async {
    const browserTimerLimit = Duration(milliseconds: 0x7fffffff);
    var now = DateTime.utc(2026, 9, 5, 12);
    final deadline = now.add(const Duration(days: 30));
    final requestedDelays = <Duration>[];
    final timers = <_FakeTimer>[];
    final service = _service(
      (_) async => _page(<Object?>[_timedPhotoWire(4, deadline)], null),
    );

    await _pumpFeed(
      tester,
      service,
      now: () => now,
      expiryTimerFactory: (delay, callback) {
        requestedDelays.add(delay);
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    expect(requestedDelays, [browserTimerLimit]);
    expect(find.text('Creator 4'), findsOneWidget);

    // A platform timer may wake early. The feed must keep the Reel and arm
    // another safe chunk instead of treating the wake-up as expiry.
    timers.last.fire();
    await tester.pump();
    expect(find.text('Creator 4'), findsOneWidget);
    expect(requestedDelays, [browserTimerLimit, browserTimerLimit]);

    now = now.add(browserTimerLimit);
    timers.last.fire();
    await tester.pump();
    final finalChunk = deadline.difference(now);
    expect(requestedDelays.last, finalChunk);
    expect(
      requestedDelays.every((delay) => delay <= browserTimerLimit),
      isTrue,
    );

    now = deadline;
    timers.last.fire();
    await tester.pump();
    expect(find.text('Creator 4'), findsNothing);
    expect(find.text('No Reels yet'), findsOneWidget);
  });
}

Future<void> _pumpFeed(
  WidgetTester tester,
  ReelService service, {
  ValueListenable<bool>? isVisible,
  DateTime Function()? now,
  ReelExpiryTimerFactory? expiryTimerFactory,
  ReelAudioPlaybackFactory? audioPlaybackFactory,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: ReelsFeedScreen(
        embedded: true,
        service: service,
        isVisible: isVisible,
        now: now,
        expiryTimerFactory: expiryTimerFactory,
        audioPlaybackFactory: audioPlaybackFactory,
        videoBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ReelService _service(
  Future<Map<Object?, Object?>> Function(String? cursor) list, {
  Map<Object?, Object?>? mediaGrant,
}) {
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'viewer'),
  );
  return ReelService(
    auth: auth,
    callableInvoker: (name, payload) async {
      if (name == 'listReelsV2') return list(payload['cursor'] as String?);
      if (name == 'getReelMediaAccessV2') {
        return mediaGrant ??
            <Object?, Object?>{
              'schemaVersion': 2,
              'url':
                  'https://storage.googleapis.com/yovoice/reel.mp4?token=test',
              'expiresAtMillis': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .millisecondsSinceEpoch,
              'generation': '7',
              'availabilityHours': 'permanent',
              'contentExpiresAtMillis': null,
            };
      }
      throw StateError('Unexpected callable $name');
    },
  );
}

Map<Object?, Object?> _page(List<Object?> items, String? nextCursor) {
  return <Object?, Object?>{
    'schemaVersion': 2,
    'items': items,
    'nextCursor': nextCursor,
  };
}

Map<String, Object?> _reelWire(int index) {
  final millis = 1725000000000 - index;
  return <String, Object?>{
    'id': 'reel_feed_$index',
    'authorId': 'creator_$index',
    'authorName': 'Creator $index',
    'media': <String, Object?>{
      'kind': 'video',
      'contentType': 'video/mp4',
      'size': 4096,
      'generation': '7',
      'durationMs': 10000,
    },
    'backingAudio': null,
    'composition': const ReelComposition(
      trimStartMs: 0,
      trimEndMs: 10000,
    ).toWire(),
    'publishedAtMillis': millis,
    'sortKey': '${millis}_reel_feed_$index',
    'availability': <String, Object?>{
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
  };
}

Map<String, Object?> _timedPhotoWire(int index, DateTime deadline) {
  final value = _reelWire(index);
  value
    ..['media'] = <String, Object?>{
      'kind': 'image',
      'contentType': 'image/jpeg',
      'size': 4096,
      'generation': '7',
      'durationMs': 0,
    }
    ..['backingAudio'] = <String, Object?>{
      'contentType': 'audio/mpeg',
      'size': 4096,
      'generation': '8',
      'durationMs': 3000,
    }
    ..['composition'] = const ReelComposition(
      originalAudioVolume: 0,
      backingAudioVolume: 70,
      audioTrimStartMs: 0,
      audioRightsAttested: true,
    ).toWire()
    ..['availability'] = <String, Object?>{
      'schemaVersion': 2,
      'availabilityHours': 24,
      'expiresAtMillis': deadline.millisecondsSinceEpoch,
    };
  return value;
}

class _FakeTimer implements Timer {
  _FakeTimer(this._callback);

  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}

class _FakeAudioPlayback implements ReelAudioPlayback {
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<void> _completions = StreamController<void>.broadcast(
    sync: true,
  );
  int playCount = 0;
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Stream<Duration> get positionChanges => _positions.stream;

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    await _positions.close();
    await _completions.close();
  }

  @override
  Future<void> load(Uri uri) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async => playCount += 1;

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async => stopCount += 1;
}
