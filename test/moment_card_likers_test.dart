// "See who liked" on MomentCard (ADR-230, owner variant A): with likes, the
// heart and the count are two targets. The heart keeps its key and only
// toggles; the count (`moment-card-likers`) opens the list for a VIP and the
// U1 upsell for everyone else. With no likes there is no count target.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';

import 'support/likers_fixtures.dart';

const _likers = ValueKey('moment-card-likers');

class _RecordingFeed extends HomeFeedService {
  _RecordingFeed()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      );

  final List<(String, bool)> writes = <(String, bool)>[];

  @override
  Future<void> setLike(String momentId, {required bool liked}) async {
    writes.add((momentId, liked));
  }
}

VoiceMoment _moment({int likes = 7}) => VoiceMoment(
  id: 'm1',
  authorId: 'nadia',
  authorName: 'Nadia Rutkowska',
  authorPhotoUrl: null,
  caption: 'The night bus is where the truth lives.',
  audioUrl: null,
  durationSeconds: 27,
  likeCount: likes,
  commentCount: 2,
  isPublished: true,
  createdAt: DateTime(2026, 9, 27),
);

void main() {
  late _RecordingFeed feed;

  setUp(() => feed = _RecordingFeed());

  Future<ScriptedLikers> pumpCard(
    WidgetTester tester, {
    required bool vip,
    int likes = 7,
    double width = 390,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')]),
    ]);
    await tester.pumpWidget(
      likersHost(
        textScale: textScale,
        Scaffold(
          body: SingleChildScrollView(
            child: MomentCard(
              moment: _moment(likes: likes),
              onComments: () {},
              feedService: feed,
              mediaUriResolver: (_) async => Uri.parse('https://cdn/m1.m4a'),
              likersLauncher: testLikersLauncher(allowed: vip, script: script),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return script;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
  }

  testWidgets('the heart keeps its key and toggles; the count is separate', (
    tester,
  ) async {
    final script = await pumpCard(tester, vip: true);
    final heart = find.byKey(const ValueKey('like-moment-7-false'));
    expect(heart, findsOneWidget);
    expect(find.descendant(of: heart, matching: find.text('7')), findsNothing);
    expect(
      find.descendant(of: find.byKey(_likers), matching: find.text('7')),
      findsOneWidget,
    );
    expect(tester.getSize(heart).shortestSide, greaterThanOrEqualTo(44));
    expect(
      tester.getSize(find.byKey(_likers)).shortestSide,
      greaterThanOrEqualTo(44),
    );

    await tester.tap(heart);
    await tester.pump();
    expect(feed.writes, <(String, bool)>[('m1', true)]);
    expect(
      find.descendant(of: find.byKey(_likers), matching: find.text('8')),
      findsOneWidget,
    );
    expect(script.calls, isEmpty);
    expect(find.byKey(kLikersListSurface), findsNothing);
  });

  testWidgets('a VIP taps the count and gets the list', (tester) async {
    final script = await pumpCard(tester, vip: true);
    expect(find.bySemanticsLabel('See who liked. Likes: 7'), findsOneWidget);
    await tester.tap(find.byKey(_likers));
    await settle(tester);
    expect(feed.writes, isEmpty);
    expect(find.byKey(kLikersListSurface), findsOneWidget);
    expect(find.text('Julia Nowak'), findsOneWidget);
    expect(script.calls.single.name, 'listVoiceMomentLikersV1');
    expect(script.calls.single.payload, <String, Object?>{'momentId': 'm1'});
  });

  testWidgets('a non-VIP taps the count and gets the U1 upsell', (
    tester,
  ) async {
    final script = await pumpCard(tester, vip: false);
    await tester.tap(find.byKey(_likers));
    await settle(tester);
    expect(find.byKey(kLikersUpsellSurface), findsOneWidget);
    expect(find.text('7 people liked this Moment'), findsOneWidget);
    expect(script.calls, isEmpty);
  });

  testWidgets('no likes: the heart keeps its "Like" verb and there is no '
      'count target', (tester) async {
    await pumpCard(tester, vip: true, likes: 0);
    expect(find.byKey(_likers), findsNothing);
    expect(
      find.byKey(const ValueKey('like-moment-Like-false')),
      findsOneWidget,
    );
    expect(find.text('Like'), findsOneWidget);
  });

  testWidgets('320 px at 200 % text lays out without overflow', (tester) async {
    await pumpCard(tester, vip: true, likes: 1234, width: 320, textScale: 2);
    expect(find.byKey(_likers), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
