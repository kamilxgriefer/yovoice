// Premium Pages package C1: the shell side of the Treści destination.
//
// Slot 14, the mobile order and history identities, the desktop rail row,
// MoreDestinationHost's six-tab dock and rail, the fail-closed availability
// gate, and the strict `?page=` deep-link parser. The five-tab behaviour with
// Pages off stays pinned by main_shell_servers_slot_test.dart,
// mobile_rooms_navigation_test.dart and server_surface_cutover_test.dart.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/timezone_world_map_card.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/onboarding/presentation/guided_onboarding_tour.dart';
import 'package:yovoice/features/pages/data/page_links.dart';
import 'package:yovoice/features/pages/data/services/pages_availability.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/pages_local_store.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/screens/content_screen.dart';

class _MemoryStore implements PagesAvailabilityStore {
  final values = <String, bool>{};
  int writes = 0;

  @override
  Future<bool?> read(String userId) async => values[userId];

  @override
  Future<void> write(String userId, {required bool enabled}) async {
    writes++;
    values[userId] = enabled;
  }
}

Widget _localized(Widget home, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

void main() {
  group('content slot 14', () {
    test('is appended after Servers and is not a More destination', () {
      expect(MainShell.contentSlot, 14);
      expect(
        MainShell.desktopSlots.containsKey(MainShell.contentSlot),
        isFalse,
        reason: 'Treści is not listed in the More sheet or popover',
      );
      expect(
        MainShell.desktopSlots.keys.toList()..sort(),
        List.generate(11, (index) => index + 3),
        reason: 'no existing slot renumbers',
      );
    });

    test('mobile keeps slot 14 only while Pages are enabled', () {
      expect(MainShell.mobileIndexFor(14), 0);
      expect(MainShell.mobileIndexFor(14, contentEnabled: true), 14);
      for (final root in [0, 1, 2, 3, 5, 13]) {
        expect(MainShell.mobileIndexFor(root, contentEnabled: true), root);
      }
      for (final desktopOnly in [4, 6, 7, 8, 9, 10, 11, 12]) {
        expect(MainShell.mobileIndexFor(desktopOnly, contentEnabled: true), 0);
      }
    });

    test('the six-tab visual order is Start · Serwery · Czaty · Treści · '
        'Momenty · Więcej', () {
      expect(
        [0, 13, 1, 14, 5].map(
          (index) =>
              MainShell.mobileNavigationOrder(index, contentEnabled: true),
        ),
        [0, 1, 2, 3, 4],
      );
      for (final hidden in [2, 3, 4, 6, 12]) {
        expect(
          MainShell.mobileNavigationOrder(hidden, contentEnabled: true),
          5,
          reason: 'slot $hidden has no dock cell and sorts with More',
        );
      }
      expect(
        [0, 13, 1, 5].map(MainShell.mobileNavigationOrder),
        [0, 1, 2, 3],
        reason: 'Pages off: the five-tab order is unchanged',
      );
    });

    test('the rail lights Treści for slot 14', () {
      expect(
        MainShell.desktopNavItemForSlot(MainShell.contentSlot),
        DesktopNavItem.content,
      );
      expect(MainShell.desktopNavItemForSlot(5), DesktopNavItem.moments);
      expect(MainShell.desktopNavItemForSlot(12), DesktopNavItem.more);
    });

    test('tour anchors move to {2, 4, 5} with Treści', () {
      expect(MainShell.mobileTourDestinationSlots(contentEnabled: false), {
        GuidedOnboardingTarget.chats: 2,
        GuidedOnboardingTarget.moments: 3,
        GuidedOnboardingTarget.more: 4,
      });
      expect(MainShell.mobileTourDestinationSlots(contentEnabled: true), {
        GuidedOnboardingTarget.chats: 2,
        GuidedOnboardingTarget.moments: 4,
        GuidedOnboardingTarget.more: 5,
      });
    });

    test('Treści never appears in the More sheet destinations', () {
      expect(
        MoreDestination.values.map((destination) => destination.name),
        isNot(contains('content')),
      );
    });
  });

  group('MoreDestinationHost with Pages', () {
    Future<void> pumpHost(
      WidgetTester tester, {
      required ValueChanged<int> onDestinationSelected,
      int selectedIndex = MainShell.contentSlot,
      bool contentEnabled = true,
      ValueNotifier<bool>? listenable,
      Size size = const Size(390, 844),
      ValueChanged<DesktopNavItem>? onDesktopNavSelected,
      DesktopNavItem? activeDesktopItem,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: Text('SHELL')),
        ),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => MoreDestinationHost(
            body: const Text('DESTINATION'),
            selectedIndex: selectedIndex,
            unreadConversationCount: 0,
            onDestinationSelected: onDestinationSelected,
            onVoicePressed: () {},
            onMorePressed: () {},
            contentEnabled: contentEnabled,
            contentEnabledListenable: listenable,
            activeDesktopItem: activeDesktopItem,
            onDesktopNavSelected: onDesktopNavSelected,
            onCreateRoom: () {},
            onCreateMoment: () {},
            onOpenProfile: () {},
            onOpenProfileSettings: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a hosted Page shows the six-tab dock with Treści selected', (
      tester,
    ) async {
      int? selected;
      await pumpHost(tester, onDestinationSelected: (i) => selected = i);
      for (var slot = 0; slot < 6; slot++) {
        expect(find.byKey(ValueKey('yo-destination-$slot')), findsOneWidget);
      }
      final content = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('yo-destination-3')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(content.properties.label, 'Content');
      expect(content.properties.selected, isTrue);

      // Re-tapping Treści pops the host and lands on the shell's slot 14.
      await tester.tap(find.byKey(const ValueKey('yo-destination-3')));
      await tester.pumpAndSettle();
      expect(selected, MainShell.contentSlot);
      expect(find.text('SHELL'), findsOneWidget);
    });

    testWidgets('Momenty moves to slot 4 and still reaches slot 5', (
      tester,
    ) async {
      int? selected;
      await pumpHost(
        tester,
        selectedIndex: 0,
        onDestinationSelected: (i) => selected = i,
      );
      await tester.tap(find.byKey(const ValueKey('yo-destination-4')));
      await tester.pumpAndSettle();
      expect(selected, 5);
    });

    testWidgets('the kill switch drops the hosted dock back to five tabs', (
      tester,
    ) async {
      final enabled = ValueNotifier<bool>(true);
      addTearDown(enabled.dispose);
      await pumpHost(
        tester,
        selectedIndex: 0,
        listenable: enabled,
        onDestinationSelected: (_) {},
      );
      expect(find.byKey(const ValueKey('yo-destination-5')), findsOneWidget);
      enabled.value = false;
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('yo-destination-5')), findsNothing);
      expect(find.byKey(const ValueKey('yo-destination-4')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Pages off: the hosted dock is the unchanged five-tab dock', (
      tester,
    ) async {
      await pumpHost(
        tester,
        selectedIndex: 0,
        contentEnabled: false,
        onDestinationSelected: (_) {},
      );
      expect(find.byKey(const ValueKey('yo-destination-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('yo-destination-5')), findsNothing);
      expect(find.bySemanticsLabel('Content'), findsNothing);
    });

    testWidgets('desktop: the hosted rail shows and lights the Treści row', (
      tester,
    ) async {
      DesktopNavItem? tapped;
      await pumpHost(
        tester,
        size: const Size(1440, 900),
        activeDesktopItem: DesktopNavItem.content,
        onDestinationSelected: (_) {},
        onDesktopNavSelected: (item) => tapped = item,
      );
      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(find.byKey(const ValueKey('yo-destination-0')), findsNothing);
      expect(find.text('Content'), findsOneWidget);
      await tester.tap(find.text('Content'));
      await tester.pumpAndSettle();
      expect(tapped, DesktopNavItem.content);
    });
  });

  group('desktop rail Treści row', () {
    DesktopSidebar rail({bool showContent = true}) => DesktopSidebar(
      active: DesktopNavItem.content,
      showContent: showContent,
      unreadConversationCount: 0,
      unreadNotificationCount: 0,
      onSelect: (_) {},
      onCreateRoom: () {},
      onCreateMoment: () {},
      onOpenProfile: () {},
      onOpenProfileSettings: () {},
    );

    testWidgets('sits between Czaty and Momenty and is hidden with Pages off', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _localized(Scaffold(body: rail()), locale: const Locale('pl')),
      );
      await tester.pump();
      final chats = tester.getCenter(find.text('Czaty')).dy;
      final content = tester.getCenter(find.text('Treści')).dy;
      final moments = tester.getCenter(find.text('Momenty')).dy;
      expect(content, greaterThan(chats));
      expect(content, lessThan(moments));
      expect(content - chats, closeTo(52, .01), reason: 'row pitch 52');
      expect(
        find.descendant(
          of: find.byType(DesktopSidebar),
          matching: find.byIcon(Icons.article),
        ),
        findsOneWidget,
        reason: 'the selected row uses the filled glyph',
      );

      await tester.pumpWidget(
        _localized(
          Scaffold(body: rail(showContent: false)),
          locale: const Locale('pl'),
        ),
      );
      await tester.pump();
      expect(find.text('Treści'), findsNothing);
    });

    for (final (height, scale) in const [
      (620.0, 1.0),
      (620.0, 1.49),
      (620.0, 2.0),
      (680.0, 1.0),
      (680.0, 2.0),
      (700.0, 1.0),
      (720.0, 1.0),
      (900.0, 1.0),
    ]) {
      testWidgets('every rail action stays in bounds with the sixth row at '
          '${height}px, ${scale}x', (tester) async {
        tester.view.physicalSize = Size(1440, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _localized(
            Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: Size(1440, height),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Row(
                  children: [
                    rail(),
                    const Expanded(child: SizedBox.expand()),
                  ],
                ),
              ),
            ),
            locale: const Locale('pl'),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          find.descendant(
            of: find.byType(DesktopSidebar),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
        );
        final railRect = tester.getRect(find.byType(DesktopSidebar));
        for (final target in [
          find.byTooltip('Powiadomienia'),
          find.text('Start'),
          find.text('Serwery'),
          find.text('Czaty'),
          find.text('Treści'),
          find.text('Momenty'),
          find.text('Stwórz serwer'),
          // A labelled button on a tall rail, an icon with a tooltip on a
          // short one.
          find.byTooltip('Nagraj Voice Moment').evaluate().isEmpty
              ? find.text('Nagraj Voice Moment')
              : find.byTooltip('Nagraj Voice Moment'),
          find.text('Więcej'),
          find.byTooltip('Ustawienia profilu'),
        ]) {
          expect(target, findsOneWidget);
          expect(
            railRect.contains(tester.getCenter(target)),
            isTrue,
            reason: '$target must stay inside the rail',
          );
        }
        if (scale > 1) {
          expect(find.byType(TimezoneWorldMapCard), findsNothing);
        }
        expect(
          find.text('UTWÓRZ'),
          height < DesktopSidebar.compactCreateActionsBelow || scale > 1
              ? findsNothing
              : findsOneWidget,
          reason: 'section labels yield to the sixth row on a short rail',
        );
      });
    }
  });

  group('Treści destination chrome', () {
    // The wall's own states are covered in pages_wall_test.dart; here only
    // the destination's chrome matters, over an empty directory (E3).
    ContentScreen content({required bool root}) => ContentScreen(
      isRootTab: root,
      service: PagesService(
        invoker: (name, payload) async => name == PagesService.feedCallable
            ? {
                'schemaVersion': 1,
                'posts': <Object>[],
                'nextCursor': null,
                'hasMore': false,
                'suggestions': <Object>[],
              }
            : {
                'schemaVersion': 1,
                'pages': <Object>[],
                'nextCursor': null,
                'hasMore': false,
              },
      ),
      accessStream: () => Stream.value(
        const PageAccessState(
          resolved: true,
          hasVipGrant: false,
          ownPage: null,
        ),
      ),
      localStore: MemoryPagesLocalStore(),
      userId: 'me',
    );

    for (final width in [320.0, 768.0, 1280.0]) {
      testWidgets(
        'root tab draws no app bar; pushed route has Back at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            _localized(
              Scaffold(body: content(root: true)),
              locale: const Locale('pl'),
            ),
          );
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.byType(AppBar), findsNothing);
          // Phone and tablet: the wall's own header. Desktop: the panel's.
          expect(
            find.byKey(
              ValueKey(
                width >= MainShell.desktopBreakpoint
                    ? 'content-panel-title'
                    : 'content-screen-title',
              ),
            ),
            findsOneWidget,
          );
          expect(find.text('Treści'), findsOneWidget);
          expect(find.text('Wkrótce'), findsNothing);
          expect(find.text('Nie ma jeszcze żadnych stron'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(
            _localized(content(root: false), locale: const Locale('pl')),
          );
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.byType(AppBar), findsOneWidget);
          expect(
            find.byKey(const ValueKey('content-screen-title')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('content-panel-title')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('200% text at 320 px does not overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _localized(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(body: content(root: true)),
          ),
          locale: const Locale('pl'),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('Page deep links (spec §4.7)', () {
    const uid = 'Ab3_page-owner';
    final post = 'pp_${'a' * 40}';

    test('builds and parses a Page and a post', () {
      final page = buildPageLink(uid);
      expect(page.toString(), 'https://app.yovoice.app/?page=$uid');
      expect(parsePageLink(page), const PageLinkTarget(pageId: uid));
      final withPost = buildPageLink(uid, postId: post);
      expect(
        withPost.toString(),
        'https://app.yovoice.app/?page=$uid&post=$post',
      );
      expect(
        parsePageLink(withPost),
        PageLinkTarget(pageId: uid, postId: post),
      );
      // Links built to the spec's apex shape keep opening.
      for (final host in ['yovoice.app', 'www.yovoice.app']) {
        expect(
          parsePageLink(Uri.parse('https://$host/?page=$uid')),
          const PageLinkTarget(pageId: uid),
        );
      }
    });

    test('rejects malformed ids when building', () {
      expect(() => buildPageLink('../x'), throwsArgumentError);
      expect(() => buildPageLink(uid, postId: 'pp_short'), throwsArgumentError);
    });

    test('fails closed for altered contracts', () {
      for (final raw in <String>[
        'http://yovoice.app/?page=$uid',
        'https://evil.example/?page=$uid',
        'https://yovoice.app.evil.example/?page=$uid',
        'https://yovoice.app/p?page=$uid',
        'https://yovoice.app/?page=$uid#x',
        'https://yovoice.app/?page=$uid&page=other',
        'https://yovoice.app/?page=$uid&server=srv',
        'https://yovoice.app/?page=$uid&room=r1',
        'https://user@yovoice.app/?page=$uid',
        'https://yovoice.app:444/?page=$uid',
        'https://yovoice.app/?page=../private',
        'https://yovoice.app/?page=',
        'https://yovoice.app/?post=$post',
        'https://yovoice.app/?page=$uid&post=pp_${'A' * 40}',
        'https://yovoice.app/?page=$uid&post=pc_${'a' * 40}',
        'https://yovoice.app/?page=$uid&post=$post&post=$post',
        'https://yovoice.app/?page=${'a' * 129}',
      ]) {
        expect(parsePageLink(Uri.parse(raw)), isNull, reason: raw);
      }
    });

    test('a Page link is never a Server link and vice versa', () {
      expect(
        parseInitialServerWorkspaceLink(
          Uri.parse('https://app.yovoice.app/?page=$uid'),
        ),
        isNull,
      );
      expect(
        parsePageLink(Uri.parse('https://app.yovoice.app/?server=srv_1')),
        isNull,
      );
      expect(
        carriesPageLinkParameters(
          Uri.parse('https://yovoice.app/?page=bad/../&room=r1'),
        ),
        isTrue,
        reason: 'the shell refuses the room fallback for an altered Page link',
      );
      expect(
        carriesPageLinkParameters(Uri.parse('https://yovoice.app/?room=r1')),
        isFalse,
      );
    });
  });

  group('PagesAvailability (fail closed)', () {
    FirebaseFunctionsException refusal(String code, [Object? details]) =>
        FirebaseFunctionsException(
          code: code,
          message: 'refused',
          details: details,
        );

    test('probes findPagesV1 following mode with the exact request', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final availability = PagesAvailability(
        store: _MemoryStore(),
        invoker: (name, payload) async {
          calls.add((name, payload));
          return <String, Object?>{
            'schemaVersion': 1,
            'pages': <Object?>[],
            'nextCursor': null,
            'hasMore': false,
          };
        },
      );
      expect(availability.enabled.value, isFalse);
      expect(await availability.refresh('u1'), isTrue);
      expect(availability.enabled.value, isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.$1, 'findPagesV1');
      expect(calls.single.$2, {
        'mode': 'following',
        'query': null,
        'cursor': null,
      });
    });

    test('maps refusals: pagesNotEnabled and not-found hide, others keep', () {
      expect(
        PagesAvailability.outcomeFor(
          refusal('failed-precondition', {'reason': 'pagesNotEnabled'}),
        ),
        PagesProbeOutcome.disabled,
      );
      expect(
        PagesAvailability.outcomeFor(refusal('not-found')),
        PagesProbeOutcome.disabled,
      );
      expect(
        PagesAvailability.outcomeFor(refusal('unauthenticated')),
        PagesProbeOutcome.disabled,
      );
      for (final code in [
        'unavailable',
        'resource-exhausted',
        'internal',
        'deadline-exceeded',
      ]) {
        expect(
          PagesAvailability.outcomeFor(refusal(code)),
          PagesProbeOutcome.unknown,
          reason: code,
        );
      }
      expect(
        PagesAvailability.outcomeFor(
          refusal('failed-precondition', {'reason': 'pageAccessRequired'}),
        ),
        PagesProbeOutcome.unknown,
      );
    });

    test(
      'a transient failure keeps the cached answer; no cache stays off',
      () async {
        final store = _MemoryStore()..values['u1'] = true;
        final availability = PagesAvailability(
          store: store,
          invoker: (_, _) async => throw refusal('unavailable'),
        );
        expect(await availability.refresh('u1'), isTrue);
        expect(availability.enabled.value, isTrue);

        final fresh = PagesAvailability(
          store: _MemoryStore(),
          invoker: (_, _) async => throw StateError('offline'),
        );
        expect(await fresh.refresh('u2'), isFalse);
      },
    );

    test('an inconclusive probe backs off before asking again', () async {
      var now = DateTime.utc(2026, 9, 28, 12);
      var calls = 0;
      final availability = PagesAvailability(
        store: _MemoryStore(),
        clock: () => now,
        invoker: (_, _) async {
          calls++;
          throw StateError('offline');
        },
      );
      await availability.refresh('u1');
      expect(calls, 1);
      // Resumes and tab focus inside the backoff do not call again.
      now = now.add(const Duration(minutes: 2));
      await availability.refresh('u1');
      expect(calls, 1);
      now = now.add(PagesAvailability.unknownBackoff);
      await availability.refresh('u1');
      expect(calls, 2);
      // An explicit re-check still goes through.
      await availability.refresh('u1', force: true);
      expect(calls, 3);
    });

    test(
      'the kill switch hides and persists; a new account starts hidden',
      () async {
        final store = _MemoryStore();
        var enabled = true;
        final availability = PagesAvailability(
          store: store,
          invoker: (_, _) async {
            if (!enabled) {
              throw refusal('failed-precondition', {
                'reason': 'pagesNotEnabled',
              });
            }
            return const <String, Object?>{};
          },
        );
        expect(await availability.refresh('u1'), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(store.values['u1'], isTrue);

        enabled = false;
        expect(await availability.refresh('u1', force: true), isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(store.values['u1'], isFalse);

        enabled = true;
        await availability.refresh('u1', force: true);
        expect(availability.enabled.value, isTrue);
        availability.reportNotEnabled();
        expect(availability.enabled.value, isFalse);

        enabled = true;
        await availability.refresh('u1', force: true);
        expect(availability.enabled.value, isTrue);
        // Switching accounts drops the answer before anything is awaited.
        final pending = availability.refresh('u2');
        expect(availability.enabled.value, isFalse);
        await pending;
        availability.reset();
        expect(availability.enabled.value, isFalse);
        expect(availability.userId, isEmpty);
      },
    );

    test('a settled answer is re-probed at most hourly', () async {
      var now = DateTime(2026, 9, 28, 12);
      var probes = 0;
      final availability = PagesAvailability(
        store: _MemoryStore(),
        clock: () => now,
        invoker: (_, _) async {
          probes++;
          return const <String, Object?>{};
        },
      );
      await availability.refresh('u1');
      await availability.refresh('u1');
      expect(probes, 1);
      now = now.add(const Duration(minutes: 61));
      await availability.refresh('u1');
      expect(probes, 2);
    });

    test('an empty account id is always disabled and never probes', () async {
      var probes = 0;
      final availability = PagesAvailability(
        store: _MemoryStore(),
        invoker: (_, _) async {
          probes++;
          return const <String, Object?>{};
        },
      );
      expect(await availability.refresh(''), isFalse);
      expect(probes, 0);
    });
  });
}
