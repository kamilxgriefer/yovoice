import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/models/server_whiteboard.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
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

class _FakeWhiteboardRepository implements ServerWhiteboardRepository {
  _FakeWhiteboardRepository({
    this.userId = 'owner',
    List<ServerWhiteboardStroke> strokes = const [],
    this.stream,
    this.createFailure,
  }) : snapshot = _snapshot(strokes);

  final String userId;
  final ServerWhiteboardSnapshot snapshot;
  final Stream<ServerWhiteboardSnapshot>? stream;
  final Object? createFailure;
  final calls = <(String, Map<String, Object?>)>[];
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

Future<void> _pumpBoard(
  WidgetTester tester,
  _FakeWhiteboardRepository repository, {
  ServerMemberRole role = ServerMemberRole.member,
  Size size = const Size(390, 844),
  double textScale = 1,
  bool settle = true,
}) => pumpServers(
  tester,
  ServerWhiteboardBoard(
    server: _server,
    channel: _channel,
    repository: repository,
    role: role,
    compact: size.width < 768,
  ),
  size: size,
  textScale: textScale,
  settle: settle,
);

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
    expect(find.textContaining('Goście mogą śledzić'), findsOneWidget);
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

  testWidgets(
    'the canvas and controls fit a narrow phone at 200 percent text',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpBoard(
        tester,
        _FakeWhiteboardRepository(strokes: [_stroke()]),
        role: ServerMemberRole.admin,
        size: const Size(320, 760),
        textScale: 2,
      );

      expect(
        find.byKey(const ValueKey('server-whiteboard-canvas')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
