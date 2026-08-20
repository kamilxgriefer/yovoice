// The Moments redesign: the Discover AVATAR BOARD, the compact Following
// grid, and the live like/comment counters.
//
// Three defects are pinned here, each of which shipped:
//
//  * Discover rendered ONE Moment per viewport with a large empty middle;
//    it is now a board of circles, wall to wall.
//  * the board's order did not reflect engagement — the weighted shuffle
//    could bury the most-liked Moment at the bottom of the stack.
//  * likes and comments were read once, by a deliberate one-shot `get()`,
//    and never re-read: a like or a comment only appeared after a full
//    page reload.
//
// `moments_discovery_test.dart` still owns the ranking arithmetic, the
// shuffle and the safety filter; this file owns what the surface does
// with them.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

const _me = 'me';

VoiceMoment _moment(
  String id, {
  String author = 'author',
  String? authorName,
  int likes = 0,
  int comments = 0,
  int durationSeconds = 12,
  bool published = true,
}) => VoiceMoment(
  id: id,
  authorId: author,
  authorName: authorName ?? 'Author $author',
  authorPhotoUrl: null,
  caption: 'caption $id',
  audioUrl: 'https://cdn.example/$id.m4a',
  durationSeconds: durationSeconds,
  likeCount: likes,
  commentCount: comments,
  isPublished: published,
  createdAt: DateTime(2026, 8, 1),
  schemaVersion: 2,
  status: 'published',
);

Map<String, dynamic> _doc(VoiceMoment moment) => <String, dynamic>{
  'authorId': moment.authorId,
  'authorName': moment.authorName,
  'authorPhotoUrl': null,
  'caption': moment.caption,
  'audioUrl': moment.audioUrl,
  'durationSeconds': moment.durationSeconds,
  'likeCount': moment.likeCount,
  'commentCount': moment.commentCount,
  'isPublished': moment.isPublished,
  'createdAt': Timestamp.fromDate(moment.createdAt!),
  'schemaVersion': 2,
  'status': 'published',
  'isDeleted': false,
};

const _playerKey = ValueKey('moments-discovery-player');

