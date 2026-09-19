import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/models/family_check_in.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_company_file.dart';
import 'package:yovoice/features/servers/data/models/server_creation.dart';
import 'package:yovoice/features/servers/data/models/server_event.dart';
import 'package:yovoice/features/servers/data/models/server_family_memory.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_member.dart';
import 'package:yovoice/features/servers/data/models/server_list_item.dart';
import 'package:yovoice/features/servers/data/models/server_podcast_episode.dart';
import 'package:yovoice/features/servers/data/models/server_podcast_question.dart';
import 'package:yovoice/features/servers/data/models/server_session.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/models/server_whiteboard.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/data/services/server_company_file_service.dart';
import 'package:yovoice/features/servers/data/services/server_family_check_in_service.dart';
import 'package:yovoice/features/servers/data/services/server_family_memory_service.dart';
import 'package:yovoice/features/servers/data/services/server_follow_service.dart';
import 'package:yovoice/features/servers/data/services/server_podcast_episode_repository.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/data/services/server_shared_list_service.dart';
import 'package:yovoice/features/servers/data/services/server_voice_device.dart';
import 'package:yovoice/features/servers/data/services/server_whiteboard_repository.dart';

ServerPodcastEpisodeReceipt _podcastReceipt({
  required String serverId,
  required String channelId,
  required String studioChannelId,
  required String episodeId,
  required String sessionId,
  required ServerPodcastEpisodeStatus status,
  required ServerPodcastProviderStatus providerStatus,
  required int revision,
}) => ServerPodcastEpisodeReceipt(
  serverId: serverId,
  channelId: channelId,
  studioChannelId: studioChannelId,
  episodeId: episodeId,
  sessionId: sessionId,
  status: status,
  providerStatus: providerStatus,
  revision: revision,
);

