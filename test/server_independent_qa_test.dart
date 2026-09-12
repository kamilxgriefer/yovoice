import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_template.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import 'server_independent_qa_support.dart';
import 'server_test_support.dart';

/// Independent QA of the in-server shell and the five template boards.
///
/// Written against the contract and the four slice reports' own claims, not
/// against the suites those slices shipped. Every assertion here answers one
/// of the questions the QA brief asks: which states exist, which controls are
/// honestly unavailable, who can see a restricted channel, what the join path
/// actually calls, and whether anything opens a device on its own.
///
/// The layout matrix (six widths × two text sizes × in-session × long names)
/// lives in `server_independent_qa_layout_test.dart`.

/// A repository whose channel stream fails once and succeeds on the next
/// subscription, which is what "error with retry" has to mean: the retry
/// resubscribes rather than redrawing the same dead stream.
class _FailingOnceRepository extends TestServerRepository {
  int subscriptions = 0;

  @override
  Stream<List<ServerChannel>> watchChannels(String serverId) {
    subscriptions++;
    if (subscriptions == 1) {
      return Stream<List<ServerChannel>>.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
    }
    return Stream.value(channels);
  }
}

void main() {
  // The honesty guard is the single assertion the whole "no invented
  // presence" case rests on, so it is itself pinned: a net nobody has tested
  // is a net that quietly stops catching things. The strings below are the
  // mockups' own wording (contract §4.2) — the exact copy that must never be
  // renderable — and the member count, which must stay renderable.
  group('the presence guard catches the mockups and spares the member count', () {
    test('every presence claim the five boards were drawn with is caught', () {
      for (final claim in const [
        '4 osoby rozmawiają',
        'LIVE · 126 widzów',
        '84 słuchaczy',
        'Publiczność · 84 słuchaczy',
        'Teraz rozmawiają 3 osoby',
        'Spotkanie zespołu / 6 uczestników',
        '6 osób potwierdziło',
        '12 reakcji',
        '8 głosów',
      ]) {
        expect(
          qaFabricatedCount.hasMatch(claim),
          isTrue,
          reason: 'the guard would let "$claim" through',
        );
      }
    });

    test('the member count the backend really writes is not caught', () {
      for (final honest in const [
        '12 osób',
        '12 osób w serwerze',
        'Prywatny serwer · 12 osób',
        'Społeczność · 248 osób',
        'Przestrzeń firmowa · 24 osoby',
        'Nikt jeszcze nie rozmawia',
        'Pytania słuchaczy',
        'Znajome głosy. Te same historie.',
        'Rodzinne terminy i kto już potwierdził.',
      ]) {
        expect(
          qaFabricatedCount.hasMatch(honest),
          isFalse,
          reason: 'the guard would fail the surface for "$honest"',
        );
      }
    });
  });

  group('the states one surface has to be able to be in', () {
    testWidgets('loading draws a spoken spinner and calls nothing', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [320.0, 768.0, 1440.0]) {
        final repository = TestServerRepository()
          ..servers = [qaServer(ServerType.friends)]
          ..channels = qaChannels(ServerType.friends)
          // A subscription that has not produced its first snapshot yet:
          // never emits, never closes.
          ..serverStream = Completer<Server?>().future.asStream()
          ..channelStream =
              Completer<List<ServerChannel>>().future.asStream();
        await pumpServers(
          tester,
          qaWorkspace(repository, channelId: qaFirstMedia(ServerType.friends)),
          size: Size(width, 760),
          settle: false,
        );
        await tester.pump();
        final reason = 'loading at $width';
        expect(
          find.byType(CircularProgressIndicator),
          findsWidgets,
          reason: reason,
        );
        expect(qaJoin, findsNothing, reason: reason);
        expect(qaDock, findsNothing, reason: reason);
        expect(repository.calls, isEmpty, reason: reason);
        expect(tester.takeException(), isNull, reason: reason);
      }
    });

    testWidgets('a failed channel read shows an error whose retry resubscribes',
        (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _FailingOnceRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: qaFirstMedia(ServerType.friends)),
        size: const Size(768, 900),
      );
      expect(find.byType(YoErrorState), findsOneWidget);
      expect(qaJoin, findsNothing);
      expect(repository.subscriptions, 1);

      final retry = find.descendant(
        of: find.byType(YoErrorState),
        matching: find.text('Spróbuj ponownie'),
      );
      expect(retry, findsOneWidget, reason: 'an error without a way out');
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(repository.subscriptions, greaterThan(1));
      expect(find.byType(YoErrorState), findsNothing);
      expect(qaPanel, findsOneWidget);
      expect(repository.calls, isEmpty, reason: 'a retry is not a join');
    });

    testWidgets('a server with no channels says so and offers no scene', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [320.0, 768.0, 1440.0]) {
        final repository = TestServerRepository()
          ..servers = [qaServer(ServerType.community)]
          ..channels = const [];
        await pumpServers(
          tester,
          qaWorkspace(repository, channelId: 'nothing'),
          size: Size(width, 760),
        );
        final reason = 'empty at $width';
        expect(tester.takeException(), isNull, reason: reason);
        expect(qaJoin, findsNothing, reason: reason);
        expect(qaDock, findsNothing, reason: reason);
        expect(qaLivePill, findsNothing, reason: reason);
        expect(repository.calls, isEmpty, reason: reason);
      }
    });

    testWidgets(
      'a held root offers an inert join and an inert invite in every template',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final type in ServerType.values) {
          for (final width in [390.0, 1440.0]) {
            final repository = TestServerRepository()
              ..servers = [qaServer(type, held: true)]
              ..channels = qaChannels(type);
            await pumpServers(
              tester,
              qaWorkspace(repository, channelId: qaJoinableChannel(type)),
              size: Size(width, 820),
            );
            final reason = 'held $type at $width';
            expect(tester.takeException(), isNull, reason: reason);
            expect(qaLivePill, findsNothing, reason: reason);
            expect(qaDock, findsNothing, reason: reason);
            for (final join in tester.widgetList<ButtonStyleButton>(qaJoin)) {
              expect(
                join.onPressed,
                isNull,
                reason: '$reason — a held root offered a live join',
              );
            }
            if (width >= 768) {
              final invite = find.byKey(
                const ValueKey('server-invite-action'),
              );
              expect(invite, findsOneWidget, reason: reason);
              expect(
                tester.widget<ButtonStyleButton>(invite).onPressed,
                isNull,
                reason: '$reason — a held root offered a live invite',
              );
            }
            expect(repository.calls, isEmpty, reason: reason);
          }
        }
      },
    );

    testWidgets(
      'a provider that drops an established link says so and offers a retry',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()
          ..servers = [qaServer(ServerType.friends)]
          ..channels = qaChannels(ServerType.friends);
        final connector = FakeServerMediaConnector();
        await pumpServers(
          tester,
          qaWorkspace(
            repository,
            channelId: qaFirstMedia(ServerType.friends),
            connector: connector,
          ),
          size: const Size(1440, 900),
        );
        final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);
        expect(qaDock, findsOneWidget);

        link.report(ServerMediaLinkState.disconnected);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Połączenie zostało przerwane'),
          findsWidgets,
          reason: 'a dropped link has to be named, not silently idle',
        );
        expect(
          find.byKey(const ValueKey('server-join-retry')),
          findsWidgets,
          reason: 'a dropped link with no way back is a dead end',
        );
        qaExpectNoMatch(
          tester,
          qaFabricatedCount,
          'a dropped link invented presence',
        );
      },
    );
  });

  group('nothing opens a device by itself', () {
    testWidgets(
      'opening a server, browsing its channels and switching tabs starts no '
      'capture and calls nothing',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final type in ServerType.values) {
          final repository = TestServerRepository()
            ..servers = [qaServer(type)]
            ..channels = qaChannels(type);
          final connector = FakeServerMediaConnector();
          await pumpServers(
            tester,
            qaWorkspace(
              repository,
              channelId: qaJoinableChannel(type),
              connector: connector,
            ),
            size: const Size(1440, 900),
          );
          // Walk every channel the panel offers.
          for (final channel in qaChannels(type)) {
            final row = find.byKey(ValueKey('server-channel-${channel.id}'));
            if (row.evaluate().isEmpty) continue;
            await tester.ensureVisible(row);
            await tester.tap(row);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$type → ${channel.id}',
            );
          }
          expect(
            connector.connections,
            isEmpty,
            reason: '$type reached the provider without being asked to',
          );
          expect(
            repository.calls,
            isEmpty,
            reason: '$type called a callable by merely being opened',
          );
        }
      },
    );

    testWidgets(
      'joining connects the link and still opens no microphone, camera or '
      'screen in any template',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final type in ServerType.values) {
          final repository = TestServerRepository()
            ..servers = [qaServer(type)]
            ..channels = qaChannels(type);
          final connector = FakeServerMediaConnector();
          await pumpServers(
            tester,
            qaWorkspace(
              repository,
              channelId: qaJoinableChannel(type),
              connector: connector,
            ),
            size: const Size(1440, 900),
          );
          final link = await qaJoinAndSettle(
            tester,
            connector,
            roster: qaRoster,
          );
          final reason = '$type after joining';
          expect(connector.connections, hasLength(1), reason: reason);
          expect(link.microphoneCalls, isEmpty, reason: reason);
          expect(link.screenShareCalls, isEmpty, reason: reason);
          expect(link.isMicrophoneEnabled, isFalse, reason: reason);
          expect(link.isScreenShareEnabled, isFalse, reason: reason);
          expect(link.isDeafened, isFalse, reason: reason);
        }
      },
    );

    testWidgets(
      'the microphone opens only when its own control is pressed, and only '
      'with a grant that permits it',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()
          ..servers = [qaServer(ServerType.friends)]
          ..channels = qaChannels(ServerType.friends);
        final connector = FakeServerMediaConnector();
        await pumpServers(
          tester,
          qaWorkspace(
            repository,
            channelId: qaFirstMedia(ServerType.friends),
            connector: connector,
          ),
          size: const Size(1440, 900),
        );
        final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);
        expect(link.microphoneCalls, isEmpty);

        final control = find.byKey(const ValueKey('server-dock-microphone'));
        expect(control, findsOneWidget);
        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(link.microphoneCalls, [true]);
        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(link.microphoneCalls, [true, false]);
      },
    );

    testWidgets(
      'a listener grant carries no microphone control at all, so nothing can '
      'be pressed into failing',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()
          ..servers = [qaServer(ServerType.podcast)]
          ..channels = qaChannels(
            ServerType.podcast,
            liveness: ServerChannelLiveness(
              isLive: true,
              startedAt: DateTime(2026, 9, 12, 19, 40),
            ),
            activeSessionId: 'session-live',
          )
          ..sessionRole = 'listener'
          ..permittedTrackSources = const [];
        final connector = FakeServerMediaConnector();
        await pumpServers(
          tester,
          qaWorkspace(
            repository,
            channelId: qaFirstMedia(ServerType.podcast),
            connector: connector,
          ),
          size: const Size(1440, 900),
        );
        final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);
        expect(
          find.byKey(const ValueKey('server-dock-microphone')),
          findsNothing,
          reason: 'a listener was offered a microphone their grant refuses',
        );
        expect(
          find.byKey(const ValueKey('server-session-microphone')),
          findsNothing,
          reason: 'a listener was offered a microphone on the scene',
        );
        expect(link.microphoneCalls, isEmpty);
        expect(find.textContaining('Słuchasz'), findsWidgets);
      },
    );
  });

  group('the reviewed join path, and nothing beside it', () {
    testWidgets('every template joins through start → token → provider', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final type in ServerType.values) {
        final repository = TestServerRepository()
          ..servers = [qaServer(type)]
          ..channels = qaChannels(type);
        final connector = FakeServerMediaConnector();
        final media = qaJoinableChannel(type);
        await pumpServers(
          tester,
          qaWorkspace(repository, channelId: media, connector: connector),
          size: const Size(1440, 900),
        );
        await qaJoinAndSettle(tester, connector);
        expect(
          repository.calls.map((call) => call.$1).toList(),
          ['startServerChannelSessionV1', 'createServerChannelTokenV1'],
          reason: '$type joined through something other than the reviewed path',
        );
        expect(repository.calls[0].$2, {
          'serverId': 's',
          'channelId': media,
          'requestId': 'request-1',
        });
        expect(repository.calls[1].$2, {
          'serverId': 's',
          'channelId': media,
          'sessionId': 'session-1',
          'requestId': 'request-2',
        });
        expect(connector.connections.single.$1, 'wss://livekit.test');
        expect(connector.connections.single.$2, 'token-session-1');
      }
    });

    testWidgets('a generation that is already live is not started again', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(
          ServerType.friends,
          liveness: ServerChannelLiveness(
            isLive: true,
            startedAt: DateTime(2026, 9, 12, 19, 40),
          ),
          activeSessionId: 'already-live',
        );
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(
          repository,
          channelId: qaFirstMedia(ServerType.friends),
          connector: connector,
        ),
        size: const Size(1440, 900),
      );
      await qaJoinAndSettle(tester, connector);
      expect(repository.calls.map((call) => call.$1).toList(), [
        'createServerChannelTokenV1',
      ]);
      expect(repository.calls.single.$2['sessionId'], 'already-live');
    });

    testWidgets(
      'the device\'s other voice owner blocks the join before any call is made',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()
          ..servers = [qaServer(ServerType.family)]
          ..channels = qaChannels(ServerType.family);
        final connector = FakeServerMediaConnector();
        await pumpServers(
          tester,
          qaWorkspace(
            repository,
            channelId: qaFirstMedia(ServerType.family),
            connector: connector,
            anotherVoiceSessionActive: () => true,
          ),
          size: const Size(1440, 900),
        );
        await tester.tap(qaJoin);
        await tester.pumpAndSettle();
        expect(repository.calls, isEmpty);
        expect(connector.connections, isEmpty);
        expect(
          find.textContaining('Najpierw zakończ trwającą rozmowę'),
          findsWidgets,
        );
      },
    );

    testWidgets('an unregistered callable reads as "still being prepared"', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.community)]
        ..channels = qaChannels(ServerType.community)
        ..failNextCall['startServerChannelSessionV1'] =
            FirebaseFunctionsException(
              code: 'not-found',
              message: 'NOT_FOUND',
            );
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(
          repository,
          channelId: qaFirstMedia(ServerType.community),
          connector: connector,
        ),
        size: const Size(1440, 900),
      );
      await tester.tap(qaJoin);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('jeszcze przygotowywana'),
        findsWidgets,
        reason: 'the raw callable code reached the reader',
      );
      for (final rendered in qaRenderedStrings(tester)) {
        expect(rendered, isNot(contains('NOT_FOUND')));
        expect(rendered, isNot(contains('not-found')));
      }
      expect(connector.connections, isEmpty);
    });

    testWidgets('a failed join can be retried and then succeeds', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends)
        ..failNextCall['startServerChannelSessionV1'] =
            FirebaseFunctionsException(
              code: 'unavailable',
              message: 'Offline',
            );
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(
          repository,
          channelId: qaFirstMedia(ServerType.friends),
          connector: connector,
        ),
        size: const Size(1440, 900),
      );
      await tester.tap(qaJoin);
      await tester.pumpAndSettle();
      expect(connector.connections, isEmpty);

      final retry = find.byKey(const ValueKey('server-join-retry'));
      expect(retry, findsOneWidget);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(connector.connections, hasLength(1));
      expect(
        repository.calls.map((call) => call.$1).toList(),
        [
          'startServerChannelSessionV1',
          'startServerChannelSessionV1',
          'createServerChannelTokenV1',
        ],
      );
    });

    testWidgets(
      'moving to another media channel while connected leaves the first one '
      'and starts exactly one new session',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()
          ..servers = [qaServer(ServerType.friends)]
          ..channels = qaChannels(ServerType.friends);
        final connector = FakeServerMediaConnector();
        await pumpServers(
          tester,
          qaWorkspace(
            repository,
            channelId: 'lounge',
            connector: connector,
          ),
          size: const Size(1440, 900),
        );
        final first = await qaJoinAndSettle(tester, connector);
        await tester.tap(find.byKey(const ValueKey('server-channel-gaming')));
        await tester.pumpAndSettle();
        // Browsing keeps the conversation; only an explicit join moves it.
        expect(qaDock, findsOneWidget);
        expect(first.disconnects, 0);
        await tester.tap(qaJoin);
        await tester.pumpAndSettle();
        expect(first.disconnects, 1);
        expect(connector.links, hasLength(2));
        expect(
          repository.calls.map((call) => call.$1).toList(),
          [
            'startServerChannelSessionV1',
            'createServerChannelTokenV1',
            'startServerChannelSessionV1',
            'createServerChannelTokenV1',
          ],
        );
        expect(repository.calls[2].$2['channelId'], 'gaming');
      },
    );

    testWidgets('leaving releases the link and ends nothing server-side', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(
          repository,
          channelId: qaFirstMedia(ServerType.friends),
          connector: connector,
        ),
        size: const Size(1440, 900),
      );
      final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);
      final before = repository.calls.length;
      await tester.tap(qaLeave);
      await tester.pumpAndSettle();
      expect(link.disconnects, 1);
      expect(qaDock, findsNothing);
      expect(qaJoin, findsOneWidget, reason: 'leaving has to be reversible');
      expect(
        repository.calls.length,
        before,
        reason: 'leaving called something server-side; it must not',
      );
    });

    testWidgets(
      'a member without moderator power is told a quiet stage is not live '
      'instead of being given a start button the Rules would refuse',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final type in [ServerType.community, ServerType.podcast]) {
          final stage = serverTemplateChannelsFor(
            type,
          ).firstWhere((seed) => seed.kind == ServerChannelKind.stage).seedKey;
          final repository = TestServerRepository()
            ..servers = [qaServer(type)]
            ..channels = qaChannels(type)
            ..myRole = ServerMemberRole.member;
          final connector = FakeServerMediaConnector();
          await pumpServers(
            tester,
            qaWorkspace(
              repository,
              channelId: stage,
              connector: connector,
            ),
            size: const Size(1440, 900),
          );
          expect(
            qaJoin,
            findsNothing,
            reason: '$type offered a listener a stage start',
          );
          expect(
            find.textContaining('Będzie można słuchać'),
            findsWidgets,
            reason: '$type left a listener with no explanation',
          );
          expect(repository.calls, isEmpty);
        }
      },
    );
  });

  group('controls that cannot work are visibly unavailable', () {
    testWidgets(
      'every disabled control a person can reach stays silent when pressed',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final type in ServerType.values) {
          for (final width in [390.0, 1440.0]) {
            final repository = TestServerRepository()
              ..servers = [qaServer(type)]
              ..channels = qaChannels(type);
            final connector = FakeServerMediaConnector();
            await pumpServers(
              tester,
              qaWorkspace(
                repository,
                channelId: qaJoinableChannel(type),
                connector: connector,
              ),
              size: Size(width, 900),
            );
            final inert = find
                .byWidgetPredicate(
                  (widget) =>
                      widget is ButtonStyleButton &&
                      widget.onPressed == null &&
                      widget.onLongPress == null,
                )
                .hitTestable();
            final count = inert.evaluate().length;
            for (var index = 0; index < count; index++) {
              await tester.tap(inert.at(index), warnIfMissed: false);
            }
            await tester.pumpAndSettle();
            final reason = '$type at $width: $count inert controls';
            expect(tester.takeException(), isNull, reason: reason);
            expect(repository.calls, isEmpty, reason: reason);
            expect(connector.connections, isEmpty, reason: reason);
          }
        }
      },
    );

    testWidgets(
      'the modules with no persistence are named, labelled and disabled, '
      'never silently missing',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        // Each board's honest modules, on the destination that board is
        // about (board 03's is the home view, which has no channel id).
        const modules = <ServerType, List<String>>{
          ServerType.friends: ['server-friends-event-card'],
          ServerType.family: [
            'server-family-plans',
            'server-family-memories',
            'server-family-shopping',
          ],
          ServerType.podcast: [
            'server-podcast-next-episode',
            'server-podcast-recent-episodes',
          ],
          ServerType.community: ['server-community-event-card'],
        };
        for (final entry in modules.entries) {
          final type = entry.key;
          final repository = TestServerRepository()
            ..servers = [qaServer(type)]
            ..channels = qaChannels(type);
          await pumpServers(
            tester,
            qaWorkspace(repository, channelId: qaBoardChannel(type)),
            size: const Size(1440, 940),
          );
          for (final key in entry.value) {
            final card = find.byKey(ValueKey(key));
            expect(card, findsOneWidget, reason: '$type is missing $key');
            expect(
              find.descendant(
                of: card,
                matching: find.textContaining('Wkrótce'),
              ),
              findsWidgets,
              reason: '$key promises something without saying it cannot',
            );
            for (final button in tester.widgetList<ButtonStyleButton>(
              find.descendant(of: card, matching: find.byType(ButtonStyleButton)),
            )) {
              expect(
                button.onPressed,
                isNull,
                reason: '$key carries a live action with nothing behind it',
              );
            }
          }
          expect(repository.calls, isEmpty);
        }
      },
    );

    testWidgets(
      'a module card is not drawn at all when its channel does not exist',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()
          ..servers = [qaServer(ServerType.family)]
          ..channels = qaChannels(ServerType.family)
              .where(
                (channel) =>
                    channel.kind != ServerChannelKind.calendar &&
                    channel.kind != ServerChannelKind.memories &&
                    channel.kind != ServerChannelKind.list,
              )
              .toList();
        await pumpServers(
          tester,
          qaWorkspace(repository),
          size: const Size(1440, 940),
        );
        for (final key in [
          'server-family-plans',
          'server-family-memories',
          'server-family-shopping',
        ]) {
          expect(
            find.byKey(ValueKey(key)),
            findsNothing,
            reason: '$key was drawn for a channel that does not exist',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the podcast never claims a transmission is being recorded',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final live in [false, true]) {
          final repository = TestServerRepository()
            ..servers = [qaServer(ServerType.podcast)]
            ..channels = qaChannels(
              ServerType.podcast,
              liveness: live
                  ? ServerChannelLiveness(
                      isLive: true,
                      startedAt: DateTime(2026, 9, 12, 19, 40),
                    )
                  : ServerChannelLiveness.idle,
              activeSessionId: live ? 'session-live' : null,
            );
          final connector = FakeServerMediaConnector();
          await pumpServers(
            tester,
            qaWorkspace(
              repository,
              channelId: qaFirstMedia(ServerType.podcast),
              connector: connector,
            ),
            size: const Size(1440, 940),
          );
          qaExpectNoMatch(
            tester,
            qaRecordingClaim,
            'the studio claimed a recording (live: $live)',
          );
          if (live) {
            await qaJoinAndSettle(tester, connector, roster: qaRoster);
            qaExpectNoMatch(
              tester,
              qaRecordingClaim,
              'the studio claimed a recording in session',
            );
          }
        }
      },
    );

    testWidgets(
      'no surface of any template renders a number of people, in any state',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final type in ServerType.values) {
          List<ServerChannel> live() => qaChannels(
            type,
            liveness: ServerChannelLiveness(
              isLive: true,
              startedAt: DateTime(2026, 9, 12, 19, 40),
            ),
            activeSessionId: 'session-live',
          );
          // The board's own destination, before anybody joins.
          await pumpServers(
            tester,
            qaWorkspace(
              TestServerRepository()
                ..servers = [qaServer(type, members: 126)]
                ..channels = live(),
              channelId: qaBoardChannel(type),
            ),
            size: const Size(1440, 940),
          );
          qaExpectNoMatch(tester, qaFabricatedCount, '$type before joining');

          // And the same board with a real roster on screen.
          final connector = FakeServerMediaConnector();
          await pumpServers(
            tester,
            qaWorkspace(
              TestServerRepository()
                ..servers = [qaServer(type, members: 126)]
                ..channels = live(),
              channelId: qaJoinableChannel(type),
              connector: connector,
            ),
            size: const Size(1440, 940),
          );
          await qaJoinLive(tester, connector, roster: qaRoster);
          qaExpectNoMatch(tester, qaFabricatedCount, '$type in session');
        }
      },
    );
  });

  group('a restricted channel is invisible without its own pointer', () {
    /// The company seeds, shaped exactly as `createServerV1` writes them.
    Future<FakeFirebaseFirestore> seedCompany() async {
      final firestore = FakeFirebaseFirestore();
      await firestore.doc('clubs/s').set({
        'serverSchemaVersion': 1,
        'serverType': 'company',
        'name': 'Studio North',
        'ownerId': 'boss',
        'privacy': 'inviteOnly',
        'serverActivationState': 'active',
        'status': 'active',
        'memberCount': 24,
        'defaultChannelId': 'general',
      });
      final seeds = serverTemplateChannelsFor(ServerType.company);
      for (var index = 0; index < seeds.length; index++) {
        final seed = seeds[index];
        await firestore.doc('clubs/s/channels/${seed.seedKey}').set({
          'serverSchemaVersion': 1,
          'serverId': 's',
          'name': seed.polishName,
          'kind': seed.kind.name,
          'accessMode': seed.restricted ? 'restricted' : 'members',
          'isPrivate': seed.restricted,
          'status': 'active',
          'position': index,
          if (seed.kind.isMedia) ...{
            'roomId': 'room-${seed.seedKey}',
            'experience': 'community',
            'mediaMode': seed.mediaMode!.name,
          },
        });
      }
      return firestore;
    }

    ServerService serviceFor(FakeFirebaseFirestore firestore) => ServerService(
      firestore: firestore,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u')),
    );

    test('a member with no pointer never receives the restricted rows', () async {
      final firestore = await seedCompany();
      final channels = await serviceFor(firestore).watchChannels('s').first;
      expect(channels.map((channel) => channel.id), [
        'general',
        'announcements',
        'team',
        'projects',
        'meeting',
        'board',
        'files',
      ]);
      expect(
        channels.any(
          (channel) => channel.access == ServerChannelAccess.restricted,
        ),
        isFalse,
      );
    });

    test('one pointer opens exactly one row and never its sibling', () async {
      final firestore = await seedCompany();
      await firestore.doc('users/u/serverChannelRefs/hr').set({
        'serverId': 's',
        'channelId': 'hr',
      });
      final channels = await serviceFor(firestore).watchChannels('s').first;
      final ids = channels.map((channel) => channel.id).toList();
      expect(ids, contains('hr'));
      expect(
        ids,
        isNot(contains('boardroom')),
        reason: 'a row nobody pointed at arrived anyway',
      );
      expect(
        channels.firstWhere((channel) => channel.id == 'hr').access,
        ServerChannelAccess.restricted,
      );
      // Position order survives the merge: `hr` is seeded at 4, between
      // `projects` (3) and `boardroom` (5).
      expect(ids.indexOf('hr'), ids.indexOf('projects') + 1);
    });

    test(
      'a pointer at a channel that no longer exists drops quietly and keeps '
      'the rest of the list',
      () async {
        final firestore = await seedCompany();
        await firestore.doc('users/u/serverChannelRefs/gone').set({
          'serverId': 's',
          'channelId': 'deleted-long-ago',
        });
        final channels = await serviceFor(firestore).watchChannels('s').first;
        expect(channels.map((channel) => channel.id), contains('general'));
        expect(
          channels.map((channel) => channel.id),
          isNot(contains('deleted-long-ago')),
        );
      },
    );

    test('a pointer belonging to another server is not followed', () async {
      final firestore = await seedCompany();
      await firestore.doc('users/u/serverChannelRefs/elsewhere').set({
        'serverId': 'other-server',
        'channelId': 'hr',
      });
      final channels = await serviceFor(firestore).watchChannels('s').first;
      expect(
        channels.map((channel) => channel.id),
        isNot(contains('hr')),
        reason: 'a pointer scoped to another server opened a row here',
      );
    });

    testWidgets(
      'the panel shows a restricted row only when the repository returned it, '
      'and names it with a lock',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final without = TestServerRepository()
          ..servers = [qaServer(ServerType.company)]
          ..channels = qaChannels(ServerType.company, restricted: false);
        await pumpServers(
          tester,
          qaWorkspace(without, channelId: 'meeting'),
          size: const Size(1440, 940),
        );
        expect(find.byKey(const ValueKey('server-channel-hr')), findsNothing);
        expect(
          find.byKey(const ValueKey('server-channel-boardroom')),
          findsNothing,
        );
        for (final rendered in qaRenderedStrings(tester)) {
          expect(
            rendered,
            isNot(equals('HR')),
            reason: 'a channel the query never returned was named anyway',
          );
          expect(rendered, isNot(equals('Zarząd')));
        }

        final with_ = TestServerRepository()
          ..servers = [qaServer(ServerType.company)]
          ..channels = qaChannels(ServerType.company);
        await pumpServers(
          tester,
          qaWorkspace(with_, channelId: 'meeting'),
          size: const Size(1440, 940),
        );
        final row = find.byKey(const ValueKey('server-channel-hr'));
        expect(row, findsOneWidget);
        expect(
          find.descendant(of: row, matching: find.byIcon(Icons.lock_outline)),
          findsOneWidget,
          reason: 'a restricted row was drawn like any other',
        );
      },
    );

    testWidgets(
      'board 04\'s panel search filters what is on screen and reveals nothing '
      'that is not',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()
          ..servers = [qaServer(ServerType.company)]
          ..channels = qaChannels(ServerType.company, restricted: false);
        await pumpServers(
          tester,
          qaWorkspace(repository, channelId: 'meeting'),
          size: const Size(1440, 940),
        );
        await tester.enterText(
          find.byKey(const ValueKey('server-panel-search')),
          'hr',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('server-channel-hr')), findsNothing);
        expect(
          find.byKey(const ValueKey('server-panel-search-empty')),
          findsOneWidget,
          reason: 'an empty result has to say it found nothing',
        );
        expect(repository.calls, isEmpty);
      },
    );
  });
}
