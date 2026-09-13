import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_event.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_events_board.dart';

import 'server_test_support.dart';

const _server = Server(
  id: 'friends',
  name: 'Ekipa',
  description: '',
  ownerId: 'owner',
  type: ServerType.friends,
  privacy: ServerPrivacy.private,
  schemaVersion: 1,
  activationState: 'active',
  revision: 1,
);

const _channel = ServerChannel(
  id: 'events',
  serverId: 'friends',
  name: 'wydarzenia',
  kind: ServerChannelKind.events,
  schemaVersion: 1,
  revision: 1,
  aclRevision: 1,
);

Server _serverFor(ServerType type) => Server(
  id: type.name,
  name: 'Serwer ${type.name}',
  description: '',
  ownerId: 'owner',
  type: type,
  privacy: type == ServerType.community
      ? ServerPrivacy.public
      : ServerPrivacy.private,
  schemaVersion: 1,
  activationState: 'active',
  revision: 1,
);

ServerChannel _eventChannelFor(ServerType type) => ServerChannel(
  id: type == ServerType.family ? 'calendar' : 'events',
  serverId: type.name,
  name: type == ServerType.family ? 'Kalendarz' : 'Wydarzenia',
  kind: type == ServerType.family
      ? ServerChannelKind.calendar
      : ServerChannelKind.events,
  schemaVersion: 1,
  revision: 1,
  aclRevision: 1,
);

ServerEvent _eventFor({
  required String id,
  required ServerType type,
  required DateTime startsAt,
  required DateTime endsAt,
  int revision = 1,
  bool reminder = false,
}) => ServerEvent(
  id: id,
  serverId: type.name,
  channelId: type == ServerType.family ? 'calendar' : 'events',
  title: 'Termin $id',
  description: '',
  startsAt: startsAt,
  endsAt: endsAt,
  timeZone: 'Europe/Warsaw',
  status: ServerEventStatus.scheduled,
  authorId: 'friend',
  revision: revision,
  eventKind: switch (type) {
    ServerType.friends => ServerEventKind.friendsEvent,
    ServerType.community => ServerEventKind.communityEvent,
    ServerType.family => ServerEventKind.familyCalendarEvent,
    ServerType.podcast => ServerEventKind.podcastProgramEvent,
    ServerType.company => throw ArgumentError('Company has no Events V1.'),
  },
  serverType: type,
  channelKind: type == ServerType.family
      ? ServerChannelKind.calendar
      : ServerChannelKind.events,
  reminderOptInEnabled: reminder,
);

