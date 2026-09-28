import 'dart:async';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/image_sanitizer.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';

/// Where one reserved object is written. Production writes to Firebase
/// Storage with the reservation's exact custom metadata (storage.rules
/// admits exactly one create per live reservation); tests inject a fake.
///
/// [onProgress] reports 0..1 when the transport can tell.
typedef PageMediaUploader =
    Future<void> Function(
      PageMediaSlot slot,
      PageMediaPayload payload, {
      required void Function(double fraction) onProgress,
    });

/// The bytes of one upload: a sanitised photo or a finished recording.
@immutable
sealed class PageMediaPayload {
  const PageMediaPayload();

  String get contentType;
  int get size;
}

final class PagePhotoPayload extends PageMediaPayload {
  const PagePhotoPayload(this.jpeg);

  final SanitizedJpeg jpeg;

  @override
  String get contentType => 'image/jpeg';

  @override
  int get size => jpeg.bytes.length;
}

final class PageVoicePayload extends PageMediaPayload {
  const PageVoicePayload(this.audio);

  final RecordedAudio audio;

  @override
  String get contentType => 'audio/mp4';

  @override
  int get size => audio.byteLength;
}

/// Firebase Storage, bounded like the Voice Moment upload (60 s, then the
/// task is cancelled and the same reservation can be retried).
Future<void> firebasePageMediaUploader(
  PageMediaSlot slot,
  PageMediaPayload payload, {
  required void Function(double fraction) onProgress,
}) async {
  final reference = FirebaseStorage.instance.ref(slot.storagePath);
  final metadata = SettableMetadata(
    contentType: payload.contentType,
    customMetadata: slot.metadata,
  );
  switch (payload) {
    case PagePhotoPayload(:final jpeg):
      final task = reference.putData(jpeg.bytes, metadata);
      final progress = task.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes;
        if (total > 0) onProgress(snapshot.bytesTransferred / total);
      }, onError: (Object _) {});
      try {
        await awaitVoiceMomentUpload(task);
      } finally {
        await progress.cancel();
      }
    case PageVoicePayload(:final audio):
      await audio.uploadTo(reference, metadata);
  }
  onProgress(1);
}

/// One item's upload state in the composer's publishing view (R3).
enum PageUploadState { waiting, uploading, done, failed }

/// Runs sanitise → reserve → upload → publish for one composer (spec
/// premium-pages §4.5, `PageMediaService`), and keeps what a retry needs:
///
/// * the reserve `requestId`, so a retry replays the same live reservation
///   (the server reuses the `postId` and media ids for it);
/// * which objects already reached Storage (a reservation admits one
///   create, so an uploaded object is never written twice);
/// * the publish `requestId`, so a retried publish replays the ledger.
///
/// A photo removed after the reservation is simply left out of `mediaIds`
/// (the server accepts any subset of the lease). Adding media after a
/// reservation exists is not possible: the owner has one open upload at a
/// time, so the composer locks the set while [hasReservation].
class PagePostPublisher extends ChangeNotifier {
  PagePostPublisher({PagesService? service, PageMediaUploader? uploader})
    : _service = service ?? PagesService.instance,
      _uploader = uploader ?? firebasePageMediaUploader;

  final PagesService _service;
  final PageMediaUploader _uploader;

  String? _reserveRequestId;
  String? _publishRequestId;
  PageMediaReservation? _reservation;
  List<Object> _reservedKeys = const <Object>[];
  final Set<String> _uploaded = <String>{};
  List<PageUploadState> _states = const <PageUploadState>[];
  List<double> _progress = const <double>[];
  bool _disposed = false;

  /// True while a reservation this composer made is still in use: the media
  /// set is locked until the post is published or the composer closes.
  bool get hasReservation => _reservation != null;

  /// True after a publish whose outcome is unknown (offline, a timeout, an
  /// unmapped answer): the server may already have the post. Its request id
  /// is kept, so the retry must send the SAME input to be answered
  /// idempotently; the composer locks the text and the comments switch
  /// until then. A refusal the server did answer clears it.
  bool get publishUnresolved => _publishRequestId != null;

  /// Keeps the request id only when the outcome is unknown.
  void _settle(PagesException error) {
    final unresolved =
        error.failure == PagesFailure.network ||
        error.failure == PagesFailure.unknown;
    if (!unresolved) _publishRequestId = null;
    _notify();
  }

  List<PageUploadState> get states => _states;
  List<double> get progress => _progress;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// A text post: the server allocates the id (§2.4).
  Future<PagePostView> publishText({
    required String text,
    required bool commentsEnabled,
  }) async {
    _publishRequestId ??= _service.newRequestId();
    final PagePostView post;
    try {
      post = await _service.publishPost(
        requestId: _publishRequestId!,
        kind: PagePostKind.text,
        text: text,
        commentsEnabled: commentsEnabled,
      );
    } on PagesException catch (error) {
      _settle(error);
      rethrow;
    }
    _publishRequestId = null;
    _notify();
    return post;
  }

