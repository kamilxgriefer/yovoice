// Refine-look batch 4 (Servers, spec §8.2): the directory's R2 blocks, the
// session card's light budget, the header lamp, the identity tokens, the
// conversation bar's glass controls and the speaking-ring jitter fix.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_channel_scene.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_voice_stage.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

import 'server_independent_qa_support.dart';
import 'server_test_support.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + .05) / (lb + .05) : (lb + .05) / (la + .05);
}

Server _server(
  String id,
  String name,
  ServerType type, {
  int members = 8,
  String description = '',
}) => Server(
  id: id,
  name: name,
  description: description,
  ownerId: 'owner',
  type: type,
  privacy: ServerPrivacy.private,
  memberCount: members,
  defaultChannelId: null,
  schemaVersion: 1,
  activationState: 'active',
  status: 'active',
);

final _live = ServerChannelLiveness(
  isLive: true,
  startedAt: DateTime(2026, 9, 25, 19, 40),
);

/// A workspace on the friends board's `Salon`, optionally live.
Widget _salon({
  bool live = false,
  bool held = false,
  FakeServerMediaConnector? connector,
}) {
  final repository = TestServerRepository()
    ..servers = [qaServer(ServerType.friends, held: held)]
    ..channels = qaChannels(
      ServerType.friends,
      liveness: live ? _live : ServerChannelLiveness.idle,
      activeSessionId: live ? 'session-live' : null,
    );
  return qaWorkspace(repository, channelId: 'lounge', connector: connector);
}

/// [child] under system high contrast (the pump helper owns MediaQuery above
/// `home`, so the override sits just below it).
Widget _highContrast(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(highContrast: true),
    child: child,
  ),
);

Finder get _card => find.byKey(const ValueKey('server-session-card'));
Finder get _glow => find.byKey(const ValueKey('server-session-glow'));
Finder get _corner => find.byKey(const ValueKey('server-session-corner'));
Finder get _tint => find.byKey(const ValueKey('server-session-tint'));
Finder get _orb => find.byKey(const ValueKey('server-session-orb'));

