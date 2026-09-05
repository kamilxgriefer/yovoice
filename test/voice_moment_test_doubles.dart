// Shared test doubles for the Voice Moment recording seam.
//
// Not a test file (no `_test.dart` suffix), so `flutter test` imports it
// without trying to run it.
import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:record/record.dart' show Amplitude, AudioEncoder, RecordConfig;

import 'package:yovoice/features/moments/data/models/moment_availability.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';

const fakeVoiceMomentReportReceipt =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<Object?, Object?> _fakeMomentProjection(VoiceMoment moment) =>
    <Object?, Object?>{
      'schemaVersion': 2,
      'momentId': moment.id,
      'authorId': moment.authorId,
      'authorName': moment.authorName,
      'authorPhotoUrl': null,
      'caption': moment.caption,
      'durationSeconds': moment.durationSeconds,
      'likeCount': moment.likeCount,
      'commentCount': moment.commentCount,
      'callerLiked': moment.callerLiked,
      'createdAtMillis': moment.createdAt!.millisecondsSinceEpoch,
      'publishedAtMillis': moment.createdAt!.millisecondsSinceEpoch,
      'expiresAtMillis': moment.expiresAt?.millisecondsSinceEpoch,
      'reportReceipt': fakeVoiceMomentReportReceipt,
    };

/// Strict-shape test transport for Build 20 Voice Moment views.
///
/// It deliberately lives outside production code: widget tests can seed fake
/// Firestore as their server fixture without reintroducing a client Firestore
/// fallback into [VoiceMomentReadService].
VoiceMomentViewInvoker fakeVoiceMomentViewInvoker({
  required FakeFirebaseFirestore firestore,
  String viewerUid = 'me',
}) => (request) async {
  final momentId = request['momentId'] as String;
  final momentSnapshot = await firestore
      .collection('voiceMoments')
      .doc(momentId)
      .get();
  if (!momentSnapshot.exists) {
    throw FirebaseFunctionsException(
      code: 'permission-denied',
      message: 'This Voice Moment is unavailable.',
    );
  }
  late final VoiceMoment moment;
  try {
    moment = VoiceMoment.fromFirestore(momentSnapshot);
  } on Object {
    throw FirebaseFunctionsException(
      code: 'permission-denied',
      message: 'This Voice Moment is unavailable.',
    );
  }
  if (!moment.isCanonicalPublished || moment.createdAt == null) {
    throw FirebaseFunctionsException(
      code: 'permission-denied',
      message: 'This Voice Moment is unavailable.',
    );
  }

  final commentLimit = request['commentLimit'] as int? ?? 7;
  final rawCursor = request['commentCursor'] as String?;
  final offset = rawCursor == null
      ? 0
      : int.tryParse(rawCursor.replaceFirst('test_comment_', '')) ?? 0;
  final commentSnapshot = await momentSnapshot.reference
      .collection('comments')
      .orderBy('createdAt')
      .get();
  final commentDocs = commentSnapshot.docs
      .skip(offset)
      .take(commentLimit)
      .toList(growable: false);
  final comments = <Map<Object?, Object?>>[
    for (final document in commentDocs)
      <Object?, Object?>{
        'schemaVersion': 2,
        'commentId': document.id,
        'type': document.data()['type'] as String? ?? 'text',
        'authorId': document.data()['authorId'] as String? ?? viewerUid,
        'authorName':
            document.data()['authorName'] as String? ?? 'YO Voice viewer',
        'authorPhotoUrl': null,
        'text': document.data()['text'] as String? ?? '',
        'durationSeconds': document.data()['durationSeconds'] as int?,
        'createdAtMillis':
            (document.data()['createdAt'] as Timestamp).millisecondsSinceEpoch,
        'reportReceipt': fakeVoiceMomentReportReceipt,
      },
  ];

  final reactionLimit = request['reactionLimit'] as int? ?? 3;
  final likes = await momentSnapshot.reference
      .collection('likes')
      .orderBy('createdAt', descending: true)
      .limit(reactionLimit)
      .get();
  final reactions = <Map<Object?, Object?>>[];
  for (final like in likes.docs) {
    final profile = await firestore
        .collection('publicProfiles')
        .doc(like.id)
        .get();
    reactions.add(<Object?, Object?>{
      'userId': like.id,
      'displayName': profile.data()?['displayName'] as String? ?? like.id,
      'photoUrl': null,
    });
  }
  final callerLike = await momentSnapshot.reference
      .collection('likes')
      .doc(viewerUid)
      .get();
  final projected = moment.copyWith(callerLiked: callerLike.exists);
  final nextOffset = offset + commentDocs.length;
  final truncated = nextOffset < commentSnapshot.docs.length;
  return <Object?, Object?>{
    'schemaVersion': 2,
    'moment': _fakeMomentProjection(projected),
    'comments': comments,
    'commentsTruncated': truncated,
    'nextCommentCursor': truncated ? 'test_comment_$nextOffset' : null,
    'topReactions': reactions,
  };
};

