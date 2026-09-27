import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_channel_scene.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_voice_stage.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_waiting_dot.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/inputs/yo_segmented_pill.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/rows/yo_channel_row.dart';

import 'server_independent_qa_support.dart';
import 'server_test_support.dart';

/// Refine-look batch 4 (spec §8.2): the Servers directory and workspace get
/// the block finish, the live session card is the workspace's one emitted
/// light, the join is the one lifted action, the header says LIVE with a
/// lamp, and a speaking tile no longer jiggles.
void main() {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return la > lb ? (la + .05) / (lb + .05) : (lb + .05) / (la + .05);
  }

  Server server(
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

  final directoryServers = [
    server('a', 'Po godzinach', ServerType.friends, members: 12),
    server(
      'b',
      'Klub książki',
      ServerType.community,
      members: 184,
      description:
          'Co miesiąc jedna książka i jedna długa rozmowa o niej, '
          'a potem jeszcze jedna.',
    ),
    server('c', 'Rodzina Nowaków', ServerType.family, members: 6),
  ];

  Widget directory({List<Server>? servers}) => ServersScreen(
    key: UniqueKey(),
    isRootTab: true,
    repository: TestServerRepository()..servers = servers ?? directoryServers,
    chatService: qaChat(),
    connector: FakeServerMediaConnector(),
  );

  Finder row(String id) => find.byKey(ValueKey('server-directory-$id'));

  BoxDecoration rowFinish(WidgetTester tester, String id) =>
      tester
              .widget<Ink>(
                find.descendant(of: row(id), matching: find.byType(Ink)).first,
              )
              .decoration!
          as BoxDecoration;

  /// The row's outer box: Pearl's shadow pair, and its edge as a foreground.
  AnimatedContainer rowBox(WidgetTester tester, String id) =>
      tester.widget<AnimatedContainer>(
        find
            .ancestor(of: row(id), matching: find.byType(AnimatedContainer))
            .first,
      );

  Border rowEdge(WidgetTester tester, String id) =>
      (rowBox(tester, id).foregroundDecoration! as BoxDecoration).border!
          as Border;

  group('the directory', () {
    for (final light in [false, true]) {
      final palette = light ? AppPalette.light : AppPalette.dark;
      testWidgets('rows are neutral R2 blocks (light=$light)', (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpServers(tester, directory(), light: light);
        for (final id in ['a', 'b', 'c']) {
          final finish = rowFinish(tester, id);
          // The same top-lit block for every template: identity lives only
          // in the squircle, never as a tint on the block.
          expect(finish.gradient, palette.blockGradient, reason: id);
          expect(finish.borderRadius, AppRadius.block, reason: id);
          // The edge is a foreground over the block: an `Ink` border would
          // pad the content by its width and move it on focus.
          expect(finish.border, isNull, reason: id);
          expect(rowEdge(tester, id).top.color, palette.hairline, reason: id);
          expect(rowEdge(tester, id).top.width, 1, reason: id);
          expect(
            tester.getSize(row(id)).height,
            greaterThanOrEqualTo(72),
            reason: id,
          );
        }
        // Pearl's shadow pair sits outside the row's clip; Dark has none.
        expect(
          (rowBox(tester, 'a').decoration! as BoxDecoration).boxShadow ??
              const [],
          light ? palette.blockShadows : isEmpty,
        );
        // Rows keep the block rhythm: 12 px between them.
        expect(
          tester.getTopLeft(row('b')).dy - tester.getBottomLeft(row('a')).dy,
          12,
        );
        // The member count never parts from its noun, and the dot never
        // starts a line.
        expect(find.textContaining('\u00A0· 12\u00A0osób'), findsOneWidget);
      });
    }

    testWidgets('high contrast drops the finish for a flat, strongly edged '
        'row', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(highContrast: true),
            child: directory(),
          ),
        ),
      );
      final finish = rowFinish(tester, 'a');
      expect(finish.gradient, isNull);
      expect(finish.color, AppPalette.dark.surface);
      expect(rowEdge(tester, 'a').top.color, AppPalette.dark.borderStrong);
    });

    for (final (label, size) in [
      ('one column', const Size(390, 844)),
      ('two columns', const Size(1440, 900)),
    ]) {
      testWidgets('keyboard focus rings a row and moves nothing ($label)', (
        tester,
      ) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpServers(tester, directory(), size: size);
        final watched = [
          row('a'),
          find.text('Po godzinach'),
          row('b'),
          find.text('Klub książki'),
          row('c'),
        ];
        final before = [for (final finder in watched) tester.getRect(finder)];
        // Tab onto the first row, exactly as a keyboard user would (the
        // create action comes first).
        for (var tabs = 0; tabs < 8; tabs++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          if (rowEdge(tester, 'a').top.width == 2) break;
        }
        final edge = rowEdge(tester, 'a');
        expect(edge.top.color, AppPalette.dark.focus);
        expect(rowEdge(tester, 'b').top.width, 1);
        expect([for (final finder in watched) tester.getRect(finder)], before);
      });
    }

    testWidgets('at 200 % the stacked details keep a 12 px inset at both '
        'ends', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, directory(), textScale: 2);
      final block = tester.getRect(row('b'));
      final details = tester.getRect(
        find
            .ancestor(
              of: find.text('Klub książki'),
              matching: find.byType(Column),
            )
            .first,
      );
      expect(details.width, lessThan(block.width - 20), reason: 'stacked');
      // 12 px of padding plus the 1 px edge, at the start and at the end.
      expect(details.left - block.left, 13);
      expect(block.right - details.right, 13);
    });

    testWidgets('two columns are equal-height pairs in row-major order', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, directory(), size: const Size(1440, 900));
      final a = tester.getRect(row('a'));
      final b = tester.getRect(row('b'));
      final c = tester.getRect(row('c'));
      // `a` and `b` share a row; the longer description stretches both.
      expect(a.top, b.top);
      expect(a.height, b.height);
      expect(b.left, greaterThan(a.right));
      expect(b.left - a.right, 16, reason: 'the column gap is 16');
      // `c` starts the next pair under `a`, 12 px lower.
      expect(c.left, a.left);
      expect(c.top - a.bottom, 12);
    });

    testWidgets('the create action is the one lift; the rail owns it on a '
        'desktop', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      ServerGradientFilledButton create() => tester.widget(
        find.ancestor(
          of: find.byKey(const ValueKey('servers-create')),
          matching: find.byType(ServerGradientFilledButton),
        ),
      );
      await pumpServers(tester, directory());
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('servers-create')))
            .enabled,
        isTrue,
      );
      expect(create().lifted, isTrue);
      expect(create().gradient, isA<LinearGradient>());
      // The shell decides from the window (MediaQuery), not from the slot.
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpServers(tester, directory(), size: const Size(1440, 900));
      expect(create().lifted, isFalse);
      // A wide but short window gets the phone shell (MainShell also needs
      // the rail's minimum height): no rail, so the action keeps its lift.
      tester.view.physicalSize = const Size(1440, 600);
      await pumpServers(tester, directory(), size: const Size(1440, 600));
      expect(create().lifted, isTrue);
    });

    testWidgets('the first-run directory carries the real logo', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, directory(servers: const []));
      final mark = tester.widget<YoBrandMark>(
        find.byKey(const ValueKey('servers-empty-logo')),
      );
      expect(mark.size, 72);
      expect(find.text('Twoje miejsce na wspólne rozmowy'), findsOneWidget);
    });
  });

  group('the session card', () {
    setUp(ServerSessionCard.debugResetIgnitions);

    Future<FakeServerMediaConnector> pumpLive(
      WidgetTester tester, {
      bool live = true,
      bool highContrast = false,
      bool light = false,
    }) async {
      final connector = FakeServerMediaConnector();
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(
          ServerType.friends,
          liveness: live
              ? ServerChannelLiveness(
                  isLive: true,
                  startedAt: DateTime(2026, 9, 19, 19, 40),
                )
              : ServerChannelLiveness.idle,
          activeSessionId: live ? 'session-live' : null,
        );
      final workspace = qaWorkspace(
        repository,
        channelId: 'lounge',
        connector: connector,
      );
      await pumpServers(
        tester,
        highContrast
            ? Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(highContrast: true),
                  child: workspace,
                ),
              )
            : workspace,
        size: const Size(1440, 900),
        light: light,
      );
      return connector;
    }

    Finder glow() => find.byKey(const ValueKey('server-session-glow'));
    Finder corner() => find.byKey(const ValueKey('server-session-corner'));
    Finder tint() => find.byKey(const ValueKey('server-session-tint'));

    testWidgets('live and not joined is the one lit block, with a gem orb '
        'and no participants', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpLive(tester);
      expect(glow(), findsOneWidget);
      expect(corner(), findsOneWidget);
      expect(tint(), findsNothing);
      final orb = tester.widget<Container>(
        find.byKey(const ValueKey('server-session-orb')),
      );
      final visuals = ServerIdentity.of(
        ServerType.friends,
      ).resolve(Brightness.dark);
      expect(
        (orb.decoration! as BoxDecoration).gradient,
        visuals.liveOrbGradient,
      );
      expect((orb.decoration! as BoxDecoration).boxShadow, isNull);
      // Nobody is drawn before a join (ADR-177).
      expect(find.byType(ServerParticipantTile), findsNothing);
    });

    testWidgets('quiet is a plain block with no light', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpLive(tester, live: false);
      expect(glow(), findsNothing);
      expect(corner(), findsNothing);
      expect(tint(), findsNothing);
      final orb = tester.widget<Container>(
        find.byKey(const ValueKey('server-session-orb')),
      );
      final visuals = ServerIdentity.of(
        ServerType.friends,
      ).resolve(Brightness.dark);
      expect(
        (orb.decoration! as BoxDecoration).gradient,
        visuals.unlitGradient,
      );
    });

    testWidgets('connected trades the glow for the voice accent edge and '
        'tint, without moving or remounting the card', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connector = await pumpLive(tester);
      final card = find.byKey(const ValueKey('server-session-card'));
      final before = tester.getTopLeft(card);
      final element = tester.element(card);
      await qaJoinAndSettle(tester, connector, roster: qaRoster);
      expect(glow(), findsNothing);
      expect(corner(), findsNothing);
      expect(tint(), findsOneWidget);
      expect(tester.getTopLeft(card), before);
      expect(
        tester.element(card),
        same(element),
        reason: 'a join must not remount the card (focus would be lost)',
      );
    });

    testWidgets('high contrast shows no light at all', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpLive(tester, highContrast: true);
      expect(glow(), findsNothing);
      expect(corner(), findsNothing);
      final card = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('server-session-card')),
      );
      final edge =
          (card.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(edge.top.color, AppColors.live);
      expect(edge.top.width, 1.5);
    });

    testWidgets('the light ignites once per live generation', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(
          ServerType.friends,
          liveness: ServerChannelLiveness(
            isLive: true,
            startedAt: DateTime(2026, 9, 19, 19, 40),
          ),
          activeSessionId: 'session-live',
        );
      Future<void> mount() async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('pl'),
            theme: AppTheme.darkTheme,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: qaWorkspace(repository, channelId: 'lounge'),
          ),
        );
      }

      double glowOpacity() => tester
          .widget<FadeTransition>(
            find
                .ancestor(of: glow(), matching: find.byType(FadeTransition))
                .first,
          )
          .opacity
          .value;

      await mount();
      // Let the stream deliver the server and its channels.
      for (var i = 0; i < 4 && glow().evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(glow(), findsOneWidget);
      expect(glowOpacity(), lessThan(.5), reason: 'the light fades in');
      await tester.pumpAndSettle();
      expect(glowOpacity(), 1);
      // A return to the same generation does not replay it.
      await tester.pumpWidget(const SizedBox());
      await mount();
      for (var i = 0; i < 4 && glow().evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(glowOpacity(), 1);
      await tester.pumpAndSettle();
    });
  });

  group('the header lamp', () {
    testWidgets('replaces the header pill, keeps its words, and rests under '
        'Reduce Motion', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final handle = tester.ensureSemantics();
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(
          ServerType.friends,
          liveness: ServerChannelLiveness(
            isLive: true,
            startedAt: DateTime(2026, 9, 19, 19, 40),
          ),
          activeSessionId: 'session-live',
        );
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'lounge'),
        size: const Size(1440, 900),
      );
      final header = find.byKey(const ValueKey('server-channel-header'));
      final lamp = find.byKey(const ValueKey('server-live-lamp'));
      expect(find.descendant(of: header, matching: lamp), findsOneWidget);
      expect(
        find.descendant(of: header, matching: qaLivePill),
        findsNothing,
        reason: 'the header says LIVE with the lamp, not a second pill',
      );
      // The pill stays on the scene's card.
      expect(qaLivePill, findsWidgets);
      expect(
        find.descendant(of: lamp, matching: find.text('Na żywo od 19:40')),
        findsOneWidget,
      );
      // The lamp itself says LIVE (the card and row pills say it too, so
      // an unscoped label search would prove nothing about the lamp).
      final lampWords = find.descendant(
        of: lamp,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'NA ŻYWO',
        ),
      );
      expect(lampWords, findsOneWidget);
      expect(tester.getSemantics(lampWords).label, contains('NA ŻYWO'));
      final dot = find.descendant(
        of: lamp,
        matching: find.byType(FadeTransition),
      );
      expect(tester.getSize(dot), const Size.square(8));
      // Reduce Motion (pumpServers) parks the dot: nothing is scheduled.
      expect(tester.widget<FadeTransition>(dot).opacity.value, 1);
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
      handle.dispose();
    });

    testWidgets('pulses a bounded three cycles, then settles', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ServerLiveLamp(
              semanticLabel: 'NA ŻYWO',
              label: 'Na żywo od 19:40',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
      );
      final dot = find.descendant(
        of: find.byKey(const ValueKey('server-live-lamp')),
        matching: find.byType(FadeTransition),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.widget<FadeTransition>(dot).opacity.value, lessThan(1));
      await tester.pump(const Duration(milliseconds: 3000));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<FadeTransition>(dot).opacity.value, 1);
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    });
  });

  group('the voice stage', () {
    Future<void> pumpTile(WidgetTester tester, {required bool speaking}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('pl'),
            home: Scaffold(
              body: Center(
                child: ServerParticipantTile(
                  person: ServerMediaParticipant(
                    identity: 'ola',
                    name: 'Ola',
                    isLocal: false,
                    isSpeaking: speaking,
                    isMicrophoneEnabled: true,
                  ),
                  colors: ServerIdentity.of(
                    ServerType.friends,
                  ).resolve(Brightness.dark),
                  width: 104,
                ),
              ),
            ),
          ),
        );

    testWidgets('a speaking tile does not jiggle: the ring is a foreground '
        'and the glow is paint', (tester) async {
      await pumpTile(tester, speaking: false);
      final ring = find.byKey(const ValueKey('server-participant-ring-ola'));
      final avatar = find.descendant(
        of: ring,
        matching: find.byType(UserAvatar),
      );
      final quietRing = tester.getRect(ring);
      final quietAvatar = tester.getRect(avatar.first);
      final quietName = tester.getRect(find.text('Ola'));
      Container box() => tester.widget<Container>(ring);
      expect((box().decoration! as BoxDecoration).boxShadow, isEmpty);

      await pumpTile(tester, speaking: true);
      expect(tester.getRect(ring), quietRing);
      expect(tester.getRect(avatar.first), quietAvatar);
      expect(tester.getRect(find.text('Ola')), quietName);
      final glow = (box().decoration! as BoxDecoration).boxShadow!;
      expect(glow, hasLength(1));
      expect(
        glow.single.color,
        AppPalette.dark.audioAccent.withValues(alpha: .40),
      );
      expect(glow.single.blurRadius, 12);
      final edge = (box().foregroundDecoration! as BoxDecoration).border!;
      expect((edge as Border).top.width, 3);
    });
  });

  group('the channel rows', () {
    testWidgets('the panel keeps its approved flat wash, and selecting a row '
        'moves nothing', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'lounge'),
        size: const Size(1440, 900),
      );
      final visuals = ServerIdentity.of(
        ServerType.friends,
      ).resolve(Brightness.dark);
      final lounge = find.byKey(const ValueKey('server-channel-lounge'));
      final general = find.byKey(ValueKey('server-channel-$_generalId'));
      BoxDecoration paintedOf(Finder tile) =>
          tester
                  .widget<Ink>(
                    find.ancestor(of: tile, matching: find.byType(Ink)).first,
                  )
                  .decoration!
              as BoxDecoration;
      // Kamil's approved panel: the flat identity wash, no gradient, edge or
      // shadow, and the identity ink.
      final selected = paintedOf(lounge);
      expect(selected.color, visuals.selectedWash);
      expect(selected.gradient, isNull);
      expect(selected.border, isNull);
      expect(selected.boxShadow, isNull);
      expect(
        tester.widget<ListTile>(lounge).selectedColor,
        visuals.selectedForeground,
      );
      expect(paintedOf(general).color, isNull);
      final title = find.descendant(of: general, matching: find.byType(Text));
      final before = tester.getRect(title.first);
      await tester.tap(general);
      await tester.pumpAndSettle();
      expect(paintedOf(general).color, visuals.selectedWash);
      expect(tester.getRect(title.first), before);
    });

    for (final light in [false, true]) {
      testWidgets('keyboard focus rings a panel row and moves nothing '
          '(light=$light)', (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final palette = light ? AppPalette.light : AppPalette.dark;
        final repository = TestServerRepository()
          ..servers = [qaServer(ServerType.friends)]
          ..channels = qaChannels(ServerType.friends);
        await pumpServers(
          tester,
          qaWorkspace(repository, channelId: 'lounge'),
          size: const Size(1440, 900),
          light: light,
        );
        final lounge = find.byKey(const ValueKey('server-channel-lounge'));
        final general = find.byKey(ValueKey('server-channel-$_generalId'));
        final watched = [
          for (final tile in [general, lounge])
            find.descendant(of: tile, matching: find.byType(Text)).first,
          lounge,
        ];
        final before = [for (final finder in watched) tester.getRect(finder)];
        Border? ringOf(Finder tile) =>
            (tester
                            .widget<DecoratedBox>(
                              find
                                  .ancestor(
                                    of: tile,
                                    matching: find.byType(DecoratedBox),
                                  )
                                  .first,
                            )
                            .decoration
                        as BoxDecoration)
                    .border
                as Border?;
        for (final tile in [general, lounge]) {
          tester.widget<ListTile>(tile).focusNode!.requestFocus();
          await tester.pumpAndSettle();
          final ring = ringOf(tile)!;
          expect(ring.top.color, palette.focus);
          expect(ring.top.width, 2);
          // The ring alone marks focus: no tint washes over the selection.
          expect(tester.widget<ListTile>(tile).focusColor, Colors.transparent);
          // The tile itself never takes an edge: its `Ink` would pad the
          // content by that edge.
          expect(
            (tester.widget<ListTile>(tile).shape! as RoundedRectangleBorder)
                .side,
            BorderSide.none,
          );
          expect([
            for (final finder in watched) tester.getRect(finder),
          ], before);
        }
      });
    }

    test('the waiting dot reads on the selected wash and on the directory '
        'block', () {
      for (final brightness in Brightness.values) {
        final palette = brightness == Brightness.dark
            ? AppPalette.dark
            : AppPalette.light;
        final grounds = <String, Color>{
          'block top': palette.blockTop,
          'block end': palette.surface,
        };
        for (final type in ServerType.values) {
          final visuals = ServerIdentity.of(type).resolve(brightness);
          grounds['$type selected'] = Color.alphaBlend(
            visuals.selectedWash,
            palette.surfaceMuted,
          );
        }
        for (final MapEntry(key: name, value: ground) in grounds.entries) {
          expect(
            contrast(palette.warningForeground, ground),
            greaterThanOrEqualTo(3),
            reason: 'waiting dot on $name, $brightness',
          );
        }
      }
    });

    testWidgets('a decorated row moves nothing when it is selected or '
        'focused, and keeps its waiting dot', (tester) async {
      // The handoff finish shape (a gradient, an edge and a shadow), built
      // here because no screen adopts it yet.
      final finish = BoxDecoration(
        borderRadius: AppRadius.md,
        gradient: LinearGradient(
          colors: [
            AppPalette.light.audioAccent.withValues(alpha: .10),
            AppPalette.light.audioAccent.withValues(alpha: .03),
          ],
        ),
        border: Border.all(
          color: AppPalette.light.audioAccent.withValues(alpha: .35),
        ),
        boxShadow: AppPalette.light.blockShadows.take(1).toList(),
      );
      Widget rowWith({required bool selected}) => MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Material(
            color: AppPalette.light.surfaceMuted,
            child: SizedBox(
              width: 280,
              child: YoVoiceChannelRow(
                tileKey: const ValueKey('row'),
                label: 'Studio LIVE',
                icon: Icons.mic_none_rounded,
                selected: selected,
                selectedDecoration: finish,
                attention: const ServerWaitingDot(
                  key: ValueKey('dot'),
                  semanticLabel: 'Czeka 1 osoba',
                ),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      Border? edge() =>
          (tester
                          .widget<DecoratedBox>(
                            find
                                .ancestor(
                                  of: find.byKey(const ValueKey('row')),
                                  matching: find.byType(DecoratedBox),
                                )
                                .first,
                          )
                          .decoration
                      as BoxDecoration)
                  .border
              as Border?;
      final label = find.text('Studio LIVE');
      final dot = find.byKey(const ValueKey('dot'));
      await tester.pumpWidget(rowWith(selected: false));
      final rest = [tester.getRect(label), tester.getRect(dot)];
      expect(edge(), isNull);
      await tester.pumpWidget(rowWith(selected: true));
      expect([tester.getRect(label), tester.getRect(dot)], rest);
      expect(edge(), finish.border);
      tester
          .widget<ListTile>(find.byKey(const ValueKey('row')))
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      expect(edge()!.top.color, AppPalette.light.focus);
      expect(edge()!.top.width, 2);
      expect([tester.getRect(label), tester.getRect(dot)], rest);
      // The raised-hands dot is still painted on the selected finish.
      expect(dot, findsOneWidget);
    });
  });

  group('YoSegmentedPill finish parameters', () {
    Future<void> pumpPill(WidgetTester tester, YoSegmentedPill pill) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(body: Center(child: pill)),
          ),
        );

    YoSegmentedPill pill({
      Decoration? thumb,
      Color? selectedForeground,
      bool hairlineTrack = false,
    }) => YoSegmentedPill(
      segments: const [
        YoSegmentedPillSegment(label: 'Salon'),
        YoSegmentedPillSegment(label: 'Czat'),
      ],
      selectedIndex: 0,
      onSelected: (_) {},
      thumbDecoration: thumb,
      selectedForeground: selectedForeground,
      hairlineTrack: hairlineTrack,
    );

    Color labelColor(WidgetTester tester, String label) =>
        tester.widget<Text>(find.text(label)).style!.color!;

    testWidgets('defaults are unchanged: a primary thumb, onPrimary ink and '
        'the border track', (tester) async {
      await pumpPill(tester, pill());
      final scheme = AppTheme.darkTheme.colorScheme;
      final thumb = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(AnimatedAlign),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((thumb.decoration as BoxDecoration).color, scheme.primary);
      expect(labelColor(tester, 'Salon'), scheme.onPrimary);
      final track = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(YoSegmentedPill),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        ((track.foregroundDecoration! as BoxDecoration).border! as Border)
            .top
            .color,
        AppPalette.dark.border,
      );
    });

    testWidgets('a tonal thumb, its ink and a hairline track apply without '
        'moving a label', (tester) async {
      await pumpPill(tester, pill());
      final before = tester.getRect(find.text('Salon'));
      final visuals = ServerIdentity.of(
        ServerType.friends,
      ).resolve(Brightness.dark);
      final tonal = BoxDecoration(
        color: Color.alphaBlend(
          ServerIdentity.of(ServerType.friends).primary.withValues(alpha: .22),
          AppPalette.dark.surfaceRaised,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: visuals.foreground.withValues(alpha: .6)),
      );
      await pumpPill(
        tester,
        pill(
          thumb: tonal,
          selectedForeground: visuals.selectedForeground,
          hairlineTrack: true,
        ),
      );
      final thumb = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(AnimatedAlign),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(thumb.decoration, tonal);
      expect(labelColor(tester, 'Salon'), visuals.selectedForeground);
      expect(labelColor(tester, 'Czat'), AppPalette.dark.textSecondary);
      expect(tester.getRect(find.text('Salon')), before);
      final track = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(YoSegmentedPill),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        ((track.foregroundDecoration! as BoxDecoration).border! as Border)
            .top
            .color,
        AppPalette.dark.hairline,
      );
    });
  });

  group('the conversation bar', () {
    testWidgets('an open microphone is its only light, and the controls are '
        'round glass', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'lounge', connector: connector),
        size: const Size(1440, 900),
      );
      await qaJoinAndSettle(tester, connector, roster: qaRoster);
      Container mic() => tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const ValueKey('server-dock-microphone')),
              matching: find.byType(Container),
            )
            .first,
      );
      final bar = find.byKey(const ValueKey('server-conversation-dock'));
      final barSize = tester.getSize(bar);
      final micRect = tester.getRect(
        find.byKey(const ValueKey('server-dock-microphone')),
      );
      expect((mic().decoration! as BoxDecoration).boxShadow, isEmpty);
      final button = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(const ValueKey('server-dock-headphones')),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.style!.shape!.resolve(const {}), isA<CircleBorder>());

      await tester.tap(find.byKey(const ValueKey('server-dock-microphone')));
      await tester.pumpAndSettle();
      final glow = (mic().decoration! as BoxDecoration).boxShadow!;
      expect(glow, hasLength(1));
      expect(
        glow.single.color,
        AppPalette.dark.audioAccent.withValues(alpha: .36),
      );
      expect(glow.single.blurRadius, 12);
      expect(glow.single.spreadRadius, -4);
      // The light is paint: the bar and its controls keep their geometry.
      expect(tester.getSize(bar), barSize);
      expect(
        tester.getRect(find.byKey(const ValueKey('server-dock-microphone'))),
        micRect,
      );
      final dock = tester.widget<Container>(bar);
      final fill = (dock.decoration! as BoxDecoration).color!;
      expect(
        fill,
        Color.alphaBlend(
          AppPalette.dark.audioAccent.withValues(alpha: .10),
          AppPalette.dark.surfaceRaised,
        ),
      );
    });
  });

  group('the phone Kanały sheet', () {
    for (final light in [false, true]) {
      testWidgets('is one surface with a hairline edge (light=$light)', (
        tester,
      ) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final palette = light ? AppPalette.light : AppPalette.dark;
        final repository = TestServerRepository()
          // A second server, so the sheet carries the server rail.
          ..servers = [
            qaServer(ServerType.friends),
            server('k', 'Klub książki', ServerType.community),
          ]
          ..channels = qaChannels(ServerType.friends);
        await pumpServers(
          tester,
          qaWorkspace(repository, channelId: 'lounge'),
          light: light,
        );
        await tester.tap(qaOpenChannels);
        await tester.pumpAndSettle();
        final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
        expect(sheet.backgroundColor, palette.surfaceMuted);
        final shape = sheet.shape! as OutlinedBorder;
        expect(shape.side.color, palette.hairline);
        // A 28 px rounded top and a square bottom.
        final outline = shape.getOuterPath(const Rect.fromLTWH(0, 0, 390, 600));
        expect(outline.contains(const Offset(3, 3)), isFalse);
        expect(outline.contains(const Offset(195, 1)), isTrue);
        expect(outline.contains(const Offset(1, 599)), isTrue);
        // R16: the hairline is the top side only: one crescent between the
        // rounded outline and the same outline lowered by 1 px at the top —
        // never a stroked ring round the sides and the bottom.
        const rect = Rect.fromLTWH(0, 0, 390, 600);
        final outer = RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(28),
          topRight: const Radius.circular(28),
        );
        void paintEdge(Canvas canvas) => shape.paint(canvas, rect);
        expect(
          paintEdge,
          paints..drrect(
            outer: outer,
            inner: const EdgeInsets.only(top: 1).deflateRRect(outer),
            color: palette.hairline,
          ),
        );
        expect(paintEdge, isNot(paints..rrect()));
        // The rail column wears the sheet's own surface, so the handle band
        // runs into it without a darker, square-topped notch.
        final rail = tester.widget<Material>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('server-rail')),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(rail.color, palette.surfaceMuted);
        // The tonal action that opened it keeps its key and widget type.
        expect(
          tester
              .widget<ButtonStyleButton>(qaOpenChannels)
              .style!
              .side!
              .resolve(const {})!
              .color,
          palette.hairlineControl,
        );
      });
    }
  });

  group('the one lifted action', () {
    Future<Color> pixelAt(
      WidgetTester tester,
      GlobalKey boundary,
      Offset at,
    ) async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await render.toImage();
        try {
          return await image.toByteData();
        } finally {
          image.dispose();
        }
      });
      final width = render.size.width.round();
      final i = (at.dy.floor() * width + at.dx.floor()) * 4;
      return Color.fromARGB(
        bytes!.getUint8(i + 3),
        bytes.getUint8(i),
        bytes.getUint8(i + 1),
        bytes.getUint8(i + 2),
      );
    }

    double distance(Color a, Color b) =>
        ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) * 255;

    for (final light in [false, true]) {
      final theme = light ? AppTheme.lightTheme : AppTheme.darkTheme;
      final brightness = light ? Brightness.light : Brightness.dark;
      final scheme = theme.colorScheme;
      final cases = <String, (Gradient, Color, Color)>{
        'create': (
          AppGradients.primaryAction(scheme),
          scheme.primary,
          scheme.onPrimary,
        ),
        for (final type in [ServerType.friends, ServerType.community])
          'join ${type.name}': () {
            final visuals = ServerIdentity.of(type).resolve(brightness);
            return (visuals.ctaGradient, visuals.cta, visuals.onCta);
          }(),
      };
      for (final MapEntry(key: name, value: (gradient, fill, ink))
          in cases.entries) {
        testWidgets('the $name focus ring is painted over the gradient '
            '(light=$light)', (tester) async {
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: boundary,
                    child: ServerGradientFilledButton(
                      buttonKey: const ValueKey('cta'),
                      onPressed: () {},
                      gradient: gradient,
                      fill: fill,
                      foreground: ink,
                      lifted: false,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Stwórz serwer'),
                    ),
                  ),
                ),
              ),
            ),
          );
          final size = tester.getSize(find.byKey(boundary));
          // The second pixel row at the middle of the stadium's top edge:
          // inside a 2 px ring, and plain gradient at rest.
          final probe = Offset(size.width / 2, 1);
          final label = tester.getRect(find.text('Stwórz serwer'));
          final rest = await pixelAt(tester, boundary, probe);
          expect(
            distance(rest, ink),
            greaterThan(60),
            reason: 'at rest the edge is the gradient, not the ring',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(
            FocusManager.instance.primaryFocus?.context?.widget,
            isNot(isNull),
          );
          final focused = await pixelAt(tester, boundary, probe);
          expect(
            distance(focused, ink),
            lessThan(24),
            reason: 'the ring ($ink) must be what is painted, got $focused',
          );
          // The ring is a foreground: the label does not move.
          expect(tester.getRect(find.text('Stwórz serwer')), label);
        });
      }
    }
  });

  group('the session scene', () {
    for (final (width, inset) in [(390.0, 16.0), (1440.0, 24.0)]) {
      testWidgets('its scroll dissolves into the canvas at the end '
          '($width)', (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()
          ..servers = [qaServer(ServerType.friends)]
          ..channels = qaChannels(ServerType.friends);
        await pumpServers(
          tester,
          qaWorkspace(repository, channelId: 'lounge'),
          size: Size(width, width < 600 ? 844 : 900),
        );
        final fade = find.byKey(const ValueKey('server-session-edge-fade'));
        expect(fade, findsOneWidget);
        // Exactly the scroll padding, at the very bottom of the viewport.
        expect(tester.getSize(fade).height, inset);
        final scroll = find.byKey(
          const ValueKey('server-channel-content-scroll'),
        );
        final sceneScroll = find.descendant(
          of: find.ancestor(of: fade, matching: find.byType(Stack)).first,
          matching: scroll,
        );
        expect(tester.getRect(fade).bottom, tester.getRect(sceneScroll).bottom);
        final gradient =
            (tester.widget<DecoratedBox>(fade).decoration as BoxDecoration)
                    .gradient!
                as LinearGradient;
        expect(gradient.colors.last, AppPalette.dark.background);
        expect(gradient.colors.first.a, 0);
        // It never takes a pointer.
        expect(
          find.ancestor(of: fade, matching: find.byType(IgnorePointer)),
          findsWidgets,
        );
      });
    }

    testWidgets('high contrast keeps the plain edge', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      await pumpServers(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(highContrast: true),
            child: qaWorkspace(repository, channelId: 'lounge'),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('server-session-edge-fade')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('server-channel-content-scroll')),
        findsWidgets,
      );
    });
  });

  test('the live gems and the identity join keep their ink readable', () {
    for (final brightness in Brightness.values) {
      for (final type in ServerType.values) {
        final visuals = ServerIdentity.of(type).resolve(brightness);
        for (final stop in visuals.liveOrbGradient.colors) {
          // The 46 px symbol is a graphic object: 3:1 is the floor, and the
          // director-verified stops clear 5:1.
          expect(
            contrast(visuals.onLiveOrb, stop),
            greaterThanOrEqualTo(5),
            reason: '$type $brightness gem $stop',
          );
        }
        for (final stop in visuals.ctaGradient.colors) {
          expect(
            contrast(visuals.onCta, stop),
            greaterThanOrEqualTo(4.5),
            reason: '$type $brightness join $stop',
          );
        }
        for (final stop in visuals.ctaGradient.colors) {
          expect(
            contrast(visuals.onCta, stop),
            greaterThanOrEqualTo(contrast(visuals.onCta, visuals.cta) - .001),
            reason: '$type $brightness: the sweep only ever gains contrast',
          );
        }
      }
    }
    expect(
      AppFinish.blockShadows(AppPalette.dark),
      isEmpty,
      reason: 'a Dark block casts no shadow',
    );
  });
}

/// The friends template's first text channel.
final String _generalId = qaFirstText(ServerType.friends);