class TestServerRepository
    implements
        ServerRepository,
        ServerManagementRepository,
        ServerEventsRepository,
        ServerPodcastEpisodeRepository,
        ServerPodcastQuestionsRepository,
        ServerFamilyCheckInRepository,
        ServerFamilyMemoryRepository,
        ServerSharedListRepository,
        ServerFollowRepository,
        ServerWhiteboardRepository,
        ServerCompanyFileRepository {
  final requests = <ServerCreationRequest>[];
  Completer<ServerCreationResult>? pending;
  bool failNext = false;

  /// Thrown on every attempt, for failures that do not clear by retrying —
  /// an unregistered callable being the one this stage cares about.
  Object? alwaysFailWith;
  int allocated = 0;
  List<Server> servers = [];
  List<ServerChannel> channels = [];
  List<ServerMember> members = const [];
  List<ServerEvent> events = const [];
  final eventResponses = <String, ServerEventAttendance>{};
  List<ServerListItem> listItems = const [];
  List<FamilyCheckIn> familyCheckIns = const [];
  List<ServerFamilyMemory> familyMemories = const [];
  Stream<List<ServerFamilyMemory>>? familyMemoriesStream;
  ServerFamilyMemoryMediaAccess? familyMemoryAccess;
  ServerFamilyMemoryPublishAttempt? familyMemoryPublishAttempt;
  int familyMemoryRequests = 0;
  int familyMemoryPublishes = 0;
  bool followsCommunity = false;
  List<ServerPodcastQuestion> podcastQuestions = const [];
  final podcastQuestionVotes = <String, bool>{};
  List<ServerPodcastEpisode> podcastEpisodes = const [];
  ServerPodcastRecordingState? podcastRecording;
  Stream<ServerPodcastRecordingState?>? podcastRecordingStream;
  Stream<List<ServerPodcastEpisode>>? podcastEpisodesStream;
  ServerWhiteboardSnapshot? whiteboardSnapshot;
  List<ServerCompanyFile> companyFiles = const [];
  Stream<List<ServerCompanyFile>>? companyFilesStream;
  int companyFileUploads = 0;
  Stream<Server?>? serverStream;
  Stream<List<ServerChannel>>? channelStream;
  int watchChannelsCalls = 0;
  Stream<List<ServerMember>>? memberStream;

  /// The viewer's own role row; the owner by default, as the fixtures'
  /// `ownerId` says.
  ServerMemberRole? myRole = ServerMemberRole.owner;
  Stream<ServerMemberRole?>? roleStream;
  List<ServerInviteCandidate> friends = const [];

  /// Every shell callable the fake answered, in order: `[name, payload]`.
  final calls = <(String, Map<String, Object?>)>[];

  /// Thrown by the next shell callable of that name, once.
  final failNextCall = <String, Object>{};
  ServerInviteResult? inviteResult;
  int allocatedChannels = 0;

  /// The role the token receipt carries for this generation. `host` is what
  /// the starter of a session gets; a stage's audience gets `listener`.
  String sessionRole = 'host';

  /// The track sources the grant permits, exactly as `deriveSessionGrant`
  /// reports them.
  List<String> permittedTrackSources = const ['microphone'];

  /// In-memory stand-in for the durable pending-creation store, scoped by
  /// owner and template exactly as the SharedPreferences store scopes it.
  final pendingCreations = <String, ServerCreationRequest>{};

  /// Makes every store call throw, to prove the store is a safety net and
  /// never a gate in front of creating a server.
  bool failPendingStore = false;
  @override
  String get currentUserId => 'owner';
  @override
  String newRequestId() => 'request-${++allocated}';
  String _scope(ServerType type) => '$currentUserId/${type.name}';
  @override
  Future<ServerCreationRequest?> pendingCreation(ServerType type) async {
    if (failPendingStore) throw StateError('store unavailable');
    return pendingCreations[_scope(type)];
  }

  @override
  Future<ServerCreationRequest> rememberPendingCreation(
    ServerCreationRequest request,
  ) async {
    if (failPendingStore) throw StateError('store unavailable');
    return pendingCreations.putIfAbsent(
      _scope(request.serverType),
      () => request,
    );
  }

  @override
  Future<void> forgetPendingCreation(ServerCreationRequest request) async {
    if (failPendingStore) throw StateError('store unavailable');
    final scope = _scope(request.serverType);
    if (pendingCreations[scope]?.requestId == request.requestId) {
      pendingCreations.remove(scope);
    }
  }

  @override
  Future<ServerCreationResult> createServer(
    ServerCreationRequest request,
  ) async {
    requests.add(request);
    final persistent = alwaysFailWith;
    if (persistent != null) throw persistent;
    if (failNext) {
      failNext = false;
      throw FirebaseFunctionsException(code: 'unavailable', message: 'Offline');
    }
    return pending?.future ??
        const ServerCreationResult(
          serverId: 'saved',
          defaultChannelId: 'general',
          channelIds: ['general'],
          alreadyExisted: false,
        );
  }

  @override
  Stream<List<Server>> watchMyServers() => Stream.value(servers);
  @override
  Stream<Server?> watchServer(String serverId) =>
      serverStream ??
      Stream.value(
        servers.where((server) => server.id == serverId).firstOrNull,
      );
  @override
  Stream<List<ServerChannel>> watchChannels(String serverId) {
    watchChannelsCalls++;
    return channelStream ??
        Stream.value(
          channels.where((channel) => channel.serverId == serverId).toList(),
        );
  }

  @override
  Stream<List<ServerMember>> watchMembers(String serverId) =>
      memberStream ?? Stream.value(members);

  @override
  Stream<List<ServerEvent>> watchEvents(String serverId, String channelId) =>
      Stream.value(
        events
            .where(
              (event) =>
                  event.serverId == serverId && event.channelId == channelId,
            )
            .toList(),
      );

  @override
  Stream<ServerEventAttendance?> watchMyEventResponse(
    String serverId,
    String channelId,
    String eventId,
  ) => Stream.value(eventResponses[eventId]);

  @override
  Stream<List<ServerPodcastQuestion>> watchPodcastQuestions(
    String serverId,
    String channelId,
  ) => Stream.value(
    podcastQuestions
        .where(
          (question) =>
              question.serverId == serverId && question.channelId == channelId,
        )
        .toList(),
  );

  @override
  Stream<bool> watchMyPodcastQuestionVote(
    String serverId,
    String channelId,
    String questionId,
  ) => Stream.value(podcastQuestionVotes[questionId] ?? false);

  @override
  Stream<ServerMemberRole?> watchMyRole(String serverId) =>
      roleStream ?? Stream.value(myRole);

  /// The ids the fake roster returns with moderator power or above.
  Set<String> moderators = const {};
  Stream<Set<String>>? moderatorStream;

  @override
  Stream<Set<String>> watchModerators(String serverId) =>
      moderatorStream ?? Stream.value(moderators);

  /// The answer `setServerSessionHandV1` gives, or null for the plain
  /// "the hand is now where you asked" receipt.
  ServerSessionHandResult? handResult;
  ServerSessionParticipationResult? participationResult;

  @override
  Future<ServerSessionHandResult> setSessionHand({
    required String serverId,
    required String channelId,
    required String sessionId,
    required bool raised,
    required String requestId,
  }) => _answer(
    'setServerSessionHandV1',
    {
      'serverId': serverId,
      'channelId': channelId,
      'sessionId': sessionId,
      'requestId': requestId,
      'raised': raised,
    },
    () =>
        handResult ??
        ServerSessionHandResult(
          sessionId: sessionId,
          raised: raised,
          changed: true,
          sessionRole: 'listener',
        ),
  );

  @override
  Future<ServerSessionParticipationResult> setSessionParticipantRole({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String participantId,
    required String role,
    required String requestId,
  }) => _answer(
    'setServerSessionParticipantRoleV1',
    {
      'serverId': serverId,
      'channelId': channelId,
      'sessionId': sessionId,
      'participantId': participantId,
      'role': role,
      'requestId': requestId,
    },
    () =>
        participationResult ??
        ServerSessionParticipationResult(
          serverId: serverId,
          channelId: channelId,
          sessionId: sessionId,
          participantId: participantId,
          role: role,
          hostMuted: false,
          serverMuted: false,
          participantRevision: 2,
          changed: true,
          cleanupPending: true,
        ),
  );

  @override
  Future<ServerSessionParticipationResult> setSessionParticipantMute({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String participantId,
    required bool muted,
    required String requestId,
  }) => _answer(
    'setServerSessionMuteV1',
    {
      'serverId': serverId,
      'channelId': channelId,
      'sessionId': sessionId,
      'participantId': participantId,
      'muted': muted,
      'requestId': requestId,
    },
    () =>
        participationResult ??
        ServerSessionParticipationResult(
          serverId: serverId,
          channelId: channelId,
          sessionId: sessionId,
          participantId: participantId,
          role: 'guest',
          hostMuted: muted,
          serverMuted: false,
          participantRevision: 2,
          changed: true,
          cleanupPending: true,
          requestedMuted: muted,
        ),
  );

  @override
  Stream<List<ServerInviteCandidate>> watchInviteCandidates() =>
      Stream.value(friends);

  Future<T> _answer<T>(
    String name,
    Map<String, Object?> payload,
    T Function() result,
  ) async {
    calls.add((name, payload));
    final failure = failNextCall.remove(name);
    if (failure != null) throw failure;
    return result();
  }

  @override
  Future<ServerInviteResult> createInvite({
    required String serverId,
    required String inviteeId,
    required String requestId,
  }) => _answer(
    'createServerInviteV1',
    {'serverId': serverId, 'inviteeId': inviteeId, 'requestId': requestId},
    () =>
        inviteResult ??
        ServerInviteResult(
          serverId: serverId,
          inviteeId: inviteeId,
          generation: 1,
          status: 'pending',
          alreadyExisted: false,
        ),
  );

  @override
  Future<void> joinServer({
    required String serverId,
    required String requestId,
  }) => _answer<void>('joinServerV1', {
    'serverId': serverId,
    'requestId': requestId,
  }, () => myRole = ServerMemberRole.member);

  @override
  Future<void> updateServer({
    required String serverId,
    required int expectedRevision,
    required Map<String, Object?> patch,
    required String requestId,
  }) => _answer<void>('updateServerV1', {
    'serverId': serverId,
    'requestId': requestId,
    'expectedRevision': expectedRevision,
    'patch': patch,
  }, () {});

  @override
  Future<void> updateChannel({
    required String serverId,
    required String channelId,
    required int expectedRevision,
    required Map<String, Object?> patch,
    required String requestId,
  }) => _answer<void>('updateServerChannelV1', {
    'serverId': serverId,
    'channelId': channelId,
    'requestId': requestId,
    'expectedRevision': expectedRevision,
    'patch': patch,
  }, () {});

  @override
  Future<void> reorderChannels({
    required String serverId,
    required int expectedRevision,
    required List<String> channelIds,
    required String requestId,
  }) => _answer<void>('reorderServerChannelsV1', {
    'serverId': serverId,
    'requestId': requestId,
    'expectedRevision': expectedRevision,
    'channelIds': channelIds,
  }, () {});

  @override
  Future<void> setChannelAccess({
    required String serverId,
    required String channelId,
    required int expectedAclRevision,
    required ServerChannelAccess access,
    required List<String> roleIds,
    required List<String> userIds,
    required String requestId,
  }) => _answer<void>('setServerChannelAccessV1', {
    'serverId': serverId,
    'channelId': channelId,
    'requestId': requestId,
    'expectedAclRevision': expectedAclRevision,
    'policy': {
      'accessMode': access.name,
      'roleIds': roleIds,
      'userIds': userIds,
    },
  }, () {});

  Future<void> _terminateChannel(
    String name, {
    required String serverId,
    required String channelId,
    required String requestId,
  }) => _answer<void>(name, {
    'serverId': serverId,
    'channelId': channelId,
    'requestId': requestId,
  }, () {});

  @override
  Future<void> archiveChannel({
    required String serverId,
    required String channelId,
    required String requestId,
  }) => _terminateChannel(
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
  }) => _terminateChannel(
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
  }) => _answer<void>('revokeServerInviteV1', {
    'serverId': serverId,
    'inviteeId': inviteeId,
    'requestId': requestId,
  }, () {});

  @override
  Future<void> respondToInvite({
    required String serverId,
    required bool accept,
    required String requestId,
  }) => _answer<void>('respondToServerInviteV1', {
    'serverId': serverId,
    'requestId': requestId,
    'response': accept ? 'accept' : 'decline',
  }, () {});

  @override
  Future<void> leaveServer({
    required String serverId,
    required String requestId,
  }) => _answer<void>('leaveServerV1', {
    'serverId': serverId,
    'requestId': requestId,
  }, () {});

  @override
  Future<void> setMemberRole({
    required String serverId,
    required String memberId,
    required ServerMemberRole role,
    required String requestId,
  }) => _answer<void>('setServerMemberRoleV1', {
    'serverId': serverId,
    'memberId': memberId,
    'requestId': requestId,
    'role': role.name,
  }, () {});

  @override
  Future<void> removeMember({
    required String serverId,
    required String memberId,
    required String requestId,
  }) => _answer<void>('removeServerMemberV1', {
    'serverId': serverId,
    'memberId': memberId,
    'requestId': requestId,
  }, () {});

  @override
  Future<void> setMemberBan({
    required String serverId,
    required String memberId,
    required bool banned,
    required String reason,
    required String requestId,
  }) => _answer<void>('setServerMemberBanV1', {
    'serverId': serverId,
    'memberId': memberId,
    'requestId': requestId,
    'banned': banned,
    'reason': reason,
  }, () {});

  @override
  Future<void> transferOwnership({
    required String serverId,
    required String newOwnerId,
    required String requestId,
  }) => _answer<void>('transferServerOwnershipV1', {
    'serverId': serverId,
    'newOwnerId': newOwnerId,
    'requestId': requestId,
  }, () {});

  @override
  Future<void> deleteServer({
    required String serverId,
    required String requestId,
  }) => _answer<void>('deleteServerV1', {
    'serverId': serverId,
    'requestId': requestId,
  }, () {});

  @override
  Future<ServerChannelCreationResult> createChannel(
    ServerChannelCreationRequest request,
  ) => _answer(
    'createServerChannelV1',
    request.toCallableData(),
    () => ServerChannelCreationResult(
      serverId: request.serverId,
      channelId: 'created-${++allocatedChannels}',
    ),
  );

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
  }) => _answer<void>('createServerEventV1', {
    'serverId': serverId,
    'channelId': channelId,
    'requestId': requestId,
    'title': title,
    'description': description,
    'startsAtMillis': startsAt.millisecondsSinceEpoch,
    'endsAtMillis': endsAt.millisecondsSinceEpoch,
    'timeZone': timeZone,
  }, () {});

  @override
  Future<void> updateEvent({
    required ServerEvent event,
    required String title,
    required String description,
    required DateTime startsAt,
    required DateTime endsAt,
    required String timeZone,
    required String requestId,
  }) => _answer<void>('updateServerEventV1', {
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
  }, () {});

  @override
  Future<void> cancelEvent({
    required ServerEvent event,
    required String requestId,
  }) => _answer<void>('cancelServerEventV1', {
    'serverId': event.serverId,
    'channelId': event.channelId,
    'eventId': event.id,
    'requestId': requestId,
    'expectedRevision': event.revision,
  }, () {});

  @override
  Future<void> respondToEvent({
    required ServerEvent event,
    required ServerEventResponse response,
    required String requestId,
    bool? reminderRequested,
  }) => _answer<void>(
    'respondToServerEventV1',
    {
      'serverId': event.serverId,
      'channelId': event.channelId,
      'eventId': event.id,
      'requestId': requestId,
      'expectedRevision': event.revision,
      'response': response.name,
      'reminderRequested': ?reminderRequested,
    },
    () {
      eventResponses[event.id] = ServerEventAttendance(
        response: response,
        reminderRequested: reminderRequested ?? false,
      );
    },
  );

  @override
  Stream<List<ServerListItem>> watchItems(String serverId, String channelId) =>
      Stream.value(
        listItems
            .where(
              (item) =>
                  item.serverId == serverId && item.channelId == channelId,
            )
            .toList(growable: false),
      );

  @override
  Future<void> createItem({
    required String serverId,
    required String channelId,
    required String text,
    required String requestId,
  }) => _answer<void>('createServerListItemV1', {
    'serverId': serverId,
    'channelId': channelId,
    'requestId': requestId,
    'text': text,
  }, () {});

  @override
  Future<void> updateItem({
    required ServerListItem item,
    required Map<String, Object?> patch,
    required String requestId,
  }) => _answer<void>('updateServerListItemV1', {
    'serverId': item.serverId,
    'channelId': item.channelId,
    'itemId': item.id,
    'requestId': requestId,
    'expectedRevision': item.revision,
    'patch': patch,
  }, () {});

  @override
  Future<void> deleteItem({
    required ServerListItem item,
    required String requestId,
  }) => _answer<void>('deleteServerListItemV1', {
    'serverId': item.serverId,
    'channelId': item.channelId,
    'itemId': item.id,
    'requestId': requestId,
    'expectedRevision': item.revision,
  }, () {});

  @override
  Stream<List<FamilyCheckIn>> watchCheckIns(
    String serverId, {
    int limit = 20,
  }) => Stream.value(familyCheckIns.take(limit).toList(growable: false));

  @override
  Future<void> postCheckIn({
    required String serverId,
    required FamilyCheckInStatus status,
  }) => _answer<void>('createServerFamilyCheckInV1', {
    'serverId': serverId,
    'requestId': newRequestId(),
    'status': status.value,
  }, () {});

  @override
  Future<void> deleteCheckIn({
    required String serverId,
    required String checkInId,
  }) => _answer<void>('deleteServerFamilyCheckInV1', {
    'serverId': serverId,
    'checkInId': checkInId,
    'requestId': newRequestId(),
  }, () {});

  @override
  String newFamilyMemoryRequestId() =>
      'family_memory_${++familyMemoryRequests}';

  @override
  Stream<List<ServerFamilyMemory>> watchFamilyMemories(
    String serverId,
    String channelId,
  ) =>
      familyMemoriesStream ??
      Stream.value(
        familyMemories
            .where(
              (memory) =>
                  memory.serverId == serverId && memory.channelId == channelId,
            )
            .toList(growable: false),
      );

  @override
  ServerFamilyMemoryPublishAttempt newFamilyMemoryPublishAttempt({
    required String serverId,
    required String channelId,
    required String caption,
    required Uint8List photoBytes,
    required String photoContentType,
    required RecordedAudio voice,
    required int voiceDurationMs,
  }) => familyMemoryPublishAttempt = ServerFamilyMemoryPublishAttempt(
    serverId: serverId,
    channelId: channelId,
    caption: caption.trim(),
    photoBytes: photoBytes,
    photoContentType: photoContentType,
    voice: voice,
    voiceDurationMs: voiceDurationMs,
    reserveRequestId: newFamilyMemoryRequestId(),
    finalizeRequestId: newFamilyMemoryRequestId(),
  );

  @override
  Future<String> publishFamilyMemory(
    ServerFamilyMemoryPublishAttempt attempt,
  ) async {
    familyMemoryPublishes += 1;
    return attempt.reservation?.memoryId ?? 'family-memory-published';
  }

  @override
  Future<ServerFamilyMemoryMediaAccess> getFamilyMemoryMediaAccess({
    required String serverId,
    required String channelId,
    required String memoryId,
  }) => _answer<ServerFamilyMemoryMediaAccess>(
    'getServerFamilyMemoryMediaAccessV1',
    {'serverId': serverId, 'channelId': channelId, 'memoryId': memoryId},
    () =>
        familyMemoryAccess ??
        ServerFamilyMemoryMediaAccess(
          serverId: serverId,
          channelId: channelId,
          memoryId: memoryId,
          expiresAt: DateTime.now().add(const Duration(seconds: 90)),
          photo: ServerFamilyMemoryMediaAsset(
            url: Uri.parse(
              'https://media.example/$memoryId.jpg?signature=photo',
            ),
            generation: '1700000000000001',
            contentType: 'image/jpeg',
            size: 2048,
          ),
          voice: ServerFamilyMemoryMediaAsset(
            url: Uri.parse(
              'https://media.example/$memoryId.m4a?signature=voice',
            ),
            generation: '1700000000000002',
            contentType: 'audio/mp4',
            size: 4096,
            durationMs: 4200,
          ),
        ),
  );

  @override
  Future<void> deleteFamilyMemory({
    required String serverId,
    required String channelId,
    required String memoryId,
    required int expectedRevision,
    required String requestId,
  }) => _answer<void>('deleteServerFamilyMemoryV1', {
    'serverId': serverId,
    'channelId': channelId,
    'memoryId': memoryId,
    'expectedRevision': expectedRevision,
    'requestId': requestId,
  }, () {});

  @override
  Stream<bool> watchCommunityFollow(String serverId) =>
      Stream.value(followsCommunity);

  @override
  Future<bool> setCommunityFollow({
    required String serverId,
    required bool following,
  }) => _answer<bool>('setCommunityServerFollowV1', {
    'serverId': serverId,
    'following': following,
  }, () => followsCommunity = following);

  @override
  Stream<ServerPodcastRecordingState?> watchPodcastRecording(
    String serverId,
    String studioChannelId,
  ) => podcastRecordingStream ?? Stream.value(podcastRecording);

  @override
  Stream<List<ServerPodcastEpisode>> watchPodcastEpisodes(
    String serverId,
    String channelId, {
    required bool canModerate,
  }) =>
      podcastEpisodesStream ??
      Stream.value(
        podcastEpisodes
            .where(
              (episode) =>
                  episode.serverId == serverId &&
                  episode.channelId == channelId &&
                  (canModerate ||
                      episode.status == ServerPodcastEpisodeStatus.published),
            )
            .toList(growable: false),
      );

  @override
  Future<ServerPodcastEpisodeReceipt> startPodcastRecording({
    required String serverId,
    required String channelId,
    required String studioChannelId,
    required String sessionId,
    required String title,
    required String requestId,
  }) => _answer<ServerPodcastEpisodeReceipt>(
    'startServerPodcastRecordingV1',
    {
      'serverId': serverId,
      'channelId': channelId,
      'studioChannelId': studioChannelId,
      'sessionId': sessionId,
      'title': title,
      'requestId': requestId,
    },
    () => ServerPodcastEpisodeReceipt(
      serverId: serverId,
      channelId: channelId,
      studioChannelId: studioChannelId,
      episodeId: 'episode-1',
      sessionId: sessionId,
      status: ServerPodcastEpisodeStatus.recording,
      providerStatus: ServerPodcastProviderStatus.active,
      revision: 2,
    ),
  );

  @override
  Future<ServerPodcastEpisodeReceipt> stopPodcastRecording({
    required ServerPodcastRecordingState recording,
    required String requestId,
  }) => _answer<ServerPodcastEpisodeReceipt>(
    'stopServerPodcastRecordingV1',
    {
      'serverId': recording.serverId,
      'channelId': recording.channelId,
      'studioChannelId': recording.studioChannelId,
      'episodeId': recording.episodeId,
      'expectedRevision': recording.episodeRevision,
      'requestId': requestId,
    },
    () => _podcastReceipt(
      serverId: recording.serverId,
      channelId: recording.channelId,
      studioChannelId: recording.studioChannelId,
      episodeId: recording.episodeId,
      sessionId: recording.sessionId,
      status: ServerPodcastEpisodeStatus.processing,
      providerStatus: ServerPodcastProviderStatus.ending,
      revision: recording.episodeRevision + 1,
    ),
  );

  @override
  Future<ServerPodcastEpisodeReceipt> finalizePodcastEpisode({
    required ServerPodcastEpisode episode,
    required String requestId,
  }) => _podcastMutation(
    'finalizeServerPodcastEpisodeV1',
    episode,
    requestId,
    status: ServerPodcastEpisodeStatus.ready,
  );

  @override
  Future<ServerPodcastEpisodeReceipt> retryPodcastRecording({
    required ServerPodcastEpisode episode,
    required String requestId,
  }) => _podcastMutation(
    'retryServerPodcastRecordingV1',
    episode,
    requestId,
    status: ServerPodcastEpisodeStatus.recording,
  );

  @override
  Future<ServerPodcastEpisodeReceipt> publishPodcastEpisode({
    required ServerPodcastEpisode episode,
    required String requestId,
  }) => _podcastMutation(
    'publishServerPodcastEpisodeV1',
    episode,
    requestId,
    status: ServerPodcastEpisodeStatus.published,
  );

  Future<ServerPodcastEpisodeReceipt> _podcastMutation(
    String name,
    ServerPodcastEpisode episode,
    String requestId, {
    required ServerPodcastEpisodeStatus status,
  }) => _answer<ServerPodcastEpisodeReceipt>(
    name,
    {
      'serverId': episode.serverId,
      'channelId': episode.channelId,
      'studioChannelId': episode.studioChannelId,
      'episodeId': episode.id,
      'expectedRevision': episode.revision,
      'requestId': requestId,
    },
    () => _podcastReceipt(
      serverId: episode.serverId,
      channelId: episode.channelId,
      studioChannelId: episode.studioChannelId,
      episodeId: episode.id,
      sessionId: episode.sessionId,
      status: status,
      providerStatus: status == ServerPodcastEpisodeStatus.recording
          ? ServerPodcastProviderStatus.active
          : ServerPodcastProviderStatus.complete,
      revision: episode.revision + 1,
    ),
  );

  @override
  Future<ServerPodcastEpisodeAccess> getPodcastEpisodeAccess({
    required ServerPodcastEpisode episode,
  }) => _answer<ServerPodcastEpisodeAccess>(
    'getServerPodcastEpisodeAccessV1',
    {
      'serverId': episode.serverId,
      'channelId': episode.channelId,
      'episodeId': episode.id,
    },
    () => ServerPodcastEpisodeAccess(
      serverId: episode.serverId,
      channelId: episode.channelId,
      episodeId: episode.id,
      title: episode.title,
      url: Uri.parse('https://storage.googleapis.com/test/${episode.id}.mp3'),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      media: episode.media!,
    ),
  );

  @override
  Future<void> createPodcastQuestion({
    required String serverId,
    required String channelId,
    required String body,
    required String requestId,
  }) => _answer<void>('createServerPodcastQuestionV1', {
    'serverId': serverId,
    'channelId': channelId,
    'requestId': requestId,
    'body': body,
  }, () {});

  @override
  Future<void> setPodcastQuestionVote({
    required ServerPodcastQuestion question,
    required bool voted,
    required String requestId,
  }) => _answer<void>(
    'setServerPodcastQuestionVoteV1',
    {
      'serverId': question.serverId,
      'channelId': question.channelId,
      'questionId': question.id,
      'requestId': requestId,
      'expectedRevision': question.revision,
      'voted': voted,
    },
    () => podcastQuestionVotes[question.id] = voted,
  );

  @override
  Future<void> setPodcastQuestionOnAir({
    required ServerPodcastQuestion question,
    required bool onAir,
    required String requestId,
  }) => _answer<void>('setServerPodcastQuestionOnAirV1', {
    'serverId': question.serverId,
    'channelId': question.channelId,
    'questionId': question.id,
    'requestId': requestId,
    'expectedRevision': question.revision,
    'onAir': onAir,
  }, () {});

  @override
  Stream<ServerWhiteboardSnapshot> watchWhiteboard(
    String serverId,
    String channelId,
  ) => Stream.value(
    whiteboardSnapshot ??
        ServerWhiteboardSnapshot(
          state: ServerWhiteboardState.empty(
            serverId: serverId,
            channelId: channelId,
          ),
          strokes: const [],
        ),
  );

  @override
  Future<void> createWhiteboardStroke({
    required String serverId,
    required String channelId,
    required List<ServerWhiteboardPoint> points,
    required ServerWhiteboardColor color,
    required int lineWidth,
    required String requestId,
  }) => _answer<void>('createServerWhiteboardStrokeV1', {
    'serverId': serverId,
    'channelId': channelId,
    'requestId': requestId,
    'points': [for (final point in points) point.toMap()],
    'color': color.name,
    'lineWidth': lineWidth,
  }, () {});

  @override
  Future<void> undoWhiteboardStroke({
    required ServerWhiteboardStroke stroke,
    required String requestId,
  }) => _answer<void>('undoServerWhiteboardStrokeV1', {
    'serverId': stroke.serverId,
    'channelId': stroke.channelId,
    'strokeId': stroke.id,
    'requestId': requestId,
    'expectedRevision': stroke.revision,
  }, () {});

  @override
  Future<void> clearWhiteboard({
    required String serverId,
    required String channelId,
    required int expectedRevision,
    required String requestId,
  }) => _answer<void>('clearServerWhiteboardV1', {
    'serverId': serverId,
    'channelId': channelId,
    'requestId': requestId,
    'expectedRevision': expectedRevision,
  }, () {});

  @override
  Stream<List<ServerCompanyFile>> watchCompanyFiles(
    String serverId,
    String channelId,
  ) =>
      companyFilesStream ??
      Stream.value(
        companyFiles
            .where(
              (file) =>
                  file.serverId == serverId && file.channelId == channelId,
            )
            .toList(growable: false),
      );

  @override
  ServerCompanyFileUploadAttempt newCompanyFileUploadAttempt({
    required String serverId,
    required String channelId,
    required ServerCompanyFileSelection selection,
  }) => ServerCompanyFileUploadAttempt(
    serverId: serverId,
    channelId: channelId,
    selection: selection,
    reserveRequestId: newRequestId(),
    finalizeRequestId: newRequestId(),
  );

  @override
  Future<String> publishCompanyFile(
    ServerCompanyFileUploadAttempt attempt, {
    void Function(double progress)? onProgress,
  }) async {
    companyFileUploads += 1;
    onProgress?.call(1);
    await _answer<void>('reserveServerCompanyFileV1', {
      'serverId': attempt.serverId,
      'channelId': attempt.channelId,
      'requestId': attempt.reserveRequestId,
      'displayName': attempt.selection.displayName,
      'contentType': attempt.selection.contentType,
      'size': attempt.selection.bytes.lengthInBytes,
    }, () {});
    await _answer<void>('finalizeServerCompanyFileV1', {
      'serverId': attempt.serverId,
      'channelId': attempt.channelId,
      'fileId': 'cf_0000000000000000000000000000000000000000',
      'generation': '1',
      'requestId': attempt.finalizeRequestId,
    }, () {});
    return 'cf_0000000000000000000000000000000000000000';
  }

  @override
  Future<ServerCompanyFileAccess> getCompanyFileAccess({
    required ServerCompanyFile file,
  }) => _answer<ServerCompanyFileAccess>(
    'getServerCompanyFileAccessV1',
    {'serverId': file.serverId, 'channelId': file.channelId, 'fileId': file.id},
    () => ServerCompanyFileAccess(
      serverId: file.serverId,
      channelId: file.channelId,
      fileId: file.id,
      displayName: file.displayName,
      url: Uri.parse(
        'https://storage.googleapis.com/test/${file.id}?signature=test',
      ),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      generation: file.file.generation,
      contentType: file.file.contentType,
      size: file.file.size,
    ),
  );

  @override
  Future<void> deleteCompanyFile({
    required ServerCompanyFile file,
    required String requestId,
  }) => _answer<void>('deleteServerCompanyFileV1', {
    'serverId': file.serverId,
    'channelId': file.channelId,
    'fileId': file.id,
    'expectedRevision': file.revision,
    'requestId': requestId,
  }, () {});

  @override
  Future<ServerSessionStart> startChannelSession({
    required String serverId,
    required String channelId,
    required String requestId,
  }) => _answer(
    'startServerChannelSessionV1',
    {'serverId': serverId, 'channelId': channelId, 'requestId': requestId},
    () => const ServerSessionStart(roomId: 'room', sessionId: 'session-1'),
  );

  @override
  Future<ServerSessionConnection> createChannelToken({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String requestId,
  }) => _answer(
    'createServerChannelTokenV1',
    {
      'serverId': serverId,
      'channelId': channelId,
      'sessionId': sessionId,
      'requestId': requestId,
    },
    () => ServerSessionConnection(
      serverUrl: 'wss://livekit.test',
      participantToken: 'token-$sessionId',
      roomName: 'lk-room',
      participantIdentity: currentUserId,
      participantName: 'Owner',
      expiresAtMillis: 0,
      canPublish: permittedTrackSources.isNotEmpty,
      canSubscribe: true,
      permittedTrackSources: permittedTrackSources,
      sessionRole: sessionRole,
      roomId: 'room',
      sessionId: sessionId,
    ),
  );

  @override
  Future<void> endChannelSession({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String requestId,
  }) => _answer<void>('endServerChannelSessionV1', {
    'serverId': serverId,
    'channelId': channelId,
    'sessionId': sessionId,
    'requestId': requestId,
  }, () {});

  /// Every `releaseServerChannelSessionIfEmptyV1` payload, in order. Kept
  /// apart from [calls]: it is the backstop signal leaving sends by itself,
  /// never something a person's press asked for, so a test of what a press
  /// asked for is not rewritten by it.
  final releases = <Map<String, Object?>>[];

  /// The receipt the next releases answer with. `occupied` by default, which
  /// schedules nothing.
  String releaseOutcome = 'occupied';
  Duration releaseRecheckAfter = Duration.zero;

  /// Thrown by the next release, once.
  Object? failNextRelease;

  @override
  Future<ServerSessionReleaseResult> releaseChannelSessionIfEmpty({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String requestId,
  }) async {
    releases.add({
      'serverId': serverId,
      'channelId': channelId,
      'sessionId': sessionId,
      'requestId': requestId,
    });
    final failure = failNextRelease;
    if (failure != null) {
      failNextRelease = null;
      throw failure;
    }
    return ServerSessionReleaseResult(
      sessionId: sessionId,
      outcome: releaseOutcome,
      recheckAfter: releaseRecheckAfter,
    );
  }
}

