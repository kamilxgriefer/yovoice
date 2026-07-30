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
        : user.email?.split('@').first ?? 'YoVoice user';

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
      'replyToMomentId': replyToMomentId,
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

      await _firestore.runTransaction((transaction) async {
        transaction.update(document, {
          'audioUrl': downloadUrl,
          'isPublished': true,
          'publishedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (replyToMomentId != null && replyToMomentId.isNotEmpty) {
          final parentReference = _moments.doc(replyToMomentId);
          final parentSnapshot = await transaction.get(parentReference);
          if (parentSnapshot.exists) {
            final currentCount =
                (parentSnapshot.data()?['commentCount'] as num?)?.toInt() ?? 0;
            transaction.update(parentReference, {
              'commentCount': currentCount + 1,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      });

      return document.id;
    } catch (_) {
      await document.delete().catchError((_) {});
      await storageReference.delete().catchError((_) {});
      rethrow;
    }
  }
}
