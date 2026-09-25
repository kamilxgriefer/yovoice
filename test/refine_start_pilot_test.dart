// Refine-look B2 "Start pilot" (spec §8.1, W1 Start part, W2): the finish
// of Start's own blocks, pinned by value. The shared primitives are pinned
// in yo_refine_primitives_test.dart and app_finish_test.dart; this file pins
// how Start adopts them and the two behaviours it adds (the live ignite and
// the section arrival).
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_friend_tile.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_greeting_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_live_now.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_record_moment_card.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_server_overview.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/badges/yo_count_badge.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';
import 'package:yovoice/shared/widgets/layout/home_section_header.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

import 'voice_moment_test_doubles.dart';

Widget _host(
  Widget child, {
  Brightness brightness = Brightness.dark,
  Size size = const Size(390, 900),
  double textScale = 1,
  bool disableAnimations = false,
  bool highContrast = false,
  bool accessibleNavigation = false,
  bool scroll = true,
}) => MaterialApp(
  locale: const Locale('pl'),
  theme: brightness == Brightness.dark
      ? AppTheme.darkTheme
      : AppTheme.lightTheme,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: TextScaler.linear(textScale),
      disableAnimations: disableAnimations,
      highContrast: highContrast,
      accessibleNavigation: accessibleNavigation,
    ),
    child: Scaffold(
      body: scroll
          ? SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            )
          : child,
    ),
  ),
);

void _useView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Server _server(String id, {ServerType type = ServerType.podcast}) => Server(
  id: id,
  name: 'Serwer $id',
  description: 'Opis serwera $id',
  ownerId: 'owner',
  type: type,
  privacy: ServerPrivacy.public,
  schemaVersion: 1,
  activationState: 'active',
);

ServerChannel _live(String serverId, String id, DateTime since) =>
    ServerChannel(
      id: id,
      serverId: serverId,
      name: 'Kanał $id',
      kind: ServerChannelKind.stage,
      liveness: ServerChannelLiveness(isLive: true, startedAt: since),
    );

/// Only `watchChannels` is real here.
class _Channels implements ServerRepository {
  final Map<String, StreamController<List<ServerChannel>>> controllers = {};

