// MEASUREMENT PROBE (not a regression test): records the exact ordered
// sequence of callables the Reels tab issues from mount to first card, and
// whether anything ever asks the coordinator to play without a tap.
//
//   flutter test tool/perfprobe/reels_open_trace_test.dart

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';

void main() {
  testWidgets('trace: tab open -> first card', (tester) async {
    final trace = <String>[];
    final sw = Stopwatch()..start();
    final service = _service(trace, sw);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    trace.add('${sw.elapsedMilliseconds}ms  MOUNT ReelsFeedScreen');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: ReelsFeedScreen(
          embedded: true,
          service: service,
          videoBuilder: (_, uri, reel) {
            trace.add(
              '${sw.elapsedMilliseconds}ms  VIDEO WIDGET BUILT for ${reel.id} '
              '(decoder would start loading here)',
            );
            return const ColoredBox(color: Colors.black);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    trace.add('--- steady state after first paint ---');
    trace.add('ReelCard widgets mounted: '
        '${tester.widgetList(find.byType(ReelCard)).length}');
    trace.add('play-glyph / paused surfaces present: '
        '${find.bySemanticsLabel('Play video').evaluate().length}');

    // Swipe to the next page and record what that costs.
    final before = trace.length;
    await tester.drag(find.byType(PageView), const Offset(0, -800));
    await tester.pumpAndSettle();
    trace.add('--- after one swipe: ${trace.length - before - 0} new events ---');

    // ignore: avoid_print
    print('\n===== REELS TAB OPEN TRACE =====\n${trace.join('\n')}\n=====\n');
  });
}

ReelService _service(List<String> trace, Stopwatch sw) => ReelService(
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
  ),
  callableInvoker: (name, payload) async {
    final label = name == 'getReelMediaAccessV2'
        ? "$name(reelId=${payload['reelId']}, asset=${payload['asset']})"
        : "$name(cursor=${payload['cursor']}, limit=${payload['limit']})";
    trace.add('${sw.elapsedMilliseconds}ms  CALL  $label');
    // Zero simulated network time: the ORDER and the COUNT are what this
    // probe measures, not the latency.
    await Future<void>.delayed(Duration.zero);
    trace.add('${sw.elapsedMilliseconds}ms  DONE  $label');
    if (name == 'listReelsV2') {
      return <Object?, Object?>{
        'schemaVersion': 2,
        'items': <Object?>[for (var i = 0; i < 10; i++) _reelWire(i)],
        'nextCursor': null,
      };
    }
    if (name == 'getReelMediaAccessV2') {
      return <Object?, Object?>{
        'schemaVersion': 2,
        'url': 'https://storage.googleapis.com/yovoice/reel.mp4?x=1',
        'expiresAtMillis': DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 90))
            .millisecondsSinceEpoch,
        'generation': '7',
        'availabilityHours': 'permanent',
        'contentExpiresAtMillis': null,
      };
    }
    throw StateError('Unexpected callable $name');
  },
);

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
    'composition':
        const ReelComposition(trimStartMs: 0, trimEndMs: 10000).toWire(),
    'publishedAtMillis': millis,
    'sortKey': '${millis}_reel_feed_$index',
    'availability': <String, Object?>{
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
  };
}
