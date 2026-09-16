import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/models/server_whiteboard.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/data/services/server_whiteboard_live_transport.dart';
import 'package:yovoice/features/servers/data/services/server_whiteboard_repository.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_whiteboard_board.dart';

import 'server_test_support.dart';

const _server = Server(
  id: 'company',
  name: 'Studio North',
  description: '',
  ownerId: 'owner',
  type: ServerType.company,
  privacy: ServerPrivacy.inviteOnly,
  schemaVersion: 1,
  activationState: 'active',
  revision: 1,
);

const _channel = ServerChannel(
  id: 'whiteboard',
  serverId: 'company',
  name: 'Tablica',
  kind: ServerChannelKind.whiteboard,
  schemaVersion: 1,
  revision: 1,
  aclRevision: 1,
);

const _restrictedChannel = ServerChannel(
  id: 'whiteboard',
  serverId: 'company',
  name: 'Private board',
  kind: ServerChannelKind.whiteboard,
  access: ServerChannelAccess.restricted,
  schemaVersion: 1,
  revision: 1,
  aclRevision: 1,
);

ServerWhiteboardStroke _stroke({
  String id = 'stroke-1',
  String authorId = 'owner',
  int sequence = 1,
}) => ServerWhiteboardStroke(
  id: id,
  serverId: _server.id,
  channelId: _channel.id,
  authorId: authorId,
  generation: 1,
  sequence: sequence,
  revision: 1,
  color: ServerWhiteboardColor.blue,
  lineWidth: 5,
  points: const [ServerWhiteboardPoint(.1, .2), ServerWhiteboardPoint(.8, .7)],
  createdAt: DateTime.utc(2026, 9, 13, 12),
);

ServerWhiteboardSnapshot _snapshot(List<ServerWhiteboardStroke> strokes) =>
    ServerWhiteboardSnapshot(
      state: ServerWhiteboardState(
        serverId: _server.id,
        channelId: _channel.id,
        generation: 1,
        revision: strokes.length,
        strokeCount: strokes.length,
        nextSequence: strokes.length + 1,
      ),
      strokes: strokes,
    );

ServerWhiteboardLiveDraft _liveDraft({
  String draftId = 'remote-draft',
  String authorId = 'teammate',
  String channelId = 'whiteboard',
  int generation = 1,
  List<ServerWhiteboardPoint> points = const [
    ServerWhiteboardPoint(.2, .3),
    ServerWhiteboardPoint(.7, .6),
  ],
}) => ServerWhiteboardLiveDraft(
  draftId: draftId,
  serverId: _server.id,
  channelId: channelId,
  mediaChannelId: 'meeting',
  roomId: 'room',
  sessionId: 'session',
  authorId: authorId,
  generation: generation,
  sequence: 1,
  points: points,
  color: ServerWhiteboardColor.green,
  lineWidth: 5,
  receivedAt: DateTime.now().toUtc(),
  expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
);

class _FakeWhiteboardRepository implements ServerWhiteboardRepository {
  _FakeWhiteboardRepository({
    this.userId = 'owner',
    List<ServerWhiteboardStroke> strokes = const [],
    this.stream,
    this.createFailure,
    this.createAction,
  }) : snapshot = _snapshot(strokes);

  final String userId;
  final ServerWhiteboardSnapshot snapshot;
  final Stream<ServerWhiteboardSnapshot>? stream;
  final Object? createFailure;
  final Future<void> Function()? createAction;
  final calls = <(String, Map<String, Object?>)>[];
  final submittedStrokes = <ServerWhiteboardLocalStroke>[];
  var _requests = 0;

  @override
  String get currentUserId => userId;

  @override
  String newRequestId() => 'request-${++_requests}';

  @override
  Stream<ServerWhiteboardSnapshot> watchWhiteboard(
    String serverId,
    String channelId,
  ) => stream ?? Stream.value(snapshot);

  @override
  Future<void> createWhiteboardStroke({
    required String serverId,
    required String channelId,
    required List<ServerWhiteboardPoint> points,
    required ServerWhiteboardColor color,
    required int lineWidth,
    required String requestId,
  }) async {
    submittedStrokes.add(
      ServerWhiteboardLocalStroke(
        requestId: requestId,
        observedGeneration: snapshot.state.generation,
        minimumSequence: snapshot.state.nextSequence,
        points: points,
        color: color,
        lineWidth: lineWidth,
      ),
    );
    calls.add((
      'createServerWhiteboardStrokeV1',
      {
        'serverId': serverId,
        'channelId': channelId,
        'points': [for (final point in points) point.toMap()],
        'color': color.name,
        'lineWidth': lineWidth,
        'requestId': requestId,
      },
    ));
    final failure = createFailure;
    if (failure != null) throw failure;
    await createAction?.call();
  }

