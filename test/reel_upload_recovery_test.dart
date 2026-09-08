// Lost-acknowledgement recovery for a Reel asset upload.
//
// `ReelService._upload` has exactly one call site for `_recoverUpload`, and it
// is reached from the guarded region around the Storage task. When the upload
// switched to a streamed transport, the transport gained the ability to throw
// BEFORE it hands back a task — the picker's temporary file evicted, moved or
// resized between selection and upload — and that class of failure used to
// escape the guarded region entirely. A retry could then never reconcile an
// object Storage may already hold at the deterministic path.
//
// These tests drive the real `_upload` (no `uploadInvoker` override) through an
// injected Storage fake, so both the pre-task and the task failure paths are
// exercised as production runs them.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// XFile through image_picker, the package that actually produces it here.
import 'package:image_picker/image_picker.dart' show XFile;

import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _mediaPath = 'reels/creator-1/reel_1/media.mp4';
const String _photoPath = 'reels/creator-1/reel_1/media.jpg';

/// A minimal but real MP4: `ftyp` at offset 4 is what the client sniffer keys
/// on, and it is what makes [ReelUploadPayload.fromXFile] produce a *streamed*
/// payload — the only kind the io transport can fail on before uploading.
Uint8List _videoBytes(int length) {
  final bytes = Uint8List(length);
  bytes.setAll(0, const <int>[
    0, 0, 0, 24, // box size
    0x66, 0x74, 0x79, 0x70, // 'ftyp'
    0x69, 0x73, 0x6f, 0x6d, // 'isom'
  ]);
  return bytes;
}

Uint8List _jpegBytes(int length) {
  final bytes = Uint8List(length);
  bytes.setAll(0, const <int>[0xff, 0xd8, 0xff]);
  return bytes;
}

Future<XFile> _tempFile(String name, Uint8List bytes) async {
  final directory = await Directory.systemTemp.createTemp('yo_reel_recovery');
  addTearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes, flush: true);
  return XFile(file.path);
}

Map<Object?, Object?> _reservation(String mediaStoragePath) =>
    <Object?, Object?>{
      'schemaVersion': 2,
      'reelId': 'reel_1',
      'mediaStoragePath': mediaStoragePath,
      'backingAudioStoragePath': null,
      'expiresAtMillis': 1900000900000,
      'availabilityHours': 24,
      'contentExpiresAtMillis': 2000000000000,
    };

Map<Object?, Object?> _finalized() => <Object?, Object?>{
  'schemaVersion': 2,
  'reelId': 'reel_1',
  'published': true,
  'availabilityHours': 24,
  'expiresAtMillis': 2000000000000,
};

/// The Storage metadata a previous, acknowledged-but-lost attempt would have
/// left at the deterministic path for this exact upload.
_FakeFullMetadata _committed({
  required int size,
  required String contentType,
  String generation = '4242',
  String ownerId = 'creator-1',
  String reelId = 'reel_1',
  String assetKind = 'media',
}) => _FakeFullMetadata(<String, dynamic>{
  'size': size,
  'contentType': contentType,
  'generation': generation,
  'customMetadata': <String, String>{
    'ownerId': ownerId,
    'reelId': reelId,
    'assetKind': assetKind,
  },
});

ReelService _service(
  _FakeStorage storage,
  Map<String, Map<String, Object?>> calls, {
  String mediaStoragePath = _mediaPath,
}) => ReelService(
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'creator-1', isEmailVerified: true),
  ),
  storage: storage,
  callableInvoker: (name, payload) async {
    calls[name] = Map<String, Object?>.of(payload);
    return name == 'reserveReelDraftV2'
        ? _reservation(mediaStoragePath)
        : _finalized();
  },
);

ReelPublishSession _session(
  ReelUploadPayload media,
  ReelComposition composition,
) => ReelPublishSession(
  plan: ReelDraftPlan(media: media, composition: composition),
  requestId: 'request-00000001',
);

