import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_whiteboard.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/data/services/server_whiteboard_live_transport.dart';

const _points = [ServerWhiteboardPoint(.1, .2), ServerWhiteboardPoint(.8, .7)];

ServerMediaSessionBinding _binding({
  String author = 'local',
  String serverId = 'company',
  String channelId = 'meeting',
  String roomId = 'room',
  String sessionId = 'session',
  String role = 'guest',
}) => ServerMediaSessionBinding(
  serverId: serverId,
  channelId: channelId,
  roomId: roomId,
  sessionId: sessionId,
  participantIdentity: author,
  sessionRole: role,
);

ServerMediaDataPacket _updatePacket({
  required ServerMediaSessionBinding sender,
  String connectionId = 'PA_connection',
  String boardChannelId = 'whiteboard',
  int generation = 1,
  int sequence = 1,
  String draftId = 'draft',
}) => ServerMediaDataPacket(
  topic: serverWhiteboardLiveTopic,
  sender: sender,
  senderConnectionId: connectionId,
  data: ServerWhiteboardLiveCodec.encodeUpdate(
    mediaBinding: sender,
    boardChannelId: boardChannelId,
    draftId: draftId,
    generation: generation,
    sequence: sequence,
    points: _points,
    color: ServerWhiteboardColor.blue,
    lineWidth: 5,
  ),
);

ServerMediaDataPacket _clearPacket({
  required ServerMediaSessionBinding sender,
  String connectionId = 'PA_connection',
  String boardChannelId = 'whiteboard',
  int generation = 1,
  int sequence = 2,
  String draftId = 'draft',
}) => ServerMediaDataPacket(
  topic: serverWhiteboardLiveTopic,
  sender: sender,
  senderConnectionId: connectionId,
  data: ServerWhiteboardLiveCodec.encodeClear(
    mediaBinding: sender,
    boardChannelId: boardChannelId,
    draftId: draftId,
    generation: generation,
    sequence: sequence,
  ),
);

