import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/server.dart';
import '../models/server_channel.dart';
import '../models/server_creation.dart';
import '../models/server_type.dart';
import 'server_creation_request_store.dart';

abstract interface class ServerRepository {
  String get currentUserId;
  String newRequestId();
  Stream<List<Server>> watchMyServers();
  Stream<Server?> watchServer(String serverId);
  Stream<List<ServerChannel>> watchChannels(String serverId);
  Future<ServerCreationResult> createServer(ServerCreationRequest request);

  /// The unresolved submission this owner still has open for [type], so a
  /// configuration step that is re-entered resumes the identical request
  /// instead of allocating a second identity. Null when nothing is pending.
  Future<ServerCreationRequest?> pendingCreation(ServerType type);

  /// Commits [request] as pending for its owner and template before the
  /// callable runs. Returns the request that is actually pending: [request]
  /// itself, or an earlier unresolved one for the same scope, which wins
  /// because its id may already have created a server.
  Future<ServerCreationRequest> rememberPendingCreation(
    ServerCreationRequest request,
  );

  /// Clears the pending record once the backend has answered for that id.
  Future<void> forgetPendingCreation(ServerCreationRequest request);
}

typedef ServerCallable =
    Future<Map<Object?, Object?>> Function(
      String name,
      Map<String, Object> data,
    );

/// Reads the existing Club graph through a server vocabulary. Authorization
/// remains in Rules/callables; no read creates or migrates a document.
class ServerService implements ServerRepository {
  ServerService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    ServerCallable? call,
    ServerCreationRequestStore? pendingStore,
    DateTime Function()? now,
  }) : _firestoreOverride = firestore,
       _authOverride = auth,
       _functionsOverride = functions,
       _callOverride = call,
       _pendingStore =
           pendingStore ?? SharedPreferencesServerCreationRequestStore(),
       _now = now ?? DateTime.now;

  /// How long an unresolved creation stays resumable. Long enough to survive
  /// a night offline; short enough that a record nobody ever resends does not
  /// lock a template for good.
  static const pendingCreationTtl = Duration(hours: 24);

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;
  final FirebaseFunctions? _functionsOverride;
  final ServerCallable? _callOverride;
  final ServerCreationRequestStore _pendingStore;
  final DateTime Function() _now;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  @override
  String get currentUserId => _auth.currentUser?.uid ?? '';

  Stream<String?> _watchAccountId() => Stream<String?>.multi((controller) {
    final subscription = _auth.authStateChanges().listen(
      (user) => controller.add(user?.uid),
      onError: controller.addError,
    );
    controller.add(_auth.currentUser?.uid);
    controller.onCancel = subscription.cancel;
  }).distinct();

  @override
  String newRequestId() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  Future<ServerCreationResult> createServer(
    ServerCreationRequest request,
  ) async {
    final call = _callOverride;
    final data = call == null
        ? (await _functions
                  .httpsCallable('createServerV1')
                  .call<Map<Object?, Object?>>(request.toCallableData()))
              .data
        : await call('createServerV1', request.toCallableData());
    return ServerCreationResult.fromMap(data);
  }

  @override
  Future<ServerCreationRequest?> pendingCreation(ServerType type) =>
      _pendingStore.load(
        ownerId: currentUserId,
        type: type,
        now: _now(),
        ttl: pendingCreationTtl,
      );

  @override
  Future<ServerCreationRequest> rememberPendingCreation(
    ServerCreationRequest request,
  ) => _pendingStore.remember(
    ownerId: currentUserId,
    request: request,
    now: _now(),
  );

  @override
  Future<void> forgetPendingCreation(ServerCreationRequest request) =>
      _pendingStore.forget(
        ownerId: currentUserId,
        type: request.serverType,
        expectedRequestId: request.requestId,
      );

  @override
  Stream<Server?> watchServer(String serverId) {
    _requireId(serverId);
    return _firestore
        .collection('clubs')
        .doc(serverId)
        .snapshots()
        .map((doc) => doc.exists ? Server.fromFirestore(doc) : null);
  }

  @override
  Stream<List<Server>> watchMyServers() => _switchMap(_watchAccountId(), (uid) {
    if (uid == null) return Stream.value(const <Server>[]);
    return _switchMap(
      _firestore
          .collection('users')
          .doc(uid)
          .collection('clubs')
          .orderBy('joinedAt', descending: true)
          .snapshots(),
      (snapshot) {
        // Mirrors locate roots, but every root has its own authorized read.
        final ids = snapshot.docs
            .map((doc) => serverString(doc.data()['clubId']) ?? doc.id)
            .toSet()
            .toList();
        return _combineNullable(
          ids.map((id) => _dropDenied(watchServer(id))).toList(),
        );
      },
    );
  });

  @override
  Stream<List<ServerChannel>> watchChannels(String serverId) {
    _requireId(serverId);
    return _switchMap(_watchAccountId(), (uid) {
      if (uid == null) return Stream.value(const <ServerChannel>[]);
      return _switchMap(watchServer(serverId), (server) {
        if (server == null) return Stream.value(const <ServerChannel>[]);
        final channels = _firestore
            .collection('clubs')
            .doc(serverId)
            .collection('channels');
        if (server.isLegacy) {
          return channels
              .orderBy('position')
              .snapshots()
              .map(
                (snapshot) => snapshot.docs
                    .map(
                      (doc) => ServerChannel.fromFirestore(
                        serverId: serverId,
                        document: doc,
                      ),
                    )
                    .toList(growable: false),
              );
        }
        // A broad collection query cannot safely list mixed restricted rows.
        final members = channels
            .where('accessMode', isEqualTo: 'members')
            .where('status', isEqualTo: 'active')
            .orderBy('position')
            .snapshots()
            .map(
              (snapshot) => snapshot.docs
                  .map(
                    (doc) => ServerChannel.fromFirestore(
                      serverId: serverId,
                      document: doc,
                    ),
                  )
                  .toList(growable: false),
            );
        final restricted = _switchMap(
          _firestore
              .collection('users')
              .doc(uid)
              .collection('serverChannelRefs')
              .where('serverId', isEqualTo: serverId)
              .snapshots(),
          (snapshot) {
            final ids = snapshot.docs
                .map((doc) => serverString(doc.data()['channelId']))
                .whereType<String>()
                .toSet();
            return _combineNullable(
              ids.map((id) {
                _requireId(id);
                return _dropDenied(
                  channels
                      .doc(id)
                      .snapshots()
                      .map(
                        (doc) => doc.exists
                            ? ServerChannel.fromFirestore(
                                serverId: serverId,
                                document: doc,
                              )
                            : null,
                      ),
                );
              }).toList(),
            );
          },
        );
        return _combineNullable<List<ServerChannel>>([members, restricted]).map(
          (parts) {
            final byId = <String, ServerChannel>{
              for (final part in parts)
                for (final channel in part)
                  if (channel.status == 'active') channel.id: channel,
            };
            final result = byId.values.toList()
              ..sort((a, b) {
                final position = a.position.compareTo(b.position);
                return position == 0 ? a.id.compareTo(b.id) : position;
              });
            return result;
          },
        );
      });
    });
  }

  static void _requireId(String id) {
    if (id.isEmpty || id.contains('/')) {
      throw ArgumentError.value(id, 'id', 'Invalid document identity.');
    }
  }
}

