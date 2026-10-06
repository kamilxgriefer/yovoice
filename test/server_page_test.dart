// The server page (`Strona serwera`, ADR-240): what every server opens on.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/navigation/embedded_back_scope.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_event.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_podcast_question.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_home_page.dart';

import 'server_page_support.dart';
import 'server_test_support.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

final _page = _key('server-page');
final _join = _key('server-join');
final _dock = _key('server-conversation-dock');
final _livePill = _key('server-live-pill');

/// Any phrasing that could only come from a presence writer that does not
/// exist: a number of viewers, listeners or people talking.
final _fabricated = RegExp(
  r'\d+\s*(widz|słuchacz|osob[ay]? (rozmawia|w rozmowie)|ogląda)',
  caseSensitive: false,
);

const _widths = [320.0, 390.0, 768.0, 1100.0, 1440.0, 1920.0];

List<String> _texts(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    if (text.data != null) text.data!,
];

/// Brings a part of the page into view before it is pressed.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

List<ServerEvent> _communityEvents() => [
  pageEvent(
    ServerType.community,
    id: 'e1',
    title: 'Wieczór pytań',
    startsAt: pageDay(1, 20),
  ),
  pageEvent(
    ServerType.community,
    id: 'e2',
    title: 'Turniej drużynowy',
    startsAt: pageDay(3, 19),
  ),
  pageEvent(
    ServerType.community,
    id: 'e3',
    title: 'Finał sezonu',
    startsAt: pageDay(9, 19),
  ),
];

