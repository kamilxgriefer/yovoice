import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';

/// Shared doubles for the board-08 stage suites.
///
/// Everything reaches the widgets through the real [ReelService] over a fake
/// callable transport, exactly as production parses it, and the video engine
/// is injected so no widget test ever starts a platform decoder.

const reelLikeKey = ValueKey<String>('reel-like-action');
const reelCommentsKey = ValueKey<String>('reel-comments-action');
const reelShareKey = ValueKey<String>('reel-share-action');
const reelMoreKey = ValueKey<String>('reel-more-action');
const reelSoundKey = ValueKey<String>('reel-sound-toggle');
const reelNextKey = ValueKey<String>('reel-next-action');
const reelStageFooterKey = ValueKey<String>('reel-stage-footer-bar');
const reelStageCaptionKey = ValueKey<String>('reel-stage-caption');
const reelProgressBarKey = ValueKey<String>('reel-progress-bar');
const reelProgressTimesKey = ValueKey<String>('reel-progress-times');
const reelNextCardKey = ValueKey<String>('reel-next-card');
const reelPanelThreadToggleKey = ValueKey<String>('reel-panel-thread-toggle');
const reelPlaybackSurfaceKey = ValueKey<String>('reel-video-playback-surface');

const reelStageCaption =
    'Night shift stories from the harbour, recorded between two calls and '
    'edited on the way home while the city was still awake.';

Map<String, Object?> reelWire(
  int index, {
  bool photo = false,
  String authorId = 'creator',
  String caption = reelStageCaption,
  int likeCount = 12,
  int commentCount = 3,
}) {
  final millis = 1725000000000 + index;
  return <String, Object?>{
    'id': 'reel_$index',
    'authorId': '${authorId}_$index',
    'authorName': 'Creator $index',
    'media': <String, Object?>{
      'kind': photo ? 'image' : 'video',
      'contentType': photo ? 'image/jpeg' : 'video/mp4',
      'size': 4096,
      'generation': '7',
      'durationMs': photo ? 0 : 18000,
    },
    'backingAudio': photo
        ? <String, Object?>{
            'contentType': 'audio/mpeg',
            'size': 4096,
            'generation': '8',
            'durationMs': 12000,
          }
        : null,
    'composition':
        (photo
                ? ReelComposition(
                    originalAudioVolume: 0,
                    backingAudioVolume: 70,
                    audioTrimStartMs: 0,
                    audioRightsAttested: true,
                    caption: caption,
                  )
                : ReelComposition(
                    trimStartMs: 0,
                    trimEndMs: 18000,
                    originalAudioVolume: 100,
                    caption: caption,
                  ))
            .toWire(),
    'publishedAtMillis': millis,
    'sortKey': '${millis}_reel_$index',
    'availability': <String, Object?>{
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
    'likeCount': likeCount,
    'commentCount': commentCount,
    'callerLiked': false,
  };
}

/// A [ReelService] over a fake transport, with the callables these suites use.
ReelService reelStageService({
  int count = 2,
  bool photo = false,
  String viewerUid = 'viewer',
  String authorId = 'creator',
  List<Map<String, Object?>> comments = const <Map<String, Object?>>[],
  List<String>? calls,
}) => ReelService(
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: viewerUid, isEmailVerified: true),
  ),
  callableInvoker: (name, payload) async {
    calls?.add(name);
    switch (name) {
      case 'listReelsV2':
        return <Object?, Object?>{
          'schemaVersion': 2,
          'items': <Object?>[
            for (var index = 1; index <= count; index++)
              reelWire(index, photo: photo, authorId: authorId),
          ],
          'nextCursor': null,
        };
      case 'getReelMediaAccessV2':
        final isAudio = payload['asset'] == 'backingAudio';
        return <Object?, Object?>{
          'schemaVersion': 2,
          'url': isAudio
              ? 'https://storage.googleapis.com/yovoice/audio.mp3'
              : 'https://storage.googleapis.com/yovoice/${payload['reelId']}.mp4',
          'expiresAtMillis': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'generation': '7',
          'availabilityHours': 'permanent',
          'contentExpiresAtMillis': null,
        };
      case 'getReelViewV2':
        return <Object?, Object?>{
          'schemaVersion': 2,
          'reel': reelWire(1, photo: photo, authorId: authorId),
          'comments': <Object?>[...comments],
          'commentsTruncated': false,
          'nextCommentCursor': null,
        };
      case 'listReelCommentsV2':
        return <Object?, Object?>{
          'schemaVersion': 2,
          'items': <Object?>[...comments],
          'nextCursor': null,
        };
    }
    throw StateError('Unexpected callable $name with $payload');
  },
);

Map<String, Object?> reelCommentWire({
  String id = 'c1',
  String authorId = 'creator_1',
  String authorName = 'Creator 1',
  String text = 'Great one.',
}) => <String, Object?>{
  'schemaVersion': 1,
  'commentId': id,
  'type': 'text',
  'authorId': authorId,
  'authorName': authorName,
  'authorPhotoUrl': null,
  'text': text,
  'durationSeconds': null,
  'createdAtMillis': 1725000000000,
};