/// Access revocation removes that item immediately without making unrelated
/// memberships disappear. Network/configuration failures remain visible errors.
Stream<T?> _dropDenied<T>(Stream<T?> source) => source.transform(
  StreamTransformer<T?, T?>.fromHandlers(
    handleError: (error, stack, sink) {
      if (error is FirebaseException && error.code == 'permission-denied') {
        sink.add(null);
      } else {
        sink.addError(error, stack);
      }
    },
  ),
);

Stream<List<T>> _combineNullable<T>(List<Stream<T?>> sources) {
  if (sources.isEmpty) return Stream.value(<T>[]);
  late StreamController<List<T>> controller;
  final values = List<T?>.filled(sources.length, null);
  final ready = List<bool>.filled(sources.length, false);
  final subscriptions = <StreamSubscription<T?>>[];
  controller = StreamController<List<T>>(
    onListen: () {
      for (var i = 0; i < sources.length; i++) {
        final index = i;
        subscriptions.add(
          sources[i].listen((value) {
            values[index] = value;
            ready[index] = true;
            if (ready.every((value) => value)) {
              controller.add(values.whereType<T>().toList(growable: false));
            }
          }, onError: controller.addError),
        );
      }
    },
    onCancel: () async {
      await Future.wait(
        subscriptions.map((subscription) => subscription.cancel()),
      );
    },
  );
  return controller.stream;
}

/// Switches authority scopes, cancelling old listeners and rejecting late data.
Stream<R> _switchMap<T, R>(Stream<T> source, Stream<R> Function(T) project) {
  late StreamController<R> controller;
  StreamSubscription<T>? outer;
  StreamSubscription<R>? inner;
  var generation = 0;
  controller = StreamController<R>(
    onListen: () {
      outer = source.listen((value) {
        final current = ++generation;
        unawaited(inner?.cancel());
        try {
          inner = project(value).listen(
            (result) {
              if (current == generation) controller.add(result);
            },
            onError: (Object error, StackTrace stack) {
              if (current == generation) controller.addError(error, stack);
            },
          );
        } catch (error, stack) {
          if (current == generation) controller.addError(error, stack);
        }
      }, onError: controller.addError);
    },
    onCancel: () async {
      generation++;
      await outer?.cancel();
      await inner?.cancel();
    },
  );
  return controller.stream;
}
