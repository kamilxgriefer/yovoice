import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';

void main() {
  late _ProfileFirestore firestore;
  late _MutableAuth auth;
  late ProfileService service;
  late List<StreamSubscription<UserProfile>> listeners;

  setUp(() {
    ProfileService.resetCurrentProfileCache();
    firestore = _ProfileFirestore();
    auth = _MutableAuth(MockUser(uid: 'profile-account-a'));
    service = ProfileService(firestore: firestore, auth: auth);
    listeners = [];
  });

  tearDown(() async {
    for (final document in firestore.users.documents.values) {
      for (final source in document.sources) {
        source.releaseCancellation();
      }
    }
    for (final listener in listeners) {
      await listener.cancel();
    }
    for (final document in firestore.users.documents.values) {
      for (final source in document.sources) {
        await source.controller.close();
      }
    }
    ProfileService.resetCurrentProfileCache();
  });

  test('a late cancellation cannot orphan the replacement listener', () async {
    final document = firestore.users.document('profile-account-a');
    document.delayNextCancellation = true;
    final stream = service.watchCurrentProfile();
    final first = stream.listen((_) {});
    listeners.add(first);
    final original = document.sources.single;

    await first.cancel();
    expect(original.cancelCalls, 1);
    expect(original.cancellationReleased, isFalse);

    final replacementNames = <String>[];
    final replacement = stream.listen(
      (profile) => replacementNames.add(profile.displayName),
    );
    listeners.add(replacement);
    expect(document.sources, hasLength(2));
    final next = document.sources.last;
    next.emit('Replacement');
    await _settleStreams();
    expect(replacementNames, ['Replacement']);

    // Firestore finishes cancelling the old subscription only after the
    // route has already installed its replacement subscription.
    original.releaseCancellation();
    await _settleStreams();
    await replacement.cancel();
    await _settleStreams();

    expect(
      next.cancelCalls,
      1,
      reason:
          'the final screen must still cancel its Firestore listener '
          'after an older cancellation finishes',
    );

    final thirdNames = <String>[];
    listeners.add(
      stream.listen((profile) => thirdNames.add(profile.displayName)),
    );
    document.sources.last.emit('Third subscription');
    await _settleStreams();
    expect(thirdNames, ['Replacement', 'Third subscription']);
    expect(document.sources, hasLength(3));
  });

  test(
    'screens share one listener and late screens replay the latest profile',
    () async {
      final firstNames = <String>[];
      final secondNames = <String>[];
      final first = service.watchCurrentProfile().listen(
        (profile) => firstNames.add(profile.displayName),
      );
      listeners.add(first);
      final document = firestore.users.document('profile-account-a');
      final source = document.sources.single;
      source.emit('Initial');
      await _settleStreams();

      final otherService = ProfileService(firestore: firestore, auth: auth);
      final second = otherService.watchCurrentProfile().listen(
        (profile) => secondNames.add(profile.displayName),
      );
      listeners.add(second);
      await _settleStreams();
      expect(secondNames, ['Initial']);
      expect(document.sources, hasLength(1));

      source.emit('Saved profile');
      await _settleStreams();
      expect(firstNames, ['Initial', 'Saved profile']);
      expect(secondNames, firstNames);

      await first.cancel();
      expect(source.cancelCalls, 0);
      source.emit('Remaining screen');
      await _settleStreams();
      expect(secondNames.last, 'Remaining screen');
      await second.cancel();
      expect(source.cancelCalls, 1);
    },
  );

  test(
    'Firestore errors are forwarded and later data remains reactive',
    () async {
      final errors = <Object>[];
      final names = <String>[];
      listeners.add(
        service.watchCurrentProfile().listen(
          (profile) => names.add(profile.displayName),
          onError: (Object error) => errors.add(error),
        ),
      );
      final document = firestore.users.document('profile-account-a');
      final source = document.sources.single;
      source.emit('Before outage');
      await _settleStreams();
      final outage = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      source.controller.addError(outage, StackTrace.current);
      await _settleStreams();
      expect(errors, [same(outage)]);

      source.emit('After recovery');
      await _settleStreams();
      final replayed = <String>[];
      listeners.add(
        service.watchCurrentProfile().listen(
          (profile) => replayed.add(profile.displayName),
        ),
      );
      await _settleStreams();
      expect(names, ['Before outage', 'After recovery']);
      expect(replayed, ['After recovery']);
      expect(document.sources, hasLength(1));
    },
  );

  test(
    'switching accounts never replays the previous account profile',
    () async {
      final accountA = <UserProfile>[];
      final first = service.watchCurrentProfile().listen(accountA.add);
      listeners.add(first);
      final documentA = firestore.users.document('profile-account-a');
      documentA.sources.single.emit('Private A');
      await _settleStreams();
      await first.cancel();

      auth.currentUser = MockUser(uid: 'profile-account-b');
      final accountB = <UserProfile>[];
      listeners.add(service.watchCurrentProfile().listen(accountB.add));
      await _settleStreams();
      expect(accountB, isEmpty);
      final documentB = firestore.users.document('profile-account-b');
      documentB.sources.single.emit('Private B');
      await _settleStreams();
      expect(accountB.single.uid, 'profile-account-b');
      expect(accountB.single.displayName, 'Private B');
      expect(documentA.sources.single.cancelCalls, 1);

      auth.currentUser = null;
      expect(service.watchCurrentProfile, throwsStateError);
    },
  );

  test(
    'cache reset reacquires the profile without replaying stale values',
    () async {
      final first = service.watchCurrentProfile().listen((_) {});
      listeners.add(first);
      final document = firestore.users.document('profile-account-a');
      document.sources.single.emit('Old session');
      await _settleStreams();
      await first.cancel();
      ProfileService.resetCurrentProfileCache();

      final names = <String>[];
      listeners.add(
        service.watchCurrentProfile().listen(
          (profile) => names.add(profile.displayName),
        ),
      );
      await _settleStreams();
      expect(names, isEmpty);
      expect(document.sources, hasLength(2));
      document.sources.last.emit('New session');
      await _settleStreams();
      expect(names, ['New session']);
    },
  );
}

