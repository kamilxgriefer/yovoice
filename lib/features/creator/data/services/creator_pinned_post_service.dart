import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/creator/data/models/creator_pinned_post.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';

typedef PinnedPostMutationInvoker =
    Future<Map<String, dynamic>> Function(String? momentId);

class CreatorPinnedPostService {
  CreatorPinnedPostService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    PinnedPostMutationInvoker? mutationInvoker,
    VoiceMomentReadService? voiceMomentReadService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions,
       _mutationInvoker = mutationInvoker,
       _voiceMomentReadServiceOverride = voiceMomentReadService;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;
  final PinnedPostMutationInvoker? _mutationInvoker;
  final VoiceMomentReadService? _voiceMomentReadServiceOverride;

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

  /// Reads `creatorPinnedPosts/{knownUid}`, then resolves the referenced Moment
  /// only through the server-owned Build 20 projection. There is no direct
  /// foreign `voiceMoments/{id}` read or production fallback.
  Stream<PinnedVoiceMoment?> watchPinnedPostForCreator(String creatorId) {
    if (!_canonicalCreatorId(creatorId)) return Stream.value(null);

    late final StreamController<PinnedVoiceMoment?> controller;
    StreamSubscription<CreatorPinnedPost?>? pinSubscription;
    var generation = 0;

    Future<void> switchMoment(CreatorPinnedPost? pin) async {
      final version = ++generation;
      if (controller.isClosed || version != generation) return;
      if (pin == null) {
        controller.add(null);
        return;
      }
      try {
        final reads =
            _voiceMomentReadServiceOverride ??
            VoiceMomentReadService(functions: _functionsOverride);
        final view = await reads.loadView(momentId: pin.momentId);
        if (controller.isClosed || version != generation) return;
        final moment = view.moment;
        final eligible =
            moment.id == pin.momentId &&
            moment.authorId == creatorId &&
            moment.isCanonicalPublished;
        controller.add(
          eligible ? PinnedVoiceMoment(pin: pin, moment: moment) : null,
        );
      } on Object {
        if (!controller.isClosed && version == generation) {
          controller.add(null);
        }
      }
    }

    controller = StreamController<PinnedVoiceMoment?>(
      onListen: () {
        pinSubscription = watchPinForCreator(creatorId).listen(
          (pin) => unawaited(switchMoment(pin)),
          onError: (_) {
            if (!controller.isClosed) controller.add(null);
          },
        );
      },
      onCancel: () async {
        generation += 1;
        await pinSubscription?.cancel();
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