void main() {
  test('media metadata preserves opaque Firebase UIDs but fences resource IDs', () {
    const uid = 'Alicja Żółć 42';
    String metadata({
      String author = uid,
      String serverId = 'company',
    }) => jsonEncode({
      'uid': author,
      'role': 'guest',
      'serverId': serverId,
      'channelId': 'meeting',
      'roomId': 'room',
      'sessionId': 'session',
    });

    final binding = decodeServerMediaSessionBinding(
      rawMetadata: metadata(),
      participantIdentity: uid,
    );
    expect(binding?.participantIdentity, uid);
    expect(binding?.serverId, 'company');
    expect(
      decodeServerMediaSessionBinding(
        rawMetadata: metadata(),
        participantIdentity: 'Alicja Zołc 42',
      ),
      isNull,
      reason: 'opaque identities are compared exactly, without normalization',
    );
    expect(
      decodeServerMediaSessionBinding(
        rawMetadata: metadata(serverId: 'company space'),
        participantIdentity: uid,
      ),
      isNull,
    );
    for (final invalidUid in ['', 'path/uid', 'control\nuid']) {
      expect(isValidOpaqueServerParticipantIdentity(invalidUid), isFalse);
      expect(
        decodeServerMediaSessionBinding(
          rawMetadata: metadata(author: invalidUid),
          participantIdentity: invalidUid,
        ),
        isNull,
      );
    }
  });

  test('whiteboard codec accepts the exact opaque provider identity', () {
    const uid = 'Zażółć gęślą';
    final local = _binding();
    final remote = _binding(author: uid);
    final bytes = ServerWhiteboardLiveCodec.encodeUpdate(
      mediaBinding: remote,
      boardChannelId: 'whiteboard',
      draftId: 'draft',
      generation: 1,
      sequence: 1,
      points: _points,
      color: ServerWhiteboardColor.blue,
      lineWidth: 5,
    );

    final decoded = ServerWhiteboardLiveCodec.decode(
      bytes: bytes,
      sender: remote,
      expectedMediaBinding: local,
    );
    expect(decoded?.authorId, uid);
  });

  test(
    'codec binds payload to provider-authenticated generation and author',
    () {
      final local = _binding();
      final remote = _binding(author: 'remote', role: 'host');
      final bytes = ServerWhiteboardLiveCodec.encodeUpdate(
        mediaBinding: remote,
        boardChannelId: 'whiteboard',
        draftId: 'draft_1',
        generation: 7,
        sequence: 4,
        points: _points,
        color: ServerWhiteboardColor.purple,
        lineWidth: 9,
      );

      final decoded =
          ServerWhiteboardLiveCodec.decode(
                bytes: bytes,
                sender: remote,
                expectedMediaBinding: local,
              )
              as ServerWhiteboardLiveUpdate;
      expect(decoded.serverId, 'company');
      expect(decoded.boardChannelId, 'whiteboard');
      expect(decoded.mediaChannelId, 'meeting');
      expect(decoded.sessionId, 'session');
      expect(decoded.authorId, 'remote');
      expect(decoded.generation, 7);
      expect(decoded.sequence, 4);
      expect(decoded.points, hasLength(2));

      expect(
        ServerWhiteboardLiveCodec.decode(
          bytes: bytes,
          sender: _binding(author: 'foreign', role: 'host'),
          expectedMediaBinding: local,
        ),
        isNull,
        reason: 'the payload author cannot be forged independently of LiveKit',
      );
      expect(
        ServerWhiteboardLiveCodec.decode(
          bytes: bytes,
          sender: remote,
          expectedMediaBinding: _binding(sessionId: 'next-session'),
        ),
        isNull,
      );
    },
  );

  test('codec drops oversize, malformed and non-exact payloads', () {
    final expected = _binding();
    final remote = _binding(author: 'remote');
    final valid = ServerWhiteboardLiveCodec.encodeUpdate(
      mediaBinding: remote,
      boardChannelId: 'whiteboard',
      draftId: 'draft',
      generation: 1,
      sequence: 1,
      points: _points,
      color: ServerWhiteboardColor.blue,
      lineWidth: 5,
    );
    final map = jsonDecode(utf8.decode(valid)) as Map<String, dynamic>;
    expect(
      ServerWhiteboardLiveCodec.decode(
        bytes: utf8.encode(jsonEncode({...map, 'unknown': true})),
        sender: remote,
        expectedMediaBinding: expected,
      ),
      isNull,
    );
    expect(
      ServerWhiteboardLiveCodec.decode(
        bytes: List.filled(ServerWhiteboardLiveCodec.maximumPacketBytes + 1, 1),
        sender: remote,
        expectedMediaBinding: expected,
      ),
      isNull,
    );
    expect(
      ServerWhiteboardLiveCodec.decode(
        bytes: const [0xff, 0xfe],
        sender: remote,
        expectedMediaBinding: expected,
      ),
      isNull,
    );
  });

  test('publish uses lossy updates, reliable clear and exact topic', () async {
    final link = _FakeDataLink(_binding());
    final plane = ServerWhiteboardLiveDataPlane(
      link: link,
      expectedMediaBinding: _binding(),
    );
    addTearDown(plane.dispose);

    expect(
      await plane.publishDraft(
        serverId: 'company',
        channelId: 'whiteboard',
        draftId: 'draft',
        generation: 1,
        points: _points,
        color: ServerWhiteboardColor.blue,
        lineWidth: 5,
      ),
      isTrue,
    );
    expect(
      await plane.clearDraft(
        serverId: 'company',
        channelId: 'whiteboard',
        draftId: 'draft',
        generation: 1,
      ),
      isTrue,
    );
    expect(link.published.map((entry) => entry.reliable), [false, true]);
    expect(link.published.map((entry) => entry.topic).toSet(), {
      serverWhiteboardLiveTopic,
    });
  });

  test(
    'foreign, listener, old sequence and cross-session packets are dropped',
    () async {
      final link = _FakeDataLink(_binding());
      final plane = ServerWhiteboardLiveDataPlane(
        link: link,
        expectedMediaBinding: _binding(),
      );
      addTearDown(plane.dispose);
      final snapshots = <List<ServerWhiteboardLiveDraft>>[];
      final subscription = plane.drafts.listen(snapshots.add);
      addTearDown(subscription.cancel);

      link.emit(
        _updatePacket(
          sender: _binding(author: 'listener', role: 'listener'),
        ),
      );
      link.emit(
        _updatePacket(
          sender: _binding(author: 'foreign', serverId: 'other'),
        ),
      );
      link.emit(_updatePacket(sender: _binding(author: 'remote'), sequence: 2));
      link.emit(_updatePacket(sender: _binding(author: 'remote'), sequence: 1));

      expect(snapshots, hasLength(1));
      expect(snapshots.single.single.authorId, 'remote');
      expect(snapshots.single.single.sequence, 2);
    },
  );

  test('malformed flood and participant state remain bounded', () async {
    var now = DateTime.utc(2026, 9, 14, 12);
    final link = _FakeDataLink(_binding());
    final plane = ServerWhiteboardLiveDataPlane(
      link: link,
      expectedMediaBinding: _binding(),
      clock: () => now,
    );
    addTearDown(plane.dispose);
    var latest = const <ServerWhiteboardLiveDraft>[];
    final subscription = plane.drafts.listen((value) => latest = value);
    addTearDown(subscription.cancel);

    final remote = _binding(author: 'remote');
    for (
      var index = 0;
      index < ServerWhiteboardLiveDataPlane.maximumInboundEventsPerWindow;
      index++
    ) {
      link.emit(
        ServerMediaDataPacket(
          topic: serverWhiteboardLiveTopic,
          data: const [0xff],
          sender: remote,
          senderConnectionId: 'PA_remote',
        ),
      );
    }
    link.emit(_updatePacket(sender: remote, connectionId: 'PA_remote'));
    expect(latest, isEmpty, reason: 'bounded budget stops JSON flood work');

    now = now.add(ServerWhiteboardLiveDataPlane.inboundWindow);
    link.emit(_updatePacket(sender: remote, connectionId: 'PA_remote'));
    expect(latest, hasLength(1));

    for (
      var index = 0;
      index < ServerWhiteboardLiveDataPlane.maximumRemoteAuthors + 10;
      index++
    ) {
      final author = _binding(author: 'user_$index');
      link.emit(
        _updatePacket(
          sender: author,
          connectionId: 'PA_$index',
          draftId: 'draft_$index',
        ),
      );
    }
    expect(
      latest.length,
      lessThanOrEqualTo(ServerWhiteboardLiveDataPlane.maximumRemoteAuthors),
    );
  });

  test(
    'new participant connection resets ordering and retires delayed packets',
    () async {
      final link = _FakeDataLink(_binding());
      final plane = ServerWhiteboardLiveDataPlane(
        link: link,
        expectedMediaBinding: _binding(),
      );
      addTearDown(plane.dispose);
      var latest = const <ServerWhiteboardLiveDraft>[];
      final subscription = plane.drafts.listen((value) => latest = value);
      addTearDown(subscription.cancel);
      final remote = _binding(author: 'remote');

      link.emit(
        _updatePacket(sender: remote, connectionId: 'PA_old', sequence: 50),
      );
      link.emit(
        _updatePacket(
          sender: remote,
          connectionId: 'PA_new',
          sequence: 1,
          draftId: 'new_draft',
        ),
      );
      expect(latest.single.draftId, 'new_draft');
      link.emit(
        _updatePacket(
          sender: remote,
          connectionId: 'PA_old',
          sequence: 51,
          draftId: 'delayed_old',
        ),
      );
      expect(latest.single.draftId, 'new_draft');
    },
  );

  test('reconnect history fails closed before an old SID can be replayed', () {
    final link = _FakeDataLink(_binding());
    final plane = ServerWhiteboardLiveDataPlane(
      link: link,
      expectedMediaBinding: _binding(),
    );
    addTearDown(plane.dispose);
    var latest = const <ServerWhiteboardLiveDraft>[];
    final subscription = plane.drafts.listen((value) => latest = value);
    addTearDown(subscription.cancel);
    final remote = _binding(author: 'remote');

    for (
      var index = 0;
      index <=
          ServerWhiteboardLiveDataPlane.maximumRetiredConnectionsPerAuthor;
      index++
    ) {
      link.emit(
        _updatePacket(
          sender: remote,
          connectionId: 'PA_$index',
          sequence: index + 1,
          draftId: 'draft_$index',
        ),
      );
    }
    expect(latest.single.draftId, 'draft_4');

    link.emit(
      _updatePacket(
        sender: remote,
        connectionId: 'PA_5',
        sequence: 6,
        draftId: 'unbounded_rotation',
      ),
    );
    link.emit(
      _updatePacket(
        sender: remote,
        connectionId: 'PA_0',
        sequence: 99,
        draftId: 'delayed_old',
      ),
    );
    expect(latest.single.draftId, 'draft_4');
  });

  test('inactive author state is reclaimed instead of locking out the room', () {
    var now = DateTime.utc(2026, 9, 14, 12);
    final link = _FakeDataLink(_binding());
    final plane = ServerWhiteboardLiveDataPlane(
      link: link,
      expectedMediaBinding: _binding(),
      clock: () => now,
    );
    addTearDown(plane.dispose);
    var latest = const <ServerWhiteboardLiveDraft>[];
    final subscription = plane.drafts.listen((value) => latest = value);
    addTearDown(subscription.cancel);

    for (
      var index = 0;
      index < ServerWhiteboardLiveDataPlane.maximumRemoteAuthors;
      index++
    ) {
      link.emit(
        _updatePacket(
          sender: _binding(author: 'user_$index'),
          connectionId: 'PA_$index',
          draftId: 'draft_$index',
        ),
      );
    }
    expect(latest, hasLength(ServerWhiteboardLiveDataPlane.maximumRemoteAuthors));

    now = now.add(
      ServerWhiteboardLiveDataPlane.inactiveAuthorStateLifetime +
          const Duration(milliseconds: 1),
    );
    link.emit(
      _updatePacket(
        sender: _binding(author: 'newcomer'),
        connectionId: 'PA_newcomer',
        draftId: 'newcomer_draft',
      ),
    );
    expect(latest, hasLength(1));
    expect(latest.single.authorId, 'newcomer');
  });

  test(
    'reliable clear does not block the next draft on the same link',
    () async {
      final link = _FakeDataLink(_binding());
      final plane = ServerWhiteboardLiveDataPlane(
        link: link,
        expectedMediaBinding: _binding(),
      );
      addTearDown(plane.dispose);
      var latest = const <ServerWhiteboardLiveDraft>[];
      final subscription = plane.drafts.listen((value) => latest = value);
      addTearDown(subscription.cancel);
      final remote = _binding(author: 'remote');

      link.emit(_updatePacket(sender: remote, sequence: 1));
      expect(latest.single.draftId, 'draft');
      link.emit(_clearPacket(sender: remote, sequence: 2));
      expect(latest, isEmpty);
      link.emit(
        _updatePacket(sender: remote, sequence: 3, draftId: 'next_draft'),
      );
      expect(latest.single.draftId, 'next_draft');
      expect(latest.single.sequence, 3);
    },
  );

  test(
    'suspend clears previews, blocks sends, resume and expiry recover',
    () async {
      var now = DateTime.utc(2026, 9, 14, 12);
      final link = _FakeDataLink(_binding());
      final plane = ServerWhiteboardLiveDataPlane(
        link: link,
        expectedMediaBinding: _binding(),
        clock: () => now,
      );
      addTearDown(plane.dispose);
      var latest = const <ServerWhiteboardLiveDraft>[];
      final subscription = plane.drafts.listen((value) => latest = value);
      addTearDown(subscription.cancel);
      link.emit(_updatePacket(sender: _binding(author: 'remote')));
      expect(latest, hasLength(1));

      plane.suspend();
      expect(latest, isEmpty);
      expect(
        await plane.publishDraft(
          serverId: 'company',
          channelId: 'whiteboard',
          draftId: 'local_draft',
          generation: 1,
          points: _points,
          color: ServerWhiteboardColor.blue,
          lineWidth: 5,
        ),
        isFalse,
      );

      plane.resume();
      link.emit(
        _updatePacket(
          sender: _binding(author: 'remote'),
          connectionId: 'PA_next',
        ),
      );
      expect(latest, hasLength(1));
      now = now.add(const Duration(seconds: 3));
      plane.expireNow();
      expect(latest, isEmpty);
    },
  );

  test(
    'mismatched local account/session binding refuses dataplane creation',
    () {
      expect(
        () => ServerWhiteboardLiveDataPlane(
          link: _FakeDataLink(_binding(author: 'other')),
          expectedMediaBinding: _binding(),
        ),
        throwsStateError,
      );
      expect(
        () => ServerWhiteboardLiveDataPlane(
          link: _FakeDataLink(_binding(sessionId: 'old')),
          expectedMediaBinding: _binding(),
        ),
        throwsStateError,
      );
    },
  );
}

class _FakeDataLink implements ServerMediaDataLink {
  _FakeDataLink(this.localSessionBinding);

  @override
  final ServerMediaSessionBinding? localSessionBinding;
  final StreamController<ServerMediaDataPacket> _packets =
      StreamController<ServerMediaDataPacket>.broadcast(sync: true);
  final List<({List<int> data, String topic, bool reliable})> published = [];

  @override
  Stream<ServerMediaDataPacket> get dataPackets => _packets.stream;

  void emit(ServerMediaDataPacket packet) => _packets.add(packet);

  @override
  Future<void> publishData(
    List<int> data, {
    required String topic,
    required bool reliable,
  }) async {
    published.add((data: List<int>.of(data), topic: topic, reliable: reliable));
  }
}
