import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_reels_feed_integration.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';

Map<String, Object?> _wire(String id, {String author = 'creator'}) => {
  'id': id,
  'authorId': author,
  'authorName': 'Creator',
  'media': {
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
  'publishedAtMillis': 1725000000000,
  'sortKey': '1725000000000_$id',
  'availability': {
    'schemaVersion': 1,
    'availabilityHours': 'permanent',
    'expiresAtMillis': null,
  },
};
Map<Object?, Object?> _page(List<Object?> items, {String? cursor}) => {
  'schemaVersion': 2,
  'items': items,
  'nextCursor': cursor,
};
MockFirebaseAuth _auth() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
);

void main() {
  setUp(() {
    ReelService.clearAllMediaAccessCaches();
    ReelService.debugResetInlineGrantSupport();
  });

  test(
    'own scope uses the server query and defensively keeps canonical ownership',
    () async {
      final payloads = <Map<String, Object?>>[];
      final service = ReelService(
        auth: _auth(),
        callableInvoker: (_, payload) async {
          payloads.add(payload);
          return _page([_wire('foreign'), _wire('mine', author: 'viewer')]);
        },
      );
      final page = await service.fetchFeed(
        scope: ReelFeedScope.own,
        warmLeadingMedia: false,
      );
      expect(payloads.single['scope'], 'own');
      expect(page.items.single.id, 'mine');
    },
  );

  test(
    'own flag refusal falls back once only after unscoped success',
    () async {
      final payloads = <Map<String, Object?>>[];
      final service = ReelService(
        auth: _auth(),
        callableInvoker: (_, payload) async {
          payloads.add(payload);
          if (payload.containsKey('scope')) {
            throw FirebaseFunctionsException(
              code: 'invalid-argument',
              message: 'old contract',
            );
          }
          return _page([_wire('mine', author: 'viewer')]);
        },
      );
      await service.fetchFeed(
        warmLeadingMedia: false,
      ); // inline capability known
      await service.fetchFeed(
        scope: ReelFeedScope.own,
        warmLeadingMedia: false,
      );
      await service.fetchFeed(
        scope: ReelFeedScope.own,
        warmLeadingMedia: false,
      );
      expect(payloads.where((p) => p['scope'] == 'own'), hasLength(1));
      expect(payloads.last.containsKey('scope'), isFalse);
    },
  );

  test(
    'missing index or authorization never triggers old-server fallback',
    () async {
      for (final code in [
        'failed-precondition',
        'permission-denied',
        'unavailable',
      ]) {
        var calls = 0;
        final service = ReelService(
          auth: _auth(),
          callableInvoker: (_, _) async {
            calls++;
            throw FirebaseFunctionsException(code: code, message: 'refused');
          },
        );
        await expectLater(
          service.fetchFeed(scope: ReelFeedScope.own),
          throwsA(isA<FirebaseFunctionsException>()),
        );
        expect(calls, 1);
      }
    },
  );

  test('failed bare replay does not latch unsupported scope', () async {
    var fail = true;
    final scopes = <Object?>[];
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (_, payload) async {
        scopes.add(payload['scope']);
        if (fail) {
          throw FirebaseFunctionsException(
            code: 'invalid-argument',
            message: 'refused',
          );
        }
        return _page([]);
      },
    );
    await expectLater(
      service.fetchFeed(scope: ReelFeedScope.own),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    fail = false;
    await service.fetchFeed(scope: ReelFeedScope.own);
    expect(scopes.last, 'own');
  });

  test(
    'seen ledger records exact owner timestamp and bounded retention, once',
    () async {
      final db = FakeFirebaseFirestore();
      final service = ReelService(auth: _auth(), firestore: db);
      final reel = Reel.fromV2Wire(_wire('viewed'));
      await service.recordViewed(reel);
      final ref = db.doc('users/viewer/reelViews/viewed');
      final first = (await ref.get()).data()!;
      expect(first.keys.toSet(), {'viewedAt', 'expiresAt'});
      expect(first['viewedAt'], isA<Timestamp>());
      expect(
        (first['expiresAt'] as Timestamp)
            .toDate()
            .difference(DateTime.now())
            .inDays,
        inInclusiveRange(89, 90),
      );
      await service.recordViewed(reel);
      expect((await ref.get()).data(), first);
      await service.recordViewed(
        Reel.fromV2Wire(_wire('own', author: 'viewer')),
      );
      expect(
        (await db.collection('users/viewer/reelViews').get()).docs,
        hasLength(1),
      );
    },
  );

  test(
    'a ready, stalled, paused or suspended decoder contributes no watch time',
    () async {
      var progress = Duration.zero;
      final player = _Video();
      final playback = ReelPlaybackCoordinator(
        reel: Reel.fromV2Wire(_wire('watch')),
        resolveBackingAudioUri: () async => Uri.parse('memory:unused'),
        autoplay: true,
        muted: true,
        onVideoProgress: (value) => progress += value,
      );
      addTearDown(playback.dispose);
      await playback.attachVideo(player);
      await playback.synchronizeVideoTick();
      await playback.synchronizeVideoTick();
      expect(progress, Duration.zero);
      player.position = const Duration(milliseconds: 500);
      await playback.synchronizeVideoTick();
      expect(progress, const Duration(milliseconds: 500));
      await playback.toggle();
      player.position = const Duration(seconds: 1);
      await playback.synchronizeVideoTick();
      expect(progress, const Duration(milliseconds: 500));
      await playback.setAutoplaySuspended(true);
      player.position = const Duration(seconds: 2);
      await playback.synchronizeVideoTick();
      expect(progress, const Duration(milliseconds: 500));
      await playback.setAutoplaySuspended(false);
      await playback.toggle();
      await playback.synchronizeVideoTick();
      player.position = const Duration(seconds: 8); // seek, not watching
      await playback.synchronizeVideoTick();
      expect(progress, const Duration(milliseconds: 500));
    },
  );

  testWidgets(
    'drained unseen feed confirms seen content and offers Watch again',
    (tester) async {
      final requests = <Map<String, Object?>>[];
      final service = ReelService(
        auth: _auth(),
        callableInvoker: (name, payload) async {
          if (name != 'listReelsV2') throw StateError('no media');
          requests.add(payload);
          return _page(payload['includeSeen'] == true ? [_wire('seen')] : []);
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: ReelsFeedScreen(
            service: service,
            videoBuilder: (_, _, _) => const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('You’re all caught up'), findsOneWidget);
      expect(find.text('No Reels yet'), findsNothing);
      await tester.tap(find.text('Watch again'));
      await tester.pumpAndSettle();
      expect(find.byType(ReelCard), findsOneWidget);
      expect(requests.last['includeSeen'], isTrue);
    },
  );

  testWidgets('loading a page warms only its leading card and next neighbor', (
    tester,
  ) async {
    final grants = <String>[];
    final db = FakeFirebaseFirestore();
    final service = ReelService(
      auth: _auth(),
      firestore: db,
      callableInvoker: (name, payload) async {
        if (name == 'listReelsV2') {
          return _page([_wire('first'), _wire('next'), _wire('later')]);
        }
        grants.add(payload['reelId']! as String);
        return {
          'schemaVersion': 2,
          'url': 'https://storage.googleapis.com/bucket/${payload['reelId']}',
          'generation': '7',
          'expiresAtMillis': DateTime.now()
              .add(const Duration(minutes: 2))
              .millisecondsSinceEpoch,
          'availabilityHours': 'permanent',
          'contentExpiresAtMillis': null,
        };
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: ReelsFeedScreen(
          service: service,
          videoBuilder: (_, _, _) => const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(grants, ['first', 'next']);
    expect((await db.collection('users/viewer/reelViews').get()).docs, isEmpty);
  });

  test(
    'caught-up copy has all 41 translated variants, without English fallback',
    () {
      expect(
        reelsFeedIntegrationTranslations.keys.toSet(),
        appTranslations.keys.toSet(),
      );
      for (final entry in reelsFeedIntegrationTranslations.entries) {
        expect(entry.value.keys.toSet(), reelsFeedIntegrationKeys.toSet());
        for (final key in reelsFeedIntegrationKeys) {
          expect(entry.value[key]!.trim(), isNotEmpty);
          expect(entry.value[key], isNot(key));
          expect(translatedPhrase(entry.key, key), entry.value[key]);
        }
      }
    },
  );
}

class _Video implements ReelVideoPlayback {
  @override
  bool isPlaying = false;
  @override
  Duration position = Duration.zero;
  @override
  Future<void> pause() async => isPlaying = false;
  @override
  Future<void> play() async => isPlaying = true;
  @override
  Future<void> seek(Duration value) async => position = value;
  @override
  Future<void> setVolume(double volume) async {}
}
