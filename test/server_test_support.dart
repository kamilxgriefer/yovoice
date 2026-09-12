import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_creation.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_session.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/data/services/server_voice_device.dart';

class TestServerRepository implements ServerRepository {
  final requests = <ServerCreationRequest>[];
  Completer<ServerCreationResult>? pending;
  bool failNext = false;

  /// Thrown on every attempt, for failures that do not clear by retrying —
  /// an unregistered callable being the one this stage cares about.
  Object? alwaysFailWith;
  int allocated = 0;
  List<Server> servers = [];
  List<ServerChannel> channels = [];
  Stream<Server?>? serverStream;
  Stream<List<ServerChannel>>? channelStream;

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
  Stream<List<ServerChannel>> watchChannels(String serverId) =>
      channelStream ??
      Stream.value(
        channels.where((channel) => channel.serverId == serverId).toList(),
      );

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
}

/// A provider link that never touches native audio. Tests move it through
/// its states explicitly, so "connected" in the UI is provably tied to the
/// provider's own report and not to token issuance.
class FakeServerMediaLink extends ServerMediaLink {
  ServerMediaLinkState _state = ServerMediaLinkState.connecting;
  List<ServerMediaParticipant> roster = const [];
  bool microphone = false;
  bool deafened = false;
  bool screenShare = false;
  final microphoneCalls = <bool>[];

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
