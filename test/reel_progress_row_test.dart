import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_progress_row.dart';

import 'reel_stage_test_support.dart';

/// The Reel's progress row (board 08).
///
/// Two facts are held here. The bar, its labels and the spoken value read ONE
/// clock — the coordinator's — so a bar at 51 % can never sit beside a
/// "0:06 / 0:18" that means 33 %. And that clock is published as a
/// [ValueListenable] rather than a notifier tick, so a Reel running at 60 fps
/// repaints a 4-px bar instead of rebuilding the card sixty times a second
/// (spec §9 line 167).
void main() {
  group('the clock', () {
    test('the position listenable never notifies the card', () async {
      final video = FakeReelVideoPlayback();
      final coordinator = _coordinator(video: video);
      addTearDown(coordinator.dispose);
      await coordinator.attachVideo(video);

      var notifications = 0;
      coordinator.addListener(() => notifications += 1);

      for (var second = 1; second <= 5; second++) {
        video.position = Duration(seconds: second);
        await coordinator.synchronizeVideoTick();
      }

      expect(coordinator.position.value, const Duration(seconds: 5));
      expect(
        notifications,
        0,
        reason:
            'a position tick must not rebuild anything that listens to '
            'the coordinator itself',
      );
    });

    test('position is the timeline offset, clamped at both ends', () async {
      final video = FakeReelVideoPlayback();
      final coordinator = _coordinator(video: video, trimStartMs: 5000);
      addTearDown(coordinator.dispose);
      await coordinator.attachVideo(video);

      // Before the trim start there is no negative progress.
      video.position = const Duration(seconds: 1);
      await coordinator.synchronizeVideoTick();
      expect(coordinator.position.value, Duration.zero);

      video.position = const Duration(seconds: 11);
      await coordinator.synchronizeVideoTick();
      expect(coordinator.position.value, const Duration(seconds: 6));

      // And never past the published timeline — a Reel that reaches its trim
      // end loops back to the start, so the bar is either full or back at
      // zero, never beyond.
      video.position = const Duration(seconds: 90);
      await coordinator.synchronizeVideoTick();
      expect(
        coordinator.position.value,
        lessThanOrEqualTo(coordinator.timelineDuration),
      );
    });

    test('leaving the page returns the bar to zero', () async {
      final video = FakeReelVideoPlayback();
      final coordinator = _coordinator(video: video);
      addTearDown(coordinator.dispose);
      await coordinator.attachVideo(video);
      video.position = const Duration(seconds: 7);
      await coordinator.synchronizeVideoTick();
      expect(coordinator.position.value, const Duration(seconds: 7));

      await coordinator.setActive(false);
      expect(coordinator.position.value, Duration.zero);
    });
  });

  group('the row', () {
    testWidgets('bar and labels read the same value', (tester) async {
      final position = ValueNotifier<Duration>(const Duration(seconds: 6));
      addTearDown(position.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: ReelProgressRow(
                  position: position,
                  total: const Duration(seconds: 18),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0:06 / 0:18'), findsOneWidget);
      final played = tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey<String>('reel-progress-bar')),
          matching: find.byType(FractionallySizedBox),
        ),
      );
      final track = tester.getSize(
        find.byKey(const ValueKey<String>('reel-progress-bar')),
      );
      expect(played.width / track.width, closeTo(6 / 18, .01));

      position.value = const Duration(seconds: 9);
      await tester.pump();
      expect(find.text('0:09 / 0:18'), findsOneWidget);
      final advanced = tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey<String>('reel-progress-bar')),
          matching: find.byType(FractionallySizedBox),
        ),
      );
      expect(advanced.width / track.width, closeTo(.5, .01));
    });

    testWidgets('an unknown timeline leaves the track empty', (tester) async {
      final position = ValueNotifier<Duration>(const Duration(seconds: 4));
      addTearDown(position.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: ReelProgressRow(position: position, total: Duration.zero),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final played = tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey<String>('reel-progress-bar')),
          matching: find.byType(FractionallySizedBox),
        ),
      );
      expect(played.width, 0);
    });

    testWidgets('the stage bar follows the real engine', (tester) async {
      // End to end through the production seam: a photo Reel's timeline IS
      // its backing track, so the track's own position is what the bar reads.
      final audio = FakeReelAudioPlayback();
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(900, 1000),
        count: 1,
        photo: true,
        audioPlaybackFactory: () => audio,
      );

      expect(find.text('0:00 / 0:12'), findsOneWidget);

      // A photo Reel waits to be asked, and its track is what it plays: the
      // deliberate start is also what connects the clock.
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-playback-toggle')),
      );
      await tester.pumpAndSettle();

      audio.emit(const Duration(seconds: 6));
      await tester.pump();

      expect(find.text('0:06 / 0:12'), findsOneWidget);
      expect(find.text('0:00 / 0:12'), findsNothing);
    });
  });
}

ReelPlaybackCoordinator _coordinator({
  required FakeReelVideoPlayback video,
  int trimStartMs = 0,
}) => ReelPlaybackCoordinator(
  reel: Reel(
    id: 'video_reel',
    authorId: 'creator',
    authorName: 'Creator',
    media: const ReelMediaDescriptor(
      kind: ReelMediaKind.video,
      contentType: 'video/mp4',
      size: 4096,
      generation: '1',
      durationMs: 20000,
    ),
    composition: ReelComposition(
      trimStartMs: trimStartMs,
      trimEndMs: trimStartMs + 18000,
      originalAudioVolume: 100,
    ),
    publishedAt: DateTime.utc(2026, 9, 3),
    sortKey: '1788408000000_video_reel',
  ),
  resolveBackingAudioUri: () async => Uri(scheme: 'memory', path: 'a'),
  audioPlaybackFactory: FakeReelAudioPlayback.new,
  autoplay: true,
  muted: true,
);
