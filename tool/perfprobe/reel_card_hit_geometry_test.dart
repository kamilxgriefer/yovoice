// MEASUREMENT PROBE: how much of a Reel card's surface is covered by
// interactive footer controls (which do something other than play/pause), at
// the phone size the maintainer is using.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';

void main() {
  testWidgets('geometry: card vs interactive footer controls', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final reel = Reel.fromV2Wire(_reelWire());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ReelCard(
                reel: reel,
                service: _service(),
                videoBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
                onLike: () {},
                onComments: () {},
                onReport: () async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final card = tester.getRect(find.byType(AspectRatio).first);
    final report = StringBuffer()
      ..writeln('card rect: $card  (${card.width.toStringAsFixed(0)} x '
          '${card.height.toStringAsFixed(0)})');

    var coveredArea = 0.0;
    final boxes = <String, Rect>{};
    for (final type in <Type>[InkWell, GestureDetector, IconButton, TextButton]) {
      var i = 0;
      for (final element in find.byType(type).evaluate()) {
        final ro = element.renderObject;
        if (ro is! RenderBox || !ro.hasSize) continue;
        final topLeft = ro.localToGlobal(Offset.zero);
        final rect = topLeft & ro.size;
        if (!card.overlaps(rect)) continue;
        final clipped = rect.intersect(card);
        if (clipped.width <= 0 || clipped.height <= 0) continue;
        boxes['$type#${i++}'] = clipped;
      }
    }
    // Union area, sampled on a 2 px grid so overlapping controls are not
    // double-counted.
    const step = 2.0;
    for (var y = card.top; y < card.bottom; y += step) {
      for (var x = card.left; x < card.right; x += step) {
        final p = Offset(x, y);
        if (boxes.values.any((r) => r.contains(p))) coveredArea += step * step;
      }
    }
    report.writeln('interactive footer controls found: ${boxes.length}');
    boxes.forEach((k, r) => report.writeln(
        '  $k  ${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)} '
        'at y=${(r.top - card.top).toStringAsFixed(0)}..'
        '${(r.bottom - card.top).toStringAsFixed(0)} of ${card.height.toStringAsFixed(0)}'));
    final pct = 100 * coveredArea / (card.width * card.height);
    report.writeln('share of the card covered by non-playback controls: '
        '${pct.toStringAsFixed(1)}%');
    var lowest = card.top;
    for (final r in boxes.values) {
      if (r.top < lowest || lowest == card.top) lowest = r.top;
    }
    report.writeln('highest control starts at y=${(lowest - card.top).toStringAsFixed(0)} '
        '(${(100 * (lowest - card.top) / card.height).toStringAsFixed(0)}% down the card)');
    // ignore: avoid_print
    print('\n===== REEL CARD HIT GEOMETRY =====\n$report=====\n');
  });
}

ReelService _service() => ReelService(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
      ),
      callableInvoker: (name, payload) async => throw StateError(name),
    );

Map<String, Object?> _reelWire() => <String, Object?>{
      'id': 'reel_geometry_0',
      'authorId': 'creator_0',
      'authorName': 'Creator Zero',
      'media': <String, Object?>{
        'kind': 'video',
        'contentType': 'video/mp4',
        'size': 4096,
        'generation': '7',
        'durationMs': 10000,
      },
      'backingAudio': null,
      'composition': const ReelComposition(
        caption: 'A caption of a realistic length for a published Reel.',
        trimStartMs: 0,
        trimEndMs: 10000,
      ).toWire(),
      'publishedAtMillis': 1725000000000,
      'sortKey': '1725000000000_reel_geometry_0',
      'availability': <String, Object?>{
        'schemaVersion': 1,
        'availabilityHours': 'permanent',
        'expiresAtMillis': null,
      },
      'likeCount': 12,
      'commentCount': 3,
      'callerLiked': false,
    };
