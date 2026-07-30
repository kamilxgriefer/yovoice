import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';

class HomeFeedService {
  HomeFeedService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    return user.uid;
  }

  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) {
    final controller = StreamController<List<VoiceMoment>>.broadcast();
    var friendIds = <String>{};
    var followingIds = <String>{};
    var moments = <VoiceMoment>[];

    void emit() {
      if (controller.isClosed) return;
      final allowedAuthors = <String>{_uid, ...friendIds, ...followingIds};
      final filtered = moments
          .where((moment) => allowedAuthors.contains(moment.authorId))
          .toList(growable: false);
      filtered.sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      controller.add(filtered);
    }

    final subscriptions = <StreamSubscription<dynamic>>[];

    subscriptions.add(
      _firestore
          .collection('users')
          .doc(_uid)
          .collection('friends')
          .snapshots()
          .listen((snapshot) {
            friendIds = snapshot.docs.map((doc) => doc.id).toSet();
            emit();
          }, onError: controller.addError),
    );

    subscriptions.add(
      _firestore
          .collection('users')
          .doc(_uid)
          .collection('following')
          .snapshots()
          .listen((snapshot) {
            followingIds = snapshot.docs.map((doc) => doc.id).toSet();
            emit();
          }, onError: controller.addError),
    );

    subscriptions.add(
      _firestore
          .collection('voiceMoments')
          .where('isPublished', isEqualTo: true)
          .limit(limit)
          .snapshots()
          .listen((snapshot) {
            moments = snapshot.docs
                .map(VoiceMoment.fromFirestore)
                .toList(growable: false);
            emit();
          }, onError: controller.addError),
    );

    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };
    return controller.stream;
  }

  Stream<List<Club>> watchSuggestedClubs({int limit = 8}) {
    return _firestore
        .collection('clubs')
        .where('privacy', isEqualTo: 'public')
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final clubs = snapshot.docs.map(Club.fromFirestore).toList();
          clubs.sort((a, b) => b.memberCount.compareTo(a.memberCount));
          return clubs;
        });
  }

  Stream<bool> watchLiked(String momentId) {
    return _firestore
        .collection('voiceMoments')
        .doc(momentId)
        .collection('likes')
        .doc(_uid)
        .snapshots()
        .map((document) => document.exists);
  }

  Future<void> toggleLike(String momentId) async {
    final moment = _firestore.collection('voiceMoments').doc(momentId);
    final like = moment.collection('likes').doc(_uid);

    await _firestore.runTransaction((transaction) async {
      final momentSnapshot = await transaction.get(moment);
      final likeSnapshot = await transaction.get(like);
      if (!momentSnapshot.exists) {
        throw StateError('Voice Moment no longer exists.');
      }
      final current =
          (momentSnapshot.data()?['likeCount'] as num?)?.toInt() ?? 0;
      if (likeSnapshot.exists) {
        transaction.delete(like);
        transaction.update(moment, {
          'likeCount': current > 0 ? current - 1 : 0,
        });
      } else {
        transaction.set(like, {
          'userId': _uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(moment, {'likeCount': current + 1});
      }
    });
  }
}