void main() {
  group('a server opens on its page', () {
    testWidgets('every template renders the page at six widths and 200 '
        'percent text without fabricating presence', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final type in ServerType.values) {
        for (final width in _widths) {
          for (final scale in [1.0, 2.0]) {
            await pumpServers(
              tester,
              pageWorkspace(
                pageRepository(
                  type,
                  live: scale == 2 ? pageLive : ServerChannelLiveness.idle,
                ),
              ),
              size: Size(width, 760),
              textScale: scale,
              light: scale == 2,
            );
            final reason = '$type $width ×$scale';
            expect(tester.takeException(), isNull, reason: reason);
            expect(_page, findsOneWidget, reason: reason);
            expect(_key('server-page-cover'), findsOneWidget, reason: reason);
            expect(_key('server-page-name'), findsOneWidget, reason: reason);
            final phone = width < ServerWorkspaceScreen.tabletBreakpoint;
            final desktop = width >= ServerWorkspaceScreen.desktopBreakpoint;
            // A phone shows the page alone; wider layouts keep the channel
            // column beside it and a desktop the server's conversation.
            expect(
              _key('server-panel'),
              phone ? findsNothing : findsOneWidget,
              reason: reason,
            );
            expect(
              _key('server-context-panel'),
              desktop ? findsOneWidget : findsNothing,
              reason: reason,
            );
            // The cover's controls belong to the phone; wider layouts have
            // the channel column's own way back and settings.
            expect(
              _key('server-page-back'),
              phone ? findsOneWidget : findsNothing,
              reason: reason,
            );
            // No local tab strip: the page replaced it.
            expect(_key('server-tab-scene'), findsNothing, reason: reason);
            expect(_key('server-channel-header'), findsNothing, reason: reason);
            expect(
              _texts(tester).where(_fabricated.hasMatch),
              isEmpty,
              reason: reason,
            );
          }
        }
      }
    });

    testWidgets('a requested channel still opens directly; a new server opens '
        'on its page with the invitation', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        pageWorkspace(pageRepository(ServerType.friends), channelId: 'general'),
      );
      expect(_page, findsNothing);
      expect(_key('server-channel-header'), findsOneWidget);
      expect(_key('server-channel-back'), findsOneWidget);

      await pumpServers(
        tester,
        pageWorkspace(
          pageRepository(ServerType.friends),
          channelId: 'general',
          justCreated: true,
        ),
      );
      expect(_page, findsOneWidget);
      expect(_key('server-invite-introduction'), findsOneWidget);
    });
  });

  group('before joining', () {
    testWidgets('a public server shows its page with Dołącz and nothing a '
        'channel would, then opens for the new member', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [390.0, 768.0, 1440.0]) {
        final repository = pageRepository(
          ServerType.community,
          live: pageLive,
          events: _communityEvents(),
        )..myRole = null;
        await pumpServers(
          tester,
          pageWorkspace(repository),
          size: Size(width, 844),
        );
        final reason = 'at $width';
        expect(_key('server-public-admission'), findsOneWidget, reason: reason);
        expect(find.text('Nocne Granie'), findsOneWidget, reason: reason);
        expect(
          tester.widget<Text>(_key('server-page-meta')).data,
          'Społeczność\u00A0· publiczny\u00A0· 128\u00A0osób',
          reason: reason,
        );
        expect(
          find.descendant(
            of: _key('server-public-join'),
            matching: find.text('Dołącz do serwera'),
          ),
          findsOneWidget,
          reason: reason,
        );
        // No channel, no liveness, no event and no channel count before the
        // member row exists; the channel list was not even asked for.
        expect(_page, findsNothing, reason: reason);
        expect(_livePill, findsNothing, reason: reason);
        expect(find.text('Wieczór pytań'), findsNothing, reason: reason);
        expect(find.textContaining('Wszystkie kanały'), findsNothing);
        expect(_key('server-panel'), findsNothing, reason: reason);
        expect(repository.watchChannelsCalls, 0, reason: reason);
        expect(_key('server-page-invite'), findsNothing, reason: reason);
        // A phone leaves from the cover; wider, the host's own bar does.
        expect(
          _key('server-page-back'),
          width < 768 ? findsOneWidget : findsNothing,
          reason: reason,
        );

        await tester.tap(_key('server-public-join'));
        await tester.pumpAndSettle();
        expect(repository.calls.single.$1, 'joinServerV1', reason: reason);
        expect(_key('server-public-admission'), findsNothing, reason: reason);
        expect(_page, findsOneWidget, reason: reason);
        expect(_key('server-page-live-hero'), findsOneWidget, reason: reason);
        expect(tester.takeException(), isNull, reason: reason);
      }
    });

    testWidgets('a private server shows a stranger nothing to join', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        pageWorkspace(pageRepository(ServerType.friends)..myRole = null),
      );
      expect(_key('server-public-admission'), findsNothing);
      expect(_key('server-public-join'), findsNothing);
      expect(_page, findsNothing);
      expect(find.text('Nie należysz do tego serwera.'), findsOneWidget);
    });
  });

  group('header and actions', () {
    testWidgets('the meta line says what the server is, whether anyone may '
        'join, and counts real members', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String meta() => tester.widget<Text>(_key('server-page-meta')).data!;

      await pumpServers(
        tester,
        pageWorkspace(pageRepository(ServerType.community)),
      );
      expect(find.text('Nocne Granie'), findsOneWidget);
      expect(meta(), 'Społeczność · publiczny · 128 osób');
      expect(find.text('Gramy wieczorami, gadamy do późna.'), findsOneWidget);
      expect(_key('server-page-lock'), findsNothing);

      // The same template made private by its owner is not "public".
      final private = TestServerRepository()
        ..servers = [
          pageServer(ServerType.community, privacy: ServerPrivacy.private),
        ]
        ..channels = pageChannels(ServerType.community);
      await pumpServers(tester, pageWorkspace(private));
      expect(meta(), 'Prywatna społeczność · 128 osób');

      await pumpServers(
        tester,
        pageWorkspace(pageRepository(ServerType.friends)),
      );
      expect(meta(), 'Prywatny serwer · 12 osób');

      // A family states its boundary with the lock and the line.
      await pumpServers(
        tester,
        pageWorkspace(pageRepository(ServerType.family)),
      );
      expect(meta(), 'Tylko na zaproszenie · 6 osób');
      expect(_key('server-page-lock'), findsOneWidget);
    });

    testWidgets('Zaproś follows the invite authority and Udostępnij only a '
        'server anyone may join', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final shared = <Uri>[];
      Future<void> open(
        ServerType type,
        ServerMemberRole role, {
        bool held = false,
      }) => pumpServers(
        tester,
        pageWorkspace(
          pageRepository(type, role: role, held: held),
          shareServer: (link) async => shared.add(link),
        ),
      );

      // A public community: every member may invite and share.
      await open(ServerType.community, ServerMemberRole.member);
      expect(_key('server-page-invite'), findsOneWidget);
      expect(_key('server-page-share'), findsOneWidget);
      await tester.tap(_key('server-page-share'));
      await tester.pumpAndSettle();
      // The page's link opens the server itself, not one of its channels.
      expect(shared.single.queryParameters, {'server': 's'});

      // A guest is the demoted state: no invitation, the link still works.
      await open(ServerType.community, ServerMemberRole.guest);
      expect(_key('server-page-invite'), findsNothing);
      expect(_key('server-page-share'), findsOneWidget);

      // A private server is entered by invitation, which stays with the
      // moderating roles; a link to it would lead nowhere.
      await open(ServerType.friends, ServerMemberRole.member);
      expect(_key('server-page-invite'), findsNothing);
      expect(_key('server-page-share'), findsNothing);
      await open(ServerType.friends, ServerMemberRole.owner);
      expect(_key('server-page-invite'), findsOneWidget);
      expect(_key('server-page-share'), findsNothing);

      // A held root can send nothing: the control is there and disabled.
      await open(ServerType.friends, ServerMemberRole.owner, held: true);
      expect(
        tester.widget<OutlinedButton>(_key('server-page-invite')).onPressed,
        isNull,
      );
    });

    testWidgets('Nadaj LIVE is offered to a role that may start a quiet stage '
        'and only opens it', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = pageRepository(
        ServerType.community,
        events: _communityEvents(),
      );
      await pumpServers(tester, pageWorkspace(repository));
      expect(find.text('Nadaj LIVE'), findsOneWidget);
      await tester.tap(_key('server-page-go-live'));
      await tester.pumpAndSettle();
      // The stage is on screen and nothing was started: the broadcast still
      // begins with the stage's own action.
      expect(_key('server-community-scene'), findsOneWidget);
      expect(repository.calls, isEmpty);
      expect(_dock, findsNothing);
      expect(find.text('Rozpocznij nadawanie'), findsOneWidget);

      for (final role in [ServerMemberRole.member, ServerMemberRole.guest]) {
        await pumpServers(
          tester,
          pageWorkspace(pageRepository(ServerType.community, role: role)),
        );
        expect(_key('server-page-go-live'), findsNothing, reason: '$role');
      }
      // A live stage is watched, not started.
      await pumpServers(
        tester,
        pageWorkspace(pageRepository(ServerType.community, live: pageLive)),
      );
      expect(_key('server-page-go-live'), findsNothing);
      // A lounge is not a broadcast.
      await pumpServers(
        tester,
        pageWorkspace(pageRepository(ServerType.friends)),
      );
      expect(_key('server-page-go-live'), findsNothing);
    });

    testWidgets('the action row stacks when its labels would not fit, and '
        'never cuts one', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<bool> stacked(Locale locale, Size size) async {
        await pumpServers(
          tester,
          pageWorkspace(pageRepository(ServerType.community)),
          size: size,
          locale: locale,
        );
        expect(tester.takeException(), isNull, reason: '$locale $size');
        final live = tester.getRect(_key('server-page-go-live'));
        final invite = tester.getRect(_key('server-page-invite'));
        final share = tester.getRect(_key('server-page-share'));
        final page = tester.getRect(_page);
        // Whatever the arrangement, every control is whole inside the page.
        for (final rect in [live, invite, share]) {
          expect(rect.left, greaterThanOrEqualTo(page.left + 16));
          expect(rect.right, lessThanOrEqualTo(page.right - 16));
        }
        return invite.top >= live.bottom;
      }

      // The test font is far wider than Inter, so the row is measured at the
      // page's own 720 px here; the 390 px row of the chosen frame is in the
      // capture (`page_390_dark_pl_100_A1-community-owner-offline`).
      expect(await stacked(const Locale('pl'), const Size(1920, 900)), isFalse);
      expect(await stacked(const Locale('pl'), const Size(320, 700)), isTrue);
      for (final locale in const [
        Locale('de'),
        Locale('pt', 'BR'),
        Locale('bg'),
        Locale('bn'),
        Locale('sw'),
      ]) {
        await stacked(locale, const Size(390, 844));
        await stacked(locale, const Size(768, 1024));
      }
    });
  });

  group('the main thing', () {
    testWidgets('a live stage is a 16:9 card with the marker, the clock and '
        'Oglądaj, which joins and opens the stage', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = pageRepository(
        ServerType.community,
        role: ServerMemberRole.member,
        live: pageLive,
        events: _communityEvents(),
      )..sessionRole = 'listener';
      await pumpServers(tester, pageWorkspace(repository));

      final hero = _key('server-page-live-hero');
      expect(hero, findsOneWidget);
      final frame = find.descendant(
        of: hero,
        matching: find.byType(AspectRatio),
      );
      expect(
        tester.widget<AspectRatio>(frame.first).aspectRatio,
        closeTo(16 / 9, .001),
      );
      expect(_livePill, findsOneWidget);
      expect(find.text('od 21:04'), findsOneWidget);
      expect(find.text('Scena LIVE'), findsOneWidget);
      expect(find.text('Dołącz, aby oglądać i słuchać.'), findsOneWidget);
      // The next event is not the hero while the stage is live.
      expect(_key('server-page-next-event'), findsNothing);
      expect(
        find.descendant(of: _join, matching: find.text('Oglądaj')),
        findsOneWidget,
      );
      expect(_texts(tester).where(_fabricated.hasMatch), isEmpty);

      await tester.tap(_join);
      await tester.pumpAndSettle();
      expect(repository.calls.map((call) => call.$1), [
        'startServerChannelSessionV1',
        'createServerChannelTokenV1',
      ]);
      expect(repository.calls.first.$2['channelId'], 'stage');
      expect(_page, findsNothing);
      expect(_key('server-community-scene'), findsOneWidget);
      expect(_dock, findsOneWidget);

      // Back on the page, the card leads to the stage this device is in.
      await tester.tap(_key('server-channel-back'));
      await tester.pumpAndSettle();
      expect(_key('server-page-live-hero'), findsNothing);
      expect(_key('server-page-open-main'), findsOneWidget);
      expect(_dock, findsOneWidget, reason: 'the page kept the conversation');
      await tester.tap(_key('server-page-open-main'));
      await tester.pumpAndSettle();
      expect(_key('server-community-scene'), findsOneWidget);
    });

    testWidgets('a quiet stage shows the next real event as Następny LIVE and '
        'answers it with the RSVP it has', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cancelled = pageEvent(
        ServerType.community,
        id: 'gone',
        title: 'Odwołane',
        startsAt: pageDay(0, 23),
      );
      final repository = pageRepository(
        ServerType.community,
        role: ServerMemberRole.member,
        events: [
          ..._communityEvents().reversed,
          ServerEvent(
            id: cancelled.id,
            serverId: cancelled.serverId,
            channelId: cancelled.channelId,
            title: cancelled.title,
            description: '',
            startsAt: cancelled.startsAt,
            endsAt: cancelled.endsAt,
            timeZone: cancelled.timeZone,
            status: ServerEventStatus.cancelled,
            authorId: 'owner',
            revision: 2,
            eventKind: ServerEventKind.communityEvent,
            serverType: ServerType.community,
          ),
        ],
      );
      await pumpServers(tester, pageWorkspace(repository));

      final card = _key('server-page-next-event');
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('NASTĘPNY LIVE')),
        findsOneWidget,
      );
      // The earliest scheduled event, whatever order the read returned.
      expect(
        find.descendant(of: card, matching: find.text('Wieczór pytań')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('jutro · Scena LIVE')),
        findsOneWidget,
      );
      expect(find.text('Odwołane'), findsNothing);
      expect(_livePill, findsNothing);
      expect(_join, findsNothing, reason: 'a listener cannot start a stage');

      // A community event has no reminder on the backend, so the card does
      // not promise one: its action is the RSVP.
      final respond = _key('server-page-event-respond');
      expect(find.text('Przypomnij mi'), findsNothing);
      expect(
        find.descendant(of: respond, matching: find.text('Będę')),
        findsOneWidget,
      );
      await tester.tap(respond);
      await tester.pumpAndSettle();
      final call = repository.calls.single;
      expect(call.$1, 'respondToServerEventV1');
      expect(call.$2['eventId'], 'e1');
      expect(call.$2['response'], 'going');
      expect(call.$2.containsKey('reminderRequested'), isFalse);
      expect(
        find.descendant(
          of: respond,
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsOneWidget,
      );
      // Saved: the button now leads to the event, where it can be changed.
      await tester.tap(respond);
      await tester.pumpAndSettle();
      expect(repository.calls, hasLength(1));
      expect(_key('server-events-board'), findsOneWidget);
    });

    testWidgets('a refused answer is said in one sentence under the button', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository =
          pageRepository(
              ServerType.community,
              role: ServerMemberRole.member,
              events: _communityEvents(),
            )
            ..failNextCall['respondToServerEventV1'] = StateError(
              'PERMISSION_DENIED',
            );
      await pumpServers(tester, pageWorkspace(repository));
      await tester.tap(_key('server-page-event-respond'));
      await tester.pumpAndSettle();
      expect(_key('server-page-event-error'), findsOneWidget);
      expect(find.textContaining('PERMISSION_DENIED'), findsNothing);
      // The button is ready again and has not claimed an answer.
      expect(
        find.descendant(
          of: _key('server-page-event-respond'),
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsNothing,
      );
    });

    testWidgets("a podcast's next episode carries the real reminder", (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = pageRepository(
        ServerType.podcast,
        role: ServerMemberRole.member,
        events: [
          pageEvent(
            ServerType.podcast,
            id: 'p1',
            title: 'Rozmowa o nocnych pociągach',
            startsAt: pageDay(0, 23),
          ),
        ],
      );
      await pumpServers(tester, pageWorkspace(repository));
      final card = _key('server-page-next-event');
      expect(
        find.descendant(of: card, matching: find.text('NASTĘPNY ODCINEK')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('dziś · Studio LIVE')),
        findsOneWidget,
      );
      final respond = _key('server-page-event-respond');
      expect(
        find.descendant(of: respond, matching: find.text('Przypomnij mi')),
        findsOneWidget,
      );
      await tester.tap(respond);
      await tester.pumpAndSettle();
      // Asking to be reminded is not a promise to come.
      expect(repository.calls.single.$2['response'], 'maybe');
      expect(repository.calls.single.$2['reminderRequested'], isTrue);
      expect(
        find.descendant(
          of: respond,
          matching: find.byIcon(Icons.notifications_active_rounded),
        ),
        findsOneWidget,
      );
      // The same button takes the reminder back and keeps the answer.
      await tester.tap(respond);
      await tester.pumpAndSettle();
      expect(repository.calls.last.$2['response'], 'maybe');
      expect(repository.calls.last.$2['reminderRequested'], isFalse);
    });

    testWidgets('a quiet stage without an event says so and offers a listener '
        'no control', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        pageWorkspace(
          pageRepository(ServerType.community, role: ServerMemberRole.member),
        ),
      );
      expect(_key('server-page-hero'), findsOneWidget);
      expect(find.text('Scena jeszcze nie nadaje'), findsOneWidget);
      expect(_key('server-page-stage-waiting'), findsOneWidget);
      expect(_join, findsNothing);
      expect(_key('server-page-next-event'), findsNothing);
      // The events section says there is nothing planned, and leads to the
      // board where something can be.
      await _tap(tester, _key('server-page-events-empty'));
      expect(_key('server-events-board'), findsOneWidget);
    });

    testWidgets('the friends lounge is joined in place and shows the '
        "provider's roster", (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = pageRepository(
        ServerType.friends,
        role: ServerMemberRole.member,
      );
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        pageWorkspace(repository, connector: connector),
      );
      final hero = _key('server-page-hero');
      expect(
        find.descendant(of: hero, matching: find.text('Salon')),
        findsOneWidget,
      );
      expect(find.text('Nikt jeszcze nie rozmawia'), findsOneWidget);
      expect(
        find.descendant(of: _join, matching: find.text('Dołącz do rozmowy')),
        findsOneWidget,
      );
      expect(_texts(tester).where(_fabricated.hasMatch), isEmpty);

      await tester.tap(_join);
      await tester.pumpAndSettle();
      expect(repository.calls.first.$2['channelId'], 'lounge');
      connector.links.single.setRoster(const [
        ServerMediaParticipant(
          identity: 'maja',
          name: 'Maja',
          isLocal: false,
          isSpeaking: true,
          isMicrophoneEnabled: true,
        ),
        ServerMediaParticipant(identity: 'owner', name: 'Ja', isLocal: true),
      ]);
      await tester.pumpAndSettle();
      // Still the page: the lounge card carries the people and the controls.
      expect(_page, findsOneWidget);
      expect(find.text('W rozmowie'), findsOneWidget);
      expect(find.descendant(of: hero, matching: find.text('Maja')), findsOne);
      expect(_key('server-session-leave'), findsOneWidget);
      expect(_dock, findsOneWidget);
      expect(_join, findsNothing);

      // A conversation opened from the page does not end the call.
      await _tap(tester, _key('server-page-channel-general'));
      expect(_page, findsNothing);
      expect(
        find.descendant(
          of: _key('server-channel-header'),
          matching: find.text('ogólny'),
        ),
        findsOneWidget,
      );
      expect(connector.links.single.disconnects, 0);
      expect(_dock, findsOneWidget);
    });

    testWidgets('a company leads with its meeting and a family with its Dom '
        'board', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        pageWorkspace(pageRepository(ServerType.company)),
      );
      expect(
        find.descendant(
          of: _key('server-page-hero'),
          matching: find.text('Spotkania'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _join, matching: find.text('Rozpocznij spotkanie')),
        findsOneWidget,
      );

      await pumpServers(
        tester,
        pageWorkspace(pageRepository(ServerType.family)),
      );
      expect(_key('server-family-board'), findsOneWidget);
      expect(_key('server-page-hero'), findsNothing);
      expect(find.text('Dobrze być razem.'), findsOneWidget);
      expect(_key('family-check-in-panel'), findsOneWidget);
    });
  });

  group('sections', () {
    testWidgets('conversations lead with the default channel, voice skips the '
        'main channel and the events show the next two', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        pageWorkspace(
          pageRepository(
            ServerType.community,
            role: ServerMemberRole.member,
            live: pageLive,
            events: _communityEvents(),
          ),
        ),
        size: const Size(390, 1800),
      );
      expect(find.text('Rozmowy'), findsOneWidget);
      expect(find.text('Głos'), findsOneWidget);
      expect(find.text('Wydarzenia'), findsOneWidget);
      double top(String key) => tester.getTopLeft(_key(key)).dy;
      // The server's default channel first, then questions, then
      // announcements; `Regulamin` stays in the full list.
      expect(
        top('server-page-channel-general'),
        lessThan(top('server-page-channel-questions')),
      );
      expect(
        top('server-page-channel-questions'),
        lessThan(top('server-page-channel-announcements')),
      );
      expect(_key('server-page-channel-rules'), findsNothing);
      // The stage is the hero, so only the lounge is a voice row.
      expect(_key('server-page-channel-stage'), findsNothing);
      expect(_key('server-page-channel-lounge'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('server-page-join-lounge'),
          matching: find.text('Dołącz'),
        ),
        findsOneWidget,
      );
      // The next two events, in order; the third waits on the board.
      expect(_key('server-page-event-e1'), findsOneWidget);
      expect(_key('server-page-event-e2'), findsOneWidget);
      expect(_key('server-page-event-e3'), findsNothing);
      expect(
        top('server-page-event-e1'),
        lessThan(top('server-page-event-e2')),
      );
      expect(find.text('Wszystkie kanały (7)'), findsOneWidget);

      await tester.tap(_key('server-page-event-e2'));
      await tester.pumpAndSettle();
      expect(_key('server-events-board'), findsOneWidget);
    });

    testWidgets('friends and family title their threads Czat; a family lists '
        'its calendar', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        pageWorkspace(pageRepository(ServerType.friends)),
        size: const Size(390, 1600),
      );
      expect(find.text('Czat'), findsOneWidget);
      expect(find.text('Rozmowy'), findsNothing);
      // The lounge is the hero; the other voice channel is a row.
      expect(_key('server-page-channel-lounge'), findsNothing);
      expect(_key('server-page-channel-gaming'), findsOneWidget);

      await pumpServers(
        tester,
        pageWorkspace(
          pageRepository(
            ServerType.family,
            events: [
              pageEvent(
                ServerType.family,
                id: 'f1',
                title: 'Obiad u babci',
                startsAt: pageDay(2, 14),
              ),
            ],
          ),
        ),
        size: const Size(390, 3200),
      );
      expect(find.text('Czat'), findsOneWidget);
      expect(_key('server-page-event-f1'), findsOneWidget);
      // The board already carries the family's lounge.
      expect(_key('server-page-channel-lounge'), findsNothing);
    });

    testWidgets('a voice row joins from the page and then says it is '
        'connected', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = pageRepository(
        ServerType.community,
        role: ServerMemberRole.member,
      );
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        pageWorkspace(repository, connector: connector),
        size: const Size(390, 1600),
      );
      await tester.tap(_key('server-page-join-lounge'));
      await tester.pumpAndSettle();
      expect(repository.calls.first.$2['channelId'], 'lounge');
      expect(_page, findsOneWidget, reason: 'a lounge is joined in place');
      expect(_key('server-page-join-lounge'), findsNothing);
      expect(_key('server-page-connected-lounge'), findsOneWidget);
      expect(_dock, findsOneWidget);
    });

    testWidgets('Wszystkie kanały opens the channel list, and the list leads '
        'back to the page', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        pageWorkspace(
          pageRepository(
            ServerType.community,
            others: [pageServer(ServerType.friends, id: 'p')],
          ),
        ),
      );
      await openServerChannelList(tester);
      expect(_key('server-panel'), findsOneWidget);
      // Every channel of the server, the settings and the server rail are
      // where they were.
      for (final seed in const [
        'announcements',
        'rules',
        'general',
        'questions',
        'lounge',
        'stage',
        'events',
      ]) {
        expect(_key('server-channel-$seed'), findsOneWidget, reason: seed);
      }
      expect(_key('server-manage-action'), findsOneWidget);
      expect(_key('server-add-channel'), findsOneWidget);
      expect(_key('server-rail-p'), findsOneWidget);

      await tester.tap(_key('server-channel-rules'));
      await tester.pumpAndSettle();
      expect(_page, findsNothing);
      expect(find.text('Regulamin'), findsWidgets);

      await openServerChannelList(tester);
      await tester.tap(_key('server-panel-page'));
      await tester.pumpAndSettle();
      expect(_page, findsOneWidget);
    });

    testWidgets("a podcast host's unseen listener questions put the waiting "
        'dot on Pytania', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final asked = DateTime.utc(2026, 10, 3, 18);
      final repository = pageRepository(ServerType.podcast)
        ..podcastQuestions = [
          ServerPodcastQuestion(
            id: 'q1',
            serverId: 's',
            channelId: 'questions',
            authorId: 'listener-1',
            authorName: 'Ola',
            body: 'Kiedy następny odcinek?',
            status: ServerPodcastQuestionStatus.queued,
            voteCount: 0,
            revision: 1,
            createdAt: asked,
            updatedAt: asked,
          ),
        ];
      await pumpServers(
        tester,
        pageWorkspace(repository),
        size: const Size(390, 1600),
      );
      expect(_key('server-page-questions-waiting-questions'), findsOneWidget);
      // The row itself carries it, so the list's entry does not repeat it.
      expect(_key('server-open-channels-waiting'), findsNothing);
      // No other row carries a mark: server channels have no read cursor.
      expect(_key('server-page-questions-waiting-discussion'), findsNothing);
    });

    testWidgets('a server without channels says so', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        pageWorkspace(
          TestServerRepository()..servers = [pageServer(ServerType.friends)],
        ),
      );
      expect(_key('server-page-empty'), findsOneWidget);
      expect(find.text('Nie ma jeszcze kanałów'), findsOneWidget);
      expect(_key('server-page-hero'), findsNothing);
      expect(find.text('Wszystkie kanały (0)'), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('phone: a channel has a way back to the page, and system Back '
        'takes it too', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var left = 0;
      await pumpServers(
        tester,
        pageWorkspace(pageRepository(ServerType.friends), onBack: () => left++),
      );
      await _tap(tester, _key('server-page-channel-general'));
      expect(_page, findsNothing);
      expect(_key('server-channel-header'), findsOneWidget);
      expect(find.byTooltip('Strona serwera'), findsOneWidget);
      await tester.tap(_key('server-channel-back'));
      await tester.pumpAndSettle();
      expect(_page, findsOneWidget);

      await _tap(tester, _key('server-page-channel-memes'));
      expect(_page, findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_page, findsOneWidget, reason: 'Back returns to the page first');
      expect(left, 0);

      // From the page, the cover's Back leaves the server.
      await _tap(tester, _key('server-page-back'));
      expect(left, 1);
    });

    testWidgets('phone: the leading-edge swipe returns from a channel to the '
        'page', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var left = 0;
      await pumpServers(
        tester,
        pageWorkspace(pageRepository(ServerType.friends), onBack: () => left++),
      );
      await _tap(tester, _key('server-page-channel-general'));
      expect(_page, findsNothing);

      // A drag that starts away from the edge is the channel's own.
      await tester.dragFrom(const Offset(120, 400), const Offset(220, 0));
      await tester.pumpAndSettle();
      expect(_page, findsNothing);

      // Holding the route for Back switches the platform's own back swipe
      // off, so the channel view carries the swipe itself.
      await tester.dragFrom(const Offset(6, 400), const Offset(220, 0));
      await tester.pumpAndSettle();
      expect(_page, findsOneWidget);
      expect(left, 0, reason: 'the swipe leaves the channel, not the server');
    });

    testWidgets('hosted in a shell that owns Back for its tabs, one Back '
        'returns to the page and does nothing else', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // The mobile shell holds its root route for its tab history and offers
      // every Back to the embedded scopes first (`EmbeddedBackScope`).
      var shellBacks = 0;
      await pumpServers(
        tester,
        Builder(
          builder: (context) => PopScope<Object?>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (EmbeddedBackScope.dispatch(context)) return;
              shellBacks++;
            },
            child: pageWorkspace(pageRepository(ServerType.friends)),
          ),
        ),
      );
      await _tap(tester, _key('server-page-channel-general'));
      expect(_page, findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_page, findsOneWidget);
      expect(shellBacks, 0, reason: 'one Back moved the tab history as well');

      // On the page nothing in the workspace claims Back: it is the shell's.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(shellBacks, 1);
    });

    testWidgets('a workspace whose slot is off screen does not hold Back', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      final repository = pageRepository(ServerType.friends);
      await pumpServers(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open-server'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ServerWorkspaceScreen(
                      serverId: 's',
                      repository: repository,
                      initialChannelId: 'general',
                      chatService: pageChat(),
                      connector: FakeServerMediaConnector(),
                      isVisible: visible,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(_key('open-server'));
      await tester.pumpAndSettle();
      expect(_key('server-channel-header'), findsOneWidget);

      // A retained slot that is not on screen claims nothing: Back is not
      // swallowed by a channel view nobody can see.
      visible.value = false;
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_key('server-channel-header'), findsNothing);
      expect(_page, findsNothing);
      expect(_key('open-server'), findsOneWidget);
    });

    testWidgets('phone route: the cover carries Back, no app bar is drawn, '
        'and a state keeps the route bar', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Widget host(TestServerRepository repository) => Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('open-server'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ServerWorkspaceScreen(
                    serverId: 's',
                    repository: repository,
                    chatService: pageChat(),
                    connector: FakeServerMediaConnector(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await pumpServers(tester, host(pageRepository(ServerType.community)));
      await tester.tap(_key('open-server'));
      await tester.pumpAndSettle();
      expect(_page, findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      await tester.tap(_key('server-page-back'));
      await tester.pumpAndSettle();
      expect(_page, findsNothing);
      expect(_key('open-server'), findsOneWidget);

      // While the server is still being read, the way out is already where
      // the cover will put it: no app bar appears only to be swapped away.
      final pending = StreamController<Server?>();
      addTearDown(pending.close);
      await pumpServers(
        tester,
        host(TestServerRepository()..serverStream = pending.stream),
      );
      await tester.tap(_key('open-server'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      await tester.tap(_key('server-page-back'));
      // The spinner never settles, so the pop is pumped past its transition.
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_key('open-server'), findsOneWidget);

      // A server that cannot be read keeps a real app bar with Back.
      await pumpServers(tester, host(TestServerRepository()));
      await tester.tap(_key('open-server'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Serwer jest niedostępny'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_key('open-server'), findsOneWidget);
    });

    testWidgets('tablet and desktop: the panel header selects the page, and a '
        'desktop keeps the conversation beside it', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [768.0, 1440.0]) {
        await pumpServers(
          tester,
          pageWorkspace(pageRepository(ServerType.community)),
          size: Size(width, 900),
        );
        final reason = 'at $width';
        expect(_page, findsOneWidget, reason: reason);
        // The page keeps its reading measure in a wide centre.
        expect(
          tester.getSize(_page).width,
          lessThanOrEqualTo(ServerHomePage.maxWidth),
          reason: reason,
        );
        expect(
          find.descendant(
            of: _key('server-context-panel'),
            matching: find.text('Czat · #ogólny'),
          ),
          width >= 1100 ? findsOneWidget : findsNothing,
          reason: reason,
        );
        // No row is selected while the page is the centre.
        for (final tile in tester.widgetList<ListTile>(
          find.descendant(
            of: _key('server-panel'),
            matching: find.byType(ListTile),
          ),
        )) {
          expect(tile.selected, isFalse, reason: reason);
        }

        await tester.tap(_key('server-channel-rules'));
        await tester.pumpAndSettle();
        expect(_page, findsNothing, reason: reason);
        expect(_key('server-channel-header'), findsOneWidget, reason: reason);
        expect(
          tester.widget<ListTile>(_key('server-channel-rules')).selected,
          isTrue,
          reason: reason,
        );

        await tester.tap(_key('server-panel-page'));
        await tester.pumpAndSettle();
        expect(_page, findsOneWidget, reason: reason);
        expect(tester.takeException(), isNull, reason: reason);
      }
    });

    testWidgets('the cover controls are 48 px targets around a 44 px disc', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var left = 0;
      await pumpServers(
        tester,
        pageWorkspace(
          pageRepository(ServerType.community),
          onBack: () => left++,
        ),
      );
      for (final key in const ['server-page-back', 'server-page-more']) {
        expect(tester.getSize(_key(key)), const Size(48, 48), reason: key);
        // The disc keeps the 8 / 12 px inset the frames show.
        final disc = tester.getRect(
          find.descendant(of: _key(key), matching: find.byType(InkWell)),
        );
        expect(disc.size, const Size(44, 44), reason: key);
        expect(disc.top, 8, reason: key);
      }
      expect(
        tester
            .getRect(
              find.descendant(
                of: _key('server-page-back'),
                matching: find.byType(InkWell),
              ),
            )
            .left,
        12,
      );
      // The ring between the disc and the edge of the target answers too.
      await tester.tapAt(
        tester.getTopLeft(_key('server-page-back')) + const Offset(1, 24),
      );
      await tester.pumpAndSettle();
      expect(left, 1);
      await tester.tapAt(
        tester.getTopRight(_key('server-page-more')) + const Offset(-1, 24),
      );
      await tester.pumpAndSettle();
      expect(_key('server-page-menu-channels'), findsOneWidget);
    });

    testWidgets('the ⋯ menu offers the list, a new channel and the settings '
        'by role', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        pageWorkspace(pageRepository(ServerType.community)),
        // Still a phone layout; the settings sheet it opens needs the room
        // the test font takes.
        size: const Size(700, 900),
      );
      await tester.tap(_key('server-page-more'));
      await tester.pumpAndSettle();
      expect(_key('server-page-menu-channels'), findsOneWidget);
      expect(_key('server-page-menu-addChannel'), findsOneWidget);
      expect(_key('server-page-menu-settings'), findsOneWidget);
      await tester.tap(_key('server-page-menu-settings'));
      await tester.pumpAndSettle();
      expect(find.text('Ustawienia serwera'), findsWidgets);
      expect(find.text('Zapisz zmiany'), findsOneWidget);
      Navigator.of(tester.element(find.text('Zapisz zmiany'))).pop();
      await tester.pumpAndSettle();

      // A member has nothing to manage; the list is still one tap away.
      await pumpServers(
        tester,
        pageWorkspace(
          pageRepository(ServerType.community, role: ServerMemberRole.member),
        ),
      );
      await tester.tap(_key('server-page-more'));
      await tester.pumpAndSettle();
      expect(_key('server-page-menu-addChannel'), findsNothing);
      expect(_key('server-page-menu-settings'), findsNothing);
      await tester.tap(_key('server-page-menu-channels'));
      await tester.pumpAndSettle();
      expect(_key('server-panel'), findsOneWidget);
    });
  });
}