void main() {
  setUp(ServerSessionCard.debugResetIgnitions);

  group('identity tokens (spec §6)', () {
    test('the live gems carry the director-verified ink on both stops', () {
      const minimum = <ServerType, double>{
        ServerType.friends: 11.0,
        ServerType.community: 5.04,
        ServerType.podcast: 5.55,
        ServerType.family: 9.5,
        ServerType.company: 7.8,
      };
      for (final brightness in Brightness.values) {
        for (final type in ServerType.values) {
          final colors = ServerIdentity.of(type).resolve(brightness);
          expect(colors.liveOrbGradient.colors, hasLength(2));
          expect(
            colors.onLiveOrb,
            type == ServerType.community
                ? AppColors.white
                : AppColors.contrastInk,
          );
          for (final stop in colors.liveOrbGradient.colors) {
            expect(
              _contrast(colors.onLiveOrb, stop),
              greaterThanOrEqualTo(minimum[type]!),
              reason: '$type $brightness gem ink on $stop',
            );
          }
        }
      }
      // The gem is an object, not a theme surface: identical in both themes.
      for (final type in ServerType.values) {
        expect(
          ServerIdentity.of(type).resolve(Brightness.dark).liveOrbGradient,
          ServerIdentity.of(type).resolve(Brightness.light).liveOrbGradient,
        );
      }
    });

    test('the CTA gradient starts or ends on cta and never loses the label', () {
      for (final brightness in Brightness.values) {
        for (final type in ServerType.values) {
          final colors = ServerIdentity.of(type).resolve(brightness);
          final stops = colors.ctaGradient.colors;
          expect(stops, contains(colors.cta));
          for (final stop in stops) {
            expect(stop.a, 1, reason: '$type $brightness stop is translucent');
            expect(
              _contrast(colors.onCta, stop),
              greaterThanOrEqualTo(_contrast(colors.onCta, colors.cta) - .001),
              reason: '$type $brightness label loses contrast on $stop',
            );
          }
        }
      }
    });

    test('the unlit glass is opaque and edged per theme', () {
      for (final type in ServerType.values) {
        final dark = ServerIdentity.of(type).resolve(Brightness.dark);
        final pearl = ServerIdentity.of(type).resolve(Brightness.light);
        for (final stop in [
          ...dark.unlitGradient.colors,
          ...pearl.unlitGradient.colors,
        ]) {
          expect(stop.a, 1, reason: '$type unlit stop is translucent');
        }
        expect(pearl.unlitEdge, AppPalette.light.hairline);
        expect(dark.unlitEdge.a, closeTo(.28, .01));
        expect(dark.identityEdge, dark.foreground.withValues(alpha: .30));
      }
    });

    test('a member count keeps its number and noun together', () {
      expect(serverKeepCountTogether('12 osób'), '12\u00A0osób');
      expect(serverKeepCountTogether('1 osoba'), '1\u00A0osoba');
      expect(serverKeepCountTogether('112 members'), '112\u00A0members');
      expect(serverKeepCountTogether('bez liczby'), 'bez liczby');
    });

    test('a meta line keeps its dot with the word before it', () {
      // Review round (B4-V9): a wrap falls AFTER the dot, never before it.
      expect(
        serverMetaLine('Prywatny serwer', '12 osób'),
        'Prywatny serwer\u00A0· 12\u00A0osób',
      );
    });
  });

  group('directory (R2 blocks, one CTA, the real logo)', () {
    Widget directory(List<Server> servers) => ServersScreen(
      key: UniqueKey(),
      isRootTab: true,
      repository: TestServerRepository()..servers = servers,
      chatService: qaChat(),
      connector: FakeServerMediaConnector(),
    );

    final servers = [
      _server('a', 'Po godzinach', ServerType.friends, members: 12),
      _server(
        'b',
        'Klub książki',
        ServerType.community,
        members: 184,
        description:
            'Co miesiąc jedna książka i jedna długa rozmowa o niej, a potem '
            'druga, jeszcze dłuższa, o tym, co z niej zostało.',
      ),
      _server('c', 'Nocne audycje', ServerType.podcast, members: 42),
    ];

    testWidgets('each row is a neutral block at least 72 px tall', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final light in [false, true]) {
        await pumpServers(
          tester,
          directory(servers),
          size: const Size(390, 844),
          light: light,
        );
        final palette = light ? AppPalette.light : AppPalette.dark;
        final row = find.byKey(const ValueKey('server-directory-a'));
        expect(row, findsOneWidget);
        expect(tester.widget(row), isA<Material>());
        expect(tester.getSize(row).height, greaterThanOrEqualTo(72));
        final ink = tester.widget<Ink>(
          find.descendant(of: row, matching: find.byType(Ink)).first,
        );
        final decoration = ink.decoration! as BoxDecoration;
        // Neutral: the palette's top-lit block, never an identity tint.
        expect(decoration.gradient, palette.blockGradient);
        expect((decoration.border! as Border).top.color, palette.hairline);
        // The meta line keeps "12 osób" together.
        expect(find.text('Dla znajomych\u00A0· 12\u00A0osób'), findsOneWidget);
        // 12 px between blocks.
        final a = tester.getRect(row);
        final b = tester.getRect(find.byKey(const ValueKey('server-directory-b')));
        expect(b.top - a.bottom, 12);
      }
    });

    testWidgets('two columns render equal-height pairs, row-major', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, directory(servers), size: const Size(1440, 900));
      expect(
        find.byKey(const ValueKey('servers-directory-pairs')),
        findsOneWidget,
      );
      final a = tester.getRect(find.byKey(const ValueKey('server-directory-a')));
      final b = tester.getRect(find.byKey(const ValueKey('server-directory-b')));
      final c = tester.getRect(find.byKey(const ValueKey('server-directory-c')));
      // A one-line row beside a three-line one: the same height.
      expect(a.height, b.height);
      expect(a.top, b.top);
      expect(b.left - a.right, 16);
      // The third starts the next pair, under the first.
      expect(c.left, a.left);
      expect(c.top - a.bottom, 12);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard focus paints a ring without moving the row', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, directory(servers), size: const Size(390, 844));
      final name = find.text('Po godzinach');
      final before = tester.getRect(name);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final well = find.descendant(
        of: find.byKey(const ValueKey('server-directory-a')),
        matching: find.byType(InkWell),
      );
      Focus.of(tester.element(find.descendant(
        of: well.first,
        matching: find.byType(Padding),
      ).first)).requestFocus();
      await tester.pumpAndSettle();
      expect(tester.getRect(name), before);
      final ring = tester
          .widgetList<AnimatedContainer>(
            find.ancestor(
              of: find.byKey(const ValueKey('server-directory-a')),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .first;
      final border =
          (ring.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(border.top.color, AppPalette.dark.focus);
      expect(border.top.width, 2);
    });

    testWidgets('a focused ⋯ does not light its row\'s ring as well', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, directory(servers), size: const Size(390, 844));
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      Color rowRing() {
        final box = tester
            .widgetList<AnimatedContainer>(
              find.ancestor(
                of: find.byKey(const ValueKey('server-directory-a')),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .first;
        return ((box.foregroundDecoration! as BoxDecoration).border!
                as Border)
            .top
            .color;
      }

      final actions = find.byKey(const ValueKey('server-directory-actions-a'));
      final actionsWell = find.descendant(
        of: actions,
        matching: find.byType(InkWell),
      );
      Focus.maybeOf(
        tester.element(
          find
              .descendant(
                of: find.descendant(
                  of: actionsWell,
                  matching: find.byType(Focus),
                ).first,
                matching: find.byType(Icon),
              )
              .first,
        ),
        createDependency: false,
      )!.requestFocus();
      await tester.pumpAndSettle();
      // The ⋯ has focus (its own ring); the row stays unringed.
      expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<IconButton>()
            ?.key,
        const ValueKey('server-directory-actions-a'),
      );
      expect(rowRing(), Colors.transparent);
      // Focus back on the row itself: its ring.
      final rowWell = find
          .descendant(
            of: find.byKey(const ValueKey('server-directory-a')),
            matching: find.byType(InkWell),
          )
          .first;
      Focus.maybeOf(
        tester.element(
          find.descendant(of: rowWell, matching: find.byType(Padding)).first,
        ),
        createDependency: false,
      )!.requestFocus();
      await tester.pumpAndSettle();
      expect(rowRing(), AppPalette.dark.focus);
    });

    testWidgets('the create CTA is the gradient FilledButton; the rail owns '
        'the lift on a desktop', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      List<BoxShadow> liftAt(Size size) {
        final shape = tester
            .widget<AnimatedContainer>(
              find
                  .ancestor(
                    of: find.byKey(const ValueKey('servers-create')),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            )
            .decoration! as ShapeDecoration;
        return shape.shadows ?? const [];
      }

      await pumpServers(tester, directory(servers), size: const Size(390, 844));
      final create = find.byKey(const ValueKey('servers-create'));
      expect(tester.widget(create), isA<FilledButton>());
      expect(tester.getSize(create).height, greaterThanOrEqualTo(48));
      final scheme = AppTheme.darkTheme.colorScheme;
      final ink = tester.widget<Ink>(
        find.descendant(of: create, matching: find.byType(Ink)),
      );
      expect(
        (ink.decoration! as BoxDecoration).gradient,
        AppGradients.primaryAction(scheme),
      );
      expect(liftAt(const Size(390, 844)), isNotEmpty);

      // The rail's presence follows the VIEWPORT (the shell's own layout
      // predicate), which the test view has to report as well.
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1440, 900);
      addTearDown(tester.view.reset);
      await pumpServers(
        tester,
        directory(servers),
        size: const Size(1440, 900),
      );
      expect(liftAt(const Size(1440, 900)), isEmpty);
    });

    testWidgets('the first-run directory carries the real logo', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, directory(const []), size: const Size(390, 844));
      final logo = find.byKey(const ValueKey('servers-empty-logo'));
      expect(logo, findsOneWidget);
      expect(tester.widget(logo), isA<YoBrandMark>());
      expect(tester.getSize(logo), const Size(72, 72));
      expect(find.text('Twoje miejsce na wspólne rozmowy'), findsOneWidget);
    });
  });

  group('session card light budget (R4 / W2 at card scale)', () {
    testWidgets('quiet: the plain block, the unlit orb, no light', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _salon(), size: const Size(1440, 900));
      expect(_card, findsOneWidget);
      expect(_glow, findsNothing);
      expect(_corner, findsNothing);
      expect(_tint, findsNothing);
      final colors = ServerIdentity.of(
        ServerType.friends,
      ).resolve(Brightness.dark);
      final orb = tester.widget<Container>(_orb).decoration! as BoxDecoration;
      expect(orb.gradient, colors.unlitGradient);
      expect(find.byKey(const ValueKey('server-live-lamp')), findsNothing);
    });

    testWidgets('live and not joined: the one lit card, the gem, the lamp', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _salon(live: true), size: const Size(1440, 900));
      expect(_glow, findsOneWidget);
      expect(_corner, findsOneWidget);
      expect(_tint, findsNothing);
      final colors = ServerIdentity.of(
        ServerType.friends,
      ).resolve(Brightness.dark);
      final orb = tester.widget<Container>(_orb).decoration! as BoxDecoration;
      expect(orb.gradient, colors.liveOrbGradient);
      // The card's rim is the live one, painted as a foreground.
      final card = tester.widget<AnimatedContainer>(_card);
      final rim =
          (card.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(rim.top.color, AppColors.live.withValues(alpha: .30));
      // The header says LIVE with a lamp; the pill stays on the card.
      final header = find.byKey(const ValueKey('server-channel-header'));
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const ValueKey('server-live-lamp')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const ValueKey('server-live-pill')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _card,
          matching: find.byKey(const ValueKey('server-live-pill')),
        ),
        findsOneWidget,
      );
      expect(find.text('Na żywo od 19:40'), findsWidgets);
      // Reduce Motion (the pump's default): nothing keeps ticking.
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    });

    testWidgets('the lamp says LIVE to a screen reader, once, on its line', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final handle = tester.ensureSemantics();
      await pumpServers(tester, _salon(live: true), size: const Size(1440, 900));
      // Review round (A11Y-5): the dot and its line are ONE node — one stop
      // for a screen reader, the whole line for touch exploration — instead
      // of an 8 px "NA ŻYWO" node beside a separate text node.
      final lamp = find.byKey(const ValueKey('server-live-lamp'));
      final node = tester.getSemantics(lamp);
      final label = node.getSemanticsData().label;
      expect(label, contains('NA ŻYWO'));
      expect(label, contains('Na żywo od 19:40'));
      final line = find.descendant(
        of: lamp,
        matching: find.text('Na żywo od 19:40'),
      );
      expect(
        node.rect.height,
        greaterThanOrEqualTo(tester.getSize(line).height),
      );
      handle.dispose();
    });

    testWidgets('connected: the accent edge and tint, never a glow', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        _salon(live: true, connector: connector),
        size: const Size(1440, 900),
      );
      await qaJoinAndSettle(tester, connector, roster: qaRoster);
      expect(_glow, findsNothing);
      expect(_corner, findsNothing);
      expect(_tint, findsOneWidget);
      final card = tester.widget<AnimatedContainer>(_card);
      final edge =
          (card.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(edge.top.color, AppPalette.dark.audioAccent);
      expect(edge.top.width, ServerSessionCard.connectedEdgeWidth);
    });

    testWidgets('a held server is quiet even while live', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        _salon(live: true, held: true),
        size: const Size(1440, 900),
      );
      expect(_card, findsOneWidget);
      expect(_glow, findsNothing);
      expect(_corner, findsNothing);
    });

    testWidgets('high contrast: no glow or corner, a solid live rim', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        _highContrast(_salon(live: true)),
        size: const Size(1440, 900),
      );
      expect(_glow, findsNothing);
      expect(_corner, findsNothing);
      final card = tester.widget<AnimatedContainer>(_card);
      final rim =
          (card.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(rim.top.color, AppColors.live);
      expect(rim.top.width, 1.5);
      final join = tester.widget<FilledButton>(qaJoin);
      // The fill IS the control: the gradient stays, only the lift goes.
      expect(join.onPressed, isNotNull);
    });

    testWidgets('the ignite plays once per live generation', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(600, 900));
      final colors = ServerIdentity.of(
        ServerType.friends,
      ).resolve(Brightness.dark);
      Widget card(String? key) => MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ServerSessionCard(
            state: key == null
                ? ServerSessionCardState.quiet
                : ServerSessionCardState.live,
            accent: ServerIdentity.of(ServerType.friends).accent,
            colors: colors,
            igniteKey: key,
            padding: const EdgeInsets.all(16),
            child: const SizedBox(height: 120),
          ),
        ),
      );
      double glowOpacity() => tester
          .widget<FadeTransition>(
            find
                .ancestor(of: _glow, matching: find.byType(FadeTransition))
                .first,
          )
          .opacity
          .value;

      await tester.pumpWidget(card('s/lounge/1'));
      expect(glowOpacity(), lessThan(.1));
      await tester.pumpAndSettle();
      expect(glowOpacity(), 1);
      // A rebuild, a re-mount: at rest at once.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(card('s/lounge/1'));
      expect(glowOpacity(), 1);
      // A new generation ignites again.
      await tester.pumpWidget(card('s/lounge/2'));
      await tester.pump();
      expect(glowOpacity(), lessThan(.1));
      await tester.pumpAndSettle();
      expect(glowOpacity(), 1);
    });
  });

  group('voice stage', () {
    testWidgets('a speaker never moves an avatar (the ring is a foreground)', (
      tester,
    ) async {
      const quiet = ServerMediaParticipant(
        identity: 'ola',
        name: 'Ola',
        isLocal: false,
        isMicrophoneEnabled: true,
      );
      const speaking = ServerMediaParticipant(
        identity: 'ola',
        name: 'Ola',
        isLocal: false,
        isSpeaking: true,
        isMicrophoneEnabled: true,
      );
      final colors = ServerIdentity.of(
        ServerType.friends,
      ).resolve(Brightness.dark);
      Widget tile(ServerMediaParticipant person) => Scaffold(
        body: Center(
          child: ServerParticipantTile(
            person: person,
            colors: colors,
            width: 104,
          ),
        ),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final ring = find.byKey(const ValueKey('server-participant-ring-ola'));
      await pumpServers(tester, tile(quiet));
      final restRect = tester.getRect(ring);
      final restName = tester.getRect(find.text('Ola'));
      await pumpServers(tester, tile(speaking));
      expect(tester.getRect(ring), restRect);
      expect(tester.getRect(find.text('Ola')), restName);
      final box = tester.widget<Container>(ring);
      final glow = (box.decoration! as BoxDecoration).boxShadow!;
      expect(glow, hasLength(1));
      expect(glow.single.color, AppPalette.dark.audioAccent.withValues(alpha: .40));
      final paint = (box.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(paint.top.width, ServerParticipantTile.speakingRingWidth);
    });
  });

  group('conversation bar (not the navigation dock)', () {
    testWidgets('round glass controls; the open microphone glows', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        _salon(live: true, connector: connector),
        size: const Size(1440, 900),
      );
      final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);
      final dock = find.byKey(const ValueKey('server-conversation-dock'));
      expect(dock, findsOneWidget);
      final palette = AppPalette.dark;
      final bar = tester.widget<Container>(dock).decoration! as BoxDecoration;
      final barFill = Color.alphaBlend(
        palette.audioAccent.withValues(alpha: .10),
        palette.surfaceRaised,
      );
      expect(bar.color, barFill);
      expect(
        (bar.border! as Border).top.color,
        palette.audioAccent.withValues(alpha: .45),
      );

      IconButton control(String key) => tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(IconButton),
        ),
      );
      // The headphones rest on neutral glass composited over the bar.
      final headphones = control('server-dock-headphones');
      expect(headphones.style!.shape!.resolve(const {}), isA<CircleBorder>());
      final leave = control('server-dock-leave');
      expect(
        leave.style!.backgroundColor!.resolve(const {}),
        AppColors.error,
      );

      List<BoxShadow> micGlow() {
        final boxes = tester.widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(const ValueKey('server-dock-microphone')),
            matching: find.byType(DecoratedBox),
          ),
        );
        return [
          for (final box in boxes)
            if (box.decoration case BoxDecoration(:final boxShadow?))
              ...boxShadow,
        ];
      }

      link.microphone = true;
      link.report(link.state);
      await tester.pumpAndSettle();
      expect(micGlow(), isNotEmpty);
      link.microphone = false;
      link.report(link.state);
      await tester.pumpAndSettle();
      expect(micGlow(), isEmpty);
    });
  });

  group('the "Kanały" sheet', () {
    testWidgets('sits on the panel surface with a hairline top', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _salon(), size: const Size(390, 844));
      await tester.tap(qaOpenChannels);
      await tester.pumpAndSettle();
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.backgroundColor, AppPalette.dark.surfaceMuted);
      // Review round (B4-V10): the hairline is the TOP edge only — the
      // shape's own side stays none, so nothing runs down the screen edges.
      final shape = sheet.shape! as ServerSheetTopEdge;
      expect(shape.side, BorderSide.none);
      expect(shape.edge.color, AppPalette.dark.hairline);
      expect(
        shape.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(28)),
      );
    });

    testWidgets('the hairline is painted across the top only', (tester) async {
      const width = 120;
      const height = 200;
      const shape = ServerSheetTopEdge(
        edge: BorderSide(color: Color(0xFFFF0000)),
      );
      final recorder = ui.PictureRecorder();
      shape.paint(
        Canvas(recorder),
        Offset.zero & const Size(width + .0, height + .0),
      );
      final picture = recorder.endRecording();
      final bytes = await tester.runAsync(() async {
        final image = await picture.toImage(width, height);
        final data = await image.toByteData();
        image.dispose();
        return data!;
      });
      picture.dispose();
      int alpha(int x, int y) => bytes!.getUint8((y * width + x) * 4 + 3);
      // Across the top…
      expect(alpha(width ~/ 2, 0), greaterThan(0));
      // …and never down either side of the screen, nor along the bottom.
      for (final y in [40, 100, 199]) {
        expect(alpha(0, y), 0, reason: 'left edge at $y');
        expect(alpha(width - 1, y), 0, reason: 'right edge at $y');
      }
      expect(alpha(width ~/ 2, height - 1), 0);
    });

    testWidgets('its server rail shows the sheet, not a canvas column', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [
          qaServer(ServerType.friends),
          _server('k', 'Klub książki', ServerType.community, members: 184),
          _server('r', 'Rodzina', ServerType.family, members: 6),
        ]
        ..channels = qaChannels(ServerType.friends);
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'lounge'),
        size: const Size(390, 844),
      );
      await tester.tap(qaOpenChannels);
      await tester.pumpAndSettle();
      final rail = find.byKey(const ValueKey('server-rail'));
      expect(rail, findsOneWidget);
      // Review round (B4-V1): the rail column paints nothing of its own in
      // the sheet (it was `background`, a hard-edged notch under the handle
      // band on the `surfaceMuted` sheet).
      final material = tester.widget<Material>(
        find.ancestor(of: rail, matching: find.byType(Material)).first,
      );
      expect(material.type, MaterialType.transparency);
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      // The tablet / desktop workspace rail keeps its canvas.
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'lounge'),
        size: const Size(1440, 900),
      );
      final wide = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('server-rail')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(wide.type, MaterialType.canvas);
      expect(wide.color, AppPalette.dark.background);
    });
  });

  group('YoGradientFilledButton identity variant', () {
    testWidgets('keys the FilledButton, reports the fill, inks the label', (
      tester,
    ) async {
      const gradient = LinearGradient(
        colors: [AppColors.accent, AppColors.accent],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: YoGradientFilledButton(
                buttonKey: const ValueKey('identity-cta'),
                onPressed: () {},
                gradient: gradient,
                fill: AppColors.accent,
                foreground: AppColors.contrastInk,
                liftColor: AppColors.accent,
                child: const Text('Dołącz'),
              ),
            ),
          ),
        ),
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('identity-cta')),
      );
      const focused = {WidgetState.focused};
      expect(button.style!.backgroundColor!.resolve(focused), AppColors.accent);
      expect(button.style!.side!.resolve(focused)!.color, AppColors.contrastInk);
      expect(
        button.style!.foregroundColor!.resolve(const {}),
        AppColors.contrastInk,
      );
      final lift = tester
          .widget<AnimatedContainer>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('identity-cta')),
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          )
          .decoration! as ShapeDecoration;
      expect(lift.shadows!.single.color, AppColors.accent.withValues(alpha: .32));
    });
  });

  group('YoGradientFilledButton focus ring (found in the focus frames)', () {
    testWidgets('a focused gradient action shows its ring over the gradient', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundary,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: YoGradientFilledButton(
                    focusNode: focus,
                    onPressed: () {},
                    gradient: const LinearGradient(
                      colors: [AppColors.accent, AppColors.accent],
                    ),
                    fill: AppColors.accent,
                    foreground: AppColors.contrastInk,
                    liftColor: AppColors.accent,
                    child: const Text('Dołącz'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      Future<Color> edgePixel() async {
        final origin = tester.getTopLeft(find.byKey(boundary));
        final button = tester.getRect(find.byType(FilledButton));
        // Inside the 2 px ring at the stadium's leftmost point.
        final x = (button.left - origin.dx).round() + 1;
        final y = (button.center.dy - origin.dy).round();
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final data = await tester.runAsync(() async {
          final image = await render.toImage();
          final bytes = await image.toByteData();
          final width = image.width;
          image.dispose();
          return (bytes!, width);
        });
        final (bytes, width) = data!;
        final i = (y * width + x) * 4;
        return Color.fromARGB(
          255,
          bytes.getUint8(i),
          bytes.getUint8(i + 1),
          bytes.getUint8(i + 2),
        );
      }

      // At rest the edge pixel is the gradient itself…
      expect(
        _contrast(await edgePixel(), AppColors.accent),
        lessThan(1.1),
      );
      focus.requestFocus();
      await tester.pumpAndSettle();
      // …and focused it is the 2 px ring in the label's ink, painted OVER
      // the gradient (a ButtonStyleButton paints its own `side` under its
      // content, where the gradient `Ink` covered it).
      final ring = await edgePixel();
      expect(_contrast(ring, AppColors.contrastInk), lessThan(1.1));
      expect(
        _contrast(ring, AppColors.accent),
        greaterThanOrEqualTo(3),
      );
    });
  });

  // Found by rendering the refine capture matrix (frames/after/servers):
  // two 200 % text regressions against build 36.
  group('200 % text (capture review)', () {
    testWidgets('a stacked directory row keeps its text 12 px from both '
        'edges of the block', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        ServersScreen(
          key: UniqueKey(),
          isRootTab: true,
          repository: TestServerRepository()
            ..servers = [
              _server(
                'b',
                'Klub książki',
                ServerType.community,
                members: 184,
                description:
                    'Co miesiąc jedna książka i jedna długa rozmowa o niej.',
              ),
            ],
          chatService: qaChat(),
          connector: FakeServerMediaConnector(),
        ),
        size: const Size(390, 844),
        textScale: 2,
      );
      final row = tester.getRect(
        find.byKey(const ValueKey('server-directory-b')),
      );
      // The description wraps, so its paragraph spans the whole text column.
      final text = tester.getRect(
        find.text('Co miesiąc jedna książka i jedna długa rozmowa o niej.'),
      );
      // Stacked under the avatar and the actions (the 200 % branch)…
      expect(text.top, greaterThan(row.top + 44));
      // …with the same inset at the end as at the start: 1 px edge + 12.
      expect(text.left - row.left, 13);
      expect(row.right - text.right, 13);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the join keeps FilledButton.icon\'s text-scaled padding', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      EdgeInsetsGeometry padding() => tester
          .widget<FilledButton>(find.byKey(const ValueKey('server-join')))
          .style!
          .padding!
          .resolve(const {})!;

      await pumpServers(tester, _salon(live: true), size: const Size(390, 844));
      expect(padding(), const EdgeInsetsDirectional.fromSTEB(16, 0, 24, 0));

      await pumpServers(
        tester,
        _salon(live: true),
        size: const Size(390, 844),
        textScale: 2,
      );
      // Build 36's FilledButton.icon at 200 %: 8 / 12, not a fixed 16 / 24
      // that folded "Dołącz do rozmowy" onto two lines in the card.
      expect(padding(), const EdgeInsetsDirectional.fromSTEB(8, 0, 12, 0));
      expect(tester.takeException(), isNull);
    });
  });

  // The review round of batch 4 (visual QA B4-V*, accessibility A11Y-*).
  group('review round', () {
    Finder header() => find.byKey(const ValueKey('server-channel-header'));
    Finder lamp() => find.byKey(const ValueKey('server-live-lamp'));

    Widget template(ServerType type, {bool live = true}) {
      final repository = TestServerRepository()
        ..servers = [qaServer(type)]
        ..channels = qaChannels(
          type,
          liveness: live ? _live : ServerChannelLiveness.idle,
          activeSessionId: live ? 'session-live' : null,
        );
      return qaWorkspace(repository, channelId: qaBoardChannel(type));
    }

    testWidgets('the company meeting draws no pill, so its header keeps one '
        '(B4-V3, A11Y-4)', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final size in const [Size(390, 844), Size(1440, 900)]) {
        await pumpServers(
          tester,
          template(ServerType.company),
          size: size,
        );
        expect(
          find.descendant(of: header(), matching: qaLivePill),
          findsOneWidget,
          reason: 'company $size',
        );
        expect(lamp(), findsNothing, reason: 'company $size');
      }
    });

    testWidgets('a tablet header over the conversation tab keeps the pill', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        _salon(live: true),
        size: const Size(768, 1024),
      );
      // The scene (with its own pill) is under the header: the lamp.
      expect(find.descendant(of: header(), matching: lamp()), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('server-tab-chat')));
      await tester.pumpAndSettle();
      // The conversation is: the header says it with the pill again.
      expect(find.descendant(of: header(), matching: lamp()), findsNothing);
      expect(
        find.descendant(of: header(), matching: qaLivePill),
        findsOneWidget,
      );
    });

    testWidgets('the lamp dot grows with the text, 8 → 12 px (B4-V8)', (
      tester,
    ) async {
      Future<Size> dotAt(double scale) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: const Scaffold(
                  body: Center(
                    child: ServerLiveLamp(
                      semanticLabel: 'NA ŻYWO',
                      label: 'Na żywo od 19:40',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return tester.getSize(
          find.descendant(of: lamp(), matching: find.byType(FadeTransition)),
        );
      }

      expect(await dotAt(1), const Size.square(8));
      expect((await dotAt(1.3)).width, closeTo(10.4, .001));
      expect(await dotAt(2), const Size.square(12));
      expect(await dotAt(3), const Size.square(12));
    });

    testWidgets('with motion on, the lamp pulses three times and stops', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: Center(
              child: ServerLiveLamp(
                semanticLabel: 'NA ŻYWO',
                label: 'Na żywo od 19:40',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
      );
      expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 1800));
      expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));
      // 3 × 1.2 s = 3.6 s (plus the frame its clock starts on), then at
      // rest: no ticker keeps a persistent screen awake.
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pump(const Duration(milliseconds: 17));
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 10));
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
      final dot = tester.widget<FadeTransition>(
        find.descendant(of: lamp(), matching: find.byType(FadeTransition)),
      );
      expect(dot.opacity.value, 1);
    });

    testWidgets('the live under-glow is sized for a card (B4-V4)', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _salon(live: true), size: const Size(390, 844));
      final glow = tester.widget<DecoratedBox>(_glow);
      final shadows = (glow.decoration as BoxDecoration).boxShadow!;
      expect(shadows, hasLength(1));
      expect(shadows.single.color, AppPalette.dark.liveGlow);
      expect(shadows.single.blurRadius, ServerSessionCard.cardGlowBlur);
      expect(shadows.single.offset, const Offset(0, ServerSessionCard.cardGlowY));
      expect(shadows.single.spreadRadius, ServerSessionCard.cardGlowSpread);
      expect(ServerSessionCard.cardGlowBlur, 20);
      expect(ServerSessionCard.cardGlowY, 8);
      // Pearl keeps the live tile's plum drop under it.
      final pearl = ServerSessionCard.cardGlow(AppPalette.light);
      expect(pearl, hasLength(2));
      expect(pearl.first.color, AppPalette.light.liveGlow);
    });

    testWidgets('each board lights exactly one live surface before a join, '
        'and none when quiet (B4-V2)', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final type in ServerType.values) {
        for (final size in const [Size(390, 844), Size(1440, 900)]) {
          ServerSessionCard.debugResetIgnitions();
          await pumpServers(tester, template(type), size: size);
          expect(_glow, findsOneWidget, reason: '$type $size live');
          expect(_corner, findsOneWidget, reason: '$type $size live');
          await pumpServers(tester, template(type, live: false), size: size);
          expect(_glow, findsNothing, reason: '$type $size quiet');
          expect(_corner, findsNothing, reason: '$type $size quiet');
        }
      }
    });

    testWidgets('the family lounge is a block with a hairline, not an '
        'outline (B4-V2)', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final light in [false, true]) {
        final palette = light ? AppPalette.light : AppPalette.dark;
        await pumpServers(
          tester,
          template(ServerType.family, live: false),
          size: const Size(390, 844),
          light: light,
        );
        final card = tester.widget<AnimatedContainer>(
          find.byKey(const ValueKey('server-family-lounge-card')),
        );
        final edge =
            (card.foregroundDecoration! as BoxDecoration).border! as Border;
        expect(edge.top.color, palette.hairline);
        expect(
          (card.decoration! as BoxDecoration).gradient,
          palette.blockGradient,
        );
      }
    });

    testWidgets('the community actions are neutral tonal pills (B4-V2)', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        template(ServerType.community),
        size: const Size(1440, 900),
        light: true,
      );
      for (final key in const [
        'server-community-follow',
        'server-community-share',
      ]) {
        final button = tester.widget<OutlinedButton>(
          find.byKey(ValueKey(key)),
        );
        expect(
          button.style!.side!.resolve(const {})!.color,
          AppPalette.light.hairlineControl,
          reason: key,
        );
        expect(
          button.style!.backgroundColor!.resolve(const {}),
          AppPalette.light.glass,
          reason: key,
        );
      }
    });

    testWidgets('under high contrast a focused bar control shows its whole '
        'ring (A11Y-1)', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        _highContrast(_salon(live: true, connector: connector)),
        size: const Size(1440, 900),
      );
      final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);
      // The microphone is off: the neutral control with its resting edge.
      expect(link.microphone, isFalse);
      final mic = find.byKey(const ValueKey('server-dock-microphone'));
      final edge = find.descendant(
        of: mic,
        matching: find.byKey(const ValueKey('server-dock-control-edge')),
      );
      Color edgeColor() =>
          ((tester.widget<DecoratedBox>(edge).decoration as BoxDecoration)
                      .border!
                  as Border)
              .top
              .color;
      expect(edgeColor(), AppPalette.dark.borderStrong);

      final button = find.descendant(of: mic, matching: find.byType(IconButton));
      Focus.of(
        tester.element(find.descendant(of: button, matching: find.byType(Icon))),
      ).requestFocus();
      await tester.pumpAndSettle();
      // Focused: the resting edge steps aside…
      expect(edgeColor(), Colors.transparent);
      // …and the ring is the full 2 px in the control's own ink.
      final side = tester
          .widget<IconButton>(button)
          .style!
          .side!
          .resolve(const {WidgetState.focused})!;
      expect(side.width, 2);
      expect(side.color, AppTheme.darkTheme.colorScheme.onSurface);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(edgeColor(), AppPalette.dark.borderStrong);
    });

    testWidgets('a speaker glows around the ring, never through the avatar '
        '(A11Y-3)', (tester) async {
      const quiet = ServerMediaParticipant(
        identity: 'ola',
        name: 'Ola',
        isLocal: false,
        isMicrophoneEnabled: true,
      );
      const speaking = ServerMediaParticipant(
        identity: 'ola',
        name: 'Ola',
        isLocal: false,
        isSpeaking: true,
        isMicrophoneEnabled: true,
      );
      final colors = ServerIdentity.of(
        ServerType.friends,
      ).resolve(Brightness.dark);
      final boundary = GlobalKey();
      Future<Color> avatarFill(ServerMediaParticipant person) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundary,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ServerParticipantTile(
                      person: person,
                      colors: colors,
                      width: 104,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final origin = tester.getTopLeft(find.byKey(boundary));
        final avatar = tester.getRect(find.byType(UserAvatar));
        // Inside the disc, below the initial.
        final probe = Offset(
          avatar.center.dx - origin.dx,
          avatar.center.dy + avatar.height * .36 - origin.dy,
        );
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final data = await tester.runAsync(() async {
          final image = await render.toImage();
          final bytes = await image.toByteData();
          final width = image.width;
          image.dispose();
          return (bytes!, width);
        });
        final (bytes, width) = data!;
        final i = (probe.dy.round() * width + probe.dx.round()) * 4;
        return Color.fromARGB(
          bytes.getUint8(i + 3),
          bytes.getUint8(i),
          bytes.getUint8(i + 1),
          bytes.getUint8(i + 2),
        );
      }

      // Real, blurred shadows (the test binding otherwise paints every
      // shadow as a hard block).
      debugDisableShadows = false;
      try {
        final rest = await avatarFill(quiet);
        final lit = await avatarFill(speaking);
        expect(lit, rest);
      } finally {
        debugDisableShadows = true;
      }
      final ring = tester.widget<Container>(
        find.byKey(const ValueKey('server-participant-ring-ola')),
      );
      final glow = (ring.decoration! as BoxDecoration).boxShadow!.single;
      expect(glow.blurStyle, BlurStyle.outer);
    });

    testWidgets('high contrast keeps the join and create gradients and drops '
        'their lift (A11Y-6, B4-V7: the documented R5 exception)', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      List<BoxShadow> liftOf(Finder button) =>
          (tester
                      .widget<AnimatedContainer>(
                        find
                            .ancestor(
                              of: button,
                              matching: find.byType(AnimatedContainer),
                            )
                            .first,
                      )
                      .decoration!
                  as ShapeDecoration)
              .shadows ??
          const [];
      Gradient? gradientOf(Finder button) =>
          (tester
                      .widget<Ink>(
                        find.descendant(of: button, matching: find.byType(Ink)),
                      )
                      .decoration!
                  as BoxDecoration)
              .gradient;

      await pumpServers(
        tester,
        _highContrast(_salon(live: true)),
        size: const Size(390, 844),
      );
      final colors = ServerIdentity.of(
        ServerType.friends,
      ).resolve(Brightness.dark);
      expect(gradientOf(qaJoin), colors.ctaGradient);
      expect(liftOf(qaJoin), isEmpty);

      await pumpServers(
        tester,
        _highContrast(
          ServersScreen(
            key: UniqueKey(),
            isRootTab: true,
            repository: TestServerRepository()
              ..servers = [_server('a', 'Po godzinach', ServerType.friends)],
            chatService: qaChat(),
            connector: FakeServerMediaConnector(),
          ),
        ),
        size: const Size(390, 844),
      );
      final create = find.byKey(const ValueKey('servers-create'));
      expect(
        gradientOf(create),
        AppGradients.primaryAction(AppTheme.darkTheme.colorScheme),
      );
      expect(liftOf(create), isEmpty);
    });

    testWidgets('the icon-only "Kanały" keeps a 3:1 boundary (A11Y-7)', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final light in [false, true]) {
        final palette = light ? AppPalette.light : AppPalette.dark;
        await pumpServers(
          tester,
          _salon(),
          size: const Size(390, 844),
          textScale: 2,
          light: light,
        );
        final channels = tester.widget<IconButton>(qaOpenChannels);
        final rest = channels.style!.side!.resolve(const {})!;
        expect(rest.color, palette.borderStrong);
        for (final canvas in [palette.background, palette.backgroundTop]) {
          expect(
            _contrast(rest.color, canvas),
            greaterThanOrEqualTo(3),
            reason: '${light ? 'Pearl' : 'Dark'} on $canvas',
          );
        }
        final focused = channels.style!.side!.resolve(const {
          WidgetState.focused,
        })!;
        expect(focused.color, palette.focus);
        expect(focused.width, 2);
      }
    });

    testWidgets('the invite introduction shares the scene blocks\' edges '
        '(B4-V11)', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      for (final size in const [Size(768, 1024), Size(1440, 900)]) {
        await pumpServers(
          tester,
          ServerWorkspaceScreen(
            key: UniqueKey(),
            serverId: 's',
            repository: repository,
            isRootTab: true,
            initialChannelId: 'lounge',
            justCreated: true,
            chatService: qaChat(),
            connector: FakeServerMediaConnector(),
          ),
          size: size,
        );
        final intro = tester.getRect(
          find.byKey(const ValueKey('server-invite-introduction')),
        );
        final card = tester.getRect(_card);
        expect(intro.left, card.left, reason: '$size');
        expect(intro.right, card.right, reason: '$size');
      }
    });
  });
}