/// Strict-shape feed transport for fake-Firestore widget tests.
VoiceMomentFeedInvoker fakeVoiceMomentFeedInvoker({
  required FakeFirebaseFirestore firestore,
}) => (request) async {
  final snapshot = await firestore.collection('voiceMoments').get();
  final moments = <VoiceMoment>[];
  for (final document in snapshot.docs) {
    try {
      final moment = VoiceMoment.fromFirestore(document);
      if (moment.isCanonicalPublished &&
          moment.createdAt != null &&
          moment.hasMediaReference) {
        moments.add(moment);
      }
    } on Object {
      // Mirrors the callable's fail-closed projection boundary.
    }
  }
  if (request['sortMode'] == 'popular') {
    moments.sort((a, b) => b.likeCount.compareTo(a.likeCount));
  } else {
    moments.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
  }
  final rawCursor = request['cursor'] as String?;
  final offset = rawCursor == null
      ? 0
      : int.tryParse(rawCursor.replaceFirst('test_feed_', '')) ?? 0;
  final limit = request['limit'] as int;
  final page = moments.skip(offset).take(limit).toList(growable: false);
  final nextOffset = offset + page.length;
  final hasMore = nextOffset < moments.length;
  return <Object?, Object?>{
    'schemaVersion': 2,
    'moments': page.map(_fakeMomentProjection).toList(growable: false),
    'scannedCount': page.length,
    'hasMore': hasMore,
    'nextCursor': hasMore ? 'test_feed_$nextOffset' : null,
  };
};

/// Valid short-lived private-media grant used by playback widget tests.
///
/// Canonical Moment fixtures deliberately carry no bearer `audioUrl`; this
/// seam mirrors the callable response that production resolves per viewer.
MomentMediaAccessInvoker fakeMomentMediaAccessInvoker({
  List<Map<String, Object?>>? requests,
}) => (request) async {
  requests?.add(Map<String, Object?>.from(request));
  return <Object?, Object?>{
    'schemaVersion': 1,
    'url':
        'https://storage.googleapis.com/yovoice-test/'
        '${request['momentId']}.m4a?X-Goog-Signature=test',
    'expiresAtMillis': DateTime.now()
        .add(const Duration(minutes: 1))
        .millisecondsSinceEpoch,
    'mediaGeneration': '1001',
    'mediaContentType': 'audio/mp4',
    'mediaSize': 4096,
  };
};

/// A finished recording that records what it was asked to upload.
class FakeRecordedAudio extends RecordedAudio {
  FakeRecordedAudio({
    this.contentType = kVoiceMomentContentType,
    this.byteLength = 4096,
    this.lifecycle,
  });

  @override
  final String contentType;

  @override
  final int byteLength;

  final List<String>? lifecycle;

