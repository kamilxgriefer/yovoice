import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/creator/data/models/creator_pinned_post.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';

typedef PinnedPostMutationInvoker =
    Future<Map<String, dynamic>> Function(String? momentId);

class CreatorPinnedPostService {
  CreatorPinnedPostService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    PinnedPostMutationInvoker? mutationInvoker,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions,
       _mutationInvoker = mutationInvoker;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;
  final PinnedPostMutationInvoker? _mutationInvoker;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  DocumentReference<Map<String, dynamic>> _pin(String creatorId) =>
      _firestore.collection('creatorPinnedPosts').doc(creatorId);

  static final RegExp _safeMomentIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  static bool _safeMomentId(String value) =>
      _safeMomentIdPattern.hasMatch(value);

  // Firebase Auth UIDs are opaque. Spaces, Unicode and casing are identity,
  // so only reject values that cannot be one Firestore document segment.
  static bool _canonicalCreatorId(String value) =>
      value.isNotEmpty && value.length <= 128 && !value.contains('/');

  Stream<CreatorPinnedPost?> watchPinForCreator(String creatorId) {
    if (!_canonicalCreatorId(creatorId)) return Stream.value(null);
    return _pin(creatorId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      try {
        return CreatorPinnedPost.fromFirestore(snapshot);
      } on FormatException {
        return null;
      }
    });
  }

  Stream<CreatorPinnedPost?> watchMyPin() {
    final user = _auth.currentUser;
    return user == null ? Stream.value(null) : watchPinForCreator(user.uid);
  }

  /// Reads only `creatorPinnedPosts/{knownUid}` and then the exact referenced
  /// `voiceMoments/{knownId}`. There is deliberately no collection list/query
  /// API, matching the Firestore Rules privacy boundary.
  Stream<PinnedVoiceMoment?> watchPinnedPostForCreator(String creatorId) {
    if (!_canonicalCreatorId(creatorId)) return Stream.value(null);

    late final StreamController<PinnedVoiceMoment?> controller;
    StreamSubscription<CreatorPinnedPost?>? pinSubscription;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
    momentSubscription;
    var generation = 0;

    void switchMoment(CreatorPinnedPost? pin) {
      final version = ++generation;
      unawaited(momentSubscription?.cancel());
      momentSubscription = null;
      if (controller.isClosed || version != generation) return;
      if (pin == null) {
        controller.add(null);
        return;
      }
      momentSubscription = _firestore
          .collection('voiceMoments')
          .doc(pin.momentId)
          .snapshots()
          .listen(
            (snapshot) {
              if (controller.isClosed || version != generation) return;
              if (!snapshot.exists) {
                controller.add(null);
                return;
              }
              try {
                final moment = VoiceMoment.fromFirestore(snapshot);
                final eligible =
                    moment.id == pin.momentId &&
                    moment.authorId == creatorId &&
                    moment.isCanonicalPublished;
                controller.add(
                  eligible ? PinnedVoiceMoment(pin: pin, moment: moment) : null,
                );
              } on Object {
                // The public profile is a fail-closed surface. A malformed
                // canonical document must hide the pin rather than throwing
                // out of the Firestore listener and taking down the profile.
                controller.add(null);
              }
            },
            onError: (_) {
              if (!controller.isClosed && version == generation) {
                controller.add(null);
              }
            },
          );
    }

    controller = StreamController<PinnedVoiceMoment?>(
      onListen: () {
        pinSubscription = watchPinForCreator(creatorId).listen(
          switchMoment,
          onError: (_) {
            if (!controller.isClosed) controller.add(null);
          },
        );
      },
      onCancel: () async {
        generation += 1;
        await pinSubscription?.cancel();
        await momentSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<VoiceMoment?> watchPinnedMomentForCreator(String creatorId) =>
      watchPinnedPostForCreator(creatorId).map((value) => value?.moment);

  Future<void> setPinnedMoment(String? momentId) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to manage pinned posts.');
    }
    if (momentId != null && !_safeMomentId(momentId)) {
      throw ArgumentError.value(momentId, 'momentId', 'Invalid Voice Moment.');
    }
    final invoke = _mutationInvoker;
    if (invoke != null) {
      await invoke(momentId);
      return;
    }
    await _functions.httpsCallable('setCreatorPinnedPost').call<void>({
      'momentId': momentId,
    });
  }
}
