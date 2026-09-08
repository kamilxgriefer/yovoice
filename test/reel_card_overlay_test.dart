import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';

/// The overlay rail on a real Reel frame: what it contains, in what order, and
/// how it folds when the frame is too small for a column.
///
/// Everything comes through the real [ReelService] over a fake callable
/// transport, exactly as production parses it. The author control uses the
/// injected `onOpenAuthor` seam so no widget test ever reaches Firestore.
const _like = ValueKey<String>('reel-like-action');
const _comments = ValueKey<String>('reel-comments-action');

Finder _inCard(Finder finder) =>
    find.descendant(of: find.byType(ReelCard), matching: finder);

Map<String, Object?> _reelWire({String authorId = 'creator_1'}) {
  const millis = 1725000000000;
  return <String, Object?>{
    'id': 'reel_overlay',
    'authorId': authorId,
    'authorName': 'Creator One',
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
      caption: 'Night shift stories.',
    ).toWire(),
    'publishedAtMillis': millis,
    'sortKey': '${millis}_reel_overlay',
    'availability': <String, Object?>{
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
    'likeCount': 12,
    'commentCount': 3,
    'callerLiked': false,
  };
}

ReelService _service({String authorId = 'creator_1'}) => ReelService(
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
  ),
  callableInvoker: (name, payload) async {
    if (name == 'listReelsV2') {
      return <Object?, Object?>{
        'schemaVersion': 2,
        'items': <Object?>[_reelWire(authorId: authorId)],
        'nextCursor': null,
      };
    }
    if (name == 'getReelMediaAccessV2') {
      return <Object?, Object?>{
        'schemaVersion': 2,
        'url': 'https://storage.googleapis.com/yovoice/reel.mp4?token=test',
        'expiresAtMillis': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        'generation': '7',
        'availabilityHours': 'permanent',
        'contentExpiresAtMillis': null,
      };
    }
    throw StateError('Unexpected callable $name with $payload');
  },
);

Future<List<Reel>> _pumpFeed(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  String authorId = 'creator_1',
  ThemeData? theme,
}) async {
  final opened = <Reel>[];
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: Scaffold(
        body: ReelsFeedScreen(
          embedded: true,
          service: _service(authorId: authorId),
          onOpenAuthor: opened.add,
          videoBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('the rail runs like, comment, report down one column', (
    tester,
  ) async {
    await _pumpFeed(tester);

    final like = tester.getCenter(_inCard(find.byKey(_like)));
    final comment = tester.getCenter(_inCard(find.byKey(_comments)));
    final report = tester.getCenter(_inCard(find.byTooltip('Report Reel')));

    expect(like.dy, lessThan(comment.dy));
    expect(comment.dy, lessThan(report.dy));
    // One column, not a scattered set of controls.
    expect(comment.dx, closeTo(like.dx, 1));
    expect(report.dx, closeTo(like.dx, 1));
    // The rail sits against the trailing edge, the identity against the other.
    expect(like.dx, greaterThan(tester.getCenter(find.byType(ReelCard)).dx));
  });

  testWidgets('your own Reel offers delete where a stranger offers report', (
    tester,
  ) async {
    await _pumpFeed(tester, authorId: 'viewer');

    expect(_inCard(find.byTooltip('Delete Reel')), findsOneWidget);
    expect(_inCard(find.byTooltip('Report Reel')), findsNothing);
    final like = tester.getCenter(_inCard(find.byKey(_like)));
    final delete = tester.getCenter(_inCard(find.byTooltip('Delete Reel')));
    expect(delete.dy, greaterThan(like.dy));
  });

  testWidgets('each count belongs to the control it counts', (tester) async {
    await _pumpFeed(tester);

    final likeCount = find.descendant(
      of: _inCard(find.byKey(_like)),
      matching: find.byType(Text),
    );
    final commentCount = find.descendant(
      of: _inCard(find.byKey(_comments)),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(likeCount).data, '12');
    expect(tester.widget<Text>(commentCount).data, '3');
    // Every rail item keeps a target no smaller than the accessible minimum.
    for (final finder in <Finder>[
      _inCard(find.byKey(_like)),
      _inCard(find.byKey(_comments)),
      _inCard(find.byTooltip('Report Reel')),
    ]) {
      final size = tester.getSize(finder);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('a frame too short for a column folds the rail into a row', (
    tester,
  ) async {
    // A short stage: the 9:16 frame ends up under 400 px tall, which is the
    // point at which a vertical rail would start covering the media.
    await _pumpFeed(tester, size: const Size(560, 466));

    final frame = tester.getSize(
      find
          .descendant(
            of: find.byType(ReelCard),
            matching: find.byType(ClipRRect),
          )
          .first,
    );
    expect(frame.height, lessThan(400));
    expect(frame.width / frame.height, closeTo(9 / 16, .01));

    final like = tester.getCenter(_inCard(find.byKey(_like)));
    final comment = tester.getCenter(_inCard(find.byKey(_comments)));
    expect(like.dy, closeTo(comment.dy, 1));
    expect(like.dx, lessThan(comment.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a frame with no room for three plates wraps instead of '
      'overflowing', (tester) async {
    // The pathological case — a keyboard-squeezed phone frame. Controls keep
    // their 48 px plates and wrap; nothing is scaled below the target size
    // and nothing overflows.
    await _pumpFeed(tester, size: const Size(320, 380));

    for (final finder in <Finder>[
      _inCard(find.byKey(_like)),
      _inCard(find.byKey(_comments)),
      _inCard(find.byTooltip('Report Reel')),
    ]) {
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the author asks the host to open the profile', (
    tester,
  ) async {
    final opened = await _pumpFeed(tester);

    await tester.tap(_inCard(find.text('Creator One')));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(opened.single.authorId, 'creator_1');
  });

  testWidgets('the wide panel author opens the same profile seam', (
    tester,
  ) async {
    final opened = await _pumpFeed(tester, size: const Size(1440, 900));

    // Wide moves identity into the docked panel; the frame keeps the rail.
    expect(
      find.descendant(
        of: find.byType(ReelCard),
        matching: find.text('Creator One'),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Creator One'));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(opened.single.authorId, 'creator_1');
  });
}