  int uploadCalls = 0;
  String? uploadedPath;
  SettableMetadata? uploadedMetadata;
  bool discarded = false;

  @override
  Source get playbackSource =>
      BytesSource(Uint8List(byteLength), mimeType: contentType);

  @override
  Future<String> uploadTo(
    Reference reference,
    SettableMetadata metadata,
  ) async {
    uploadCalls++;
    uploadedPath = reference.fullPath;
    uploadedMetadata = metadata;
    // Stand in for the platform upload against the real Reference, so the
    // service's follow-up calls (download URL, cleanup) behave as they do
    // in production rather than against a hole in the double.
    await reference.putData(Uint8List(byteLength), metadata);
    return '1700000000000001';
  }

  @override
  Future<void> discard() async {
    discarded = true;
    lifecycle?.add('audio.discard');
  }
}

/// Deterministic local preview player with no platform channel.
class FakePreviewAudioPlayer implements AudioPlayer {
  FakePreviewAudioPlayer({
    this.duration = const Duration(seconds: 5),
    this.lifecycle,
  });

  final Duration duration;
  final List<String>? lifecycle;
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durations =
      StreamController<Duration>.broadcast();
  final StreamController<void> _completions =
      StreamController<void>.broadcast();

  int playCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int seekCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  Source? lastSource;
  Duration? lastStartPosition;
  Duration? lastSeekPosition;
  Object? playError;

  @override
  Stream<PlayerState> get onPlayerStateChanged => _states.stream;

  @override
  Stream<Duration> get onPositionChanged => _positions.stream;

  @override
  Stream<Duration> get onDurationChanged => _durations.stream;

  @override
  Stream<void> get onPlayerComplete => _completions.stream;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    if (playError != null) throw playError!;
    playCalls++;
    lastSource = source;
    lastStartPosition = position;
    _durations.add(duration);
    _states.add(PlayerState.playing);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _states.add(PlayerState.paused);
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    _states.add(PlayerState.playing);
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    lastSeekPosition = position;
    _positions.add(position);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    lifecycle?.add('player.stop');
    if (!_states.isClosed) _states.add(PlayerState.stopped);
  }

  void emitPosition(Duration position) => _positions.add(position);

  void complete() {
    _positions.add(duration);
    _completions.add(null);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    lifecycle?.add('player.dispose');
    unawaited(
      Future.wait([
        _states.close(),
        _positions.close(),
        _durations.close(),
        _completions.close(),
      ]),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for `package:record`'s `AudioRecorder`.
class FakeRecorderBackend implements VoiceRecorderBackend {
  bool encoderSupported = true;
  bool permission = true;
  Object? startError;
  Object? stopError;
  String? stopResult = 'handle';

  int permissionCalls = 0;
  int startCalls = 0;
  int cancelCalls = 0;
  int disposeCalls = 0;
  RecordConfig? startedConfig;

  final StreamController<Amplitude> amplitudes =
      StreamController<Amplitude>.broadcast();

  @override
  Future<bool> hasPermission() async {
    permissionCalls++;
    return permission;
  }

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async =>
      encoderSupported;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    startCalls++;
    startedConfig = config;
    if (startError != null) throw startError!;
  }

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) => amplitudes.stream;

  @override
  Future<String?> stop() async {
    if (stopError != null) throw stopError!;
    return stopResult;
  }

  @override
  Future<void> cancel() async => cancelCalls++;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await amplitudes.close();
  }
}

/// A stopwatch the test drives directly.
///
/// `flutter_test`'s fake clock advances timers but not `Stopwatch`, which
/// reads real elapsed time, so recording length has to be injected for the
/// reviewing and publishing states to be reachable deterministically.
class FakeStopwatch implements Stopwatch {
  Duration value = Duration.zero;
  bool _running = false;

  @override
  Duration get elapsed => value;

  @override
  bool get isRunning => _running;

  @override
  void start() => _running = true;

  @override
  void stop() => _running = false;

