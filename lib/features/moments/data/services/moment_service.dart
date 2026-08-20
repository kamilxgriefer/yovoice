import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';

class MomentService {
  MomentService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _functionsOverride = functions;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final FirebaseFunctions? _functionsOverride;

  /// One logical publish operation per recording. Keeping this state in the
  /// service makes the screen's "try publishing again" a real retry: the
  /// same server reservation and request id are reused instead of consuming a
  /// second quota slot and leaving another abandoned draft behind.
  final Map<RecordedAudio, _PendingMomentPublish> _pendingMomentPublishes =
      Map<RecordedAudio, _PendingMomentPublish>.identity();

  FirebaseFunctions? get _functions =>
      _functionsOverride ??
      (() {
        try {
          return FirebaseFunctions.instanceFor(region: 'europe-west1');
        } on FirebaseException catch (error) {
          if (error.code == 'no-app') {
            return null;
          }
          rethrow;
        }
      })();

  CollectionReference<Map<String, dynamic>> get _moments =>
      _firestore.collection('voiceMoments');

  String _newRequestId() {
    final random = Random.secure();
    final randomPart = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-$randomPart';
  }

  bool _isCallableUnavailable(Object error) {
    if (error is FirebaseException && error.code == 'no-app') {
      return true;
    }
    return error is FirebaseFunctionsException && error.code == 'unimplemented';
  }