  /// A photo post. [keys] identify the photos across retries (the
  /// composer's draft ids), in display order.
  Future<PagePostView> publishPhotos({
    required List<Object> keys,
    required List<SanitizedJpeg> photos,
    required String text,
    required bool commentsEnabled,
  }) {
    assert(keys.length == photos.length);
    return _publishMedia(
      kind: PagePostKind.photo,
      keys: keys,
      payloads: [for (final photo in photos) PagePhotoPayload(photo)],
      items: [
        for (final photo in photos)
          PageMediaReserveItem.photo(
            size: photo.bytes.length,
            width: photo.width,
            height: photo.height,
          ),
      ],
      text: text,
      commentsEnabled: commentsEnabled,
    );
  }

  /// A voice post: one clip, its declared length clamped to 1-60 s (D8).
  Future<PagePostView> publishVoice({
    required Object key,
    required RecordedAudio audio,
    required int durationMs,
    required String text,
    required bool commentsEnabled,
  }) => _publishMedia(
    kind: PagePostKind.voice,
    keys: [key],
    payloads: [PageVoicePayload(audio)],
    items: [
      PageMediaReserveItem.voice(
        size: audio.byteLength,
        durationMs: durationMs.clamp(1000, 60000),
      ),
    ],
    text: text,
    commentsEnabled: commentsEnabled,
  );

  Future<PagePostView> _publishMedia({
    required PagePostKind kind,
    required List<Object> keys,
    required List<PageMediaPayload> payloads,
    required List<PageMediaReserveItem> items,
    required String text,
    required bool commentsEnabled,
  }) async {
    var reservation = _reservation;
    if (reservation == null) {
      _reserveRequestId ??= _service.newRequestId();
      try {
        reservation = await _service.reserveMedia(
          requestId: _reserveRequestId!,
          kind: kind,
          items: items,
        );
      } on PagesException catch (error) {
        if (error.failure == PagesFailure.uploadExpired) _resetReservation();
        rethrow;
      }
      _reservation = reservation;
      _reservedKeys = List.unmodifiable(keys);
      _uploaded.clear();
      _publishRequestId = null;
    }
    // The composer may have dropped items since the reservation: upload and
    // publish only the ones still present, in their current order.
    final slots = <PageMediaSlot>[];
    final kept = <PageMediaPayload>[];
    for (var i = 0; i < keys.length; i++) {
      final index = _reservedKeys.indexOf(keys[i]);
      if (index < 0 || index >= reservation.slots.length) {
        throw const PagesException(PagesFailure.invalidInput, 'media set');
      }
      slots.add(reservation.slots[index]);
      kept.add(payloads[i]);
    }
    _states = [
      for (final slot in slots)
        _uploaded.contains(slot.mediaId)
            ? PageUploadState.done
            : PageUploadState.waiting,
    ];
    _progress = [
      for (final slot in slots) _uploaded.contains(slot.mediaId) ? 1.0 : 0.0,
    ];
    _notify();

    Object? firstError;
    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      if (_uploaded.contains(slot.mediaId)) continue;
      _setState(i, PageUploadState.uploading);
      try {
        await _uploader(
          slot,
          kept[i],
          onProgress: (fraction) => _setProgress(i, fraction),
        );
        _uploaded.add(slot.mediaId);
        _setProgress(i, 1);
        _setState(i, PageUploadState.done);
      } catch (error) {
        _setState(i, PageUploadState.failed);
        firstError ??= error;
      }
    }
    if (firstError != null) {
      throw PageUploadException(
        failedIndexes: [
          for (var i = 0; i < _states.length; i++)
            if (_states[i] == PageUploadState.failed) i,
        ],
      );
    }

    _publishRequestId ??= _service.newRequestId();
    try {
      final post = await _service.publishPost(
        requestId: _publishRequestId!,
        postId: reservation.postId,
        kind: kind,
        text: text,
        mediaIds: [for (final slot in slots) slot.mediaId],
        commentsEnabled: commentsEnabled,
      );
      _resetReservation();
      return post;
    } on PagesException catch (error) {
      if (error.failure == PagesFailure.uploadExpired) {
        _resetReservation();
      } else {
        _settle(error);
      }
      rethrow;
    }
  }

  void _resetReservation() {
    _reservation = null;
    _reserveRequestId = null;
    _publishRequestId = null;
    _reservedKeys = const <Object>[];
    _uploaded.clear();
    _notify();
  }

  void _setState(int index, PageUploadState state) {
    if (index >= _states.length) return;
    _states = List.of(_states)..[index] = state;
    _notify();
  }

  void _setProgress(int index, double fraction) {
    if (index >= _progress.length) return;
    _progress = List.of(_progress)..[index] = fraction.clamp(0.0, 1.0);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// One or more objects did not reach Storage; the reservation stays, so
/// "Ponów" uploads only the failed ones.
class PageUploadException implements Exception {
  const PageUploadException({required this.failedIndexes});

  final List<int> failedIndexes;

  @override
  String toString() => 'PageUploadException($failedIndexes)';
}
