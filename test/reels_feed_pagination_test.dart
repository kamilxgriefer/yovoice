import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';

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
}

Future<void> _pumpFeed(WidgetTester tester, ReelService service) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: ReelsFeedScreen(
        embedded: true,
        service: service,
        videoBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ReelService _service(
  Future<Map<Object?, Object?>> Function(String? cursor) list,
) {
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'viewer'),
  );
  return ReelService(
    auth: auth,
    callableInvoker: (name, payload) async {
      if (name == 'listReels') return list(payload['cursor'] as String?);
      if (name == 'getReelMediaAccess') {
        return <Object?, Object?>{
          'schemaVersion': 1,
          'url': 'https://storage.googleapis.com/yovoice/reel.mp4?token=test',
          'expiresAtMillis': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'generation': '7',
        };
      }
      throw StateError('Unexpected callable $name');
    },
  );
}

Map<Object?, Object?> _page(List<Object?> items, String? nextCursor) {
  return <Object?, Object?>{'items': items, 'nextCursor': nextCursor};
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
  };
}