/// A streamed (video) payload whose picker file is then evicted, reproducing
/// the transport failure that happens before any task exists.
Future<ReelUploadPayload> _evictedVideoPayload() async {
  final file = await _tempFile('clip.mp4', _videoBytes(4096));
  final payload = await ReelUploadPayload.fromXFile(file, durationMs: 5000);
  await File(file.path).delete();
  return payload;
}

// ---------------------------------------------------------------------------
// Storage fakes
//
// `MockFirebaseStorage` cannot express either half of what is under test: its
// task never fails, and its `getMetadata` never carries a `generation`, so
// recovery could neither succeed nor be observed. These fakes control both.
// ---------------------------------------------------------------------------

class _FakeFullMetadata extends FullMetadata {
  _FakeFullMetadata(Map<String, dynamic> metadata) : super(metadata);
}

class _FakeTaskSnapshot implements TaskSnapshot {
  _FakeTaskSnapshot({
    this.metadata,
    this.bytesTransferred = 0,
    this.totalBytes = 0,
  });

  @override
  final FullMetadata? metadata;
  @override
  final int bytesTransferred;
  @override
  final int totalBytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An upload task whose completion is produced lazily, so an error result is
/// never an unhandled future before `_upload` awaits it.
class _FakeUploadTask implements UploadTask {
  _FakeUploadTask({required this.events, required this.result});

  final Stream<TaskSnapshot> events;
  final Future<TaskSnapshot> Function() result;
  Future<TaskSnapshot>? _pending;

  Future<TaskSnapshot> get _future => _pending ??= result();

  @override
  Stream<TaskSnapshot> get snapshotEvents => events;

  @override
  Future<S> then<S>(
    FutureOr<S> Function(TaskSnapshot) onValue, {
    Function? onError,
  }) => _future.then(onValue, onError: onError);

  @override
  Future<TaskSnapshot> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) => _future.catchError(onError, test: test);

  @override
  Future<TaskSnapshot> whenComplete(FutureOr<void> Function() action) =>
      _future.whenComplete(action);

  @override
  Stream<TaskSnapshot> asStream() => _future.asStream();

  @override
  Future<TaskSnapshot> timeout(
    Duration timeLimit, {
    FutureOr<TaskSnapshot> Function()? onTimeout,
  }) => _future.timeout(timeLimit, onTimeout: onTimeout);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeReference implements Reference {
  _FakeReference({this.onUpload, this.onGetMetadata});

  /// Produces the task for `putFile`/`putData`. Absent means "this test
  /// expects the transport never to reach Storage".
  final UploadTask Function()? onUpload;

  /// What the deterministic path answers when recovery inspects it.
  final Future<FullMetadata> Function()? onGetMetadata;

  int uploadStarts = 0;
  int getMetadataCalls = 0;
  SettableMetadata? declaredMetadata;

  UploadTask _start(SettableMetadata? metadata) {
    uploadStarts += 1;
    declaredMetadata = metadata;
    final factory = onUpload;
    if (factory == null) {
      fail('The transport reached Storage when the test expected it not to.');
    }
    return factory();
  }

  @override
  UploadTask putFile(File file, [SettableMetadata? metadata]) =>
      _start(metadata);

  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) =>
      _start(metadata);

