import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';

class MomentService {
  MomentService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _moments =>
      _firestore.collection('voiceMoments');

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

  Future<String> publishRecordedMoment({
    required String localFilePath,
    required int durationSeconds,
    required String caption,
    String? replyToMomentId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to publish a Voice Moment.');
    }

    final file = File(localFilePath);
    if (!await file.exists()) {
      throw StateError('The recorded audio file could not be found.');
    }

    if (durationSeconds < 1 || durationSeconds > 60) {
      throw ArgumentError.value(
        durationSeconds,
        'durationSeconds',
        'Voice Moments must be between 1 and 60 seconds.',
      );
    }

    final userDocument = await _firestore
        .collection('users')
        .doc(user.uid)
        .get();
    final userData = userDocument.data();
    final profileName = (userData?['displayName'] as String?)?.trim();
    final profilePhoto = userData?['photoUrl'] as String?;

    final authorName = profileName?.isNotEmpty == true
        ? profileName!
        : user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : user.email?.split('@').first ?? 'YO Voice user';

    if (replyToMomentId != null && replyToMomentId.isNotEmpty) {
      return _publishVoiceReply(
        parentMomentId: replyToMomentId,
        file: file,
        durationSeconds: durationSeconds,
        caption: caption,
        authorId: user.uid,
        authorName: authorName,
        authorPhotoUrl: profilePhoto ?? user.photoURL,
      );
    }

    final document = _moments.doc();
    final storageReference = _storage.ref(
      'voice_moments/${user.uid}/${document.id}.m4a',
    );

    await document.set({
      'authorId': user.uid,
      'authorName': authorName,
      'authorPhotoUrl': profilePhoto ?? user.photoURL,
      'caption': caption.trim().isEmpty ? 'Voice Moment' : caption.trim(),
      'audioUrl': null,
      'storagePath': storageReference.fullPath,
      'durationSeconds': durationSeconds,
      'likeCount': 0,
      'commentCount': 0,
      'replyToMomentId': null,
      'isPublished': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    try {
      await storageReference.putFile(
        file,
        SettableMetadata(
          contentType: 'audio/mp4',
          customMetadata: {'authorId': user.uid, 'momentId': document.id},
        ),
      );

      final downloadUrl = await storageReference.getDownloadURL();
      await document.update({
        'audioUrl': downloadUrl,
        'isPublished': true,
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

  Future<String> _publishVoiceReply({
    required String parentMomentId,
    required File file,
    required int durationSeconds,
    required String caption,
    required String authorId,
    required String authorName,
    required String? authorPhotoUrl,
  }) async {
    final parentReference = _moments.doc(parentMomentId);
    final commentReference = parentReference.collection('comments').doc();
    final storageReference = _storage.ref(
      'voice_replies/$authorId/$parentMomentId/${commentReference.id}.m4a',
    );

    try {
      await storageReference.putFile(
        file,
        SettableMetadata(
          contentType: 'audio/mp4',
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
        'text': caption.trim(),
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