/// A provider link that never touches native audio. Tests move it through
/// its states explicitly, so "connected" in the UI is provably tied to the
/// provider's own report and not to token issuance.
class FakeServerMediaLink extends ServerMediaLink {
  ServerMediaLinkState _state = ServerMediaLinkState.connecting;
  List<ServerMediaParticipant> roster = const [];
  bool microphone = false;
  bool deafened = false;
  bool camera = false;
  bool screenShare = false;
  final microphoneCalls = <bool>[];
  final cameraCalls = <bool>[];
  Object? failCameraWith;

  /// Every screen-share press the link received, in order, and the failure
  /// the next one answers with (a browser picker the person cancels).
  final screenShareCalls = <bool>[];
  Object? failScreenShareWith;

  /// Every `Słuchawki` press the link received, in order.
  final deafenCalls = <bool>[];
  int disconnects = 0;

  /// The failure the next microphone / headphones press answers with. The
  /// production link really does raise — `ServerMediaLink` throws
  /// `StateError('The media session is not connected.')` when the link has
  /// been released or the local participant is gone, and forwards a provider
  /// publish failure unchanged — and a press during a reconnect is exactly
  /// when that happens.
  Object? failMicrophoneWith;
  Object? failDeafenWith;

  @override
  ServerMediaLinkState get state => _state;
  @override
  List<ServerMediaParticipant> get participants => roster;
  @override
  bool get isMicrophoneEnabled => microphone;
  @override
  bool get isDeafened => deafened;
  @override
  bool get isCameraEnabled => camera;
  @override
  bool get isScreenShareEnabled => screenShare;

