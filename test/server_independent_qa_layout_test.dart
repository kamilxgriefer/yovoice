import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_session.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';

import 'server_independent_qa_support.dart';
import 'server_test_support.dart';

/// Independent QA of the shell's and the five boards' behaviour by available
/// width, at the reader's own text size, and with content nobody sized for.
///
/// The width matrix the slices ran covers the surfaces **before** a join. The
/// states that actually break a layout are the ones with a roster, a live
/// marker and a dock on screen at once, and the ones where a real name is
/// longer than the column it was drawn for; those are what this file renders.
void main() {
  group('every template survives every width, in session', () {
    testWidgets(
      'a joined conversation renders at six widths and at 200 percent with a '
      'reachable way out and no invented presence',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final type in ServerType.values) {
          for (final width in qaWidths) {
            for (final scale in [1.0, 2.0]) {
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
                size: Size(width, 760),
                textScale: scale,
                light: scale == 2,
              );
              final reason = 'in session: $type $width ×$scale';
              expect(tester.takeException(), isNull, reason: reason);
              final link = await qaJoinAndSettle(
                tester,
                connector,
                roster: qaRoster,
              );
              expect(tester.takeException(), isNull, reason: reason);
              expect(qaDock, findsOneWidget, reason: reason);
              expect(
                qaLeave,
                findsOneWidget,
                reason: '$reason — no way out of the conversation',
              );
              expect(
                tester.getRect(qaLeave).right,
                lessThanOrEqualTo(width + 0.5),
                reason: '$reason — the leave control is off the surface',
              );
              expect(
                link.microphoneCalls,
                isEmpty,
                reason: '$reason — the layout opened a microphone',
              );
              qaExpectNoMatch(tester, qaFabricatedCount, reason);
            }
          }
        }
      },
    );

    testWidgets(
      'a live generation on screen keeps its marker and its start time at '
      'every width and text size',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final type in ServerType.values) {
          for (final width in qaWidths) {
            for (final scale in [1.0, 2.0]) {
              final repository = TestServerRepository()
                ..servers = [qaServer(type)]
                ..channels = qaChannels(
                  type,
                  liveness: ServerChannelLiveness(
                    isLive: true,
                    startedAt: DateTime(2026, 9, 12, 19, 40),
                  ),
                  activeSessionId: 'session-live',
                );
              await pumpServers(
                tester,
                qaWorkspace(repository, channelId: qaJoinableChannel(type)),
                size: Size(width, 760),
                textScale: scale,
                light: scale == 2,
              );
              final reason = 'live: $type $width ×$scale';
              expect(tester.takeException(), isNull, reason: reason);
              expect(
                qaLivePill,
                findsWidgets,
                reason: '$reason — a live generation showed no marker',
              );
              final markers = qaLivePill.evaluate().length;
              for (var index = 0; index < markers; index++) {
                expect(
                  tester.getSize(qaLivePill.at(index)).height,
                  greaterThan(8),
                  reason: '$reason — a live marker was crushed to a bar',
                );
              }
              expect(
                find.textContaining('Na żywo od'),
                findsWidgets,
                reason: '$reason — live without saying since when',
              );
              qaExpectNoMatch(tester, qaFabricatedCount, reason);
            }
          }
        }
      },
    );
  });

  group('names nobody sized for', () {
    testWidgets(
      'a very long server name and very long channel names break no template '
      'at any width',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const cases = [(320.0, 2.0), (390.0, 1.0), (768.0, 1.0), (1440.0, 1.0), (1920.0, 2.0)];
        for (final type in ServerType.values) {
          for (final (width, scale) in cases) {
            final repository = TestServerRepository()
              ..servers = [qaServer(type, name: qaLongServerName)]
              ..channels = qaChannels(type, longNames: true);
            await pumpServers(
              tester,
              qaWorkspace(repository, channelId: qaJoinableChannel(type)),
              size: Size(width, 760),
              textScale: scale,
              light: scale == 2,
            );
            final reason = 'long names: $type $width ×$scale';
            expect(tester.takeException(), isNull, reason: reason);
            // The surface still works: the panel (or its phone entry) and the
            // one explicit action are both there.
            if (width < ServerWorkspaceScreen.tabletBreakpoint) {
              expect(qaOpenChannels, findsOneWidget, reason: reason);
            } else {
              expect(qaPanel, findsOneWidget, reason: reason);
            }
            qaExpectNoMatch(tester, qaFabricatedCount, reason);
          }
        }
      },
    );

    testWidgets(
      'the phone channel sheet stays usable with long names at 320 px and '
      '200 percent text',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()
          ..servers = [qaServer(ServerType.company, name: qaLongServerName)]
          ..channels = qaChannels(ServerType.company, longNames: true);
        await pumpServers(
          tester,
          qaWorkspace(repository, channelId: 'meeting'),
          size: const Size(320, 760),
          textScale: 2,
        );
        await tester.tap(qaOpenChannels);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final row = find.byKey(const ValueKey('server-channel-general'));
        expect(row, findsOneWidget, reason: 'the sheet dropped a channel row');
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(repository.calls, isEmpty);
      },
    );

    testWidgets(
      'a long server name and long friend names leave the invite sheet usable',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()
          ..servers = [qaServer(ServerType.friends, name: qaLongServerName)]
          ..channels = qaChannels(ServerType.friends)
          ..friends = const [
            ServerInviteCandidate(
              id: 'f1',
              displayName:
                  'Aleksandra Konstantynopolitańczykowiczówna-Nowakowska '
                  'z Bardzo Długim Nazwiskiem',
            ),
          ];
        await pumpServers(
          tester,
          qaWorkspace(repository, channelId: 'lounge'),
          size: const Size(320, 760),
          textScale: 2,
        );
        await tester.tap(qaOpenChannels);
        await tester.pumpAndSettle();
        final invite = find.byKey(const ValueKey('server-invite-action'));
        await tester.ensureVisible(invite);
        await tester.tap(invite);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final person = find.byKey(const ValueKey('server-invite-f1'));
        expect(person, findsOneWidget);
        await tester.ensureVisible(person);
        // `find.byType` matches the EXACT runtime type, and
        // `ButtonStyleButton` is abstract — the original spelling of this
        // assertion could never match the row's `FilledButton.tonal` and
        // always reported zero. The predicate is what the assertion meant.
        final send = find.descendant(
          of: person,
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        );
        expect(send, findsOneWidget, reason: 'the row lost its one action');
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(repository.calls.map((call) => call.$1).toList(), [
          'createServerInviteV1',
        ]);
        expect(repository.calls.single.$2, {
          'serverId': 's',
          'inviteeId': 'f1',
          'requestId': 'request-1',
        });
      },
    );
  });

  group('the tiers the shell promises', () {
    testWidgets(
      'the entry to the channel list exists exactly once on a phone and is '
      'the panel itself from a tablet up',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final type in ServerType.values) {
          for (final width in qaWidths) {
            for (final scale in [1.0, 2.0]) {
              final repository = TestServerRepository()
                ..servers = [qaServer(type)]
                ..channels = qaChannels(type);
              await pumpServers(
                tester,
                qaWorkspace(repository, channelId: qaJoinableChannel(type)),
                size: Size(width, 760),
                textScale: scale,
              );
              final phone = width < ServerWorkspaceScreen.tabletBreakpoint;
              final reason = 'tiers: $type $width ×$scale';
              expect(
                qaOpenChannels,
                phone ? findsOneWidget : findsNothing,
                reason: reason,
              );
              expect(
                qaPanel,
                phone ? findsNothing : findsOneWidget,
                reason: reason,
              );
              expect(tester.takeException(), isNull, reason: reason);
            }
          }
        }
      },
    );
  });
}
