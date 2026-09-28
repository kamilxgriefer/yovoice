// "See who liked" on a real Yeel card (ADR-230, owner variant A): the rail's
// like count opens the list for a VIP and the U1 upsell for everyone else,
// the heart still toggles, and the ⋯ sheet carries the same entry.

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';

import 'support/likers_fixtures.dart';

const _like = ValueKey<String>('reel-like-action');
const _likers = ValueKey<String>('reel-likers-action');
const _more = ValueKey<String>('reel-more-action');

Map<String, Object?> _wire({int likes = 12}) => <String, Object?>{
  'id': 'reel_likers',
  'authorId': 'creator_1',
  'authorName': 'Creator One',
  'media': <String, Object?>{
    'kind': 'video',
    'contentType': 'video/mp4',
    'size': 1024,
    'generation': '1',
    'durationMs': 15000,
  },
  'backingAudio': null,
  'composition': const ReelComposition(
    trimEndMs: 15000,
    caption: 'Harbour at dawn.',
  ).toWire(),
  'publishedAtMillis': 1900000000000,
  'sortKey': '1900000000000_reel_likers',
  'availability': <String, Object?>{
    'schemaVersion': 1,
    'availabilityHours': 'permanent',
    'expiresAtMillis': null,
  },
  'likeCount': likes,
  'commentCount': 3,
  'callerLiked': false,
};

ReelService _service() => ReelService(
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'me', isEmailVerified: true),
  ),
  callableInvoker: (name, payload) async {
    if (name == 'getReelMediaAccessV2') {
      return <String, Object?>{
        'schemaVersion': 2,
        'url': 'https://storage.googleapis.com/yovoice/reel.mp4',
        'expiresAtMillis': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        'generation': '1',
        'availabilityHours': 'permanent',
        'contentExpiresAtMillis': null,
      };
    }
    if (name == 'recordReelViewedV2') return <String, Object?>{};
    throw StateError('Unexpected callable $name');
  },
);

Widget _still(BuildContext context, Uri uri, Reel reel) =>
    const ColoredBox(color: Color(0xFF3A3F4A));

void main() {
  late int likes;

  setUp(() => likes = 0);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<ScriptedLikers> pumpCard(
    WidgetTester tester, {
    required bool vip,
    int likeCount = 12,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')]),
    ]);
    await tester.pumpWidget(
      likersHost(
        Scaffold(
          body: ReelCard(
            reel: Reel.fromV2Wire(_wire(likes: likeCount)),
            service: _service(),
            videoBuilder: _still,
            fillViewport: true,
            autoplay: false,
            onLike: () => likes++,
            likersLauncher: testLikersLauncher(allowed: vip, script: script),
          ),
        ),
      ),
    );
    await settle(tester);
    return script;
  }

  testWidgets('the heart still toggles and does not open anything', (
    tester,
  ) async {
    final script = await pumpCard(tester, vip: true);
    await tester.tap(find.byKey(_like));
    await settle(tester);
    expect(likes, 1);
    expect(script.calls, isEmpty);
    expect(find.byKey(kLikersListSurface), findsNothing);
    expect(find.byKey(kLikersUpsellSurface), findsNothing);
  });

  testWidgets('a VIP taps the count and gets the list of this Yeel', (
    tester,
  ) async {
    final script = await pumpCard(tester, vip: true);
    expect(
      find.descendant(of: find.byKey(_likers), matching: find.text('12')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(_likers));
    await settle(tester);
    expect(likes, 0);
    expect(find.byKey(kLikersListSurface), findsOneWidget);
    expect(find.text('Julia Nowak'), findsOneWidget);
    expect(script.calls.single.name, 'listReelLikersV1');
    expect(script.calls.single.payload, <String, Object?>{
      'reelId': 'reel_likers',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('a non-VIP taps the count and gets the U1 upsell', (
    tester,
  ) async {
    final script = await pumpCard(tester, vip: false);
    await tester.tap(find.byKey(_likers));
    await settle(tester);
    expect(find.byKey(kLikersUpsellSurface), findsOneWidget);
    expect(find.text('12 people liked this Yeel'), findsOneWidget);
    expect(script.calls, isEmpty);
  });

  testWidgets('the ⋯ sheet offers "See who liked" and it opens the list', (
    tester,
  ) async {
    await pumpCard(tester, vip: true);
    await tester.tap(find.byKey(_more));
    await settle(tester);
    final item = find.byKey(const ValueKey('reel-options-likers'));
    expect(item, findsOneWidget);
    expect(find.text('See who liked'), findsOneWidget);
    await tester.tap(item);
    await settle(tester);
    expect(find.byKey(kLikersListSurface), findsOneWidget);
    expect(find.text('Julia Nowak'), findsOneWidget);
  });

  // The like's own count target makes the vertical rail ~24 px taller, so
  // the switch to the shallow action row moves up by as much: at no height
  // may the rail reach the sound control at the top of the frame.
  for (final height in <double>[365, 372, 380, 400]) {
    testWidgets('at 390 x ${height.toInt()} the rail never covers the sound '
        'control', (tester) async {
      await pumpCard(tester, vip: true, size: Size(390, height));
      expect(tester.takeException(), isNull);
      final rail = tester.getRect(
        find.byKey(const ValueKey<String>('reel-action-rail')),
      );
      final sound = find.byKey(const ValueKey<String>('reel-sound-toggle'));
      expect(sound, findsOneWidget);
      expect(
        rail.overlaps(tester.getRect(sound)),
        isFalse,
        reason: 'rail $rail, sound ${tester.getRect(sound)}',
      );
      if (rail.height > rail.width) {
        // Still the vertical rail: the count is its own target.
        expect(find.byKey(_likers), findsOneWidget);
      }
    });
  }

  testWidgets('no likes: no count target and no ⋯ item', (tester) async {
    await pumpCard(tester, vip: true, likeCount: 0);
    expect(find.byKey(_likers), findsNothing);
    await tester.tap(find.byKey(_more));
    await settle(tester);
    expect(find.byKey(const ValueKey('reel-options-likers')), findsNothing);
  });
}
