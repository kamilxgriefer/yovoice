import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_session_hand.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_waiting_dot.dart';

import 'server_podcast_test.dart' as podcast;
import 'server_test_support.dart';

/// Request to speak, as the people on both sides of it see it.
///
/// Host side: the raised hands of the live generation — read from the
/// rules-admitted queue, never invented — named, with how long each has
/// waited and Approve / Decline, in the studio, in the dock from any channel,
/// and as the shared waiting dot on the connected channel row.
///
/// Listener side: what they read comes from their own participant document —
/// waiting, declined, lowered, on the stage — and never "the hosts can see
/// your request".
///
/// The backend and provider are the deterministic fakes; nothing here proves
/// a real device, a real LiveKit reconnect or a rendered frame.
Finder get requests => find.byKey(const ValueKey('server-stage-requests'));
Finder get dockRequests => find.byKey(const ValueKey('server-dock-requests'));
Finder get hand => find.byKey(const ValueKey('server-podcast-hand'));
Finder get handState => find.byKey(const ValueKey('server-podcast-hand-state'));
Finder get join => find.byKey(const ValueKey('server-join'));

const _kamil = ServerMediaParticipant(
  identity: 'kamil',
  name: 'Kamil',
  isLocal: false,
  sessionRole: 'listener',
);
const _host = ServerMediaParticipant(
  identity: 'owner',
  name: 'Kasia',
  isLocal: true,
  isMicrophoneEnabled: true,
);

ServerSessionHand _handOf(
  String userId,
  String name, {
  Duration waited = const Duration(minutes: 3),
}) => ServerSessionHand(
  userId: userId,
  displayName: name,
  role: 'listener',
  raisedAt: DateTime.now().subtract(waited),
);

ServerSessionParticipantState _own({
  int revision = 1,
  String role = 'listener',
  bool hand = false,
  ServerHandDecision? decision,
}) => ServerSessionParticipantState(
  sessionId: 'gen-7',
  role: role,
  authorizationRevision: revision,
  hostMuted: false,
  serverMuted: false,
  isHandRaised: hand,
  handDecision: decision,
  tokenFingerprint: 'token-a',
);

TestServerRepository _hostRepository(
  StreamController<List<ServerSessionHand>> hands,
) => TestServerRepository()
  ..servers = [podcast.podcastServer()]
  ..channels = podcast.podcastChannels(
    studio: podcast.live,
    activeSessionId: 'gen-7',
  )
  ..myRole = ServerMemberRole.member
  ..sessionRole = 'host'
  ..sessionHandsStream = hands.stream;

Future<FakeServerMediaLink> _joinStudio(
  WidgetTester tester,
  TestServerRepository repository, {
  Size size = const Size(1440, 900),
  double textScale = 1,
  bool light = false,
  List<ServerMediaParticipant> roster = const [_host, _kamil],
}) async {
  final connector = FakeServerMediaConnector();
  await pumpServers(
    tester,
    podcast.podcastWorkspace(repository, connector: connector),
    size: size,
    textScale: textScale,
    light: light,
  );
  await tester.ensureVisible(join.first);
  await tester.tap(join.first);
  await tester.pumpAndSettle();
  final link = connector.links.single;
  link.setRoster(roster);
  await tester.pumpAndSettle();
  return link;
}