  @override
  Future<void> undoWhiteboardStroke({
    required ServerWhiteboardStroke stroke,
    required String requestId,
  }) async {
    calls.add((
      'undoServerWhiteboardStrokeV1',
      {
        'serverId': stroke.serverId,
        'channelId': stroke.channelId,
        'strokeId': stroke.id,
        'expectedRevision': stroke.revision,
        'requestId': requestId,
      },
    ));
  }

  @override
  Future<void> clearWhiteboard({
    required String serverId,
    required String channelId,
    required int expectedRevision,
    required String requestId,
  }) async {
    calls.add((
      'clearServerWhiteboardV1',
      {
        'serverId': serverId,
        'channelId': channelId,
        'expectedRevision': expectedRevision,
        'requestId': requestId,
      },
    ));
  }
}

class _FakeWhiteboardLiveTransport extends ChangeNotifier
    implements ServerWhiteboardLiveTransport {
  _FakeWhiteboardLiveTransport({
    Stream<List<ServerWhiteboardLiveDraft>>? stream,
    this.publishAction,
  }) : _stream = stream ?? Stream.value(const []);

  bool available = true;
  final Stream<List<ServerWhiteboardLiveDraft>> _stream;
  final Future<bool> Function()? publishAction;
  final draftPublications = <Map<String, Object?>>[];
  final clearedDraftIds = <String>[];

  @override
  bool isAvailableFor(String serverId) => available && serverId == _server.id;

  @override
  Stream<List<ServerWhiteboardLiveDraft>> get whiteboardLiveDrafts => _stream;

  @override
  Future<bool> publishWhiteboardLiveDraft({
    required String serverId,
    required String channelId,
    required String draftId,
    required int generation,
    required List<ServerWhiteboardPoint> points,
    required ServerWhiteboardColor color,
    required int lineWidth,
  }) async {
    draftPublications.add({
      'serverId': serverId,
      'channelId': channelId,
      'draftId': draftId,
      'generation': generation,
      'points': List<ServerWhiteboardPoint>.of(points),
      'color': color,
      'lineWidth': lineWidth,
    });
    return await publishAction?.call() ?? true;
  }

  @override
  Future<bool> clearWhiteboardLiveDraft({
    required String serverId,
    required String channelId,
    required String draftId,
    required int generation,
  }) async {
    clearedDraftIds.add(draftId);
    return available;
  }
}

Future<void> _pumpBoard(
  WidgetTester tester,
  _FakeWhiteboardRepository repository, {
  ServerChannel channel = _channel,
  ServerMemberRole role = ServerMemberRole.member,
  Size size = const Size(390, 844),
  double textScale = 1,
  bool settle = true,
  bool light = false,
  ServerWhiteboardLiveTransport? liveTransport,
}) => pumpServers(
  tester,
  ServerWhiteboardBoard(
    server: _server,
    channel: channel,
    repository: repository,
    liveTransport: liveTransport,
    role: role,
    compact: size.width < 768,
  ),
  size: size,
  textScale: textScale,
  settle: settle,
  light: light,
);

double _contrastRatio(Color first, Color second) {
  final high = math.max(first.computeLuminance(), second.computeLuminance());
  final low = math.min(first.computeLuminance(), second.computeLuminance());
  return (high + .05) / (low + .05);
}