  @override
  void reset() => value = Duration.zero;

  @override
  int get frequency => 1000000;

  @override
  int get elapsedTicks => value.inMicroseconds;

  @override
  int get elapsedMicroseconds => value.inMicroseconds;

  @override
  int get elapsedMilliseconds => value.inMilliseconds;
}

/// Stands in for the platform byte-acquisition half.
class FakeAudioCapture implements AudioCapture {
  CaptureSupport support = const CaptureSupport.supported();
  Object? probeError;
  Object? targetError;
  Object? materializeError;
  Object? microphoneError;
  RecordedAudio? result;
  int probeCalls = 0;
  int microphoneCalls = 0;

  /// Defaults to granted; set an outcome to exercise a specific refusal.
  MicrophoneAccess microphone = const MicrophoneAccess.granted();

  /// When set, the request hangs on it — a browser that never answers the
  /// permission prompt.
  Completer<MicrophoneAccess>? microphoneGate;

  @override
  Future<MicrophoneAccess> requestMicrophone(
    VoiceRecorderBackend backend,
  ) async {
    microphoneCalls++;
    if (microphoneError != null) throw microphoneError!;
    if (microphoneGate != null) return microphoneGate!.future;
    // Mirrors the real implementations, which all consult the backend's
    // permission state before deciding.
    if (microphone.isGranted && !await backend.hasPermission()) {
      return const MicrophoneAccess.denied(
        outcome: MicrophoneOutcome.blocked,
        message: 'Microphone access for YO Voice is blocked in this browser.',
        action:
            "Allow the microphone in your browser's site settings for "
            'YO Voice, then reload this page.',
      );
    }
    return microphone;
  }

  @override
  Future<CaptureSupport> probeSupport(VoiceRecorderBackend backend) async {
    probeCalls++;
    if (probeError != null) throw probeError!;
    return support;
  }

  @override
  Future<String> newRecordingTarget() async {
    if (targetError != null) throw targetError!;
    return 'target.m4a';
  }

  @override
  Future<RecordedAudio> materialize(String? stopResult) async {
    if (materializeError != null) throw materializeError!;
    return result ?? FakeRecordedAudio();
  }
}

/// A `MomentService` whose publish call can be held open or failed on
/// demand, so the uploading and failed states are reachable in a widget
/// test without a Firebase project.
class StubMomentService extends MomentService {
  StubMomentService()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'stub-uid'),
        ),
        storage: MockFirebaseStorage(),
        mediaAccessInvoker: fakeMomentMediaAccessInvoker(),
      );

  /// When set, `publishRecordedMoment` waits on it — the uploading state.
  Completer<void>? gate;

  /// When set, `publishRecordedMoment` throws it.
  Object? failure;
  List<String>? lifecycle;

  int publishCalls = 0;
  int abandonCalls = 0;
  RecordedAudio? publishedAudio;
  RecordedAudio? abandonedAudio;
  int? publishedDuration;
  String? publishedCaption;
  MomentAvailability? publishedAvailability;
  final List<String> publishedCaptions = [];
  final List<MomentAvailability> publishedAvailabilities = [];

  @override
  void abandonPendingPublish(RecordedAudio audio) {
    abandonCalls++;
    abandonedAudio = audio;
    lifecycle?.add('service.abandon');
    super.abandonPendingPublish(audio);
  }

  @override
  Future<String> publishRecordedMoment({
    required RecordedAudio audio,
    required int durationSeconds,
    required String caption,
    String? replyToMomentId,
    MomentAvailability availability = MomentAvailability.fallback,
  }) async {
    publishCalls++;
    lifecycle?.add('service.publish');
    publishedAudio = audio;
    publishedDuration = durationSeconds;
    publishedCaption = caption;
    publishedAvailability = availability;
    publishedCaptions.add(caption);
    publishedAvailabilities.add(availability);
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return 'published-moment-id';
  }
}