  Stream<List<VoiceMoment>> watchPublishedMoments({int limit = 30}) {
    return _moments
        .where('isPublished', isEqualTo: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final moments = snapshot.docs
              .map(VoiceMoment.fromFirestore)
              .toList(growable: false);
          moments.sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
          return moments;
        });
  }

  /// ONE Moment, live.
  ///
  /// For a surface that was handed a Moment fetched some time ago and
  /// then lets you act on it — the player sheet, where you can like it
  /// and comment on it. Without this the sheet showed the counters as
  /// they were when the tile was tapped, so your own like did not appear
  /// until the surface was rebuilt from somewhere else.
  ///
  /// Emits nothing for a document that does not exist (or no longer
  /// does); the caller keeps what it already had rather than rendering an
  /// empty Moment.
  Stream<VoiceMoment> watchMoment(String momentId) {
    return _moments
        .doc(momentId)
        .snapshots()
        .where((document) => document.exists)
        .map(VoiceMoment.fromFirestore);
  }

  /// The signed-in user's own Voice Moments, published and unpublished
  /// (drafts still uploading or that failed to finish publishing).
  Stream<List<VoiceMoment>> watchMyMoments() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(const <VoiceMoment>[]);

    return _moments.where('authorId', isEqualTo: user.uid).snapshots().map((
      snapshot,
    ) {
      final moments = snapshot.docs
          .map(VoiceMoment.fromFirestore)
          .toList(growable: false);
      moments.sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      return moments;
    });
  }

  /// Publishes a finished recording.
  ///
  /// [audio] is the platform seam: native passes a temporary file, web
  /// passes the native Blob the browser produced. Everything below — the draft
  /// reservation, the object metadata the Storage rules check, the
  /// finalize call, and the legacy fallback — is identical either way.
  Future<String> publishRecordedMoment({
    required RecordedAudio audio,
    required int durationSeconds,
    required String caption,
    String? replyToMomentId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to publish a Voice Moment.');
    }

    // The Storage rules fail an upload that violates these bounds, and a
    // rejected upload leaves a draft that never finalizes. Refuse here,
    // where the reason can still be explained.
    final unusable = validateRecordedAudio(audio);
    if (unusable != null) throw unusable;

    if (durationSeconds < 1 || durationSeconds > 60) {
      throw ArgumentError.value(
        durationSeconds,
        'durationSeconds',
        'Voice Moments must be between 1 and 60 seconds.',
      );
    }

    final normalizedCaption = caption.trim().isEmpty
        ? 'Voice Moment'
        : caption.trim();
    final trimmedReplyToMomentId = replyToMomentId?.trim();
    final normalizedReplyToMomentId =
        trimmedReplyToMomentId == null || trimmedReplyToMomentId.isEmpty
        ? null
        : trimmedReplyToMomentId;

    final existingPending = _pendingMomentPublishes[audio];
    if (existingPending != null &&
        !existingPending.matches(
          caption: normalizedCaption,
          durationSeconds: durationSeconds,
          replyToMomentId: normalizedReplyToMomentId,
        )) {
      throw StateError(
        'Publishing already started with a different caption, duration, or '
        'reply target. Restore the original details to retry this recording, '
        'or record again to publish the new version.',
      );
    }

    if (normalizedReplyToMomentId != null) {
      final identity = await _identity(user);
      return _publishVoiceReply(
        parentMomentId: normalizedReplyToMomentId,
        audio: audio,
        durationSeconds: durationSeconds,
        caption: normalizedCaption,
        authorId: user.uid,
        authorName: identity.displayName,
        authorPhotoUrl: identity.photoUrl,
      );
    }

    final pending = _pendingMomentPublishes.putIfAbsent(
      audio,
      () => _PendingMomentPublish(
        requestId: _newRequestId(),
        caption: normalizedCaption,
        durationSeconds: durationSeconds,
        replyToMomentId: normalizedReplyToMomentId,
      ),
    );

    try {
      final functions = _functions;
      if (functions == null) {
        throw FirebaseFunctionsException(
          code: 'no-app',
          message: 'Cloud Functions unavailable.',
        );
      }
      if (pending.momentId == null || pending.storagePath == null) {
        final reserve = functions.httpsCallable('reserveMomentDraft');
        final reserved = await reserve.call<Map<Object?, Object?>>({
          'caption': normalizedCaption,
          'durationSeconds': durationSeconds,
          'requestId': pending.requestId,
        });
        pending
          ..momentId = reserved.data['momentId'] as String?
          ..storagePath = reserved.data['storagePath'] as String?;
      }

      final momentId = pending.momentId;
      final storagePath = pending.storagePath;
      if (momentId == null ||
          momentId.isEmpty ||
          storagePath == null ||
          storagePath.isEmpty) {
        throw StateError('Malformed server draft reservation for moment.');
      }
      final storageReference = _storage.ref(storagePath);

      if (pending.objectGeneration == null) {
        try {
          pending.objectGeneration = await audio.uploadTo(
            storageReference,
            SettableMetadata(
              contentType: audio.contentType,
              customMetadata: {'authorId': user.uid, 'momentId': momentId},
            ),
          );
        } catch (_) {
          // A mobile connection can drop after Storage commits the object but
          // before the client receives the upload response. Recovering the
          // generation turns that ambiguous failure into a safe finalize;
          // the server still validates size, MIME, metadata and ownership.
          pending.objectGeneration = await _uploadedGeneration(
            storageReference,
          );
          if (pending.objectGeneration == null) rethrow;
        }
      }

      final objectGeneration = pending.objectGeneration;
      if (objectGeneration == null || objectGeneration.isEmpty) {
        throw StateError('The upload did not return a valid generation.');
      }

      final finalize = functions.httpsCallable('finalizeMomentDraft');
      await finalize.call<Map<Object?, Object?>>({
        'momentId': momentId,
        'objectGeneration': objectGeneration,
        'requestId': pending.requestId,
      });

      _pendingMomentPublishes.remove(audio);
      return momentId;
    } catch (error) {
      if (!_isCallableUnavailable(error)) {
        rethrow;
      }
    }

    _pendingMomentPublishes.remove(audio);
    return _publishRecordedMomentLegacy(
      user: user,
      audio: audio,
      durationSeconds: durationSeconds,
      caption: normalizedCaption,
    );
  }

  Future<String?> _uploadedGeneration(Reference reference) async {
    try {
      final metadata = await reference.getMetadata();
      final generation = metadata.generation?.trim();
      return generation == null || generation.isEmpty ? null : generation;
    } catch (_) {
      return null;
    }
  }

  Future<String> _publishVoiceReply({
    required String parentMomentId,
    required RecordedAudio audio,
    required int durationSeconds,
    required String caption,
    required String authorId,
    required String authorName,
    required String? authorPhotoUrl,
  }) async {
    try {
      final requestId = _newRequestId();
      final functions = _functions;
      if (functions == null) {
        throw FirebaseFunctionsException(
          code: 'no-app',
          message: 'Cloud Functions unavailable.',
        );
      }
      final reserve = functions.httpsCallable('reserveVoiceCommentDraft');
      final reserved = await reserve.call<Map<Object?, Object?>>({
        'durationSeconds': durationSeconds,
        'momentId': parentMomentId,
        'text': caption,
        'requestId': requestId,
      });

      final reservedData = reserved.data;
      final commentId = reservedData['commentId'] as String?;
      final storagePath = reservedData['storagePath'] as String?;
      if (commentId == null ||
          commentId.isEmpty ||
          storagePath == null ||
          storagePath.isEmpty) {
        throw StateError('Malformed server voice-reply reservation.');
      }
      final storageReference = _storage.ref(storagePath);
      try {
        final objectGeneration = await audio.uploadTo(
          storageReference,
          SettableMetadata(
            contentType: audio.contentType,
            customMetadata: {
              'authorId': authorId,
              'momentId': parentMomentId,
              'commentId': commentId,
            },
          ),
        );

        if (objectGeneration.isEmpty) {
          throw StateError('The upload did not return a valid generation.');
        }

        final finalize = functions.httpsCallable('finalizeVoiceCommentDraft');
        await finalize.call<Map<Object?, Object?>>({
          'momentId': parentMomentId,
          'commentId': commentId,
          'objectGeneration': objectGeneration,
          'requestId': requestId,
        });

        return commentId;
      } catch (error) {
        await storageReference.delete().catchError((_) {});
        rethrow;
      }
    } catch (error) {
      if (!_isCallableUnavailable(error)) {
        rethrow;
      }
    }

    return _publishVoiceReplyLegacy(
      parentMomentId: parentMomentId,
      audio: audio,
      durationSeconds: durationSeconds,
      caption: caption,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
    );
  }

  Future<String> createTextComment({
    required String momentId,
    required String text,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to comment on a Voice Moment.');
    }

    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      return '';
    }

    final requestId = _newRequestId();
    try {
      final functions = _functions;
      if (functions == null) {
        throw FirebaseFunctionsException(
          code: 'no-app',
          message: 'Cloud Functions unavailable.',
        );
      }
      final callable = functions.httpsCallable('createMomentComment');
      final response = await callable.call<Map<Object?, Object?>>({
        'momentId': momentId,
        'text': trimmedText,
        'requestId': requestId,
      });

      final data = response.data;
      final commentId = data['commentId'];
      if (commentId == null || commentId is! String || commentId.isEmpty) {
        throw StateError('Malformed server response for comment creation.');
      }
      return commentId;
    } catch (error) {
      if (!_isCallableUnavailable(error)) {
        rethrow;
      }
    }

    return _createTextCommentLegacy(
      momentId: momentId,
      user: user,
      text: trimmedText,
    );
  }

  Future<String> _createTextCommentLegacy({
    required String momentId,
    required User user,
    required String text,
  }) async {
    final userSnapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .get();
    final userData = userSnapshot.data();
    final displayName = (userData?['displayName'] as String?)?.trim();
    final photoUrl = userData?['photoUrl'] as String?;

    final identityName = displayName?.isNotEmpty == true
        ? displayName
        : user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : user.email?.split('@').first ?? 'YO Voice user';

    final commentReference = _commentsFor(momentId).doc();
    final momentReference = _moments.doc(momentId);
    final batch = _firestore.batch();

    batch.set(commentReference, {
      'type': 'text',
      'authorId': user.uid,
      'authorName': identityName,
      'authorPhotoUrl': photoUrl ?? user.photoURL,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(momentReference, {
      'commentCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return commentReference.id;
  }

  Future<String> _publishRecordedMomentLegacy({
    required User user,
    required RecordedAudio audio,
    required int durationSeconds,
    required String caption,
  }) async {
    final document = _moments.doc();
    final storageReference = _storage.ref(
      'voice_moments/${user.uid}/${document.id}.$kVoiceMomentFileExtension',
    );

    final identity = await _identity(user);
    await document.set({
      'schemaVersion': 2,
      'authorId': user.uid,
      'authorName': identity.displayName,
      'authorPhotoUrl': identity.photoUrl,
      'caption': caption,
      'audioUrl': null,
      'storagePath': storageReference.fullPath,
      'durationSeconds': durationSeconds,
      'likeCount': 0,
      'commentCount': 0,
      'replyToMomentId': null,
      'isPublished': false,
      'isDeleted': false,
      'status': 'uploading',
      'mediaGeneration': null,
      'mediaSize': null,
      'mediaContentType': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'publishedAt': null,
    });

    try {
      final objectGeneration = await audio.uploadTo(
        storageReference,
        SettableMetadata(
          contentType: audio.contentType,
          customMetadata: {'authorId': user.uid, 'momentId': document.id},
        ),
      );

      final downloadUrl = await storageReference.getDownloadURL();
      await document.update({
        'audioUrl': downloadUrl,
        'isPublished': true,
        'status': 'published',
        'mediaGeneration': objectGeneration,
        'mediaSize': audio.byteLength,
        'mediaContentType': audio.contentType,
        'publishedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return document.id;
    } catch (_) {
      await document.delete().catchError((_) {});
      await storageReference.delete().catchError((_) {});
      rethrow;
    }
  }

  Future<String> _publishVoiceReplyLegacy({
    required String parentMomentId,
    required RecordedAudio audio,
    required int durationSeconds,
    required String caption,
    required String authorId,
    required String authorName,
    required String? authorPhotoUrl,
  }) async {
    final parentReference = _moments.doc(parentMomentId);
    final commentReference = parentReference.collection('comments').doc();
    final storageReference = _storage.ref(
      'voice_replies/$authorId/$parentMomentId/'
      '${commentReference.id}.$kVoiceMomentFileExtension',
    );

    try {
      await audio.uploadTo(
        storageReference,
        SettableMetadata(
          contentType: audio.contentType,
          customMetadata: {
            'authorId': authorId,
            'momentId': parentMomentId,
            'commentId': commentReference.id,
          },
        ),
      );

      final downloadUrl = await storageReference.getDownloadURL();
      final batch = _firestore.batch();
      batch.set(commentReference, {
        'type': 'voice',
        'authorId': authorId,
        'authorName': authorName,
        'authorPhotoUrl': authorPhotoUrl,
        'text': caption,
        'audioUrl': downloadUrl,
        'storagePath': storageReference.fullPath,
        'durationSeconds': durationSeconds,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(parentReference, {
        'commentCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      return commentReference.id;
    } catch (_) {
      await storageReference.delete().catchError((_) {});
      rethrow;
    }
  }

  Future<void> deleteMoment(VoiceMoment moment) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to delete a Voice Moment.');
    }
    if (moment.authorId != user.uid) {
      throw StateError('You can only delete your own Voice Moments.');
    }

    final momentReference = _moments.doc(moment.id);

    // Remove uploaded voice replies before deleting their Firestore records.
    final comments = await momentReference.collection('comments').get();
    for (final comment in comments.docs) {
      final storagePath = (comment.data()['storagePath'] as String?)?.trim();
      if (storagePath != null && storagePath.isNotEmpty) {
        await _storage.ref(storagePath).delete().catchError((_) {});
      }
    }

    await _deleteCollection(momentReference.collection('comments'));
    await _deleteCollection(momentReference.collection('likes'));

    final momentSnapshot = await momentReference.get();
    final storagePath = (momentSnapshot.data()?['storagePath'] as String?)
        ?.trim();
    if (storagePath != null && storagePath.isNotEmpty) {
      await _storage.ref(storagePath).delete().catchError((_) {});
    }

    await momentReference.delete();
  }

  Future<({String displayName, String? photoUrl})> _identity(User user) async {
    final profile = await _firestore.collection('users').doc(user.uid).get();
    final profileName = (profile.data()?['displayName'] as String?)?.trim();
    final profilePhoto = (profile.data()?['photoUrl'] as String?)?.trim();
    return (
      displayName: (profileName != null && profileName.isNotEmpty
          ? profileName
          : user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : user.email?.split('@').first ?? 'YO Voice user'),
      photoUrl: profilePhoto?.isNotEmpty == true ? profilePhoto : user.photoURL,
    );
  }

  CollectionReference<Map<String, dynamic>> _commentsFor(String momentId) =>
      _moments.doc(momentId).collection('comments');

  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    while (true) {
      final snapshot = await collection.limit(400).get();
      if (snapshot.docs.isEmpty) {
        return;
      }

      final batch = _firestore.batch();
      for (final document in snapshot.docs) {
        batch.delete(document.reference);
      }
      await batch.commit();
    }
  }
}

class _PendingMomentPublish {
  _PendingMomentPublish({
    required this.requestId,
    required this.caption,
    required this.durationSeconds,
    required this.replyToMomentId,
  });

  final String requestId;
  final String caption;
  final int durationSeconds;
  final String? replyToMomentId;
  String? momentId;
  String? storagePath;
  String? objectGeneration;

  bool matches({
    required String caption,
    required int durationSeconds,
    required String? replyToMomentId,
  }) =>
      this.caption == caption &&
      this.durationSeconds == durationSeconds &&
      this.replyToMomentId == replyToMomentId;
}