void main() {
  late PublicIdentityRepository originalIdentity;

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  _QuietFeed feed() => _QuietFeed(
    firestore: FakeFirebaseFirestore(),
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
  );

  group('the ranking the board renders', () {
    test('the most-engaged Moment is first, and the order is total and '
        'deterministic', () {
      final quiet = _moment('quiet', author: 'a');
      final loud = _moment('loud', author: 'b', likes: 40);
      final talked = _moment('talked', author: 'c', likes: 2, comments: 6);

      final ranked = MomentDiscoveryService.rankByEngagement([
        quiet,
        loud,
        talked,
      ]);
      expect(ranked.map((m) => m.id), ['loud', 'talked', 'quiet']);

      // Same input in a different order must produce the same board;
      // otherwise "most engaged at the top" would depend on which pool
      // query happened to answer first.
      expect(
        MomentDiscoveryService.rankByEngagement([
          talked,
          quiet,
          loud,
        ]).map((m) => m.id),
        ['loud', 'talked', 'quiet'],
      );
    });

    test('comments count, and nothing is dropped', () {
      final input = [
        for (var i = 0; i < 20; i++) _moment('m$i', author: 'a$i', comments: i),
      ];
      final ranked = MomentDiscoveryService.rankByEngagement(input);
      expect(ranked.length, input.length);
      expect(ranked.map((m) => m.id).toSet(), input.map((m) => m.id).toSet());
      expect(ranked.first.id, 'm19');
    });
  });

  group('the Discover board', () {
    testWidgets('renders one circle per Moment with the most-engaged at the '
        'top of the board, regardless of the order it was handed', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            feedService: feed(),
            // Deliberately worst case: the shuffle handed the board the
            // most-liked Moment LAST. This is exactly the reported
            // "a popular one gets buried".
            discoveryService: _StaticDiscovery([
              _moment('quiet', author: 'a'),
              _moment('talked', author: 'c', likes: 2, comments: 6),
              _moment('loud', author: 'b', likes: 40),
            ]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      Offset at(String id) =>
          tester.getTopLeft(find.byKey(ValueKey('moment-tile-$id')));

      final loud = at('loud');
      final talked = at('talked');
      final quiet = at('quiet');

      int reading(Offset a, Offset b) {
        final byRow = a.dy.compareTo(b.dy);
        return byRow != 0 ? byRow : a.dx.compareTo(b.dx);
      }

      expect(
        reading(loud, talked),
        lessThan(0),
        reason: '40 likes must sit ahead of 2 likes and 6 comments',
      );
      expect(
        reading(talked, quiet),
        lessThan(0),
        reason: 'engagement of any kind must sit ahead of none',
      );

      // And the top of the board is what the player has loaded.
      expect(
        find.descendant(of: find.byKey(_playerKey), matching: find.text('40')),
        findsOneWidget,
      );
    });

    testWidgets('a board of ONE renders as a board, with the recorder tile '
        'and an honest total', (tester) async {
      // Production reality when this was written: exactly one published
      // Moment. A grid that only looks composed when it is full is a
      // grid that is broken on day one.
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            feedService: feed(),
            discoveryService: _StaticDiscovery([
              _moment('solo', author: _me, likes: 1, comments: 1),
            ]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('moment-tile-solo')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('moments-discovery-record')),
        findsOneWidget,
      );
      expect(
        find.text('That is the only published Moment we could find.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a circle loads it and plays it', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final player = _FakeAudioPlayer();
      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            feedService: feed(),
            playerFactory: () => player,
            discoveryService: _StaticDiscovery([
              _moment('first', author: 'a', likes: 9),
              _moment('second', author: 'b'),
            ]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Nothing plays on arrival — audio that starts by itself is how a
      // person closes the tab.
      expect(player.playCount, 0);

      await tester.tap(find.byKey(const ValueKey('moment-tile-second')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(player.playCount, 1);
      expect(player.lastUrl, 'https://cdn.example/second.m4a');
      // And the player followed the tap rather than staying on the top of
      // the board.
      expect(
        find.descendant(of: find.byKey(_playerKey), matching: find.text('2 of 2')),
        findsOneWidget,
      );
    });

    testWidgets('likes and comments go live WITHOUT a reload — the reported '
        'defect', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final counters = StreamController<Map<String, MomentEngagement>>();
      addTearDown(counters.close);

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            feedService: feed(),
            discoveryService: _StaticDiscovery([
              _moment('solo', author: 'a', likes: 1),
            ], counters: counters.stream),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final inPlayer = find.descendant(
        of: find.byKey(_playerKey),
        matching: find.text('1'),
      );
      // First paint already shows the real loaded count...
      expect(inPlayer, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_playerKey),
          matching: find.text('Comment'),
        ),
        findsOneWidget,
        reason: 'a zero comment count is a verb, never a fabricated "0"',
      );

      // ...and a like landing afterwards arrives without any reload.
      counters.add(<String, MomentEngagement>{
        'solo': const MomentEngagement(likeCount: 7, commentCount: 3),
      });
      await tester.pump();
      await tester.pump();

      expect(
        find.descendant(of: find.byKey(_playerKey), matching: find.text('7')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(_playerKey), matching: find.text('3')),
        findsOneWidget,
      );
      // The circle carries the same fresh numbers.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('moment-tile-solo')),
          matching: find.text('7'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a counter stream that fails leaves the loaded counts alone '
        'rather than taking the board down', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            feedService: feed(),
            discoveryService: _StaticDiscovery([
              _moment('solo', author: 'a', likes: 4),
            ], counters: Stream<Map<String, MomentEngagement>>.error(
              StateError('counter stream down'),
            )),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('moment-tile-solo')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(_playerKey), matching: find.text('4')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the shuffle is still there, and it is a different order', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final discovery = _StaticDiscovery([
        for (var i = 0; i < 6; i++) _moment('m$i', author: 'a$i', likes: i),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(feedService: feed(), discoveryService: discovery),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(discovery.loads, 1);

      await tester.tap(find.byKey(const ValueKey('moments-discovery-shuffle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The board now shows what the SERVICE ordered (weighted shuffle,
      // author-spaced) rather than the engagement ranking, so the least
      // engaged Moment is no longer forced to the end.
      Offset at(String id) =>
          tester.getTopLeft(find.byKey(ValueKey('moment-tile-$id')));
      expect(at('m0').dy, lessThanOrEqualTo(at('m5').dy));

      // Tapping it again is a real reshuffle, not a no-op.
      await tester.tap(find.byKey(const ValueKey('moments-discovery-shuffle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(discovery.loads, 2);
    });

    for (final width in <double>[390, 768, 1100, 1440]) {
      for (final scale in <double>[1.0, 2.0]) {
        testWidgets('lays out with no overflow at ${width.toInt()} px and '
            '${scale}x text', (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: TextScaler.linear(scale),
                ),
                child: MomentsScreen(
                  feedService: feed(),
                  discoveryService: _StaticDiscovery([
                    for (var i = 0; i < 24; i++)
                      _moment(
                        'm$i',
                        author: 'a$i',
                        authorName:
                            'Aleksandra-Konstantina Wielkopolska-Nowakowska $i',
                        likes: i,
                        comments: i * 2,
                      ),
                  ]),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(tester.takeException(), isNull);
          // The board is the surface, and the player is reachable at
          // every width — never one at the cost of the other.
          expect(find.byKey(const ValueKey('moment-tile-m0')), findsOneWidget);
          expect(find.byKey(_playerKey), findsOneWidget);
        });
      }
    }
  });

  group('the compact Following grid', () {
    late FakeFirebaseFirestore db;

    Future<MomentService> seeded(List<VoiceMoment> mine) async {
      db = FakeFirebaseFirestore();
      for (final moment in mine) {
        await db.collection('voiceMoments').doc(moment.id).set(_doc(moment));
      }
      return MomentService(
        firestore: db,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
        storage: MockFirebaseStorage(),
      );
    }

    testWidgets('renders mini square tiles instead of full-width cards', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final moments = await seeded([
        _moment('mine-1', author: _me, likes: 1, comments: 1),
        _moment('mine-2', author: _me),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            initialTab: MomentsTab.following,
            momentService: moments,
            feedService: _QuietFeed(
              firestore: FakeFirebaseFirestore(),
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: _me),
              ),
              social: [_moment('theirs', author: 'friend', likes: 3)],
            ),
            discoveryService: _StaticDiscovery(const []),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      for (final id in ['mine-1', 'mine-2', 'theirs']) {
        expect(
          find.byKey(ValueKey('moment-square-$id')),
          findsOneWidget,
          reason: '$id should have a tile',
        );
      }

      // Compact means compact: two tiles fit one row on a 390 pt phone,
      // which the old full-width cards could never do.
      final first = tester.getRect(
        find.byKey(const ValueKey('moment-square-mine-1')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('moment-square-mine-2')),
      );
      expect(first.top, second.top);
      expect(first.width, lessThan(200));
      expect(first.height, lessThan(200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a tile opens the full card — playback, like, '
        'comment and the offline download all survive the redesign', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final moments = await seeded([_moment('mine-1', author: _me)]);

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            initialTab: MomentsTab.following,
            momentService: moments,
            feedService: _QuietFeed(
              firestore: FakeFirebaseFirestore(),
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: _me),
              ),
            ),
            discoveryService: _StaticDiscovery(const []),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(MomentCard), findsNothing);

      await tester.tap(find.byKey(const ValueKey('moment-square-mine-1')));
      await tester.pumpAndSettle();

      expect(find.byType(MomentCard), findsOneWidget);
      expect(
        find.byKey(const ValueKey('download-moment-mine-1')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    });

    testWidgets('the open sheet re-reads its own Moment, so a like made '
        'inside it moves its own counter', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final moments = await seeded([
        _moment('mine-1', author: _me, likes: 2, comments: 0),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            initialTab: MomentsTab.following,
            momentService: moments,
            feedService: _QuietFeed(
              firestore: FakeFirebaseFirestore(),
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: _me),
              ),
            ),
            discoveryService: _StaticDiscovery(const []),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byKey(const ValueKey('moment-square-mine-1')));
      await tester.pumpAndSettle();

      final card = find.byType(MomentCard);
      expect(find.descendant(of: card, matching: find.text('2')), findsOneWidget);

      // The counter changes on the server the way a like does.
      await db.collection('voiceMoments').doc('mine-1').update(
        <String, dynamic>{'likeCount': 3, 'commentCount': 5},
      );
      await tester.pump();
      await tester.pump();

      expect(find.descendant(of: card, matching: find.text('3')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('5')), findsOneWidget);
    });

    for (final width in <double>[390, 768, 1100, 1440]) {
      testWidgets('the grid lays out with no overflow at ${width.toInt()} px', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final moments = await seeded([
          for (var i = 0; i < 9; i++) _moment('mine-$i', author: _me, likes: i),
        ]);

        await tester.pumpWidget(
          MaterialApp(
            home: MomentsScreen(
              initialTab: MomentsTab.following,
              momentService: moments,
              feedService: _QuietFeed(
                firestore: FakeFirebaseFirestore(),
                auth: MockFirebaseAuth(
                  signedIn: true,
                  mockUser: MockUser(uid: _me),
                ),
                social: [
                  for (var i = 0; i < 7; i++)
                    _moment(
                      'theirs-$i',
                      author: 'friend$i',
                      authorName: 'A very long display name number $i',
                      likes: i,
                    ),
                ],
              ),
              discoveryService: _StaticDiscovery(const []),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('moment-square-theirs-0')),
          findsOneWidget,
        );
      });
    }
  });
}

class _StaticDiscovery implements MomentDiscoveryService {
  _StaticDiscovery(this.moments, {this.counters});

  final List<VoiceMoment> moments;
  final Stream<Map<String, MomentEngagement>>? counters;

  int loads = 0;

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async {
    loads += 1;
    return MomentDiscoveryFeed(
      moments: moments,
      fetchedCount: moments.length,
      drops: const <String, MomentDropReason>{},
      seed: seed ?? 0,
      poolExhausted: false,
    );
  }

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => counters ?? const Stream<Map<String, MomentEngagement>>.empty();

  @override
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async =>
      moments.take(limit).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietFeed extends HomeFeedService {
  _QuietFeed({super.firestore, super.auth, this.social = const []});

  final List<VoiceMoment> social;

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.value(social);

  @override
  Stream<bool> watchLiked(String momentId) => Stream<bool>.value(false);

  @override
  Future<void> toggleLike(String momentId) async {}
}

/// An [audio.AudioPlayer] that reports a real position shortly after play, so
/// the view's "started but produced nothing" watchdog resolves the way it
/// does against a working device.
class _FakeAudioPlayer implements audio.AudioPlayer {
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durations =
      StreamController<Duration>.broadcast();
  final StreamController<void> _completions =
      StreamController<void>.broadcast();

  int playCount = 0;
  int stopCount = 0;
  String? lastUrl;

  @override
  Stream<Duration> get onPositionChanged => _positions.stream;

  @override
  Stream<Duration> get onDurationChanged => _durations.stream;

  @override
  Stream<void> get onPlayerComplete => _completions.stream;

  @override
  Future<void> play(
    audio.Source source, {
    double? volume,
    double? balance,
    audio.AudioContext? ctx,
    Duration? position,
    audio.PlayerMode? mode,
  }) async {
    playCount += 1;
    lastUrl = source is audio.UrlSource ? source.url : null;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        if (_positions.isClosed) return;
        _durations.add(const Duration(seconds: 12));
        _positions.add(const Duration(milliseconds: 120));
      }),
    );
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {
    await _positions.close();
    await _durations.close();
    await _completions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