  void report(ServerMediaLinkState state) {
    _state = state;
    notifyListeners();
  }

  void setRoster(List<ServerMediaParticipant> participants) {
    roster = participants;
    notifyListeners();
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    microphoneCalls.add(enabled);
    final failure = failMicrophoneWith;
    if (failure != null) {
      failMicrophoneWith = null;
      throw failure;
    }
    microphone = enabled;
    notifyListeners();
  }

  @override
  Future<void> setDeafened(bool value) async {
    deafenCalls.add(value);
    final failure = failDeafenWith;
    if (failure != null) {
      failDeafenWith = null;
      throw failure;
    }
    deafened = value;
    notifyListeners();
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    cameraCalls.add(enabled);
    final failure = failCameraWith;
    if (failure != null) {
      failCameraWith = null;
      throw failure;
    }
    camera = enabled;
    notifyListeners();
  }

  @override
  Future<void> setScreenShareEnabled(bool enabled) async {
    screenShareCalls.add(enabled);
    final failure = failScreenShareWith;
    if (failure != null) {
      failScreenShareWith = null;
      throw failure;
    }
    screenShare = enabled;
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    microphone = false;
    deafened = false;
    camera = false;
    screenShare = false;
    _state = ServerMediaLinkState.disconnected;
  }
}