void main() {
  test(
    'event wall clock is converted with its IANA zone, not device local time',
    () {
      final instant = ServerEventTime.wallClockToUtc(
        DateTime.utc(2026, 1, 15, 18, 30),
        'Europe/Warsaw',
      );

      expect(instant, DateTime.utc(2026, 1, 15, 17, 30));
      final inNewYork = ServerEventTime.inZone(instant, 'America/New_York');
      expect((inNewYork.year, inNewYork.month, inNewYork.day), (2026, 1, 15));
      expect((inNewYork.hour, inNewYork.minute), (12, 30));
      expect(ServerEventTime.isValidZone('Definitely/Not_A_Zone'), isFalse);
    },
  );

  testWidgets('friends can create a real event from the empty board', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository();
    await pumpServers(
      tester,
      ServerEventsBoard(
        server: _server,
        channel: _channel,
        repository: repository,
        role: ServerMemberRole.owner,
        currentUserId: 'owner',
      ),
      size: const Size(390, 844),
    );

    expect(find.text('Nie ma jeszcze żadnych nadchodzących planów.'), findsOne);
    await tester.tap(find.byKey(const ValueKey('server-create-event')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('server-event-title')),
      'Planszówki u Oli',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('server-event-save')))
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('server-event-save')));
    await tester.tap(find.byKey(const ValueKey('server-event-save')));
    await tester.pumpAndSettle();

    expect(repository.calls.single.$1, 'createServerEventV1');
    expect(repository.calls.single.$2['title'], 'Planszówki u Oli');
    expect(repository.calls.single.$2['timeZone'], 'UTC');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an RSVP reaches the versioned event callable', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final startsAt = DateTime.now().add(const Duration(days: 2));
    final repository = TestServerRepository()
      ..events = [
        ServerEvent(
          id: 'event',
          serverId: 'friends',
          channelId: 'events',
          title: 'Kino',
          description: 'Wieczorny seans',
          startsAt: startsAt,
          endsAt: startsAt.add(const Duration(hours: 2)),
          timeZone: 'Europe/Warsaw',
          status: ServerEventStatus.scheduled,
          authorId: 'friend',
          revision: 4,
          goingCount: 2,
        ),
      ];
    await pumpServers(
      tester,
      ServerEventsBoard(
        server: _server,
        channel: _channel,
        repository: repository,
        role: ServerMemberRole.member,
        currentUserId: 'owner',
      ),
      size: const Size(390, 844),
    );

    await tester.tap(find.text('Będę · 2'));
    await tester.pumpAndSettle();
    expect(repository.calls.single.$1, 'respondToServerEventV1');
    expect(repository.calls.single.$2, {
      'serverId': 'friends',
      'channelId': 'events',
      'eventId': 'event',
      'requestId': 'request-1',
      'expectedRevision': 4,
      'response': 'going',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('each supported template presents its own real event module', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const expectations = <ServerType, (String, String)>{
      ServerType.friends: ('Plany z ekipą', 'Zaplanuj wydarzenie'),
      ServerType.community: ('Wydarzenia społeczności', 'Zaplanuj wydarzenie'),
      ServerType.family: ('Rodzinny kalendarz', 'Dodaj rodzinny termin'),
      ServerType.podcast: ('Program audycji', 'Zaplanuj audycję'),
    };

    for (final entry in expectations.entries) {
      await pumpServers(
        tester,
        ServerEventsBoard(
          key: ValueKey('events-${entry.key.name}'),
          server: _serverFor(entry.key),
          channel: _eventChannelFor(entry.key),
          repository: TestServerRepository(),
          role: ServerMemberRole.owner,
          currentUserId: 'owner',
          now: () => DateTime.utc(2026, 9, 13, 10),
        ),
        size: const Size(768, 900),
      );

      expect(find.text(entry.value.$1), findsOneWidget);
      expect(find.text(entry.value.$2), findsOneWidget);
      expect(tester.takeException(), isNull, reason: entry.key.name);
    }
  });

  testWidgets('ended events are hidden and responses close at event start', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 9, 13, 12);
    final repository = TestServerRepository()
      ..events = [
        _eventFor(
          id: 'ended',
          type: ServerType.friends,
          startsAt: now.subtract(const Duration(hours: 3)),
          endsAt: now.subtract(const Duration(hours: 1)),
        ),
        _eventFor(
          id: 'started',
          type: ServerType.friends,
          startsAt: now.subtract(const Duration(minutes: 5)),
          endsAt: now.add(const Duration(hours: 1)),
        ),
        _eventFor(
          id: 'future',
          type: ServerType.friends,
          startsAt: now.add(const Duration(hours: 2)),
          endsAt: now.add(const Duration(hours: 3)),
        ),
        ServerEvent(
          id: 'cancelled',
          serverId: 'friends',
          channelId: 'events',
          title: 'Termin cancelled',
          description: '',
          startsAt: now.add(const Duration(hours: 1)),
          endsAt: now.add(const Duration(hours: 2)),
          timeZone: 'Europe/Warsaw',
          status: ServerEventStatus.cancelled,
          authorId: 'friend',
          revision: 2,
        ),
      ];

    await pumpServers(
      tester,
      ServerEventsBoard(
        server: _serverFor(ServerType.friends),
        channel: _eventChannelFor(ServerType.friends),
        repository: repository,
        role: ServerMemberRole.member,
        currentUserId: 'owner',
        now: () => now,
      ),
      size: const Size(390, 844),
    );

    expect(find.text('Termin ended'), findsNothing);
    expect(find.text('Termin started'), findsOneWidget);
    expect(find.text('Termin future'), findsOneWidget);
    expect(find.text('Termin cancelled'), findsNothing);
    expect(
      find.byKey(const ValueKey('server-event-closed-started')),
      findsOneWidget,
    );
    final startedCard = find.byKey(const ValueKey('server-event-started'));
    expect(
      tester
          .widgetList<FilterChip>(
            find.descendant(of: startedCard, matching: find.byType(FilterChip)),
          )
          .every((chip) => chip.onSelected == null),
      isTrue,
    );
    expect(repository.calls, isEmpty);
  });

  testWidgets('family reminders persist with the current RSVP', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 9, 13, 12);
    final event = _eventFor(
      id: 'family-plan',
      type: ServerType.family,
      startsAt: now.add(const Duration(days: 2)),
      endsAt: now.add(const Duration(days: 2, hours: 1)),
      revision: 7,
      reminder: true,
    );
    final repository = TestServerRepository()
      ..events = [event]
      ..eventResponses[event.id] = const ServerEventAttendance(
        response: ServerEventResponse.going,
        reminderRequested: false,
      );

    await pumpServers(
      tester,
      ServerEventsBoard(
        server: _serverFor(ServerType.family),
        channel: _eventChannelFor(ServerType.family),
        repository: repository,
        role: ServerMemberRole.member,
        currentUserId: 'owner',
        now: () => now,
      ),
      size: const Size(390, 844),
    );

    await tester.tap(
      find.byKey(const ValueKey('server-event-reminder-family-plan')),
    );
    await tester.pumpAndSettle();

    expect(repository.calls.single.$1, 'respondToServerEventV1');
    expect(repository.calls.single.$2, <String, Object?>{
      'serverId': 'family',
      'channelId': 'calendar',
      'eventId': 'family-plan',
      'requestId': 'request-1',
      'expectedRevision': 7,
      'response': 'going',
      'reminderRequested': true,
    });
    final feedback = tester.widget<Semantics>(
      find.byKey(const ValueKey('server-event-feedback')),
    );
    expect(feedback.properties.liveRegion, isTrue);
    expect(find.byKey(const ValueKey('server-event-success')), findsOneWidget);
  });

  testWidgets('podcast program lets a listener save a reminder', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 9, 13, 12);
    final event = _eventFor(
      id: 'next-show',
      type: ServerType.podcast,
      startsAt: now.add(const Duration(days: 1)),
      endsAt: now.add(const Duration(days: 1, hours: 1)),
      revision: 3,
      reminder: true,
    );
    final repository = TestServerRepository()
      ..events = [event]
      ..eventResponses[event.id] = const ServerEventAttendance(
        response: ServerEventResponse.maybe,
        reminderRequested: false,
      );

    await pumpServers(
      tester,
      ServerEventsBoard(
        server: _serverFor(ServerType.podcast),
        channel: _eventChannelFor(ServerType.podcast),
        repository: repository,
        role: ServerMemberRole.member,
        currentUserId: 'owner',
        now: () => now,
      ),
      size: const Size(390, 844),
    );

    await tester.tap(
      find.byKey(const ValueKey('server-event-reminder-next-show')),
    );
    await tester.pumpAndSettle();
    expect(repository.calls.single.$1, 'respondToServerEventV1');
    expect(repository.calls.single.$2['response'], 'maybe');
    expect(repository.calls.single.$2['reminderRequested'], isTrue);
  });

  testWidgets('event failures are announced as an accessibility live region', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 9, 13, 12);
    final repository = TestServerRepository()
      ..events = [
        _eventFor(
          id: 'failing',
          type: ServerType.friends,
          startsAt: now.add(const Duration(days: 1)),
          endsAt: now.add(const Duration(days: 1, hours: 1)),
        ),
      ]
      ..failNextCall['respondToServerEventV1'] = StateError('offline');

    await pumpServers(
      tester,
      ServerEventsBoard(
        server: _serverFor(ServerType.friends),
        channel: _eventChannelFor(ServerType.friends),
        repository: repository,
        role: ServerMemberRole.member,
        currentUserId: 'owner',
        now: () => now,
      ),
      size: const Size(390, 844),
    );

    await tester.tap(find.text('Będę · 0'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-event-error')), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('server-event-feedback')),
          )
          .properties
          .liveRegion,
      isTrue,
    );
  });
}