void main() {
  testWidgets('the host sees who asked and for how long, and answers from the '
      'studio, the dock and the channel row', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final hands = StreamController<List<ServerSessionHand>>.broadcast();
    addTearDown(hands.close);
    final repository = _hostRepository(hands);
    await _joinStudio(tester, repository);
    // Nobody asked: no queue, no dock control, no dot — nothing invented.
    expect(requests, findsNothing);
    expect(dockRequests, findsNothing);
    expect(find.byType(ServerWaitingDot), findsNothing);

    hands.add([_handOf('kamil', 'Kamil')]);
    await tester.pumpAndSettle();
    expect(requests, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('server-podcast-scene')),
        matching: requests,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: requests, matching: find.text('Kamil')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: requests, matching: find.text('Czeka 3 min')),
      findsOneWidget,
    );
    expect(find.text('Prośby o głos: 1'), findsOneWidget);
    // The dock and the connected channel row carry the shared dot.
    expect(dockRequests, findsOneWidget);
    expect(
      find.byKey(const ValueKey('server-dock-requests-dot')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('server-channel-waiting-studio')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Czekające prośby o głos: 1'), findsWidgets);

    await tester.ensureVisible(
      find.byKey(const ValueKey('server-stage-request-approve-kamil')),
    );
    await tester.tap(
      find.byKey(const ValueKey('server-stage-request-approve-kamil')),
    );
    await tester.pumpAndSettle();
    expect(repository.calls.last.$1, 'setServerSessionParticipantRoleV1');
    expect(repository.calls.last.$2, {
      'serverId': 's',
      'channelId': 'studio',
      'sessionId': 'gen-7',
      'participantId': 'kamil',
      'role': 'guest',
      'requestId': repository.calls.last.$2['requestId'],
    });

    await tester.tap(
      find.byKey(const ValueKey('server-stage-request-decline-kamil')),
    );
    await tester.pumpAndSettle();
    expect(repository.calls.last.$1, 'answerServerSessionHandV1');
    expect(repository.calls.last.$2['participantId'], 'kamil');
    expect(repository.calls.last.$2['decision'], 'declined');

    // The backend answered: the hand leaves the queue, and every marker
    // leaves with it.
    hands.add(const []);
    await tester.pumpAndSettle();
    expect(requests, findsNothing);
    expect(dockRequests, findsNothing);
    expect(find.byType(ServerWaitingDot), findsNothing);
  });

  testWidgets('somebody who asked and then left is never offered', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final hands = StreamController<List<ServerSessionHand>>.broadcast();
    addTearDown(hands.close);
    await _joinStudio(tester, _hostRepository(hands));
    hands.add([
      _handOf('ola', 'Ola', waited: const Duration(minutes: 9)),
      _handOf('kamil', 'Kamil'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Prośby o głos: 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('server-stage-request-kamil')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('server-stage-request-ola')),
      findsNothing,
    );
  });

  testWidgets('the queue follows the host to any channel through the dock', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final hands = StreamController<List<ServerSessionHand>>.broadcast();
    addTearDown(hands.close);
    final repository = _hostRepository(hands);
    await _joinStudio(tester, repository);
    hands.add([_handOf('kamil', 'Kamil')]);
    await tester.pumpAndSettle();

    // The host browses the discussion channel; the studio scene is gone but
    // the conversation (and its dock) is not.
    await tester.tap(find.byKey(const ValueKey('server-channel-discussion')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-podcast-scene')), findsNothing);
    expect(dockRequests, findsOneWidget);

    await tester.tap(dockRequests);
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('server-stage-requests-sheet'));
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Kamil')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: sheet,
        matching: find.byKey(
          const ValueKey('server-stage-request-decline-kamil'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.calls.last.$1, 'answerServerSessionHandV1');

    // Once answered, the open sheet says so instead of going blank.
    hands.add(const []);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('server-stage-requests-empty')),
      findsOneWidget,
    );
  });

  testWidgets('a refused answer is one sentence, never the raw code', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final hands = StreamController<List<ServerSessionHand>>.broadcast();
    addTearDown(hands.close);
    final repository = _hostRepository(hands);
    await _joinStudio(tester, repository);
    hands.add([_handOf('kamil', 'Kamil')]);
    await tester.pumpAndSettle();
    repository.failNextCall['answerServerSessionHandV1'] = StateError('raw');
    await tester.ensureVisible(
      find.byKey(const ValueKey('server-stage-request-decline-kamil')),
    );
    await tester.tap(
      find.byKey(const ValueKey('server-stage-request-decline-kamil')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('server-stage-requests-error')),
      findsOneWidget,
    );
    expect(find.textContaining('raw'), findsNothing);
  });

  testWidgets('a listener never reads or sees the queue', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final hands = StreamController<List<ServerSessionHand>>.broadcast();
    addTearDown(hands.close);
    final repository = podcast.listenerRepository()
      ..sessionHandsStream = hands.stream;
    await _joinStudio(tester, repository);
    hands.add([_handOf('kamil', 'Kamil')]);
    await tester.pumpAndSettle();
    expect(repository.handQueueReads, isEmpty);
    expect(requests, findsNothing);
    expect(dockRequests, findsNothing);
    expect(find.byType(ServerWaitingDot), findsNothing);
  });

  testWidgets('the listener reads waiting, declined and lowered from their own '
      'document, never that the hosts saw it', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final own = StreamController<ServerSessionParticipantState?>.broadcast();
    addTearDown(own.close);
    final repository = podcast.listenerRepository()
      ..ownParticipantStream = own.stream;
    await _joinStudio(tester, repository, roster: podcast.broadcast);
    own.add(_own());
    await tester.pumpAndSettle();
    expect(find.text('Poproś o głos'), findsOneWidget);
    expect(handState, findsNothing);

    // Pending — even when the hand was raised on another device.
    own.add(_own(hand: true));
    await tester.pumpAndSettle();
    expect(find.text('Anuluj prośbę o głos'), findsOneWidget);
    expect(
      find.text('Prośba wysłana. Czekasz na decyzję prowadzącego.'),
      findsOneWidget,
    );

    // Declined.
    own.add(_own(decision: ServerHandDecision.declined));
    await tester.pumpAndSettle();
    expect(find.text('Poproś o głos'), findsOneWidget);
    expect(
      find.text(
        'Prowadzący tym razem nie zaprosił Cię na scenę. '
        'Możesz poprosić ponownie.',
      ),
      findsOneWidget,
    );

    // Lowered by the backend after a disconnect.
    own.add(_own(decision: ServerHandDecision.lowered));
    await tester.pumpAndSettle();
    expect(find.text('Poproś o głos'), findsOneWidget);
    expect(
      find.text(
        'Twoja prośba wygasła po rozłączeniu z transmisją. '
        'Poproś ponownie, jeśli nadal chcesz zabrać głos.',
      ),
      findsOneWidget,
    );
    expect(find.text('Prowadzący widzą Twoją prośbę.'), findsNothing);

    // Asking again: the receipt answers the press at once, and a newer
    // document snapshot takes over from it.
    await tester.ensureVisible(hand);
    await tester.tap(hand);
    await tester.pumpAndSettle();
    expect(repository.calls.last.$1, 'setServerSessionHandV1');
    expect(repository.calls.last.$2['raised'], isTrue);
    expect(
      find.text('Prośba wysłana. Czekasz na decyzję prowadzącego.'),
      findsOneWidget,
    );
    own.add(_own(decision: ServerHandDecision.declined));
    await tester.pumpAndSettle();
    expect(find.text('Poproś o głos'), findsOneWidget);
  });

  testWidgets('an approved listener moves onto the stage in place: never '
      '"Połączenie zostało przerwane.", microphone still theirs to turn on', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final own = StreamController<ServerSessionParticipantState?>.broadcast();
    addTearDown(own.close);
    final repository = podcast.listenerRepository()
      ..ownParticipantStream = own.stream;
    final connector = FakeServerMediaConnector();
    await pumpServers(
      tester,
      podcast.podcastWorkspace(repository, connector: connector),
      size: const Size(390, 844),
    );
    await tester.tap(join);
    await tester.pumpAndSettle();
    connector.links.single.setRoster(podcast.broadcast);
    own.add(_own(hand: true));
    await tester.pumpAndSettle();

    // The host approves.
    repository
      ..sessionRole = 'guest'
      ..permittedTrackSources = const ['microphone'];
    own.add(
      _own(revision: 2, role: 'guest', decision: ServerHandDecision.approved),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Wchodzisz na scenę…'), findsWidgets);
    expect(find.text('Połączenie zostało przerwane.'), findsNothing);
    // The moment between two tokens is named for what it is, not as an
    // empty studio.
    expect(find.text('Nikt nie jest teraz na antenie.'), findsNothing);
    expect(hand, findsNothing);

    // After the revocation barrier the new token connects.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(connector.links, hasLength(2));
    expect(connector.links.first.disconnects, 1);
    expect(find.text('Połączenie zostało przerwane.'), findsNothing);
    expect(hand, findsNothing);
    expect(
      find.text('Jesteś na scenie. Włącz mikrofon, gdy chcesz mówić.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('server-dock-microphone')),
      findsOneWidget,
    );
    expect(connector.links.last.microphoneCalls, isEmpty);
    expect(repository.releases, isEmpty);
    expect(pumpedVoiceDevice.keepAliveStops, 0);
  });

  for (final (size, textScale, light) in [
    (const Size(390, 844), 1.0, false),
    (const Size(390, 844), 2.0, true),
    (const Size(768, 1024), 1.0, true),
    (const Size(768, 1024), 2.0, false),
    (const Size(1280, 800), 1.0, false),
    (const Size(1280, 800), 2.0, true),
  ]) {
    testWidgets(
      'the queue keeps every answer reachable at ${size.width.toInt()} '
      'px, ${(textScale * 100).toInt()} % text, ${light ? 'Pearl' : 'Dark'}',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final hands = StreamController<List<ServerSessionHand>>.broadcast();
        addTearDown(hands.close);
        final repository = _hostRepository(hands);
        await _joinStudio(
          tester,
          repository,
          size: size,
          textScale: textScale,
          light: light,
        );
        hands.add([_handOf('kamil', 'Kamil Długonazwiskowski-Wielkopolski')]);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(dockRequests, findsOneWidget);
        for (final key in [
          'server-stage-request-approve-kamil',
          'server-stage-request-decline-kamil',
        ]) {
          final button = find.byKey(ValueKey(key));
          expect(button, findsOneWidget);
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          expect(button.hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the shared waiting dot speaks its count and is absent when '
      'nothing waits', (tester) async {
    final handle = tester.ensureSemantics();
    for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                ServerWaitingDot.on(
                  waiting: true,
                  semanticLabel: '2 waiting to speak',
                  dotKey: const ValueKey('dot'),
                  child: const Icon(Icons.podcasts_rounded),
                ),
                ServerWaitingDot.on(
                  waiting: false,
                  semanticLabel: 'never shown',
                  child: const Icon(Icons.mic_rounded),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('dot')), findsOneWidget);
      expect(find.bySemanticsLabel('2 waiting to speak'), findsOneWidget);
      expect(find.bySemanticsLabel('never shown'), findsNothing);
      expect(find.byType(ServerWaitingDot), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('dot'))),
        const Size(10, 10),
      );
    }
    handle.dispose();
  });
}