class FakeServerMediaConnector implements ServerMediaConnector {
  final connections = <(String, String)>[];
  final links = <FakeServerMediaLink>[];

  /// When set, the next connect fails instead of producing a link.
  Object? failWith;

  /// When true the connect resolves with a link that is already connected,
  /// which is what a provider handshake that completed looks like.
  bool connectImmediately = true;

  @override
  Future<ServerMediaLink> connect({
    required String serverUrl,
    required String token,
  }) async {
    connections.add((serverUrl, token));
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
    final link = FakeServerMediaLink();
    if (connectImmediately) link._state = ServerMediaLinkState.connected;
    links.add(link);
    return link;
  }
}

/// What a session asked of the device, without a method channel in sight.
///
/// Installed by [pumpServers] for every server test: the production
/// implementation reaches `AudioManager` and the Android foreground service,
/// neither of which exists under `flutter test`.
class FakeServerVoiceDevice implements ServerVoiceDevice {
  int speakerRequests = 0;
  int keepAliveStarts = 0;
  int keepAliveStops = 0;
  bool? lastCanPublish;
  String? lastTitle;

  @override
  Future<void> preferSpeakerOutput() async => speakerRequests++;

  @override
  Future<void> startKeepAlive({
    required String title,
    required String body,
    required bool canPublish,
  }) async {
    keepAliveStarts++;
    lastCanPublish = canPublish;
    lastTitle = title;
  }

  @override
  Future<void> stopKeepAlive() async => keepAliveStops++;
}

/// The device seam installed by the most recent [pumpServers].
FakeServerVoiceDevice get pumpedVoiceDevice => _pumpedVoiceDevice!;
FakeServerVoiceDevice? _pumpedVoiceDevice;

Future<void> pumpServers(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double textScale = 1,
  bool light = false,
  bool settle = true,
  Locale locale = const Locale('pl'),
  ServerVoiceDevice? device,
}) async {
  final fake = FakeServerVoiceDevice();
  _pumpedVoiceDevice = fake;
  debugServerVoiceDeviceOverride = device ?? fake;
  addTearDown(() => debugServerVoiceDeviceOverride = null);
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: child,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}