  @override
  Future<FullMetadata> getMetadata() {
    getMetadataCalls += 1;
    final answer = onGetMetadata;
    if (answer == null) {
      // Nothing at the path: exactly what real Storage reports.
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'object-not-found',
        message: 'No object exists at the desired reference.',
      );
    }
    return answer();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStorage implements FirebaseStorage {
  _FakeStorage(this.reference);

  final _FakeReference reference;
  final List<String> requestedPaths = <String>[];

  @override
  Reference ref([String? path]) {
    requestedPaths.add(path ?? '/');
    return reference;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A task that reports one progress event and then fails, standing in for a
/// Storage upload that committed its object and lost only the response.
_FakeUploadTask _failingTask(
  StreamController<TaskSnapshot> events,
  Object error,
) {
  events.add(_FakeTaskSnapshot(bytesTransferred: 512, totalBytes: 1024));
  return _FakeUploadTask(
    events: events.stream,
    result: () async {
      await Future<void>.delayed(Duration.zero);
      throw error;
    },
  );
}

void main() {
  group('a transport that throws before it returns a task', () {
    test('still reaches lost-acknowledgement recovery', () async {
      final payload = await _evictedVideoPayload();
      final reference = _FakeReference(
        onGetMetadata: () async =>
            _committed(size: payload.size, contentType: payload.contentType),
      );
      final storage = _FakeStorage(reference);
      final calls = <String, Map<String, Object?>>{};

      final reelId = await _service(
        storage,
        calls,
      ).publish(_session(payload, const ReelComposition(trimEndMs: 5000)));

      expect(reelId, 'reel_1');
      expect(
        reference.uploadStarts,
        0,
        reason:
            'The io transport refuses an evicted picker file before it ever '
            'hands back a task; that is the failure that used to escape.',
      );
      expect(
        reference.getMetadataCalls,
        1,
        reason: 'Recovery must be attempted, not skipped.',
      );
      expect(
        calls['finalizeReelDraftV2']!['mediaGeneration'],
        '4242',
        reason:
            'The retry reconciles the object Storage already holds instead of '
            'stalling behind an upload it cannot repeat.',
      );
      expect(storage.requestedPaths, <String>[_mediaPath]);
    });

    test(
      'surfaces its own refusal when nothing is committed at the path',
      () async {
        final payload = await _evictedVideoPayload();
        // No `onGetMetadata`: the path is empty, as on a genuine first attempt.
        final reference = _FakeReference();
        final storage = _FakeStorage(reference);

        await expectLater(
          _service(
            storage,
            <String, Map<String, Object?>>{},
          ).publish(_session(payload, const ReelComposition(trimEndMs: 5000))),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Choose it again'),
            ),
          ),
          reason:
              'Recovery that finds nothing must re-throw the transport\'s own '
              'honest explanation, not invent a different one.',
        );
        expect(reference.getMetadataCalls, 1);
        expect(reference.uploadStarts, 0);
      },
    );

    test('never accepts an object belonging to another Reel', () async {
      final payload = await _evictedVideoPayload();
      final reference = _FakeReference(
        onGetMetadata: () async => _committed(
          size: payload.size,
          contentType: payload.contentType,
          reelId: 'reel_someone_else',
        ),
      );

      await expectLater(
        _service(
          _FakeStorage(reference),
          <String, Map<String, Object?>>{},
        ).publish(_session(payload, const ReelComposition(trimEndMs: 5000))),
        throwsA(isA<FormatException>()),
      );
      expect(reference.getMetadataCalls, 1);
    });

    test(
      'never accepts an object whose size is not the declared one',
      () async {
        final payload = await _evictedVideoPayload();
        final reference = _FakeReference(
          onGetMetadata: () async => _committed(
            size: payload.size + 1,
            contentType: payload.contentType,
          ),
        );

        await expectLater(
          _service(
            _FakeStorage(reference),
            <String, Map<String, Object?>>{},
          ).publish(_session(payload, const ReelComposition(trimEndMs: 5000))),
          throwsA(isA<FormatException>()),
        );
        expect(reference.getMetadataCalls, 1);
      },
    );

    test('opens no progress subscription there is nothing to cancel', () async {
      final payload = await _evictedVideoPayload();
      final progress = <double>[];
      final reference = _FakeReference(
        onGetMetadata: () async =>
            _committed(size: payload.size, contentType: payload.contentType),
      );

      await _service(
        _FakeStorage(reference),
        <String, Map<String, Object?>>{},
      ).publish(
        _session(payload, const ReelComposition(trimEndMs: 5000)),
        onProgress: progress.add,
      );

      expect(
        reference.uploadStarts,
        0,
        reason: 'No task means no snapshot stream and nothing left listening.',
      );
      expect(
        progress,
        <double>[1],
        reason:
            'Only the completed publish moves the bar; a recovered asset '
            'reports no byte progress of its own.',
      );
    });
  });

  group('a task that throws after it has started', () {
    test('recovers exactly as before and cancels its subscription', () async {
      final events = StreamController<TaskSnapshot>();
      addTearDown(events.close);
      final progress = <double>[];
      final photo = ReelUploadPayload(
        bytes: _jpegBytes(4096),
        contentType: 'image/jpeg',
        durationMs: 0,
      );
      final reference = _FakeReference(
        onUpload: () => _failingTask(events, StateError('lost response')),
        onGetMetadata: () async => _committed(
          size: photo.size,
          contentType: photo.contentType,
          generation: '7',
        ),
      );
      final calls = <String, Map<String, Object?>>{};

      final reelId =
          await _service(
            _FakeStorage(reference),
            calls,
            mediaStoragePath: _photoPath,
          ).publish(
            _session(photo, const ReelComposition(originalAudioVolume: 0)),
            onProgress: progress.add,
          );

      expect(reelId, 'reel_1');
      expect(reference.uploadStarts, 1);
      expect(calls['finalizeReelDraftV2']!['mediaGeneration'], '7');
      expect(
        progress.first,
        closeTo(.5 * .95, .0001),
        reason: 'The subscription was live and byte-weighted while it ran.',
      );
      expect(
        events.hasListener,
        isFalse,
        reason: 'The progress subscription is cancelled on the recovery exit.',
      );
      // The metadata contract is untouched by moving the start inside the try.
      expect(reference.declaredMetadata!.asMap()['contentType'], 'image/jpeg');
      expect(
        reference.declaredMetadata!.asMap()['customMetadata'],
        <String, String>{
          'ownerId': 'creator-1',
          'reelId': 'reel_1',
          'assetKind': 'media',
        },
      );
    });

    test(
      're-throws its own error and still cancels its subscription',
      () async {
        final events = StreamController<TaskSnapshot>();
        addTearDown(events.close);
        final progress = <double>[];
        final photo = ReelUploadPayload(
          bytes: _jpegBytes(4096),
          contentType: 'image/jpeg',
          durationMs: 0,
        );
        // Nothing at the path: recovery refuses, the original error surfaces.
        final reference = _FakeReference(
          onUpload: () => _failingTask(events, StateError('lost response')),
        );

        await expectLater(
          _service(
            _FakeStorage(reference),
            <String, Map<String, Object?>>{},
            mediaStoragePath: _photoPath,
          ).publish(
            _session(photo, const ReelComposition(originalAudioVolume: 0)),
            onProgress: progress.add,
          ),
          throwsStateError,
        );
        expect(reference.getMetadataCalls, 1);
        expect(
          events.hasListener,
          isFalse,
          reason: 'The failure exit cancels the progress subscription too.',
        );
      },
    );
  });

  test('the success path is unchanged', () async {
    final events = StreamController<TaskSnapshot>();
    addTearDown(events.close);
    final progress = <double>[];
    final photo = ReelUploadPayload(
      bytes: _jpegBytes(4096),
      contentType: 'image/jpeg',
      durationMs: 0,
    );
    final reference = _FakeReference(
      onUpload: () {
        events.add(_FakeTaskSnapshot(bytesTransferred: 2048, totalBytes: 4096));
        return _FakeUploadTask(
          events: events.stream,
          result: () async => _FakeTaskSnapshot(
            metadata: _FakeFullMetadata(<String, dynamic>{'generation': '99'}),
          ),
        );
      },
    );
    final calls = <String, Map<String, Object?>>{};

    final reelId =
        await _service(
          _FakeStorage(reference),
          calls,
          mediaStoragePath: _photoPath,
        ).publish(
          _session(photo, const ReelComposition(originalAudioVolume: 0)),
          onProgress: progress.add,
        );

    expect(reelId, 'reel_1');
    expect(calls['finalizeReelDraftV2']!['mediaGeneration'], '99');
    expect(
      reference.getMetadataCalls,
      0,
      reason: 'A successful upload must not pay for a recovery round trip.',
    );
    expect(progress.first, closeTo(.5 * .95, .0001));
    expect(progress.last, 1);
    expect(events.hasListener, isFalse);
  });
}
