import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';

import '../models/server.dart';
import '../models/server_channel.dart';
import '../models/server_creation.dart';
import '../models/server_member_role.dart';
import '../models/server_session.dart';
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

  /// The viewer's own role row in [serverId] — the one row a member (or a
  /// held server's owner) may always read. Null while it has not arrived,
  /// when the viewer is not a member, or when the read is denied.
  Stream<ServerMemberRole?> watchMyRole(String serverId);

  /// The ids of everybody in [serverId] who actually holds moderator power
  /// or above, read from `clubs/{serverId}/members` — the roster Rules open
  /// to members of an active server. Empty while the read has not arrived,
  /// while it is denied, and for a held root, so a badge is only ever drawn
  /// from a role the backend really wrote.
  Stream<Set<String>> watchModerators(String serverId);

  /// Canonical friends, the only people `createServerInviteV1` accepts.
  Stream<List<ServerInviteCandidate>> watchInviteCandidates();

  Future<ServerInviteResult> createInvite({
    required String serverId,
    required String inviteeId,
    required String requestId,
  });

  Future<ServerChannelCreationResult> createChannel(
    ServerChannelCreationRequest request,
  );

  Future<ServerSessionStart> startChannelSession({
    required String serverId,
    required String channelId,
    required String requestId,
  });

  Future<ServerSessionConnection> createChannelToken({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String requestId,
  });

  /// Raises or lowers the caller's own hand in a live generation
  /// (`setServerSessionHandV1`). The callable refuses anybody who has not
  /// joined and refuses the generation's host, so this is only ever offered
  /// from inside a connected session.
  Future<ServerSessionHandResult> setSessionHand({
    required String serverId,
    required String channelId,
    required String sessionId,
    required bool raised,
    required String requestId,
  });
}

