import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';

import '../models/server.dart';
import '../models/server_channel.dart';
import '../models/server_creation.dart';
import '../models/server_event.dart';
import '../models/server_member_role.dart';
import '../models/server_member.dart';
import '../models/server_podcast_episode.dart';
import '../models/server_podcast_question.dart';
import '../models/server_session.dart';
import '../models/server_type.dart';
import '../models/server_whiteboard.dart';
import 'server_creation_request_store.dart';
import 'server_podcast_episode_repository.dart';
import 'server_whiteboard_repository.dart';

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

  /// Joins an active public Community or Podcast server. The backend proves
  /// the public-admission policy and writes the member, authorization and
  /// private directory projections atomically.
  Future<void> joinServer({
    required String serverId,
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

  /// Ends the current live generation for everybody. Only the generation's
  /// starter or a server moderator can pass the backend authority check.
  Future<void> endChannelSession({
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

  /// Moves one admitted participant between the stage and its audience. The
  /// callable accepts only `guest` and `listener`; `host` belongs to the
  /// generation starter and cannot be assigned by a client.
  Future<ServerSessionParticipationResult> setSessionParticipantRole({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String participantId,
    required String role,
    required String requestId,
  });

  /// Applies or releases the caller's own moderation-mute dimension for one
  /// admitted participant. A participant's local microphone control remains
  /// separate from this server authority.
  Future<ServerSessionParticipationResult> setSessionParticipantMute({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String participantId,
    required bool muted,
    required String requestId,
  });
}

/// Mutations and roster reads used by the server settings surface.
///
/// Kept separate from [ServerRepository] so small read-only integrations can
/// still provide the directory/session contract without pretending they can
/// administer a server.
abstract interface class ServerManagementRepository {
  Stream<List<ServerMember>> watchMembers(String serverId);

  Future<void> updateServer({
    required String serverId,
    required int expectedRevision,
    required Map<String, Object?> patch,
    required String requestId,
  });

  Future<void> updateChannel({
    required String serverId,
    required String channelId,
    required int expectedRevision,
    required Map<String, Object?> patch,
    required String requestId,
  });

  Future<void> reorderChannels({
    required String serverId,
    required int expectedRevision,
    required List<String> channelIds,
    required String requestId,
  });

  Future<void> setChannelAccess({
    required String serverId,
    required String channelId,
    required int expectedAclRevision,
    required ServerChannelAccess access,
    required List<String> roleIds,
    required List<String> userIds,
    required String requestId,
  });

  Future<void> archiveChannel({
    required String serverId,
    required String channelId,
    required String requestId,
  });

  Future<void> deleteChannel({
    required String serverId,
    required String channelId,
    required String requestId,
  });

  Future<void> revokeInvite({
    required String serverId,
    required String inviteeId,
    required String requestId,
  });

  Future<void> respondToInvite({
    required String serverId,
    required bool accept,
    required String requestId,
  });

  Future<void> leaveServer({
    required String serverId,
    required String requestId,
  });

  Future<void> setMemberRole({
    required String serverId,
    required String memberId,
    required ServerMemberRole role,
    required String requestId,
  });

  Future<void> removeMember({
    required String serverId,
    required String memberId,
    required String requestId,
  });

  Future<void> setMemberBan({
    required String serverId,
    required String memberId,
    required bool banned,
    required String reason,
    required String requestId,
  });

  Future<void> transferOwnership({
    required String serverId,
    required String newOwnerId,
    required String requestId,
  });

  Future<void> deleteServer({
    required String serverId,
    required String requestId,
  });
}

abstract interface class ServerEventsRepository {
  Stream<List<ServerEvent>> watchEvents(String serverId, String channelId);
  Stream<ServerEventAttendance?> watchMyEventResponse(
    String serverId,
    String channelId,
    String eventId,
  );

  Future<void> createEvent({
    required String serverId,
    required String channelId,
    required String title,
    required String description,
    required DateTime startsAt,
    required DateTime endsAt,
    required String timeZone,
    required String requestId,
  });

  Future<void> updateEvent({
    required ServerEvent event,
    required String title,
    required String description,
    required DateTime startsAt,
    required DateTime endsAt,
    required String timeZone,
    required String requestId,
  });

  Future<void> cancelEvent({
    required ServerEvent event,
    required String requestId,
  });

  Future<void> respondToEvent({
    required ServerEvent event,
    required ServerEventResponse response,
    required String requestId,
    bool? reminderRequested,
  });
}

/// The persisted listener Q&A in a podcast server's Questions channel.
///
/// Kept separate so a repository that only supports the common server shell
/// never has to claim podcast mutation support.
abstract interface class ServerPodcastQuestionsRepository {
  Stream<List<ServerPodcastQuestion>> watchPodcastQuestions(
    String serverId,
    String channelId,
  );

  Stream<bool> watchMyPodcastQuestionVote(
    String serverId,
    String channelId,
    String questionId,
  );

  Future<void> createPodcastQuestion({
    required String serverId,
    required String channelId,
    required String body,
    required String requestId,
  });

  Future<void> setPodcastQuestionVote({
    required ServerPodcastQuestion question,
    required bool voted,
    required String requestId,
  });

  Future<void> setPodcastQuestionOnAir({
    required ServerPodcastQuestion question,
    required bool onAir,
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
class ServerService
    implements
        ServerRepository,
        ServerManagementRepository,
        ServerEventsRepository,
        ServerPodcastEpisodeRepository,
        ServerPodcastQuestionsRepository,
        ServerWhiteboardRepository {
  ServerService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    ServerCallable? call,
    ServerCreationRequestStore? pendingStore,
    DateTime Function()? now,
    Stream<List<ServerInviteCandidate>> Function()? inviteCandidates,
    Duration creationAttemptTimeout = const Duration(seconds: 15),
  }) : _firestoreOverride = firestore,
       _authOverride = auth,
       _functionsOverride = functions,
       _callOverride = call,
       _pendingStore =
           pendingStore ?? SharedPreferencesServerCreationRequestStore(),
       _now = now ?? DateTime.now,
       _inviteCandidatesOverride = inviteCandidates,
       _creationAttemptTimeout = creationAttemptTimeout;

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
  final Duration _creationAttemptTimeout;
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

  Stream<String?> _watchAccountId() {
    late final FirebaseAuth auth;
    try {
      auth = _auth;
    } on FirebaseException catch (error) {
      // Widget and model tests can exercise anonymous read paths without
      // booting a Firebase app. In production a default app exists before
      // this service is built; once it does, Auth stream errors remain real
      // errors and continue through the stream below.
      if (_authOverride == null && error.code == 'no-app') {
        return Stream<String?>.value(null);
      }
      rethrow;
    }
    return Stream<String?>.multi((controller) {
      final subscription = auth.authStateChanges().listen(
        (user) => controller.add(user?.uid),
        onError: controller.addError,
      );
      controller.add(auth.currentUser?.uid);
      controller.onCancel = subscription.cancel;
    }).distinct();
  }

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

  Future<void> _mutate(String name, Map<String, Object?> data) async {
    await _invoke(name, data);
  }

  String? _creationPrincipalId() {
    // Call overrides are a unit-test seam and can run without a Firebase app.
    // When Auth is supplied alongside the seam, keep the production account
    // binding enabled so account-switch races remain testable.
    if (_callOverride != null && _authOverride == null) return null;
    return _auth.currentUser?.uid;
  }

  FirebaseFunctionsException _creationSessionChanged() =>
      FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'The signed-in account changed while creating the server.',
      );

  void _requireCreationPrincipal(String? expectedUserId) {
    if (expectedUserId != null && _creationPrincipalId() != expectedUserId) {
      throw _creationSessionChanged();
    }
  }

  @override
  Future<ServerCreationResult> createServer(
    ServerCreationRequest request,
  ) async {
    final data = request.toCallableData();
    final initialUserId = _creationPrincipalId();
    if ((_callOverride == null || _authOverride != null) &&
        (initialUserId == null || initialUserId.isEmpty)) {
      throw _creationSessionChanged();
    }
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await _invoke(
          'createServerV1',
          data,
        ).timeout(_creationAttemptTimeout);
        _requireCreationPrincipal(initialUserId);
        return ServerCreationResult.fromMap(response);
      } on TimeoutException {
        _requireCreationPrincipal(initialUserId);
        // A timeout can mean the transaction committed but its acknowledgement
        // never reached this device. One automatic replay of the exact same
        // request is safe: createServerV1 is idempotent on requestId and returns
        // the original receipt when the graph already exists.
        if (attempt == 0) {
          continue;
        }
        rethrow;
      } catch (_) {
        // A late refusal belongs to the account that started the attempt. Do
        // not let a replacement session clear that owner's pending request or
        // render the refusal as the replacement user's result.
        _requireCreationPrincipal(initialUserId);
        rethrow;
      }
    }
  }

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
  Future<void> joinServer({
    required String serverId,
    required String requestId,
  }) async {
    _requireId(serverId);
    await _mutate('joinServerV1', {
      'serverId': serverId,
      'requestId': requestId,
    });
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
  Future<void> endChannelSession({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(channelId);
    _requireId(sessionId);
    await _mutate('endServerChannelSessionV1', {
      'serverId': serverId,
      'channelId': channelId,
      'sessionId': sessionId,
      'requestId': requestId,
    });
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

  @override
  Future<ServerSessionParticipationResult> setSessionParticipantRole({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String participantId,
    required String role,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(channelId);
    _requireId(sessionId);
    _requireId(participantId);
    if (role != 'guest' && role != 'listener') {
      throw ArgumentError.value(role, 'role', 'Must be guest or listener.');
    }
    final result = ServerSessionParticipationResult.fromMap(
      await _invoke('setServerSessionParticipantRoleV1', {
        'serverId': serverId,
        'channelId': channelId,
        'sessionId': sessionId,
        'participantId': participantId,
        'role': role,
        'requestId': requestId,
      }),
    );
    if (!result.matches(
          expectedServerId: serverId,
          expectedChannelId: channelId,
          expectedSessionId: sessionId,
          expectedParticipantId: participantId,
        ) ||
        result.role != role ||
        result.requestedMuted != null) {
      throw const FormatException('Mismatched participant role receipt.');
    }
    return result;
  }

  @override
  Future<ServerSessionParticipationResult> setSessionParticipantMute({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String participantId,
    required bool muted,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(channelId);
    _requireId(sessionId);
    _requireId(participantId);
    final result = ServerSessionParticipationResult.fromMap(
      await _invoke('setServerSessionMuteV1', {
        'serverId': serverId,
        'channelId': channelId,
        'sessionId': sessionId,
        'participantId': participantId,
        'muted': muted,
        'requestId': requestId,
      }),
    );
    if (!result.matches(
          expectedServerId: serverId,
          expectedChannelId: channelId,
          expectedSessionId: sessionId,
          expectedParticipantId: participantId,
        ) ||
        result.requestedMuted != muted) {
      throw const FormatException('Mismatched participant mute receipt.');
    }
    return result;
  }

  /// The roles `capabilitiesFor` grants `moderate` to. Anything else — an
  /// unknown value, a member, a guest — carries no badge.
  static const _moderatorRoles = <String>[
    'owner',
    'coOwner',
    'admin',
    'moderator',
  ];

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
                    .map((doc) => serverString(doc.data()['userId']) ?? doc.id)
                    .toSet(),
              ),
        ).map((value) => value ?? const <String>{});
      });
    });
  }

  @override
  Stream<List<ServerEvent>> watchEvents(String serverId, String channelId) {
    _requireId(serverId);
    _requireId(channelId);
    return _firestore
        .collection('clubs')
        .doc(serverId)
        .collection('channels')
        .doc(channelId)
        .collection('events')
        .where('status', isEqualTo: 'scheduled')
        .where('endsAt', isGreaterThan: Timestamp.fromDate(_now().toUtc()))
        .orderBy('endsAt')
        .snapshots()
        .map((snapshot) {
          final events = <ServerEvent>[];
          for (final document in snapshot.docs) {
            try {
              events.add(
                ServerEvent.fromFirestore(
                  document,
                  serverId: serverId,
                  channelId: channelId,
                ),
              );
            } on FormatException {
              continue;
            }
          }
          final now = _now().toUtc();
          events.removeWhere((event) => !event.endsAt.isAfter(now));
          events.sort((first, second) {
            final starts = first.startsAt.compareTo(second.startsAt);
            return starts != 0 ? starts : first.id.compareTo(second.id);
          });
          return List<ServerEvent>.unmodifiable(events);
        });
  }

  @override
  Stream<ServerEventAttendance?> watchMyEventResponse(
    String serverId,
    String channelId,
    String eventId,
  ) {
    _requireId(serverId);
    _requireId(channelId);
    _requireId(eventId);
    return _switchMap(_watchAccountId(), (uid) {
      if (uid == null) return Stream.value(null);
      return _firestore
          .collection('clubs')
          .doc(serverId)
          .collection('channels')
          .doc(channelId)
          .collection('events')
          .doc(eventId)
          .collection('responses')
          .doc(uid)
          .snapshots()
          .map((document) {
            if (!document.exists) return null;
            final data = document.data();
            final response = switch (data?['response']) {
              'going' => ServerEventResponse.going,
              'maybe' => ServerEventResponse.maybe,
              'declined' => ServerEventResponse.declined,
              _ => null,
            };
            if (data == null ||
                data['schemaVersion'] != 1 ||
                data['serverId'] != serverId ||
                data['channelId'] != channelId ||
                data['eventId'] != eventId ||
                data['userId'] != uid ||
                response == null ||
                data['reminderRequested'] is! bool ||
                data['eventRevision'] is! int ||
                (data['eventRevision'] as int) < 1 ||
                serverString(data['operationId']) == null ||
                data['createdAt'] is! Timestamp ||
                data['updatedAt'] is! Timestamp) {
              throw const FormatException('Unsupported server event response.');
            }
            return ServerEventAttendance(
              response: response,
              reminderRequested: data['reminderRequested'] as bool,
            );
          });
    });
  }

  @override
  Future<void> createEvent({
    required String serverId,
    required String channelId,
    required String title,
    required String description,
    required DateTime startsAt,
    required DateTime endsAt,
    required String timeZone,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(channelId);
    await _mutate('createServerEventV1', {
      'serverId': serverId,
      'channelId': channelId,
      'requestId': requestId,
      'title': title,
      'description': description,
      'startsAtMillis': startsAt.millisecondsSinceEpoch,
      'endsAtMillis': endsAt.millisecondsSinceEpoch,
      'timeZone': timeZone,
    });
  }

  @override
  Future<void> updateEvent({
    required ServerEvent event,
    required String title,
    required String description,
    required DateTime startsAt,
    required DateTime endsAt,
    required String timeZone,
    required String requestId,
  }) async {
    await _mutate('updateServerEventV1', {
      'serverId': event.serverId,
      'channelId': event.channelId,
      'eventId': event.id,
      'requestId': requestId,
      'expectedRevision': event.revision,
      'patch': {
        'title': title,
        'description': description,
        'startsAtMillis': startsAt.millisecondsSinceEpoch,
        'endsAtMillis': endsAt.millisecondsSinceEpoch,
        'timeZone': timeZone,
      },
    });
  }

  @override
  Future<void> cancelEvent({
    required ServerEvent event,
    required String requestId,
  }) async {
    await _mutate('cancelServerEventV1', {
      'serverId': event.serverId,
      'channelId': event.channelId,
      'eventId': event.id,
      'requestId': requestId,
      'expectedRevision': event.revision,
    });
  }

  @override
  Future<void> respondToEvent({
    required ServerEvent event,
    required ServerEventResponse response,
    required String requestId,
    bool? reminderRequested,
  }) async {
    await _mutate('respondToServerEventV1', {
      'serverId': event.serverId,
      'channelId': event.channelId,
      'eventId': event.id,
      'requestId': requestId,
      'expectedRevision': event.revision,
      'response': response.name,
      'reminderRequested': ?reminderRequested,
    });
  }

  @override
  Stream<ServerPodcastRecordingState?> watchPodcastRecording(
    String serverId,
    String studioChannelId,
  ) {
    _requireId(serverId);
    _requireId(studioChannelId);
    return _firestore
        .collection('clubs')
        .doc(serverId)
        .collection('channels')
        .doc(studioChannelId)
        .collection('podcastRecordingState')
        .doc('main')
        .snapshots()
        .map(
          (document) => document.exists
              ? ServerPodcastRecordingState.fromFirestore(
                  document,
                  serverId: serverId,
                  studioChannelId: studioChannelId,
                )
              : null,
        );
  }

  @override
  Stream<List<ServerPodcastEpisode>> watchPodcastEpisodes(
    String serverId,
    String channelId, {
    required bool canModerate,
  }) {
    _requireId(serverId);
    _requireId(channelId);
    Query<Map<String, dynamic>> query = _firestore
        .collection('clubs')
        .doc(serverId)
        .collection('channels')
        .doc(channelId)
        .collection('episodes');
    query = canModerate
        ? query.orderBy('createdAt', descending: true)
        : query
              .where('status', isEqualTo: 'published')
              .orderBy('publishedAt', descending: true);
    return query.limit(100).snapshots().map((snapshot) {
      final episodes = <ServerPodcastEpisode>[];
      for (final document in snapshot.docs) {
        try {
          episodes.add(
            ServerPodcastEpisode.fromFirestore(
              document,
              serverId: serverId,
              channelId: channelId,
            ),
          );
        } on FormatException {
          // One future or corrupt row cannot fabricate a playable episode.
          // Omit it while the rest of this authorized channel remains usable.
        }
      }
      return List<ServerPodcastEpisode>.unmodifiable(episodes);
    });
  }

  @override
  Future<ServerPodcastEpisodeReceipt> startPodcastRecording({
    required String serverId,
    required String channelId,
    required String studioChannelId,
    required String sessionId,
    required String title,
    required String requestId,
  }) async => ServerPodcastEpisodeReceipt.fromMap(
    await _invoke('startServerPodcastRecordingV1', {
      'serverId': serverId,
      'channelId': channelId,
      'studioChannelId': studioChannelId,
      'sessionId': sessionId,
      'title': title,
      'requestId': requestId,
    }),
  );

  Map<String, Object?> _podcastEpisodeMutation(
    ServerPodcastEpisode episode,
    String requestId,
  ) => {
    'serverId': episode.serverId,
    'channelId': episode.channelId,
    'studioChannelId': episode.studioChannelId,
    'episodeId': episode.id,
    'expectedRevision': episode.revision,
    'requestId': requestId,
  };

  @override
  Future<ServerPodcastEpisodeReceipt> stopPodcastRecording({
    required ServerPodcastRecordingState recording,
    required String requestId,
  }) async => ServerPodcastEpisodeReceipt.fromMap(
    await _invoke('stopServerPodcastRecordingV1', {
      'serverId': recording.serverId,
      'channelId': recording.channelId,
      'studioChannelId': recording.studioChannelId,
      'episodeId': recording.episodeId,
      'expectedRevision': recording.episodeRevision,
      'requestId': requestId,
    }),
  );

  @override
  Future<ServerPodcastEpisodeReceipt> finalizePodcastEpisode({
    required ServerPodcastEpisode episode,
    required String requestId,
  }) async => ServerPodcastEpisodeReceipt.fromMap(
    await _invoke(
      'finalizeServerPodcastEpisodeV1',
      _podcastEpisodeMutation(episode, requestId),
    ),
  );

  @override
  Future<ServerPodcastEpisodeReceipt> retryPodcastRecording({
    required ServerPodcastEpisode episode,
    required String requestId,
  }) async => ServerPodcastEpisodeReceipt.fromMap(
    await _invoke(
      'retryServerPodcastRecordingV1',
      _podcastEpisodeMutation(episode, requestId),
    ),
  );

  @override
  Future<ServerPodcastEpisodeReceipt> publishPodcastEpisode({
    required ServerPodcastEpisode episode,
    required String requestId,
  }) async => ServerPodcastEpisodeReceipt.fromMap(
    await _invoke(
      'publishServerPodcastEpisodeV1',
      _podcastEpisodeMutation(episode, requestId),
    ),
  );

  @override
  Future<ServerPodcastEpisodeAccess> getPodcastEpisodeAccess({
    required ServerPodcastEpisode episode,
  }) async => ServerPodcastEpisodeAccess.fromMap(
    await _invoke('getServerPodcastEpisodeAccessV1', {
      'serverId': episode.serverId,
      'channelId': episode.channelId,
      'episodeId': episode.id,
    }),
  );

  @override
  Stream<List<ServerPodcastQuestion>> watchPodcastQuestions(
    String serverId,
    String channelId,
  ) {
    _requireId(serverId);
    _requireId(channelId);
    return _firestore
        .collection('clubs')
        .doc(serverId)
        .collection('channels')
        .doc(channelId)
        .collection('questions')
        .where('status', whereIn: const ['queued', 'onAir'])
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          final questions = <ServerPodcastQuestion>[];
          for (final document in snapshot.docs) {
            try {
              questions.add(
                ServerPodcastQuestion.fromFirestore(
                  document,
                  serverId: serverId,
                  channelId: channelId,
                ),
              );
            } on FormatException {
              continue;
            }
          }
          questions.sort((first, second) {
            if (first.isOnAir != second.isOnAir) {
              return first.isOnAir ? -1 : 1;
            }
            final votes = second.voteCount.compareTo(first.voteCount);
            if (votes != 0) return votes;
            final created = first.createdAt.compareTo(second.createdAt);
            return created != 0 ? created : first.id.compareTo(second.id);
          });
          return List<ServerPodcastQuestion>.unmodifiable(questions);
        });
  }

  @override
  Stream<bool> watchMyPodcastQuestionVote(
    String serverId,
    String channelId,
    String questionId,
  ) {
    _requireId(serverId);
    _requireId(channelId);
    _requireId(questionId);
    return _switchMap(_watchAccountId(), (uid) {
      if (uid == null) return Stream.value(false);
      return _firestore
          .collection('clubs')
          .doc(serverId)
          .collection('channels')
          .doc(channelId)
          .collection('questions')
          .doc(questionId)
          .collection('votes')
          .doc(uid)
          .snapshots()
          .map((document) {
            if (!document.exists) return false;
            final data = document.data();
            if (data == null ||
                data['schemaVersion'] != 1 ||
                data['serverId'] != serverId ||
                data['channelId'] != channelId ||
                data['questionId'] != questionId ||
                data['userId'] != uid ||
                data['active'] is! bool ||
                data['questionRevision'] is! int ||
                (data['questionRevision'] as int) < 1) {
              throw const FormatException('Unsupported podcast question vote.');
            }
            return data['active'] as bool;
          });
    });
  }

  @override
  Future<void> createPodcastQuestion({
    required String serverId,
    required String channelId,
    required String body,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(channelId);
    await _mutate('createServerPodcastQuestionV1', {
      'serverId': serverId,
      'channelId': channelId,
      'requestId': requestId,
      'body': body,
    });
  }

  @override
  Future<void> setPodcastQuestionVote({
    required ServerPodcastQuestion question,
    required bool voted,
    required String requestId,
  }) async {
    await _mutate('setServerPodcastQuestionVoteV1', {
      'serverId': question.serverId,
      'channelId': question.channelId,
      'questionId': question.id,
      'requestId': requestId,
      'expectedRevision': question.revision,
      'voted': voted,
    });
  }

  @override
  Future<void> setPodcastQuestionOnAir({
    required ServerPodcastQuestion question,
    required bool onAir,
    required String requestId,
  }) async {
    await _mutate('setServerPodcastQuestionOnAirV1', {
      'serverId': question.serverId,
      'channelId': question.channelId,
      'questionId': question.id,
      'requestId': requestId,
      'expectedRevision': question.revision,
      'onAir': onAir,
    });
  }

  @override
  Stream<ServerWhiteboardSnapshot> watchWhiteboard(
    String serverId,
    String channelId,
  ) {
    _requireId(serverId);
    _requireId(channelId);
    final channel = _firestore
        .collection('clubs')
        .doc(serverId)
        .collection('channels')
        .doc(channelId);
    return _switchMap(
      channel.collection('whiteboardState').doc('main').snapshots(),
      (document) {
        final state = document.exists
            ? ServerWhiteboardState.fromFirestore(
                document,
                serverId: serverId,
                channelId: channelId,
              )
            : ServerWhiteboardState.empty(
                serverId: serverId,
                channelId: channelId,
              );
        if (!document.exists) {
          return Stream.value(
            ServerWhiteboardSnapshot(state: state, strokes: const []),
          );
        }
        return channel
            .collection('whiteboardStrokes')
            .where('generation', isEqualTo: state.generation)
            .orderBy('sequence')
            .limit(181)
            .snapshots()
            .map((snapshot) {
              if (snapshot.docs.length > 180) {
                throw const FormatException(
                  'The company whiteboard exceeds its supported size.',
                );
              }
              final strokes = <ServerWhiteboardStroke>[];
              var previousSequence = 0;
              for (final document in snapshot.docs) {
                final stroke = ServerWhiteboardStroke.fromFirestore(
                  document,
                  serverId: serverId,
                  channelId: channelId,
                  generation: state.generation,
                );
                if (stroke.sequence <= previousSequence) {
                  throw const FormatException(
                    'The company whiteboard order is invalid.',
                  );
                }
                previousSequence = stroke.sequence;
                strokes.add(stroke);
              }
              return ServerWhiteboardSnapshot(
                state: state,
                strokes: List.unmodifiable(strokes),
              );
            });
      },
    );
  }

  @override
  Future<void> createWhiteboardStroke({
    required String serverId,
    required String channelId,
    required List<ServerWhiteboardPoint> points,
    required ServerWhiteboardColor color,
    required int lineWidth,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(channelId);
    if (points.length < 2 || points.length > 64) {
      throw ArgumentError.value(points.length, 'points');
    }
    for (final point in points) {
      if (!point.x.isFinite ||
          !point.y.isFinite ||
          point.x < 0 ||
          point.x > 1 ||
          point.y < 0 ||
          point.y > 1) {
        throw ArgumentError.value(point.toMap(), 'points');
      }
    }
    if (lineWidth < 1 || lineWidth > 16) {
      throw ArgumentError.value(lineWidth, 'lineWidth');
    }
    await _mutate('createServerWhiteboardStrokeV1', {
      'serverId': serverId,
      'channelId': channelId,
      'requestId': requestId,
      'points': [for (final point in points) point.toMap()],
      'color': color.name,
      'lineWidth': lineWidth,
    });
  }

  @override
  Future<void> undoWhiteboardStroke({
    required ServerWhiteboardStroke stroke,
    required String requestId,
  }) async {
    _requireId(stroke.serverId);
    _requireId(stroke.channelId);
    _requireId(stroke.id);
    await _mutate('undoServerWhiteboardStrokeV1', {
      'serverId': stroke.serverId,
      'channelId': stroke.channelId,
      'strokeId': stroke.id,
      'requestId': requestId,
      'expectedRevision': stroke.revision,
    });
  }

  @override
  Future<void> clearWhiteboard({
    required String serverId,
    required String channelId,
    required int expectedRevision,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(channelId);
    if (expectedRevision < 0) {
      throw ArgumentError.value(expectedRevision, 'expectedRevision');
    }
    await _mutate('clearServerWhiteboardV1', {
      'serverId': serverId,
      'channelId': channelId,
      'requestId': requestId,
      'expectedRevision': expectedRevision,
    });
  }

  @override
  Stream<List<ServerMember>> watchMembers(String serverId) {
    _requireId(serverId);
    return _dropDenied<List<ServerMember>>(
      _firestore
          .collection('clubs')
          .doc(serverId)
          .collection('members')
          .orderBy('joinedAt')
          .snapshots()
          .map((snapshot) {
            final members = <ServerMember>[];
            for (final document in snapshot.docs) {
              try {
                members.add(ServerMember.fromFirestore(document));
              } on FormatException {
                continue;
              }
            }
            return List<ServerMember>.unmodifiable(members);
          }),
    ).map((members) => members ?? const <ServerMember>[]);
  }

  @override
  Future<void> updateServer({
    required String serverId,
    required int expectedRevision,
    required Map<String, Object?> patch,
    required String requestId,
  }) async {
    _requireId(serverId);
    await _mutate('updateServerV1', {
      'serverId': serverId,
      'requestId': requestId,
      'expectedRevision': expectedRevision,
      'patch': patch,
    });
  }

  @override
  Future<void> updateChannel({
    required String serverId,
    required String channelId,
    required int expectedRevision,
    required Map<String, Object?> patch,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(channelId);
    await _mutate('updateServerChannelV1', {
      'serverId': serverId,
      'channelId': channelId,
      'requestId': requestId,
      'expectedRevision': expectedRevision,
      'patch': patch,
    });
  }

  @override
  Future<void> reorderChannels({
    required String serverId,
    required int expectedRevision,
    required List<String> channelIds,
    required String requestId,
  }) async {
    _requireId(serverId);
    for (final channelId in channelIds) {
      _requireId(channelId);
    }
    await _mutate('reorderServerChannelsV1', {
      'serverId': serverId,
      'requestId': requestId,
      'expectedRevision': expectedRevision,
      'channelIds': List<String>.of(channelIds),
    });
  }

  @override
  Future<void> setChannelAccess({
    required String serverId,
    required String channelId,
    required int expectedAclRevision,
    required ServerChannelAccess access,
    required List<String> roleIds,
    required List<String> userIds,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(channelId);
    await _mutate('setServerChannelAccessV1', {
      'serverId': serverId,
      'channelId': channelId,
      'requestId': requestId,
      'expectedAclRevision': expectedAclRevision,
      'policy': {
        'accessMode': access.name,
        'roleIds': List<String>.of(roleIds),
        'userIds': List<String>.of(userIds),
      },
    });
  }

  Future<void> _channelTermination(
    String name, {
    required String serverId,
    required String channelId,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(channelId);
    await _mutate(name, {
      'serverId': serverId,
      'channelId': channelId,
      'requestId': requestId,
    });
  }

  @override
  Future<void> archiveChannel({
    required String serverId,
    required String channelId,
    required String requestId,
  }) => _channelTermination(
    'archiveServerChannelV1',
    serverId: serverId,
    channelId: channelId,
    requestId: requestId,
  );

  @override
  Future<void> deleteChannel({
    required String serverId,
    required String channelId,
    required String requestId,
  }) => _channelTermination(
    'deleteServerChannelV1',
    serverId: serverId,
    channelId: channelId,
    requestId: requestId,
  );

  @override
  Future<void> revokeInvite({
    required String serverId,
    required String inviteeId,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(inviteeId);
    await _mutate('revokeServerInviteV1', {
      'serverId': serverId,
      'inviteeId': inviteeId,
      'requestId': requestId,
    });
  }

  @override
  Future<void> respondToInvite({
    required String serverId,
    required bool accept,
    required String requestId,
  }) async {
    _requireId(serverId);
    await _mutate('respondToServerInviteV1', {
      'serverId': serverId,
      'requestId': requestId,
      'response': accept ? 'accept' : 'decline',
    });
  }

  @override
  Future<void> leaveServer({
    required String serverId,
    required String requestId,
  }) async {
    _requireId(serverId);
    await _mutate('leaveServerV1', {
      'serverId': serverId,
      'requestId': requestId,
    });
  }

  @override
  Future<void> setMemberRole({
    required String serverId,
    required String memberId,
    required ServerMemberRole role,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(memberId);
    await _mutate('setServerMemberRoleV1', {
      'serverId': serverId,
      'memberId': memberId,
      'requestId': requestId,
      'role': role.name,
    });
  }

  @override
  Future<void> removeMember({
    required String serverId,
    required String memberId,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(memberId);
    await _mutate('removeServerMemberV1', {
      'serverId': serverId,
      'memberId': memberId,
      'requestId': requestId,
    });
  }

  @override
  Future<void> setMemberBan({
    required String serverId,
    required String memberId,
    required bool banned,
    required String reason,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(memberId);
    await _mutate('setServerMemberBanV1', {
      'serverId': serverId,
      'memberId': memberId,
      'requestId': requestId,
      'banned': banned,
      'reason': reason,
    });
  }

  @override
  Future<void> transferOwnership({
    required String serverId,
    required String newOwnerId,
    required String requestId,
  }) async {
    _requireId(serverId);
    _requireId(newOwnerId);
    await _mutate('transferServerOwnershipV1', {
      'serverId': serverId,
      'newOwnerId': newOwnerId,
      'requestId': requestId,
    });
  }

  @override
  Future<void> deleteServer({
    required String serverId,
    required String requestId,
  }) async {
    _requireId(serverId);
    await _mutate('deleteServerV1', {
      'serverId': serverId,
      'requestId': requestId,
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
          ids
              .map((id) => _dropUnreadable(_dropDenied(watchServer(id))))
              .toList(),
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
              .map((snapshot) => _parsedChannels(serverId, snapshot.docs));
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