/// A real [FollowService] over in-memory Firebase doubles, so the footer's
/// follow control exercises the same stream and the same mutation path as
/// production without reaching the network.
({FollowService service, List<Map<String, dynamic>> mutations})
reelFollowService({
  required String viewerUid,
  Set<String> following = const <String>{},
  Completer<void>? gate,
}) {
  final firestore = FakeFirebaseFirestore();
  for (final uid in following) {
    firestore
        .collection('users')
        .doc(viewerUid)
        .collection('following')
        .doc(uid)
        .set(<String, Object?>{'uid': uid});
  }
  final mutations = <Map<String, dynamic>>[];
  final service = FollowService(
    firestore: firestore,
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: viewerUid, isEmailVerified: true),
    ),
    mutationInvoker: (data) async {
      mutations.add(data);
      if (gate != null) await gate.future;
      final target = data['targetUserId'] as String;
      final reference = firestore
          .collection('users')
          .doc(viewerUid)
          .collection('following')
          .doc(target);
      if (data['following'] == true) {
        await reference.set(<String, Object?>{'uid': target});
      } else {
        await reference.delete();
      }
      return <String, dynamic>{};
    },
  );
  return (service: service, mutations: mutations);
}

/// One engine per Reel id, kept across mounts so a page that is scrolled away
/// and back is still observable.
class FakeReelPlayers {
  final Map<String, FakeReelVideoPlayback> _byReel =
      <String, FakeReelVideoPlayback>{};

  FakeReelVideoPlayback of(String reelId) =>
      _byReel.putIfAbsent(reelId, FakeReelVideoPlayback.new);

  int get playing => _byReel.values.where((player) => player.playing).length;
}

class FakeReelVideoPlayback implements ReelVideoPlayback {
  bool playing = false;
  @override
  Duration position = Duration.zero;
  double volume = 1;
  int playCount = 0;
  int pauseCount = 0;
  final List<Duration> seekPositions = <Duration>[];

  @override
  bool get isPlaying => playing;

  @override
  Future<void> pause() async {
    pauseCount += 1;
    playing = false;
  }

  @override
  Future<void> play() async {
    playCount += 1;
    playing = true;
  }

  @override
  Future<void> seek(Duration value) async {
    seekPositions.add(value);
    position = value;
  }

  @override
  Future<void> setVolume(double value) async => volume = value;
}

class FakeReelAudioPlayback implements ReelAudioPlayback {
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<void> _completions = StreamController<void>.broadcast(
    sync: true,
  );

  double volume = 1;
  int playCount = 0;
  int pauseCount = 0;
  final List<Uri> loaded = <Uri>[];
  final List<Duration> seekPositions = <Duration>[];

  void emit(Duration position) => _positions.add(position);

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Stream<Duration> get positionChanges => _positions.stream;

  @override
  Future<void> dispose() async {
    await _positions.close();
    await _completions.close();
  }

  @override
  Future<void> load(Uri uri) async => loaded.add(uri);

  @override
  Future<void> pause() async => pauseCount += 1;

  @override
  Future<void> play() async => playCount += 1;

  @override
  Future<void> seek(Duration position) async => seekPositions.add(position);

  @override
  Future<void> setVolume(double value) async => volume = value;

  @override
  Future<void> stop() async {}
}

/// Loads the typeface the app actually ships.
///
/// `flutter_test`'s default font draws every glyph one em wide, so a digit is
/// twice as wide there as in Inter and every width-dependent outcome — does
/// this row of four fit, does this label wrap — is decided by metrics that
/// never reach a user. Any case that asserts what a reader SEES at a width
/// has to be laid out in the real face.
Future<void> loadStageFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
  await inter.load();
}

/// A real [FollowService] over fakes, so the stage footer draws the inline
/// `Obserwuj` control the boards have on it. Without one the footer is a
/// row shorter than production's and every height measured from it is a
/// measurement of a footer nobody sees.
FollowService stageFollowService({String viewerUid = 'viewer'}) =>
    FollowService(
      firestore: FakeFirebaseFirestore(),
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: viewerUid, isEmailVerified: true),
      ),
      mutationInvoker: (_) async => <String, dynamic>{},
    );

/// Pumps the embedded Reels feed at [size], the way YO Moments hosts it.
Future<void> pumpReelStage(
  WidgetTester tester, {
  required FakeReelPlayers players,
  Size size = const Size(1440, 900),
  int count = 2,
  bool photo = false,
  bool immersive = false,
  double textScale = 1,
  ThemeData? theme,
  TextDirection textDirection = TextDirection.ltr,
  ReelService? service,
  FollowService? followService,
  void Function(dynamic reel)? onOpenAuthor,
  Future<void> Function()? onCreate,
  ReelAudioPlaybackFactory? audioPlaybackFactory,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          body: ReelsFeedScreen(
            key: ValueKey<Object>(<Object>[size, count, photo, immersive]),
            embedded: true,
            immersive: immersive,
            service: service ?? reelStageService(count: count, photo: photo),
            followService: followService,
            onOpenAuthor: onOpenAuthor,
            onCreate: onCreate,
            audioPlaybackFactory:
                audioPlaybackFactory ?? FakeReelAudioPlayback.new,
            videoPlaybackFactory: (uri, reel) => players.of(reel.id),
            videoBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}