// Every fake operation below completes in microtasks. Advancing one event
// turn drains those operations without a machine-speed-dependent time limit.
Future<void> _settleStreams() => Future<void>.delayed(Duration.zero);

class _MutableAuth implements FirebaseAuth {
  _MutableAuth(this.currentUser);

  @override
  User? currentUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileFirestore implements FirebaseFirestore {
  final users = _ProfileCollection();

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    expect(collectionPath, 'users');
    return users;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _ProfileCollection implements CollectionReference<Map<String, dynamic>> {
  final documents = <String, _ProfileDocument>{};

  _ProfileDocument document(String uid) =>
      documents.putIfAbsent(uid, () => _ProfileDocument(uid));

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      document(path!);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Cancellation timing is mutable only on this injected Firestore test double.
// ignore: subtype_of_sealed_class, must_be_immutable
class _ProfileDocument implements DocumentReference<Map<String, dynamic>> {
  _ProfileDocument(this.uid);

  final String uid;
  final sources = <_ProfileSource>[];
  bool delayNextCancellation = false;

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    final next = _ProfileSource(
      uid,
      delayedCancellation: delayNextCancellation,
    );
    delayNextCancellation = false;
    sources.add(next);
    return next.controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileSource {
  _ProfileSource(this.uid, {required bool delayedCancellation}) {
    if (!delayedCancellation) cancellation.complete();
    controller.onCancel = () {
      cancelCalls += 1;
      return cancellation.future;
    };
  }

  final String uid;
  final controller = StreamController<DocumentSnapshot<Map<String, dynamic>>>();
  final cancellation = Completer<void>();
  int cancelCalls = 0;

  bool get cancellationReleased => cancellation.isCompleted;

  void releaseCancellation() {
    if (!cancellation.isCompleted) cancellation.complete();
  }

  void emit(String displayName) =>
      controller.add(_ProfileSnapshot(uid, displayName));
}

// ignore: subtype_of_sealed_class
class _ProfileSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _ProfileSnapshot(this.id, this.displayName);

  @override
  final String id;
  final String displayName;

  @override
  Map<String, dynamic> data() => {'displayName': displayName};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