  @override
  Stream<List<ServerChannel>> watchChannels(String serverId) => controllers
      .putIfAbsent(serverId, StreamController<List<ServerChannel>>.new)
      .stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Conversation _conversation(int index, {int unread = 0}) => Conversation(
  id: 'conversation-$index',
  participantIds: ['me', 'friend-$index'],
  participantNames: {'me': 'Me', 'friend-$index': 'Przyjaciel $index'},
  participantEmails: const {},
  participantPhotoUrls: const {},
  unreadCounts: {'me': unread, 'friend-$index': 0},
  lastMessage: 'Masz chwilę na rozmowę?',
  lastMessageType: MessageType.text,
  lastMessageSenderId: 'friend-$index',
  updatedAt: DateTime(2026, 9, 25),
  createdAt: DateTime(2026, 9, 25),
  archivedBy: const [],
  mutedBy: const [],
);

double _glowOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(find.byKey(const ValueKey('home-live-glow')))
    .opacity
    .value;

void main() {
  setUp(HomeLiveNowSection.debugResetIgnitions);

  group('W1 — the Start lockup', () {
    for (final (width, mark) in const [(390.0, 32.0), (768.0, 36.0)]) {
      testWidgets('at $width px the bare mark sits in a $mark px box', (
        tester,
      ) async {
        _useView(tester, Size(width, 900));
        await tester.pumpWidget(
          _host(const HomeBrandLockup(), size: Size(width, 900)),
        );
        final markFinder = find.byKey(const ValueKey('home-brand-mark'));
        expect(tester.widget(markFinder), isA<YoBrandMark>());
        expect(tester.getSize(markFinder), Size(mark, mark));
        // No tile: nothing inside the lockup paints a box behind the mark.
        final boxes = find.descendant(
          of: find.byKey(const ValueKey('home-brand-lockup')),
          matching: find.byWidgetPredicate(
            (w) =>
                (w is Container && w.decoration != null) || (w is DecoratedBox),
          ),
        );
        expect(boxes, findsNothing);
        final handle = tester.ensureSemantics();
        expect(
          tester.getSemantics(find.byKey(const ValueKey('home-brand-lockup'))),
          matchesSemantics(label: 'YO Voice'),
        );
        handle.dispose();
      });
    }

    testWidgets('Dark blooms, Pearl drops a contact shadow, high contrast '
        'has neither', (tester) async {
      _useView(tester, const Size(390, 900));
      Future<void> pump({
        required Brightness brightness,
        bool highContrast = false,
      }) async {
        await tester.pumpWidget(
          _host(
            const HomeBrandLockup(),
            brightness: brightness,
            highContrast: highContrast,
          ),
        );
        // Let MaterialApp's theme cross-fade land on the new palette.
        await tester.pump(const Duration(milliseconds: 400));
      }

      int shadowTints() => find
          .descendant(
            of: find.byType(YoBrandMark),
            matching: find.byType(ColorFiltered),
          )
          .evaluate()
          .length;
      int images() => find
          .descendant(
            of: find.byType(YoBrandMark),
            matching: find.byType(Image),
          )
          .evaluate()
          .length;

      await pump(brightness: Brightness.dark);
      expect(images(), 2, reason: 'mark + bloom');
      expect(shadowTints(), 0);
      await pump(brightness: Brightness.light);
      expect(images(), 2, reason: 'mark + contact shadow');
      expect(shadowTints(), 1);
      await pump(brightness: Brightness.dark, highContrast: true);
      expect(images(), 1, reason: 'the mark alone');
    });
  });

  group('the header controls', () {
    Widget header({int unread = 0}) => HomeGreetingHeader(
      profile: const Stream.empty(),
      onOpenNotifications: () {},
      onOpenProfile: () {},
      unreadNotificationCount: unread,
    );

    testWidgets('the bell is a glass disc with a hairline and the one count '
        'badge, ringed in the canvas colour', (tester) async {
      _useView(tester, const Size(390, 900));
      await tester.pumpWidget(_host(header(unread: 120)));
      final palette = AppPalette.dark;
      final disc = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(HomeHeaderDisc),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = disc.decoration! as BoxDecoration;
      expect(decoration.color, palette.glass);
      expect((decoration.border! as Border).top.color, palette.hairline);
      final badge = tester.widget<YoCountBadge>(find.byType(YoCountBadge));
      expect(badge.count, 120);
      expect(badge.ring, palette.background);
      expect(find.text('99+'), findsOneWidget);
      expect(tester.getSize(find.byType(HomeHeaderDisc)).height, 46);
    });

    testWidgets('at 200 % text the bell count grows to 16.5 px, up and out '
        'of the disc, never over the bell glyph (review D2 / D7)', (
      tester,
    ) async {
      _useView(tester, const Size(390, 900));
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: HomeHeaderDisc(
                icon: Icons.notifications_none_rounded,
                onTap: () {},
                tooltip: 'Powiadomienia',
                badgeCount: 2,
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      final count = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(const ValueKey('home-bell-count')),
          matching: find.text('2'),
        ),
      );
      final fontSize = count.textScaler.scale(count.text.style!.fontSize!);
      expect(fontSize, greaterThanOrEqualTo(16));
      expect(fontSize, closeTo(16.5, .01));
      final badge = tester.getRect(find.byKey(const ValueKey('home-bell-count')));
      expect(badge.height, closeTo(30, .01), reason: 'the floor grows too');
      // The 46 px glass disc itself (its tap region may be a little larger).
      Rect discRect() => tester.getRect(
        find
            .descendant(
              of: find.byType(HomeHeaderDisc),
              matching: find.byType(Container),
            )
            .first,
      );
      final disc = discRect();
      expect(disc.size, const Size(46, 46));
      final glyph = tester.getCenter(
        find.byIcon(Icons.notifications_none_rounded),
      );
      expect(badge.contains(glyph), isFalse);
      // Up by its whole growth; out by at most 4 px of the gap beside it.
      // (The badge is placed inside the disc's 1 px hairline.)
      expect(badge.top, closeTo(disc.top + 1 - 4 - 10, .01));
      expect(badge.right, lessThanOrEqualTo(disc.right + 8 + .01));

      // At 100 % it is the 20 px badge at its old corner.
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: HomeHeaderDisc(
                icon: Icons.notifications_none_rounded,
                onTap: () {},
                tooltip: 'Powiadomienia',
                badgeCount: 2,
              ),
            ),
          ),
        ),
      );
      final small = tester.getRect(find.byKey(const ValueKey('home-bell-count')));
      final smallDisc = discRect();
      expect(small.height, 20);
      expect(small.top, closeTo(smallDisc.top + 1 - 4, .01));
    });

    testWidgets('no badge at zero, and the heading is the w700 screen title', (
      tester,
    ) async {
      _useView(tester, const Size(390, 900));
      await tester.pumpWidget(_host(header()));
      expect(find.byType(YoCountBadge), findsNothing);
      final heading = tester.widget<RichText>(
        find
            .descendant(
              of: find.byType(HomeGreetingHeader),
              matching: find.byType(RichText),
            )
            .at(1),
      );
      final style = heading.text.style!;
      expect(style.fontWeight, FontWeight.w700);
      expect(style.fontSize, 22);
      expect(style.letterSpacing, -0.5);
    });
  });

  group('W2 — LIVE is the one lit surface', () {
    Future<_Channels> pumpLive(
      WidgetTester tester, {
      bool disableAnimations = false,
      bool highContrast = false,
      Brightness brightness = Brightness.dark,
    }) async {
      _useView(tester, const Size(390, 900));
      final repository = _Channels();
      await tester.pumpWidget(
        _host(
          HomeLiveNowSection(
            servers: [_server('a')],
            repository: repository,
            onOpenServer: (_) {},
          ),
          disableAnimations: disableAnimations,
          highContrast: highContrast,
          brightness: brightness,
        ),
      );
      return repository;
    }

    testWidgets('the section arrives over the entrance and the card ignites '
        'once, from dark to rest', (tester) async {
      final repository = await pumpLive(tester);
      expect(tester.getSize(find.byType(HomeLiveNowSection)).height, 0);
      repository.controllers['a']!.add([
        _live('a', 'stage', DateTime(2026, 9, 25, 19, 40)),
      ]);
      await tester.pump();
      await tester.pump();
      // Mid-arrival: the box is still growing and the light is still off.
      await tester.pump(const Duration(milliseconds: 60));
      final early = tester.getSize(find.byType(HomeLiveNowSection)).height;
      expect(early, greaterThan(0));
      expect(_glowOpacity(tester), lessThan(.9));
      await tester.pump(AppMotion.entrance);
      final settled = tester.getSize(find.byType(HomeLiveNowSection)).height;
      expect(settled, greaterThan(early));
      expect(_glowOpacity(tester), 1);
      // Bounded: once the badge dot's own three pulses are over, nothing
      // on the card is still moving (no breathing loop).
      await tester.pump(const Duration(seconds: 5));
      expect(tester.binding.hasScheduledFrame, isFalse);

      // A rebuild with the same session never replays the ignite.
      repository.controllers['a']!.add([
        _live('a', 'stage', DateTime(2026, 9, 25, 19, 40)),
      ]);
      await tester.pump();
      await tester.pump();
      expect(_glowOpacity(tester), 1);
      expect(tester.binding.hasScheduledFrame, isFalse);

      // The same channel going live again (a new startedAt) ignites again.
      repository.controllers['a']!.add([
        _live('a', 'stage', DateTime(2026, 9, 25, 21, 5)),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(_glowOpacity(tester), lessThan(1));
      await tester.pump(AppMotion.entrance);
      expect(_glowOpacity(tester), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a session already seen is at rest when the section is '
        'rebuilt from scratch (scrolled away, tab returned)', (tester) async {
      final since = DateTime(2026, 9, 25, 18);
      final first = await pumpLive(tester);
      first.controllers['a']!.add([_live('a', 'stage', since)]);
      await tester.pump();
      await tester.pump(AppMotion.entrance * 2);
      await tester.pumpWidget(const SizedBox());

      final second = await pumpLive(tester);
      second.controllers['a']!.add([_live('a', 'stage', since)]);
      await tester.pump();
      await tester.pump();
      expect(_glowOpacity(tester), 1);
    });

    testWidgets(
      'Reduce Motion: no size animation, no ignite, at rest at once',
      (tester) async {
        final repository = await pumpLive(tester, disableAnimations: true);
        repository.controllers['a']!.add([
          _live('a', 'stage', DateTime(2026, 9, 25, 17)),
        ]);
        await tester.pump();
        await tester.pump();
        expect(find.byType(AnimatedSize), findsNothing);
        expect(_glowOpacity(tester), 1);
        expect(
          tester.getSize(find.byType(HomeLiveNowSection)).height,
          greaterThan(158),
        );
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a screen reader (accessible navigation) gets the section '
        'without a growing box, even with animations on (review D7)', (
      tester,
    ) async {
      _useView(tester, const Size(390, 900));
      final repository = _Channels();
      await tester.pumpWidget(
        _host(
          HomeLiveNowSection(
            servers: [_server('a')],
            repository: repository,
            onOpenServer: (_) {},
          ),
          accessibleNavigation: true,
        ),
      );
      repository.controllers['a']!.add([
        _live('a', 'stage', DateTime(2026, 9, 25, 17, 30)),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('home-live-now')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('home-live-now')),
          matching: find.byType(AnimatedSize),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard focus swaps the live rim for the 2 px focus ring '
        '(review D6)', (tester) async {
      final repository = await pumpLive(tester);
      repository.controllers['a']!.add([
        _live('a', 'stage', DateTime(2026, 9, 25, 16, 30)),
      ]);
      await tester.pump();
      await tester.pump(AppMotion.entrance * 2);
      Border rim() =>
          (tester
                      .widget<AnimatedContainer>(
                        find.byKey(const ValueKey('home-live-thumbnail')),
                      )
                      .foregroundDecoration!
                  as BoxDecoration)
              .border!
              as Border;
      expect(rim().top.color, AppColors.live.withValues(alpha: .30));

      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump(AppMotion.quick);
      expect(rim().top.color, AppPalette.dark.focus);
      expect(rim().top.width, 2);
    });

    testWidgets('the R4 recipe: live rim, live under-glow, identity-accent '
        'corner light, block radius', (tester) async {
      final repository = await pumpLive(tester);
      repository.controllers['a']!.add([
        _live('a', 'stage', DateTime(2026, 9, 25, 16)),
      ]);
      await tester.pump();
      await tester.pump(AppMotion.entrance * 2);
      final palette = AppPalette.dark;

      final glow = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(const ValueKey('home-live-glow')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final glowDecoration = glow.decoration! as BoxDecoration;
      expect(glowDecoration.boxShadow, AppFinish.liveGlow(palette));

      final corner = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('home-live-corner')),
          matching: find.byType(DecoratedBox),
        ),
      );
      final gradient =
          (corner.decoration as BoxDecoration).gradient! as RadialGradient;
      final accent = ServerIdentity.of(ServerType.podcast).accent;
      expect(gradient.colors.first, accent.withValues(alpha: .28));

      final tile = tester
          .widgetList<AnimatedContainer>(
            find.descendant(
              of: find.byType(HomeLiveChannelCard),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .firstWhere((w) => w.foregroundDecoration != null);
      final rim =
          (tile.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(rim.top.color, AppColors.live.withValues(alpha: .30));
      expect(
        (tile.decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(20),
      );
      expect(
        find.descendant(
          of: find.byType(HomeLiveChannelCard),
          matching: find.byType(YoPressFeedback),
        ),
        findsOneWidget,
      );
    });

    testWidgets('high contrast: no glow, no corner light, a solid live rim', (
      tester,
    ) async {
      final repository = await pumpLive(tester, highContrast: true);
      repository.controllers['a']!.add([
        _live('a', 'stage', DateTime(2026, 9, 25, 15)),
      ]);
      await tester.pump();
      await tester.pump(AppMotion.entrance * 2);
      expect(find.byKey(const ValueKey('home-live-glow')), findsNothing);
      expect(find.byKey(const ValueKey('home-live-corner')), findsNothing);
      final tile = tester
          .widgetList<AnimatedContainer>(
            find.descendant(
              of: find.byType(HomeLiveChannelCard),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .firstWhere((w) => w.foregroundDecoration != null);
      final rim =
          (tile.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(rim.top.color, AppColors.live);
      expect(rim.top.width, 1.5);
    });
  });

  group('"Tu i teraz" and the server blocks', () {
    Widget card(
      AsyncSnapshot<List<Server>> snapshot, {
      bool expanded = false,
    }) => HomeServerConversationCard(
      snapshot: snapshot,
      onOpenServers: () {},
      onRetry: () {},
      onOpenServer: (_) {},
      expanded: expanded,
    );

    testWidgets('the continue card is the lead block: the identity tint, one '
        'button, and a decorative arrow disc', (tester) async {
      _useView(tester, const Size(390, 900));
      await tester.pumpWidget(
        _host(
          card(
            AsyncSnapshot.withData(ConnectionState.active, [
              _server('s', type: ServerType.family),
            ]),
          ),
        ),
      );
      final block = tester.widget<YoCard>(find.byType(YoCard));
      expect(block.tint, ServerIdentity.of(ServerType.family).primary);
      expect(block.radius, BorderRadius.circular(20));
      expect(find.byType(YoCornerTint), findsOneWidget);
      final arrow = find.byKey(const ValueKey('home-server-continue-arrow'));
      expect(tester.getSize(arrow), const Size(36, 36));
      expect(
        find.ancestor(of: arrow, matching: find.byType(ExcludeSemantics)),
        findsWidgets,
      );
      final name = tester.widget<Text>(find.text('Serwer s'));
      expect(name.style!.fontWeight, FontWeight.w700);
      expect(name.style!.fontSize, 20);
    });

    testWidgets('wide: a 216 px floor and a 22 px name', (tester) async {
      _useView(tester, const Size(1000, 900));
      await tester.pumpWidget(
        _host(
          card(
            AsyncSnapshot.withData(ConnectionState.active, [_server('s')]),
            expanded: true,
          ),
          size: const Size(1000, 900),
        ),
      );
      expect(
        tester.getSize(find.byType(YoCard)).height,
        greaterThanOrEqualTo(216),
      );
      expect(tester.widget<Text>(find.text('Serwer s')).style!.fontSize, 22);
    });

    testWidgets('empty: the brand-tinted invitation owns the one lifted '
        '"Stwórz serwer"', (tester) async {
      _useView(tester, const Size(390, 900));
      await tester.pumpWidget(
        _host(
          card(
            const AsyncSnapshot.withData(ConnectionState.active, <Server>[]),
          ),
        ),
      );
      expect(
        tester.widget<YoCard>(find.byType(YoCard)).tint,
        AppColors.primary,
      );
      final create = find.byKey(const ValueKey('home-empty-create-server'));
      expect(tester.widget(create), isA<YoGradientFilledButton>());
      expect(
        find.descendant(of: create, matching: find.byType(FilledButton)),
        findsOneWidget,
      );
    });

    testWidgets('loading is a quiet untinted block with the spinner', (
      tester,
    ) async {
      _useView(tester, const Size(390, 900));
      await tester.pumpWidget(
        _host(card(const AsyncSnapshot<List<Server>>.waiting())),
      );
      final block = tester.widget<YoCard>(find.byType(YoCard));
      expect(block.tint, isNull);
      expect(block.minHeight, 164);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('the server list is one block with hairline dividers at 64', (
      tester,
    ) async {
      _useView(tester, const Size(390, 900));
      await tester.pumpWidget(
        _host(
          HomeServersOverview(
            snapshot: AsyncSnapshot.withData(ConnectionState.active, [
              _server('a'),
              _server('b', type: ServerType.company),
            ]),
            onOpenServers: () {},
          ),
        ),
      );
      final list = tester.widget<YoCard>(
        find.byKey(const ValueKey('home-servers-list')),
      );
      expect(list.padding, EdgeInsets.zero);
      expect(list.tint, isNull);
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.color, AppPalette.dark.hairline);
      expect(divider.indent, 64);
    });
  });

  group('actions and the record card', () {
    testWidgets('"Stwórz serwer" is the gradient CTA with the rail lift; '
        '"Znajomi" is neutral glass', (tester) async {
      _useView(tester, const Size(390, 900));
      await tester.pumpWidget(
        _host(HomeQuickActions(onCreateRoom: () {}, onFriends: () {})),
      );
      final create = find.byKey(const ValueKey('home-quick-create-server'));
      expect(tester.widget(create), isA<YoGradientFilledButton>());
      expect(tester.getSize(create).height, 44);
      final lift = tester.widget<AnimatedContainer>(
        find
            .descendant(of: create, matching: find.byType(AnimatedContainer))
            .first,
      );
      final shadows = (lift.decoration! as ShapeDecoration).shadows!;
      expect(shadows.single.color, AppColors.primary.withValues(alpha: .32));

      final friends = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('home-quick-friends')),
      );
      final palette = AppPalette.dark;
      expect(
        friends.style!.backgroundColor!.resolve(const <WidgetState>{}),
        palette.glass,
      );
      expect(
        friends.style!.side!.resolve(const <WidgetState>{})!.color,
        palette.hairlineControl,
      );
    });

    testWidgets('flat keeps the gradient and drops the lift', (tester) async {
      _useView(tester, const Size(390, 900));
      await tester.pumpWidget(
        _host(
          HomeQuickActions(
            onCreateRoom: () {},
            onFriends: () {},
            createEmphasis: YoActionEmphasis.flat,
          ),
        ),
      );
      final create = find.byKey(const ValueKey('home-quick-create-server'));
      final lift = tester.widget<AnimatedContainer>(
        find
            .descendant(of: create, matching: find.byType(AnimatedContainer))
            .first,
      );
      final shadows = (lift.decoration! as ShapeDecoration).shadows ?? [];
      expect(shadows, isEmpty);
      expect(
        find.descendant(of: create, matching: find.byType(Ink)),
        findsOneWidget,
        reason: 'the gradient stays; only the lift goes',
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets('neutral is the same R7 glass as "Znajomi" '
          '(${brightness.name}; review D2)', (tester) async {
        _useView(tester, const Size(390, 900));
        var creates = 0;
        await tester.pumpWidget(
          _host(
            HomeQuickActions(
              onCreateRoom: () => creates++,
              onFriends: () {},
              createEmphasis: YoActionEmphasis.neutral,
            ),
            brightness: brightness,
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        final palette = brightness == Brightness.dark
            ? AppPalette.dark
            : AppPalette.light;
        final create = find.byKey(const ValueKey('home-quick-create-server'));
        expect(tester.getSize(create).height, 44);
        final button = tester.widget<FilledButton>(
          find.descendant(of: create, matching: find.byType(FilledButton)),
        );
        expect(button.style!.backgroundColor!.resolve({}), palette.glass);
        expect(
          button.style!.side!.resolve({})!.color,
          palette.hairlineControl,
        );
        expect(
          button.style!.foregroundColor!.resolve({}),
          palette.interactiveForeground,
        );
        expect(find.descendant(of: create, matching: find.byType(Ink)), findsNothing);
        final lift = tester.widget<AnimatedContainer>(
          find
              .descendant(of: create, matching: find.byType(AnimatedContainer))
              .first,
        );
        expect((lift.decoration! as ShapeDecoration).shadows ?? [], isEmpty);
        final friends = tester.widget<OutlinedButton>(
          find.byKey(const ValueKey('home-quick-friends')),
        );
        expect(
          friends.style!.backgroundColor!.resolve({}),
          button.style!.backgroundColor!.resolve({}),
        );
        expect(find.byType(Tooltip), findsNWidgets(2));
        await tester.tap(create);
        expect(creates, 1);
      });
    }

    testWidgets('demoting and promoting the create pill keeps its keyboard '
        'focus (same FilledButton element)', (tester) async {
      _useView(tester, const Size(390, 900));
      Widget actions(YoActionEmphasis emphasis) => _host(
        HomeQuickActions(
          onCreateRoom: () {},
          onFriends: () {},
          createEmphasis: emphasis,
        ),
      );
      await tester.pumpWidget(actions(YoActionEmphasis.neutral));
      final create = find.byKey(const ValueKey('home-quick-create-server'));
      final focus = Focus.of(
        tester.element(
          find.descendant(of: create, matching: find.byType(Text)).first,
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.pumpWidget(actions(YoActionEmphasis.lifted));
      expect(focus.hasFocus, isTrue);
      expect(find.descendant(of: create, matching: find.byType(Ink)), findsOneWidget);
    });

    testWidgets('"Masz chwilę?" is an untinted block with the 48 px voice '
        'bead at rest', (tester) async {
      _useView(tester, const Size(390, 900));
      await tester.pumpWidget(
        _host(HomeRecordMomentCard(onCreateMoment: () {})),
      );
      final block = tester.widget<YoCard>(
        find.byKey(const ValueKey('home-record-moment')),
      );
      expect(block.tint, isNull);
      final bead = tester.widget<YoGradientDisc>(find.byType(YoGradientDisc));
      expect(bead.size, 48);
      expect(bead.emphasis, YoDiscEmphasis.rest);
      expect(bead.gloss, isTrue);
    });
  });

  group('people and chats', () {
    testWidgets('a friend is a brand letter-avatar with a touch settle', (
      tester,
    ) async {
      _useView(tester, const Size(390, 900));
      await tester.pumpWidget(
        _host(
          HomeFriendTile(
            displayName: 'Ada',
            status: PeopleStatus.online,
            onOpenProfile: () {},
          ),
        ),
      );
      expect(
        tester.widget<UserAvatar>(find.byType(UserAvatar)).finish,
        UserAvatarFinish.brand,
      );
      final press = tester.widget<YoPressFeedback>(
        find.byType(YoPressFeedback),
      );
      expect(press.scale, YoPressFeedback.tile);
    });

    testWidgets('a phone chat card is the R2 block with the gradient count', (
      tester,
    ) async {
      _useView(tester, const Size(390, 900));
      await tester.pumpWidget(
        _host(
          RecentChats(
            snapshot: AsyncSnapshot.withData(ConnectionState.active, [
              _conversation(1, unread: 3),
              _conversation(2),
            ]),
            currentUserId: 'me',
            onOpenConversation: (_) {},
            onFindFriends: () {},
          ),
        ),
      );
      expect(find.byType(YoCard), findsNWidgets(2));
      final badge = tester.widget<YoCountBadge>(find.byType(YoCountBadge));
      expect(badge.count, 3);
      expect(
        tester.widget<UserAvatar>(find.byType(UserAvatar).first).finish,
        UserAvatarFinish.brand,
      );
    });

    testWidgets('a phone chat card speaks who, the unread count and the last '
        'message as one button (review D1)', (tester) async {
      _useView(tester, const Size(390, 900));
      final handle = tester.ensureSemantics();
      var opened = 0;
      await tester.pumpWidget(
        _host(
          RecentChats(
            snapshot: AsyncSnapshot.withData(ConnectionState.active, [
              _conversation(1, unread: 2),
              _conversation(2),
            ]),
            currentUserId: 'me',
            onOpenConversation: (_) => opened++,
            onFindFriends: () {},
          ),
        ),
      );
      const copy = AppLocalizations(Locale('pl'));
      final unreadCard = tester.getSemantics(find.byType(YoCard).first);
      expect(
        unreadCard.label,
        '${copy.openChatWith('Przyjaciel 1')}. '
        '${copy.unreadMessages(2)}. '
        '${copy.lastMessage('Masz chwilę na rozmowę?')}',
      );
      expect(
        unreadCard,
        isSemantics(isButton: true, hasTapAction: true, isFocusable: true),
      );
      final readCard = tester.getSemantics(find.byType(YoCard).last);
      expect(readCard.label, isNot(contains(copy.unreadMessages(2))));
      expect(readCard.label, startsWith(copy.openChatWith('Przyjaciel 2')));
      // One node per card: the name and preview are not read twice.
      expect(find.bySemanticsLabel('Przyjaciel 1'), findsNothing);
      tester.semantics.tap(find.semantics.byLabel(unreadCard.label));
      expect(opened, 1);
      handle.dispose();
    });

    test('the peek mask starts faint and is opaque at the end and under high '
        'contrast (review D4 / D5)', () {
      final fading = recentChatsPeekMask(
        width: 300,
        peek: 32,
        gap: 12,
        hasMoreAfter: true,
        rtl: false,
        highContrast: false,
      );
      expect(fading.colors.map((c) => c.a).toList(), [1, 1, closeTo(.22, 1e-3), 0]);
      expect(fading.stops, [0, closeTo(1 - 44 / 300, 1e-9), closeTo(1 - 32 / 300, 1e-9), 1]);
      expect(fading.begin, Alignment.centerLeft);
      final rtl = recentChatsPeekMask(
        width: 300,
        peek: 32,
        gap: 12,
        hasMoreAfter: true,
        rtl: true,
        highContrast: false,
      );
      expect(rtl.begin, Alignment.centerRight);
      for (final mask in [
        recentChatsPeekMask(
          width: 300,
          peek: 32,
          gap: 12,
          hasMoreAfter: true,
          rtl: false,
          highContrast: true,
        ),
        recentChatsPeekMask(
          width: 300,
          peek: 32,
          gap: 12,
          hasMoreAfter: false,
          rtl: false,
          highContrast: false,
        ),
      ]) {
        expect(mask.colors.every((c) => c.a == 1), isTrue);
      }
    });

    testWidgets('the desktop rail fades its peek while it can scroll and keeps '
        'its offset when it reaches the end', (tester) async {
      _useView(tester, const Size(360, 400));
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 300,
            child: RecentChats(
              snapshot: AsyncSnapshot.withData(ConnectionState.active, [
                for (var i = 0; i < 3; i++) _conversation(i, unread: i),
              ]),
              currentUserId: 'me',
              onOpenConversation: (_) {},
              onFindFriends: () {},
              style: RecentChatsStyle.desktopBackdrop,
            ),
          ),
          size: const Size(360, 400),
        ),
      );
      final fade = find.byKey(const ValueKey('recent-chats-peek-fade'));
      expect(fade, findsOneWidget);
      final mask = tester.widget<ShaderMask>(fade);
      expect(mask.blendMode, BlendMode.dstIn);
      final badges = tester.widgetList<YoCountBadge>(find.byType(YoCountBadge));
      expect(
        badges.every(
          (badge) => badge.ring == AppColors.white.withValues(alpha: .28),
        ),
        isTrue,
      );

      final scrollable = find.descendant(
        of: fade,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      // The mask stays in the tree (fully opaque now), so the scroll view
      // under it is not re-parented and keeps its offset.
      expect(fade, findsOneWidget);
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        position.maxScrollExtent,
      );
    });
  });

  group('the canvas and the headings', () {
    testWidgets('scenery dissolves into the canvas; Pearl scenery is .05; the '
        'watermark is the real logo', (tester) async {
      expect(YoAtmosphereArt.pearlOpacity, .05);
      expect(YoAtmosphereArt.darkOpacity, .18);
      expect(YoPageBackground.logoAsset, YoBrandMark.markAsset);
      _useView(tester, const Size(390, 844));
      await tester.pumpWidget(
        _host(
          const YoPageBackground(
            section: YoPageSection.home,
            child: SizedBox.expand(),
          ),
          scroll: false,
          size: const Size(390, 844),
        ),
      );
      final dissolve = find.byKey(const ValueKey('yo-atmosphere-dissolve'));
      expect(dissolve, findsOneWidget);
      expect(tester.getSize(dissolve).height, closeTo(844 * .18, .5));
      expect(tester.getBottomLeft(dissolve).dy, 844);
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: dissolve, matching: find.byType(DecoratedBox)),
      );
      final gradient = (box.decoration as BoxDecoration).gradient!;
      expect(gradient.colors.last, AppPalette.dark.background);
      expect(gradient.colors.first.a, 0);
    });

    testWidgets('a section title is the calm w700 role at 17 / 19', (
      tester,
    ) async {
      _useView(tester, const Size(390, 900));
      for (final (scale, size) in const [
        (HomeSectionHeaderScale.compact, 17.0),
        (HomeSectionHeaderScale.expanded, 19.0),
      ]) {
        await tester.pumpWidget(
          _host(HomeSectionHeader(title: 'Tu i teraz', scale: scale)),
        );
        final style = tester.widget<Text>(find.text('Tu i teraz')).style!;
        expect(style.fontWeight, FontWeight.w700);
        expect(style.fontSize, size);
        expect(style.letterSpacing, -0.25);
        expect(style.height, 1.3);
      }
    });
  });

  Future<void> pumpMobileHome(
    WidgetTester tester,
    Size size, {
    bool highContrast = false,
  }) async {
    _useView(tester, size);
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'me', displayName: 'Kamil'),
    );
    await tester.pumpWidget(
      _host(
        MobileHome(
          onOpenDiscover: () {},
          onOpenFriends: () {},
          onOpenNotifications: () {},
          onOpenProfile: () {},
          onCreateMoment: () {},
          onCreateRoom: () {},
          onOpenMoment: (_) {},
          onOpenComments: (_) {},
          onOpenConversation: (_) {},
          onSeeAllChats: () {},
          serverRepository: _StaticServers(
            firestore: db,
            auth: auth,
            servers: [
              _server('a'),
              _server('b', type: ServerType.friends),
            ],
          ),
          friendService: FriendService(firestore: db, auth: auth),
          profileService: ProfileService(firestore: db, auth: auth),
          feedService: HomeFeedService(
            firestore: db,
            auth: auth,
            voiceMomentReadService: VoiceMomentReadService(
              feedInvoker: fakeVoiceMomentFeedInvoker(firestore: db),
            ),
          ),
          messageService: MessageService(firestore: db, auth: auth),
          currentUserId: 'me',
        ),
        scroll: false,
        size: size,
        highContrast: highContrast,
      ),
    );
  }

  testWidgets('high contrast: no seam fade over the page at all (review D4)', (
    tester,
  ) async {
    const size = Size(390, 700);
    await pumpMobileHome(tester, size, highContrast: true);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    final list = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('mobile-home-server-first')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(list.position.extentAfter, greaterThan(.5));
    expect(find.byKey(const ValueKey('mobile-home-seam-fade')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the phone page fades into the canvas above the dock only '
      'while there is more below', (tester) async {
    const size = Size(390, 700);
    await pumpMobileHome(tester, size);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    final fade = find.byKey(const ValueKey('mobile-home-seam-fade'));
    expect(fade, findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);
    expect(tester.getBottomLeft(fade).dy, size.height);
    expect(tester.getSize(fade).height, 24);
    // It eases in (review D6): faint over the band's upper half.
    final band = tester.widget<DecoratedBox>(
      find.descendant(of: fade, matching: find.byType(DecoratedBox)),
    );
    final ease = (band.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(ease.stops, const [0, .55, 1]);
    expect(ease.colors.map((c) => c.a).toList(), [0, closeTo(.18, 1e-3), 1]);
    expect(
      find.ancestor(of: fade, matching: find.byType(IgnorePointer)),
      findsWidgets,
    );

    final list = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('mobile-home-server-first')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    // A lazily built list learns its true extent as it goes: keep jumping
    // to the end until the end stops moving.
    for (var i = 0; i < 6; i++) {
      list.position.jumpTo(list.position.maxScrollExtent);
      for (var j = 0; j < 3; j++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }
    expect(list.position.extentAfter, lessThan(.5));
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _StaticServers extends ServerService {
  _StaticServers({
    required super.firestore,
    required super.auth,
    required this.servers,
  });

  final List<Server> servers;

  @override
  Stream<List<Server>> watchMyServers() => Stream.value(servers);
}
