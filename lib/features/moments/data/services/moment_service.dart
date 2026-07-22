import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';

class MomentService {
  MomentService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _moments =>
      _firestore.collection('voiceMoments');

  Stream<List<VoiceMoment>> watchPublishedMoments({int limit = 12}) {
    return _moments
        .where('isPublished', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(VoiceMoment.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<String> createMomentDraft({
    required String caption,
    required int durationSeconds,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to create a Voice Moment.');
    }

    final name = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : user.email?.split('@').first ?? 'YoVoice user';

    final document = await _moments.add({
      'authorId': user.uid,
      'authorName': name,
      'authorPhotoUrl': user.photoURL,
      'caption': caption.trim(),
      'audioUrl': null,
      'durationSeconds': durationSeconds,
      'likeCount': 0,
      'commentCount': 0,
      'isPublished': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return document.id;
  }
}