void main() {
  test(
    'ServerService sends the exact three whiteboard callable payloads',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      final service = ServerService(
        call: (name, payload) async {
          calls.add((name, payload));
          return <Object?, Object?>{};
        },
      );
      const points = [
        ServerWhiteboardPoint(.1, .2),
        ServerWhiteboardPoint(.8, .7),
      ];
      await service.createWhiteboardStroke(
        serverId: 'company',
        channelId: 'whiteboard',
        points: points,
        color: ServerWhiteboardColor.purple,
        lineWidth: 9,
        requestId: 'request-create',
      );
      await service.undoWhiteboardStroke(
        stroke: _stroke(),
        requestId: 'request-undo',
      );
      await service.clearWhiteboard(
        serverId: 'company',
        channelId: 'whiteboard',
        expectedRevision: 7,
        requestId: 'request-clear',
      );

      expect(calls.map((call) => call.$1), [
        'createServerWhiteboardStrokeV1',
        'undoServerWhiteboardStrokeV1',
        'clearServerWhiteboardV1',
      ]);
      expect(calls[0].$2, {
        'serverId': 'company',
        'channelId': 'whiteboard',
        'requestId': 'request-create',
        'points': [for (final point in points) point.toMap()],
        'color': 'purple',
        'lineWidth': 9,
      });
      expect(calls[1].$2, {
        'serverId': 'company',
        'channelId': 'whiteboard',
        'strokeId': 'stroke-1',
        'requestId': 'request-undo',
        'expectedRevision': 1,
      });
      expect(calls[2].$2, {
        'serverId': 'company',
        'channelId': 'whiteboard',
        'requestId': 'request-clear',
        'expectedRevision': 7,
      });
    },
  );

  test(
    'strict whiteboard models reject malformed persisted coordinates',
    () async {
      final firestore = FakeFirebaseFirestore();
      final state = firestore.doc(
        'clubs/company/channels/whiteboard/whiteboardState/main',
      );
      await state.set({
        'schemaVersion': 1,
        'serverId': 'company',
        'channelId': 'whiteboard',
        'stateId': 'main',
        'generation': 1,
        'revision': 1,
        'strokeCount': 1,
        'nextSequence': 2,
        'clearedAt': null,
        'clearedById': null,
        'updatedAt': DateTime.utc(2026, 9, 13),
      });
      expect(
        ServerWhiteboardState.fromFirestore(
          await state.get(),
          serverId: 'company',
          channelId: 'whiteboard',
        ).strokeCount,
        1,
      );

      final stroke = firestore.doc(
        'clubs/company/channels/whiteboard/whiteboardStrokes/stroke-1',
      );
      Future<void> writePoints(List<Map<String, Object?>> points) =>
          stroke.set({
            'schemaVersion': 1,
            'serverId': 'company',
            'channelId': 'whiteboard',
            'strokeId': 'stroke-1',
            'strokeKind': 'polyline',
            'authorId': 'owner',
            'generation': 1,
            'sequence': 1,
            'revision': 1,
            'color': 'blue',
            'lineWidth': 5,
            'points': points,
            'createdAt': DateTime.utc(2026, 9, 13),
          });

      await writePoints([
        {'x': .1, 'y': .2},
        {'x': .8, 'y': .7},
      ]);
      expect(
        ServerWhiteboardStroke.fromFirestore(
          await stroke.get(),
          serverId: 'company',
          channelId: 'whiteboard',
          generation: 1,
        ).points,
        hasLength(2),
      );
      await writePoints([
        {'x': .1, 'y': .2},
        {'x': 1.1, 'y': .7},
      ]);
      final malformed = await stroke.get();
      expect(
        () => ServerWhiteboardStroke.fromFirestore(
          malformed,
          serverId: 'company',
          channelId: 'whiteboard',
          generation: 1,
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('optimistic reconciliation consumes distinct persisted strokes', () {
    final first = ServerWhiteboardLocalStroke(
      requestId: 'request-1',
      observedGeneration: 1,
      minimumSequence: 1,
      points: const [
        ServerWhiteboardPoint(.1, .2),
        ServerWhiteboardPoint(.8, .7),
      ],
      color: ServerWhiteboardColor.blue,
      lineWidth: 5,
    );
    final second = ServerWhiteboardLocalStroke(
      requestId: 'request-2',
      observedGeneration: 1,
      minimumSequence: 1,
      points: first.points,
      color: first.color,
      lineWidth: first.lineWidth,
    );
    final newer = ServerWhiteboardLocalStroke(
      requestId: 'request-newer',
      observedGeneration: 1,
      minimumSequence: 2,
      points: first.points,
      color: first.color,
      lineWidth: first.lineWidth,
    );

    final guarded = _snapshot([
      _stroke(),
    ]).reconcileLocal(userId: 'owner', localStrokes: [newer]);
    expect(guarded.confirmedRequestIds, isEmpty);
    expect(guarded.unmatchedLocal.single.requestId, 'request-newer');

    final once = _snapshot([
      _stroke(),
    ]).reconcileLocal(userId: 'owner', localStrokes: [first, second]);
    expect(once.confirmedRequestIds, {'request-1'});
    expect(once.unmatchedLocal.map((stroke) => stroke.requestId), [
      'request-2',
    ]);

    final twice = _snapshot([
      _stroke(),
      _stroke(id: 'stroke-2', sequence: 2),
    ]).reconcileLocal(userId: 'owner', localStrokes: [first, second]);
    expect(twice.confirmedRequestIds, {'request-1', 'request-2'});
    expect(twice.unmatchedLocal, isEmpty);
  });

  test('long paths keep late corners when simplified to 64 wire points', () {
    final points = <ServerWhiteboardPoint>[
      for (var index = 0; index <= 80; index++)
        ServerWhiteboardPoint(.1 + .004 * index, .1),
      for (var index = 1; index <= 100; index++)
        ServerWhiteboardPoint(.42, .1 + .008 * index),
      for (var index = 1; index <= 100; index++)
        ServerWhiteboardPoint(.42 + .0048 * index, .9),
    ];

    final simplified = simplifyServerWhiteboardPoints(points);

    expect(simplified, hasLength(64));
    expect(simplified.first.x, closeTo(.1, .00001));
    expect(simplified.first.y, closeTo(.1, .00001));
    expect(simplified.last.x, closeTo(.9, .00001));
    expect(simplified.last.y, closeTo(.9, .00001));
    expect(
      simplified.any(
        (point) => (point.x - .42).abs() < .001 && (point.y - .1).abs() < .01,
      ),
      isTrue,
    );
    expect(
      simplified.any(
        (point) => (point.x - .42).abs() < .001 && (point.y - .9).abs() < .01,
      ),
      isTrue,
    );
  });

  test('ephemeral wire encoding is bounded and rejects malformed points', () {
    final points = [
      for (var index = 0; index < 64; index++)
        ServerWhiteboardPoint(index / 63, 1 - index / 63),
    ];
    final encoded = encodeServerWhiteboardPoints(points);
    final decoded = decodeServerWhiteboardPoints(encoded)!;
    expect(decoded, hasLength(64));
    expect(decoded.first.x, 0);
    expect(decoded.last.x, 1);
    expect(decodeServerWhiteboardPoints('0,0;invalid'), isNull);
    expect(
      () => encodeServerWhiteboardPoints([
        const ServerWhiteboardPoint(-.1, .2),
        const ServerWhiteboardPoint(.3, .4),
      ]),
      throwsArgumentError,
    );
  });

  testWidgets('a member gesture persists one bounded normalized polyline', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeWhiteboardRepository();
    await _pumpBoard(tester, repository);
    final canvas = find.byKey(const ValueKey('server-whiteboard-canvas'));
    await tester.ensureVisible(canvas);
    final rect = tester.getRect(canvas);
    final gesture = await tester.startGesture(
      Offset(rect.left + 20, rect.top + 30),
    );
    await gesture.moveTo(Offset(rect.right - 25, rect.bottom - 35));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(repository.calls.single.$1, 'createServerWhiteboardStrokeV1');
    final payload = repository.calls.single.$2;
    expect(payload['serverId'], 'company');
    expect(payload['channelId'], 'whiteboard');
    expect(payload['color'], 'ink');
    expect(payload['lineWidth'], 5);
    expect(payload['requestId'], 'request-1');
    final points = payload['points']! as List;
    expect(points.length, inInclusiveRange(2, 64));
    for (final point in points.cast<Map<Object?, Object?>>()) {
      expect(point['x'], inInclusiveRange(0, 1));
      expect(point['y'], inInclusiveRange(0, 1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a gesture beyond 64 samples preserves its late turns', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeWhiteboardRepository();
    await _pumpBoard(tester, repository);
    final canvas = find.byKey(const ValueKey('server-whiteboard-canvas'));
    await tester.ensureVisible(canvas);
    final rect = tester.getRect(canvas);
    final left = rect.left + 24;
    final right = rect.right - 24;
    final top = rect.top + 28;
    final bottom = rect.bottom - 28;
    final gesture = await tester.startGesture(Offset(left, top));
    for (var index = 1; index <= 80; index++) {
      await gesture.moveTo(Offset(left + (right - left) * index / 80, top));
    }
    for (var index = 1; index <= 80; index++) {
      await gesture.moveTo(Offset(right, top + (bottom - top) * index / 80));
    }
    for (var index = 1; index <= 80; index++) {
      await gesture.moveTo(Offset(right - (right - left) * index / 80, bottom));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final points = repository.submittedStrokes.single.points;
    expect(points, hasLength(64));
    expect(
      points.any((point) => point.x > .85 && point.y < .2),
      isTrue,
      reason: 'the first turn after sample 64 must remain in the final shape',
    );
    expect(
      points.any((point) => point.x > .85 && point.y > .8),
      isTrue,
      reason: 'the later second turn must remain in the final shape',
    );
  });

  testWidgets(
    'ink renders during the gesture and completed strokes stay optimistic',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final saves = <Completer<void>>[];
      final updates = StreamController<ServerWhiteboardSnapshot>.broadcast();
      addTearDown(updates.close);
      final repository = _FakeWhiteboardRepository(
        stream: updates.stream,
        createAction: () {
          final save = Completer<void>();
          saves.add(save);
          return save.future;
        },
      );
      await _pumpBoard(tester, repository, settle: false);
      updates.add(_snapshot(const []));
      await tester.pump();
      final canvas = find.byKey(const ValueKey('server-whiteboard-canvas'));
      await tester.ensureVisible(canvas);
      final rect = tester.getRect(canvas);

      final first = await tester.startGesture(
        Offset(rect.left + 24, rect.top + 34),
      );
      await first.moveTo(Offset(rect.left + 130, rect.top + 120));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('server-whiteboard-drawing-live')),
        findsOneWidget,
      );
      expect(repository.calls, isEmpty);

      await first.up();
      await tester.pump();
      expect(repository.calls, hasLength(1));
      expect(
        find.byKey(const ValueKey('server-whiteboard-sync-status')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('server-whiteboard-progress')),
        findsOneWidget,
      );

      final second = await tester.startGesture(
        Offset(rect.left + 40, rect.top + 150),
      );
      await second.moveTo(Offset(rect.left + 170, rect.top + 180));
      await second.up();
      await tester.pump();
      expect(repository.calls, hasLength(2));

      for (final save in saves) {
        save.complete();
      }
      await tester.pump();
      final persisted = <ServerWhiteboardStroke>[
        for (var index = 0; index < repository.submittedStrokes.length; index++)
          ServerWhiteboardStroke(
            id: 'stroke-${index + 1}',
            serverId: _server.id,
            channelId: _channel.id,
            authorId: repository.userId,
            generation: 1,
            sequence: index + 1,
            revision: 1,
            color: repository.submittedStrokes[index].color,
            lineWidth: repository.submittedStrokes[index].lineWidth,
            points: repository.submittedStrokes[index].points,
            createdAt: DateTime.utc(2026, 9, 14, 12, 0, index),
          ),
      ];
      updates.add(_snapshot(persisted));
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('server-whiteboard-synced')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('server-whiteboard-progress')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('live drafts are single-flight, recover, coalesce and clean up', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final draftWrites = <Completer<bool>>[];
    final repository = _FakeWhiteboardRepository();
    final transport = _FakeWhiteboardLiveTransport(
      publishAction: () {
        final write = Completer<bool>();
        draftWrites.add(write);
        return write.future;
      },
    );
    await _pumpBoard(tester, repository, liveTransport: transport);
    final canvas = find.byKey(const ValueKey('server-whiteboard-canvas'));
    await tester.ensureVisible(canvas);
    final rect = tester.getRect(canvas);
    final gesture = await tester.startGesture(
      Offset(rect.left + 20, rect.top + 30),
    );
    await gesture.moveTo(Offset(rect.left + 50, rect.top + 60));
    await tester.pump();
    expect(draftWrites, hasLength(1));

    for (var index = 1; index <= 90; index++) {
      await gesture.moveTo(
        Offset(
          rect.left + 20 + index * 2.2,
          rect.top + 30 + (index.isEven ? 45 : 70),
        ),
      );
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      draftWrites,
      hasLength(1),
      reason: 'a slow write must coalesce all later pointer samples',
    );

    draftWrites.single.completeError(StateError('rules rate limit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(draftWrites, hasLength(2));
    final latest =
        transport.draftPublications.last['points']!
            as List<ServerWhiteboardPoint>;
    expect(latest.length, inInclusiveRange(2, 64));
    expect(latest.last.x, greaterThan(.5));

    await gesture.up();
    draftWrites.last.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(transport.clearedDraftIds, contains('request-1'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote in-progress drafts render and generations isolate them', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final drafts =
        StreamController<List<ServerWhiteboardLiveDraft>>.broadcast();
    addTearDown(drafts.close);
    final repository = _FakeWhiteboardRepository();
    final transport = _FakeWhiteboardLiveTransport(stream: drafts.stream);
    await _pumpBoard(
      tester,
      repository,
      liveTransport: transport,
      settle: false,
    );
    await tester.pump();

    drafts.add([_liveDraft(channelId: 'foreign-board')]);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('server-whiteboard-remote-draft-paint-0')),
      findsOneWidget,
    );

    drafts.add([_liveDraft()]);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('server-whiteboard-remote-draft-paint-1')),
      findsOneWidget,
    );

    drafts.add([_liveDraft(generation: 2)]);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('server-whiteboard-remote-draft-paint-0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restricted boards refuse unverified live drafts and use durable writes',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final drafts =
          StreamController<List<ServerWhiteboardLiveDraft>>.broadcast();
      addTearDown(drafts.close);
      final repository = _FakeWhiteboardRepository();
      final transport = _FakeWhiteboardLiveTransport(stream: drafts.stream);
      await _pumpBoard(
        tester,
        repository,
        channel: _restrictedChannel,
        liveTransport: transport,
        settle: false,
      );
      await tester.pump();

      drafts.add([_liveDraft()]);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('server-whiteboard-remote-draft-paint-0')),
        findsOneWidget,
        reason: 'a meeting token does not prove per-board restricted access',
      );

      final canvas = find.byKey(const ValueKey('server-whiteboard-canvas'));
      await tester.ensureVisible(canvas);
      final rect = tester.getRect(canvas);
      final gesture = await tester.startGesture(
        Offset(rect.left + 20, rect.top + 30),
      );
      await gesture.moveTo(Offset(rect.left + 80, rect.top + 90));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(repository.calls.single.$1, 'createServerWhiteboardStrokeV1');
      expect(transport.draftPublications, isEmpty);
      expect(transport.clearedDraftIds, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'two concurrent failed saves stay queued with per-line and retry-all actions',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final saves = <Completer<void>>[];
      final repository = _FakeWhiteboardRepository(
        createAction: () {
          final save = Completer<void>();
          saves.add(save);
          return save.future;
        },
      );
      await _pumpBoard(tester, repository);
      final canvas = find.byKey(const ValueKey('server-whiteboard-canvas'));
      await tester.ensureVisible(canvas);
      final rect = tester.getRect(canvas);
      await tester.tapAt(Offset(rect.left + 30, rect.top + 40));
      await tester.pump();
      await tester.tapAt(Offset(rect.left + 90, rect.top + 100));
      await tester.pump();
      expect(saves, hasLength(2));

      saves[0].completeError(StateError('offline one'));
      saves[1].completeError(StateError('offline two'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('server-whiteboard-retry-request-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('server-whiteboard-retry-request-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('server-whiteboard-retry-all')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('server-whiteboard-retry-request-1')),
      );
      await tester.pump();
      expect(saves, hasLength(3));
      saves[2].complete();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('server-whiteboard-retry-request-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('server-whiteboard-retry-request-2')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('server-whiteboard-retry-all')),
      );
      await tester.pump();
      expect(saves, hasLength(4));
      saves[3].complete();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('server-whiteboard-error')),
        findsNothing,
      );
      expect(repository.calls, hasLength(4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('undo hides a pending stroke and removes it after its echo', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final save = Completer<void>();
    final updates = StreamController<ServerWhiteboardSnapshot>.broadcast();
    addTearDown(updates.close);
    final repository = _FakeWhiteboardRepository(
      stream: updates.stream,
      createAction: () => save.future,
    );
    await _pumpBoard(tester, repository, settle: false);
    updates.add(_snapshot(const []));
    await tester.pump();
    final canvas = find.byKey(const ValueKey('server-whiteboard-canvas'));
    await tester.ensureVisible(canvas);
    final rect = tester.getRect(canvas);
    await tester.tapAt(Offset(rect.left + 40, rect.top + 50));
    await tester.pump();
    expect(repository.calls.map((call) => call.$1), [
      'createServerWhiteboardStrokeV1',
    ]);

    await tester.tap(find.byKey(const ValueKey('server-whiteboard-undo')));
    await tester.pump();
    save.complete();
    await tester.pump();
    final local = repository.submittedStrokes.single;
    updates.add(
      _snapshot([
        ServerWhiteboardStroke(
          id: 'authoritative-stroke',
          serverId: _server.id,
          channelId: _channel.id,
          authorId: repository.userId,
          generation: 1,
          sequence: 1,
          revision: 1,
          color: local.color,
          lineWidth: local.lineWidth,
          points: local.points,
          createdAt: DateTime.utc(2026, 9, 14, 12),
        ),
      ]),
    );
    await tester.pump();
    await tester.pump();
    expect(repository.calls.map((call) => call.$1), [
      'createServerWhiteboardStrokeV1',
      'undoServerWhiteboardStrokeV1',
    ]);
    expect(repository.calls.last.$2['strokeId'], 'authoritative-stroke');
    expect(tester.takeException(), isNull);
  });

  testWidgets('line, rectangle and arrow tools persist bounded geometry', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeWhiteboardRepository();
    await _pumpBoard(tester, repository);
    Future<void> drawShape(String key) async {
      final tool = find.byKey(ValueKey(key));
      await tester.ensureVisible(tool);
      await tester.pump();
      await tester.tap(tool);
      await tester.pump();
      final canvas = find.byKey(const ValueKey('server-whiteboard-canvas'));
      await tester.ensureVisible(canvas);
      await tester.pump();
      final rect = tester.getRect(canvas);
      final gesture = await tester.startGesture(
        Offset(rect.left + 50, rect.top + 60),
      );
      await gesture.moveTo(Offset(rect.left + 90, rect.top + 95));
      await gesture.moveTo(Offset(rect.left + 210, rect.top + 180));
      await gesture.up();
      await tester.pump();
    }

    await drawShape('server-whiteboard-tool-line');
    await drawShape('server-whiteboard-tool-rectangle');
    await drawShape('server-whiteboard-tool-arrow');

    expect(repository.submittedStrokes[0].points, hasLength(2));
    expect(repository.submittedStrokes[1].points, hasLength(5));
    expect(repository.submittedStrokes[1].points.first.x, closeTo(.05, .2));
    expect(
      repository.submittedStrokes[1].points.last.x,
      repository.submittedStrokes[1].points.first.x,
    );
    expect(repository.submittedStrokes[2].points, hasLength(5));
    expect(
      repository.submittedStrokes[2].points[1].x,
      repository.submittedStrokes[2].points[3].x,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pointer-rate ink repaints apart from saved and pending layers', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpBoard(tester, _FakeWhiteboardRepository());
    expect(
      find.byKey(const ValueKey('server-whiteboard-static-layer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('server-whiteboard-pending-layer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('server-whiteboard-live-ink-layer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('server-whiteboard-remote-draft-layer')),
      findsOneWidget,
    );

    final canvas = find.byKey(const ValueKey('server-whiteboard-canvas'));
    await tester.ensureVisible(canvas);
    final rect = tester.getRect(canvas);
    final gesture = await tester.startGesture(
      Offset(rect.left + 30, rect.top + 35),
    );
    await gesture.moveTo(Offset(rect.left + 90, rect.top + 90));
    await tester.pump();
    final staticPaint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('server-whiteboard-static-layer')),
        matching: find.byType(CustomPaint),
      ),
    );
    final pendingPaint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('server-whiteboard-pending-layer')),
        matching: find.byType(CustomPaint),
      ),
    );

    await gesture.moveTo(Offset(rect.left + 180, rect.top + 150));
    await tester.pump();
    expect(
      identical(
        tester.widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const ValueKey('server-whiteboard-static-layer')),
            matching: find.byType(CustomPaint),
          ),
        ),
        staticPaint,
      ),
      isTrue,
      reason: 'pointer updates must not rebuild the saved/grid paint layer',
    );
    expect(
      identical(
        tester.widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const ValueKey('server-whiteboard-pending-layer')),
            matching: find.byType(CustomPaint),
          ),
        ),
        pendingPaint,
      ),
      isTrue,
      reason: 'pointer updates must not rebuild the optimistic paint layer',
    );
    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('light canvas orange and green swatches exceed 3 to 1 contrast', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpBoard(tester, _FakeWhiteboardRepository(), light: true);
    for (final color in ['orange', 'green']) {
      final control = find.byKey(ValueKey('server-whiteboard-color-$color'));
      final swatch = tester.widget<Container>(
        find.descendant(of: control, matching: find.byType(Container)).last,
      );
      final decoration = swatch.decoration! as BoxDecoration;
      final canvas = tester.element(control).appPalette.surfaceRaised;
      expect(
        _contrastRatio(decoration.color!, canvas),
        greaterThanOrEqualTo(3),
      );
    }
  });

  testWidgets('move mode exposes canvas zoom without drawing a stroke', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeWhiteboardRepository();
    await _pumpBoard(tester, repository);
    await tester.tap(
      find.byKey(const ValueKey('server-whiteboard-tool-navigate')),
    );
    await tester.pump();
    final canvas = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('server-whiteboard-canvas')),
    );
    expect(canvas.onPanStart, isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('server-whiteboard-zoom-in')),
    );
    await tester.tap(find.byKey(const ValueKey('server-whiteboard-zoom-in')));
    await tester.pump();
    expect(find.text('125%'), findsOneWidget);
    expect(repository.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'toolbar controls have one clear name and a semantic tap action',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      await _pumpBoard(tester, _FakeWhiteboardRepository());

      for (final (key, label) in const [
        ('server-whiteboard-tool-draw', 'Rysuj'),
        ('server-whiteboard-tool-navigate', 'Przesuwaj'),
      ]) {
        final glyph = find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(IconButton),
        );
        final data = tester.getSemantics(glyph).getSemanticsData();
        expect(data.label, label, reason: key);
        expect(data.hasAction(ui.SemanticsAction.tap), isTrue, reason: key);
      }

      final ink = tester
          .getSemantics(
            find.byKey(const ValueKey('server-whiteboard-color-ink')),
          )
          .getSemanticsData();
      expect(ink.label, 'Atrament');
      expect(ink.hasAction(ui.SemanticsAction.tap), isTrue);

      final navigate = tester.getSemantics(
        find.descendant(
          of: find.byKey(const ValueKey('server-whiteboard-tool-navigate')),
          matching: find.byType(IconButton),
        ),
      );
      navigate.owner!.performAction(navigate.id, ui.SemanticsAction.tap);
      await tester.pump();
      expect(
        tester
            .widget<GestureDetector>(
              find.byKey(const ValueKey('server-whiteboard-canvas')),
            )
            .onPanStart,
        isNull,
      );
      semantics.dispose();
    },
  );

  testWidgets('undo is own-only and clear is visible only to managers', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final member = _FakeWhiteboardRepository(
      strokes: [
        _stroke(),
        _stroke(id: 'foreign', authorId: 'teammate', sequence: 2),
      ],
    );
    await _pumpBoard(tester, member);
    expect(find.byKey(const ValueKey('server-whiteboard-clear')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('server-whiteboard-undo')));
    await tester.pumpAndSettle();
    expect(member.calls.single.$1, 'undoServerWhiteboardStrokeV1');
    expect(member.calls.single.$2, {
      'serverId': 'company',
      'channelId': 'whiteboard',
      'strokeId': 'stroke-1',
      'expectedRevision': 1,
      'requestId': 'request-1',
    });

    final manager = _FakeWhiteboardRepository(
      strokes: [_stroke(authorId: 'teammate')],
    );
    await _pumpBoard(tester, manager, role: ServerMemberRole.admin);
    final clear = find.byKey(const ValueKey('server-whiteboard-clear'));
    expect(clear, findsOneWidget);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(find.text('Wyczyścić tablicę?'), findsOneWidget);
    await tester.tap(find.text('Wyczyść'));
    await tester.pumpAndSettle();
    expect(manager.calls.single.$1, 'clearServerWhiteboardV1');
    expect(manager.calls.single.$2['expectedRevision'], 1);
  });

  testWidgets('a guest receives a live read-only canvas without mutations', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeWhiteboardRepository(
      userId: 'guest',
      strokes: [_stroke()],
    );
    await _pumpBoard(tester, repository, role: ServerMemberRole.guest);

    final canvas = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('server-whiteboard-canvas')),
    );
    expect(canvas.onPanStart, isNull);
    expect(canvas.onTapUp, isNull);
    expect(find.byKey(const ValueKey('server-whiteboard-clear')), findsNothing);
    expect(find.textContaining('Zapisane linie pozostają'), findsOneWidget);
    expect(repository.calls, isEmpty);
  });

  testWidgets(
    'loading and stream errors fail closed without a drawable canvas',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final updates = StreamController<ServerWhiteboardSnapshot>();
      addTearDown(updates.close);
      await _pumpBoard(
        tester,
        _FakeWhiteboardRepository(stream: updates.stream),
        settle: false,
      );

      expect(
        find.byKey(const ValueKey('server-whiteboard-loading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('server-whiteboard-canvas')),
        findsNothing,
      );

      updates.addError(StateError('offline'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('server-whiteboard-load-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('server-whiteboard-canvas')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an offline save keeps the board open and announces failure', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeWhiteboardRepository(
      createFailure: StateError('offline'),
    );
    await _pumpBoard(tester, repository);
    final canvas = find.byKey(const ValueKey('server-whiteboard-canvas'));
    await tester.ensureVisible(canvas);
    final rect = tester.getRect(canvas);
    await tester.tapAt(Offset(rect.left + 30, rect.top + 30));
    await tester.pumpAndSettle();

    expect(repository.calls.single.$1, 'createServerWhiteboardStrokeV1');
    expect(
      find.byKey(const ValueKey('server-whiteboard-error')),
      findsOneWidget,
    );
    expect(canvas, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Bugs.md F1: on a 402 pt phone the tools strip scrolled behind the pinned
  // undo and clear buttons, cutting Arrow in half and hiding Grid, and the
  // seventh ink swatch was cut at the toolbar edge. Every control must be
  // fully inside the toolbar and must not sit under another control.
  for (final (size, textScale) in const [
    (Size(320, 760), 2.0),
    (Size(390, 844), 1.0),
    (Size(402, 874), 1.0),
  ]) {
    testWidgets('every whiteboard control is fully visible at '
        '${size.width.toInt()}x${size.height.toInt()} '
        'and ${(textScale * 100).toInt()} percent text', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpBoard(
        tester,
        _FakeWhiteboardRepository(strokes: [_stroke()]),
        role: ServerMemberRole.admin,
        size: size,
        textScale: textScale,
      );

      expect(
        find.byKey(const ValueKey('server-whiteboard-canvas')),
        findsOneWidget,
      );
      final toolbar = tester.getRect(
        find.byKey(const ValueKey('server-whiteboard-toolbar')),
      );
      void expectFullyVisible(List<Rect> rects, String group) {
        for (var index = 0; index < rects.length; index++) {
          final rect = rects[index];
          expect(
            rect.left,
            greaterThanOrEqualTo(toolbar.left),
            reason: '$group #$index left edge',
          );
          expect(
            rect.right,
            lessThanOrEqualTo(toolbar.right),
            reason: '$group #$index right edge',
          );
          for (var other = index + 1; other < rects.length; other++) {
            expect(
              rect.overlaps(rects[other]),
              isFalse,
              reason: '$group #$index overlaps #$other',
            );
          }
        }
      }

      final toolRects = <Rect>[];
      for (final key in [
        'server-whiteboard-tool-draw',
        'server-whiteboard-tool-navigate',
        'server-whiteboard-tool-line',
        'server-whiteboard-tool-rectangle',
        'server-whiteboard-tool-arrow',
        'server-whiteboard-grid',
        'server-whiteboard-undo',
        'server-whiteboard-clear',
      ]) {
        final control = find.byKey(ValueKey(key));
        expect(control, findsOneWidget, reason: key);
        final rect = tester.getRect(control);
        expect(rect.width, greaterThanOrEqualTo(48), reason: key);
        expect(rect.height, greaterThanOrEqualTo(48), reason: key);
        toolRects.add(rect);
      }
      expectFullyVisible(toolRects, 'tools');

      for (final (key, count) in const [
        ('server-whiteboard-colors-strip', 7),
        ('server-whiteboard-widths-strip', 4),
      ]) {
        final buttons = find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.button == true,
          ),
        );
        expect(buttons, findsNWidgets(count), reason: key);
        expectFullyVisible([
          for (var index = 0; index < count; index++)
            tester.getRect(buttons.at(index)),
        ], key);
      }
      expect(tester.takeException(), isNull);
    });
  }

  // Bugs.md F6: a translucent zoom pill let strokes show through its buttons
  // and percentage label.
  for (final light in const [false, true]) {
    testWidgets('the zoom controls are opaque over strokes in the '
        '${light ? 'light' : 'dark'} theme', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpBoard(
        tester,
        _FakeWhiteboardRepository(strokes: [_stroke()]),
        light: light,
      );

      final controls = tester.widget<Material>(
        find.byKey(const ValueKey('server-whiteboard-zoom-controls')),
      );
      expect(controls.color, isNotNull);
      expect(controls.color!.a, 1.0);
      expect(tester.takeException(), isNull);
    });
  }
}