typedef ServerCallable =
    Future<Map<Object?, Object?>> Function(
      String name,
      Map<String, Object?> data,
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
    Stream<List<ServerInviteCandidate>> Function()? inviteCandidates,
  }) : _firestoreOverride = firestore,
       _authOverride = auth,
       _functionsOverride = functions,
       _callOverride = call,
       _pendingStore =
           pendingStore ?? SharedPreferencesServerCreationRequestStore(),
       _now = now ?? DateTime.now,
       _inviteCandidatesOverride = inviteCandidates;

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
  final Stream<List<ServerInviteCandidate>> Function()?
  _inviteCandidatesOverride;

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

  /// Every V1 callable goes through here: the exact export name, the exact
  /// payload, nothing added. The override is the test seam.
  Future<Map<Object?, Object?>> _invoke(
    String name,
    Map<String, Object?> data,
  ) async {
    final call = _callOverride;
    if (call != null) return call(name, data);
    final result = await _functions
        .httpsCallable(name)
        .call<Map<Object?, Object?>>(data);
    return result.data;
  }

  @override
  Future<ServerCreationResult> createServer(
    ServerCreationRequest request,
  ) async => ServerCreationResult.fromMap(
    await _invoke('createServerV1', request.toCallableData()),
  );

  @override
  Future<ServerInviteResult> createInvite({
    required String serverId,
    required String inviteeId,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(inviteeId);
    return ServerInviteResult.fromMap(
      await _invoke('createServerInviteV1', {
        'serverId': serverId,
        'inviteeId': inviteeId,
        'requestId': requestId,
      }),
    );
  }

  @override
  Future<ServerChannelCreationResult> createChannel(
    ServerChannelCreationRequest request,
  ) async => ServerChannelCreationResult.fromMap(
    await _invoke('createServerChannelV1', request.toCallableData()),
  );

  @override
  Future<ServerSessionStart> startChannelSession({
    required String serverId,
    required String channelId,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(channelId);
    return ServerSessionStart.fromMap(
      await _invoke('startServerChannelSessionV1', {
        'serverId': serverId,
        'channelId': channelId,
        'requestId': requestId,
      }),
    );
  }

  @override
  Future<ServerSessionConnection> createChannelToken({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(channelId);
    _requireId(sessionId);
    return ServerSessionConnection.fromMap(
      await _invoke('createServerChannelTokenV1', {
        'serverId': serverId,
        'channelId': channelId,
        'sessionId': sessionId,
        'requestId': requestId,
      }),
    );
  }

  @override
  Future<ServerSessionHandResult> setSessionHand({
    required String serverId,
    required String channelId,
    required String sessionId,
    required bool raised,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(channelId);
    _requireId(sessionId);
    return ServerSessionHandResult.fromMap(
      await _invoke('setServerSessionHandV1', {
        'serverId': serverId,
        'channelId': channelId,
        'sessionId': sessionId,
        'requestId': requestId,
        'raised': raised,
      }),
    );
  }

  /// The roles `capabilitiesFor` grants `moderate` to. Anything else — an
  /// unknown value, a member, a guest — carries no badge.
  static const _moderatorRoles = <String>['owner', 'coOwner', 'admin',
    'moderator'];

  @override
  Stream<Set<String>> watchModerators(String serverId) {
    _requireId(serverId);
    return _switchMap(_watchAccountId(), (uid) {
      if (uid == null) return Stream.value(const <String>{});
      return _switchMap(watchServer(serverId), (server) {
        // A held root denies the roster to everybody but the owner's own
        // row; asking for it would only produce a denied read.
        if (server == null || server.isHeld) {
          return Stream.value(const <String>{});
        }
        return _dropDenied<Set<String>>(
          _firestore
              .collection('clubs')
              .doc(serverId)
              .collection('members')
              .where('role', whereIn: _moderatorRoles)
              .snapshots()
              .map(
                (snapshot) => snapshot.docs
                    .map(
                      (doc) => serverString(doc.data()['userId']) ?? doc.id,
                    )
                    .toSet(),
              ),
        ).map((value) => value ?? const <String>{});
      });
    });
  }

  @override
  Stream<ServerMemberRole?> watchMyRole(String serverId) {
    _requireId(serverId);
    return _switchMap(_watchAccountId(), (uid) {
      if (uid == null) return Stream<ServerMemberRole?>.value(null);
      return _dropDenied(
        _firestore
            .collection('clubs')
            .doc(serverId)
            .collection('members')
            .doc(uid)
            .snapshots()
            .map(
              (doc) => doc.exists
                  ? ServerMemberRole.parse(doc.data()?['role'])
                  : null,
            ),
      );
    });
  }

  @override
  Stream<List<ServerInviteCandidate>> watchInviteCandidates() {
    final override = _inviteCandidatesOverride;
    if (override != null) return override();
    return _switchMap(_watchAccountId(), (uid) {
      if (uid == null) return Stream.value(const <ServerInviteCandidate>[]);
      return FriendService(
        firestore: _firestore,
        auth: _auth,
      ).watchFriends().map(
        (friends) => friends
            .map(
              (friend) => ServerInviteCandidate(
                id: friend.id,
                displayName: friend.displayName,
              ),
            )
            .toList(growable: false),
      );
    });
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
          ids.map((id) => _dropUnreadable(_dropDenied(watchServer(id)))).toList(),
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
                (snapshot) => _parsedChannels(serverId, snapshot.docs),
              );
        }
        // A broad collection query cannot safely list mixed restricted rows.
        final members = channels
            .where('accessMode', isEqualTo: 'members')
            .where('status', isEqualTo: 'active')
            .orderBy('position')
            .snapshots()
            .map((snapshot) => _parsedChannels(serverId, snapshot.docs));
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
                // A malformed pointer is one unreachable channel, not a
                // broken list: it is skipped the way a denied one is.
                .where(_isValidId)
                .toSet();
            return _combineNullable(
              ids.map((id) {
                return _dropUnreadable(
                  _dropDenied(
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

  static bool _isValidId(String id) => id.isNotEmpty && !id.contains('/');

  static void _requireId(String id) {
    if (!_isValidId(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid document identity.');
    }
  }

  /// Every channel document this client can read, with the ones it cannot
  /// parse left out.
  ///
  /// The row parsers are strict on purpose — an unknown `kind`, an unknown
  /// `accessMode` or `serverSchemaVersion: 2` is genuinely a document this
  /// build does not understand. In a LIST that must not be fatal: the
  /// versioned field exists so the backend can add a kind or bump a version
  /// additively, and an installed client turning one such document into an
  /// error state for the whole directory or the whole channel list is exactly
  /// the breakage `CLAUDE.md`'s schema rule forbids. Single-document reads
  /// keep the strict parse.
  static List<ServerChannel> _parsedChannels(
    String serverId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final parsed = <ServerChannel>[];
    for (final doc in docs) {
      try {
        parsed.add(
          ServerChannel.fromFirestore(serverId: serverId, document: doc),
        );
      } on FormatException {
        continue;
      } on ArgumentError {
        continue;
      }
    }
    return List<ServerChannel>.unmodifiable(parsed);
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

/// A row written by a newer backend drops out of a list instead of taking the
/// list down with it. See [ServerService._parsedChannels] for the reasoning;
/// this is the same rule applied to a per-document stream.
Stream<T?> _dropUnreadable<T>(Stream<T?> source) => source.transform(
  StreamTransformer<T?, T?>.fromHandlers(
    handleError: (error, stack, sink) {
      if (error is FormatException || error is ArgumentError) {
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
