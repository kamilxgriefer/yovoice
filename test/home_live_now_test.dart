import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_live_now.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/shared/widgets/badges/yo_badge.dart';
import 'package:yovoice/shared/widgets/badges/yo_metric_pill.dart';

Server _server(String id, {ServerType type = ServerType.podcast}) => Server(
  id: id,
  name: 'Serwer $id',
  description: '',
  ownerId: 'owner',
  type: type,
  privacy: ServerPrivacy.public,
  schemaVersion: 1,
  activationState: 'active',
);

ServerChannel _channel(
  String serverId,
  String id, {
  ServerChannelKind kind = ServerChannelKind.stage,
  DateTime? liveSince,
}) => ServerChannel(
  id: id,
  serverId: serverId,
  name: 'Kanał $id',
  kind: kind,
  liveness: liveSince == null
      ? ServerChannelLiveness.idle
      : ServerChannelLiveness(isLive: true, startedAt: liveSince),
);

/// Only `watchChannels` is real; everything else is out of scope here.
class _Channels implements ServerRepository {
  final Map<String, StreamController<List<ServerChannel>>> controllers = {};
  final List<String> calls = [];
  final Set<String> failing = {};

  @override
  Stream<List<ServerChannel>> watchChannels(String serverId) {
    calls.add(serverId);
    if (failing.contains(serverId)) throw StateError('no channels');
    return controllers
        .putIfAbsent(serverId, StreamController<List<ServerChannel>>.new)
        .stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Server> servers,
  required ServerRepository repository,
  ValueChanged<Server>? onOpen,
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: HomeLiveNowSection(
              servers: servers,
              repository: repository,
              onOpenServer: onOpen ?? (_) {},
              horizontalPadding: 16,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Stream events land on a microtask; give them two frames to show up.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('nothing live: no heading, no gap, no card', (tester) async {
    final repository = _Channels();
    await _pump(tester, servers: [_server('a')], repository: repository);
    repository.controllers['a']!.add([_channel('a', 'voice')]);
    await _settle(tester);

    expect(find.byKey(const ValueKey('home-live-now')), findsNothing);
    expect(find.byType(YoBadge), findsNothing);
    expect(tester.getSize(find.byType(HomeLiveNowSection)).height, 0);
  });

  testWidgets('a live channel becomes a 16:9 card with the live badge and '
      'the start clock, never a head count', (tester) async {
    final repository = _Channels();
    Server? opened;
    final a = _server('a');
    await _pump(
      tester,
      servers: [a],
      repository: repository,
      onOpen: (server) => opened = server,
    );
    repository.controllers['a']!.add([
      _channel('a', 'stage', liveSince: DateTime(2026, 9, 19, 19, 40)),
      // A text channel never reads as live, whatever its document says.
      _channel(
        'a',
        'chat',
        kind: ServerChannelKind.text,
        liveSince: DateTime(2026, 9, 19, 19, 45),
      ),
    ]);
    await _settle(tester);

    expect(find.byKey(const ValueKey('home-live-now')), findsOneWidget);
    final card = find.byKey(const ValueKey('home-live-a-stage'));
    expect(card, findsOneWidget);
    expect(find.byKey(const ValueKey('home-live-a-chat')), findsNothing);
    expect(
      tester.widget<YoBadge>(find.byType(YoBadge)).variant,
      YoBadgeVariant.live,
    );
    final pill = tester.widget<YoMetricPill>(find.byType(YoMetricPill));
    expect(pill.value, contains('7:40'));
    final thumb = tester.getSize(
      find.descendant(of: card, matching: find.byType(AspectRatio)),
    );
    expect(thumb.width / thumb.height, closeTo(16 / 9, .01));
    expect(tester.getSize(card).width, HomeLiveNowSection.cardWidth);

    await tester.tap(card);
    expect(opened, same(a));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a channel whose server-owned projection flips idle loses its '
      'card at once and the rest stay newest first', (tester) async {
    final repository = _Channels();
    await _pump(
      tester,
      servers: [_server('a'), _server('b')],
      repository: repository,
      width: 1200,
    );
    repository.controllers['a']!.add([
      _channel('a', 'stage', liveSince: DateTime(2026, 9, 19, 19, 50)),
      _channel(
        'a',
        'voice',
        kind: ServerChannelKind.voice,
        liveSince: DateTime(2026, 9, 19, 19, 10),
      ),
    ]);
    repository.controllers['b']!.add([
      _channel('b', 'stage', liveSince: DateTime(2026, 9, 19, 19, 30)),
    ]);
    await _settle(tester);
    double left(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dx;
    expect(left('home-live-a-stage'), lessThan(left('home-live-b-stage')));
    expect(left('home-live-b-stage'), lessThan(left('home-live-a-voice')));

    // The last person left: the backend retired the projection. The same
    // stream now says idle for that one channel.
    repository.controllers['a']!.add([
      _channel('a', 'stage'),
      _channel(
        'a',
        'voice',
        kind: ServerChannelKind.voice,
        liveSince: DateTime(2026, 9, 19, 19, 10),
      ),
    ]);
    await _settle(tester);
    expect(find.byKey(const ValueKey('home-live-a-stage')), findsNothing);
    expect(left('home-live-b-stage'), lessThan(left('home-live-a-voice')));

    repository.controllers['a']!.add([
      _channel('a', 'stage'),
      _channel('a', 'voice', kind: ServerChannelKind.voice),
    ]);
    repository.controllers['b']!.add([_channel('b', 'stage')]);
    await _settle(tester);
    expect(find.byKey(const ValueKey('home-live-now')), findsNothing);
    expect(tester.getSize(find.byType(HomeLiveNowSection)).height, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('listeners are bounded, keyed and never re-subscribed by a '
      'rebuild; a failing server just contributes nothing', (tester) async {
    final repository = _Channels()..failing.add('b');
    final servers = [
      _server('a'),
      _server('b'),
      _server('c'),
      _server('d'),
      _server('e'),
    ];
    await _pump(tester, servers: servers, repository: repository);
    expect(repository.calls, ['a', 'b', 'c']);

    await _pump(tester, servers: servers, repository: repository);
    expect(repository.calls, ['a', 'b', 'c'], reason: 'rebuild resubscribed');

    repository.controllers['c']!.addError(StateError('denied'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('home-live-now')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long names at 200 % text fit the 280 px card', (tester) async {
    final repository = _Channels();
    final long = Server(
      id: 'long',
      name: 'Studio głosu i rozmów bez skrótów oraz bardzo długich nazw',
      description: '',
      ownerId: 'owner',
      type: ServerType.community,
      privacy: ServerPrivacy.public,
      schemaVersion: 1,
      activationState: 'active',
    );
    await _pump(
      tester,
      servers: [long],
      repository: repository,
      width: 320,
      textScale: 2,
    );
    repository.controllers['long']!.add([
      _channel('long', 'voice', liveSince: DateTime(2026, 9, 19, 8, 5)),
    ]);
    await _settle(tester);
    expect(find.byKey(const ValueKey('home-live-long-voice')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
