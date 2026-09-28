// "See who liked" in the Voice Moment story viewer (ADR-230, owner variant
// A): with likes, `story-like` only toggles and a sibling `story-likers`
// chip carries the count and opens the flow — the list for a VIP, the U1
// upsell otherwise. The story holds still while the sheet is open and plays
// on when it closes.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'support/likers_fixtures.dart';
import 'voice_moment_test_doubles.dart';

const _like = ValueKey('story-like');
const _likers = ValueKey('story-likers');

MockFirebaseAuth _auth() =>
    MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me'));

VoiceMoment _moment(int likes) {
  final createdAt = DateTime.now().subtract(const Duration(hours: 1));
  return VoiceMoment(
    id: 'story-1',
    authorId: 'nadia',
    authorName: 'Nadia Rutkowska',
    authorPhotoUrl: null,
    caption: 'Before the city wakes.',
    audioUrl: 'https://cdn.example/story-1.m4a',
    durationSeconds: 12,
    likeCount: likes,
    commentCount: 0,
    isPublished: true,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(hours: 24)),
    schemaVersion: 2,
    status: 'published',
    isDeleted: false,
  );
}

class _StoryMoments extends MomentService {
  _StoryMoments(this.moment)
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: _auth(),
        storage: MockFirebaseStorage(),
      );

  final VoiceMoment moment;

  @override
  Stream<VoiceMoment> watchMoment(String momentId) =>
      Stream<VoiceMoment>.value(moment);

  @override
  Future<Uri> resolveMediaUri({
    required String momentId,
    String? commentId,
  }) async => Uri.parse('https://storage.googleapis.com/test/$momentId.m4a');
}

class _RecordingFeed extends HomeFeedService {
  _RecordingFeed() : super(firestore: FakeFirebaseFirestore(), auth: _auth());

  final List<(String, bool)> writes = <(String, bool)>[];

  @override
  Future<void> setLike(String momentId, {required bool liked}) async {
    writes.add((momentId, liked));
  }
}

void main() {
  late PublicIdentityRepository originalIdentity;
  late _RecordingFeed feed;
  late List<FakePreviewAudioPlayer> players;

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = identityRepository();
    feed = _RecordingFeed();
    players = <FakePreviewAudioPlayer>[];
  });

  tearDown(() => PublicIdentityRepository.instance = originalIdentity);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<ScriptedLikers> pumpViewer(
    WidgetTester tester, {
    required bool vip,
    int likes = 9,
    bool autoPlay = false,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')]),
    ]);
    final moment = _moment(likes);
    await tester.pumpWidget(
      likersHost(
        textScale: textScale,
        Scaffold(
          body: MomentStoryViewer(
            chain: buildMomentChains(<VoiceMoment>[moment]).single,
            auth: _auth(),
            autoPlay: autoPlay,
            momentService: _StoryMoments(moment),
            feedService: feed,
            playerFactory: () {
              final player = FakePreviewAudioPlayer(
                duration: const Duration(seconds: 12),
              );
              players.add(player);
              return player;
            },
            likersLauncher: testLikersLauncher(allowed: vip, script: script),
          ),
        ),
      ),
    );
    await settle(tester);
    return script;
  }

  Future<void> tapLikers(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_likers));
    await tester.tap(find.byKey(_likers));
    await settle(tester);
  }

  testWidgets('the heart toggles; the count is its own chip', (tester) async {
    final script = await pumpViewer(tester, vip: true);
    expect(
      find.descendant(of: find.byKey(_like), matching: find.text('9')),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byKey(_likers), matching: find.text('9')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(_likers)).shortestSide,
      greaterThanOrEqualTo(44),
    );
    expect(find.bySemanticsLabel('See who liked. Likes: 9'), findsOneWidget);

    await tester.ensureVisible(find.byKey(_like));
    await tester.tap(find.byKey(_like));
    await tester.pump();
    expect(feed.writes, <(String, bool)>[('story-1', true)]);
    expect(script.calls, isEmpty);
    expect(find.byKey(kLikersListSurface), findsNothing);
  });

  testWidgets('a VIP taps the count and gets the list', (tester) async {
    final script = await pumpViewer(tester, vip: true);
    await tapLikers(tester);
    expect(find.byKey(kLikersListSurface), findsOneWidget);
    expect(find.text('Julia Nowak'), findsOneWidget);
    expect(script.calls.single.name, 'listVoiceMomentLikersV1');
    expect(script.calls.single.payload, <String, Object?>{
      'momentId': 'story-1',
    });
  });

  testWidgets('a non-VIP taps the count and gets the U1 upsell', (
    tester,
  ) async {
    final script = await pumpViewer(tester, vip: false);
    await tapLikers(tester);
    expect(find.byKey(kLikersUpsellSurface), findsOneWidget);
    expect(find.text('9 people liked this Moment'), findsOneWidget);
    expect(script.calls, isEmpty);
  });

  testWidgets('playback pauses while the sheet is open and plays on after', (
    tester,
  ) async {
    await pumpViewer(tester, vip: true, autoPlay: true);
    final player = players.single;
    expect(player.playCalls, 1);
    expect(player.pauseCalls, 0);

    await tapLikers(tester);
    expect(find.byKey(kLikersListSurface), findsOneWidget);
    expect(player.pauseCalls, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byKey(kLikersListSurface), findsNothing);
    expect(player.playCalls + player.resumeCalls, 2);
  });

  testWidgets('no likes: the heart keeps "Like" and there is no count chip', (
    tester,
  ) async {
    await pumpViewer(tester, vip: true, likes: 0);
    expect(find.byKey(_likers), findsNothing);
    expect(
      find.descendant(of: find.byKey(_like), matching: find.text('Like')),
      findsOneWidget,
    );
  });

  testWidgets('at 200 % text the count is never drawn below the reader\'s '
      'text size (no scale-down; the actions take their own row)', (
    tester,
  ) async {
    await pumpViewer(
      tester,
      vip: true,
      likes: 1234,
      size: const Size(390, 844),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byKey(_likers),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    // getRect is transform-aware: a scaled-down glyph would measure short.
    final digits = tester.getRect(
      find.descendant(of: find.byKey(_likers), matching: find.text('1.2K')),
    );
    expect(digits.height, greaterThanOrEqualTo(12.5 * 2));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.byKey(_likers), matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      tester.getSize(find.byKey(_likers)).shortestSide,
      greaterThanOrEqualTo(44),
    );
  });

  // Below 390 px at 200 % the viewer's header and stage already overflow
  // without this chip (pre-existing, recorded as a follow-up), so the large
  // text case is pinned at 390 and the narrow case at 100 %.
  for (final (size, scale) in const [
    (Size(390, 844), 2.0),
    (Size(320, 700), 1.0),
  ]) {
    testWidgets('lays out at ${size.width.toInt()} px and ${scale * 100} % '
        'text', (tester) async {
      await pumpViewer(
        tester,
        vip: true,
        likes: 1234,
        size: size,
        textScale: scale,
      );
      expect(find.byKey(_likers), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
