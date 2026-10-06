// "Zacznij tutaj" on the real Start (firstSteps A, 2026-10-03): where the
// card sits on a phone, a tablet and the desktop Home, that its steps lead to
// the shell's real destinations, and that Start is exactly what it was when
// the card has nothing true to show.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/first_steps.dart';
import 'package:yovoice/features/home/data/first_steps_store.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_greeting_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_people_strip.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';

import 'home_watermark_visual_capture.dart';
import 'support/first_steps_fixtures.dart';

Widget _app(Widget home, {double textScale = 1}) => MaterialApp(
  theme: AppTheme.darkTheme,
  locale: const Locale('pl'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: true,
    ),
    child: child!,
  ),
  home: Scaffold(body: home),
);

Finder _step(FirstStep step) =>
    find.byKey(ValueKey('home-first-step-${step.name}'));

final Finder _card = find.byKey(const ValueKey('home-first-steps'));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void _view(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadHomeWatermarkFonts);
  setUp(() {
    ProfileService.resetCurrentProfileCache();
    FriendService.clearSharedReadCaches();
    ProfileMediaService.clearAllMediaAccessCaches();
  });
  tearDown(ProfileService.resetCurrentProfileCache);

  group('phone', () {
    testWidgets('the card sits under the greeting, above the friends row', (
      tester,
    ) async {
      _view(tester, const Size(390, 844));
      final world = FirstStepsWorld();
      await tester.runAsync(world.seed);
      await tester.pumpWidget(_app(world.mobileHome()));
      await _settle(tester);

      expect(_card, findsOneWidget);
      expect(find.text('Zacznij tutaj'), findsOneWidget);
      expect(find.text('1 z 5'), findsOneWidget);

      final greeting = tester.getRect(find.byType(HomeGreetingHeader));
      final card = tester.getRect(_card);
      final people = tester.getRect(find.byType(HomePeopleStrip));
      expect(card.top, greeting.bottom + AppRhythm.item);
      expect(people.top, greaterThanOrEqualTo(card.bottom));
      // Inset to the page margin on both sides, like every Start block.
      expect(card.left, AppRhythm.title);
      expect(card.right, 390 - AppRhythm.title);
      expect(tester.takeException(), isNull);
    });

    testWidgets('each open step leads to the shell destination', (
      tester,
    ) async {
      _view(tester, const Size(390, 844));
      final taps = FirstStepsTaps();
      final world = FirstStepsWorld(photo: false);
      await tester.runAsync(world.seed);
      await tester.pumpWidget(_app(world.mobileHome(taps: taps)));
      await _settle(tester);
      expect(find.text('0 z 5'), findsOneWidget);

      for (final step in FirstStep.values) {
        await tester.ensureVisible(_step(step));
        await tester.pump();
        await tester.tap(_step(step));
        await tester.pump();
      }
      expect(taps.log, [
        'edit-profile',
        'friends',
        'servers',
        'record',
        'content',
      ]);
      expect(taps.photoProfile?.uid, firstStepsUid);
    });

    testWidgets('without an editor callback the photo step opens the profile', (
      tester,
    ) async {
      _view(tester, const Size(390, 844));
      final taps = FirstStepsTaps();
      final world = FirstStepsWorld(photo: false);
      await tester.runAsync(world.seed);
      await tester.pumpWidget(
        _app(world.mobileHome(taps: taps, withPhotoDestination: false)),
      );
      await _settle(tester);
      await tester.tap(_step(FirstStep.photo));
      expect(taps.log, ['profile']);
    });

    testWidgets('Treści off, or unknown: four steps, or no card yet', (
      tester,
    ) async {
      _view(tester, const Size(390, 844));
      final off = FirstStepsWorld();
      await tester.runAsync(off.seed);
      await tester.pumpWidget(_app(off.mobileHome(contentEnabled: false)));
      await _settle(tester);
      expect(find.text('1 z 4'), findsOneWidget);
      expect(_step(FirstStep.follow), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      ProfileService.resetCurrentProfileCache();
      ProfileMediaService.clearAllMediaAccessCaches();
      final unknown = FirstStepsWorld();
      await tester.runAsync(unknown.seed);
      await tester.pumpWidget(_app(unknown.mobileHome(contentEnabled: null)));
      await _settle(tester);
      expect(_card, findsNothing);
      expect((unknown.store as MemoryFirstStepsStore).writes, isEmpty);
    });

    testWidgets(
      'while the shell holds the card for the guided tour, Start does '
      'not move; released, the card arrives',
      (tester) async {
        // On phones the tour spotlights Start's create pill. The shell passes
        // "unknown" until the tour has had its turn, so the card cannot push
        // that pill off the screen under the tour.
        _view(tester, const Size(390, 844));
        final pill = find.byKey(const ValueKey('home-quick-create-server'));

        final reference = FirstStepsWorld(
          store: MemoryFirstStepsStore(FirstStepsOutcome.dismissed),
        );
        await tester.runAsync(reference.seed);
        await tester.pumpWidget(_app(reference.mobileHome()));
        await _settle(tester);
        final withoutCard = tester.getRect(pill);
        expect(
          withoutCard.bottom,
          lessThan(844),
          reason: 'the pill is on screen',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        ProfileService.resetCurrentProfileCache();
        FriendService.clearSharedReadCaches();
        ProfileMediaService.clearAllMediaAccessCaches();
        final world = FirstStepsWorld();
        await tester.runAsync(world.seed);
        await tester.pumpWidget(_app(world.mobileHome(contentEnabled: null)));
        await _settle(tester);
        expect(_card, findsNothing);
        expect(tester.getRect(pill), withoutCard);
        expect((world.store as MemoryFirstStepsStore).writes, isEmpty);

        // The tour is over: the same Start, now told what it may show.
        await tester.pumpWidget(_app(world.mobileHome()));
        await _settle(tester);
        expect(_card, findsOneWidget);
        expect(find.text('1 z 5'), findsOneWidget);
        expect((world.store as MemoryFirstStepsStore).writes, [
          FirstStepsOutcome.started,
        ]);
        // This is the shift the hold exists for: the pill is no longer where
        // the tour would have found it.
        expect(
          pill.evaluate().isEmpty ||
              tester.getRect(pill).top >= withoutCard.top + 300,
          isTrue,
        );
      },
    );

    testWidgets('real state: a friend, a server and a Voice leave 4 z 5', (
      tester,
    ) async {
      _view(tester, const Size(390, 844));
      final world = FirstStepsWorld(
        friends: [firstStepsFriend()],
        servers: [firstStepsServer()],
        moments: 1,
      );
      await tester.runAsync(world.seed);
      await tester.pumpWidget(_app(world.mobileHome()));
      await _settle(tester);
      expect(find.text('4 z 5'), findsOneWidget);
      expect(find.text('Ich nowości zobaczysz w Treściach'), findsOneWidget);
    });

    testWidgets('a hidden card leaves Start exactly as it was', (tester) async {
      _view(tester, const Size(390, 844));
      // Closed earlier on this device.
      final world = FirstStepsWorld(
        store: MemoryFirstStepsStore(FirstStepsOutcome.dismissed),
      );
      await tester.runAsync(world.seed);
      await tester.pumpWidget(_app(world.mobileHome()));
      await _settle(tester);
      expect(_card, findsNothing);
      final greeting = tester.getRect(find.byType(HomeGreetingHeader));
      final people = tester.getRect(find.byType(HomePeopleStrip));
      expect(
        people.top,
        greeting.bottom,
        reason: 'the friends row follows the greeting with no card box',
      );
    });

    testWidgets('closing the card returns Start to its own rhythm', (
      tester,
    ) async {
      _view(tester, const Size(390, 844));
      final world = FirstStepsWorld();
      await tester.runAsync(world.seed);
      await tester.pumpWidget(_app(world.mobileHome()));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('home-first-steps-close')));
      await _settle(tester);
      expect(_card, findsNothing);
      expect(
        tester.getRect(find.byType(HomePeopleStrip)).top,
        tester.getRect(find.byType(HomeGreetingHeader)).bottom,
      );
      expect(
        (world.store as MemoryFirstStepsStore).values[firstStepsUid],
        FirstStepsOutcome.dismissed,
      );
    });

    testWidgets('no overflow at 320 px and 200 % text', (tester) async {
      _view(tester, const Size(320, 690));
      final world = FirstStepsWorld();
      await tester.runAsync(world.seed);
      await tester.pumpWidget(_app(world.mobileHome(), textScale: 2));
      await _settle(tester);
      expect(_card, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('tablet 768: the rows form two columns under the greeting', (
    tester,
  ) async {
    _view(tester, const Size(768, 1024));
    final world = FirstStepsWorld();
    await tester.runAsync(world.seed);
    await tester.pumpWidget(_app(world.mobileHome()));
    await _settle(tester);

    final card = tester.getRect(_card);
    expect(card.left, AppRhythm.section);
    expect(card.right, 768 - AppRhythm.section);
    final photo = tester.getTopLeft(_step(FirstStep.photo));
    final voice = tester.getTopLeft(_step(FirstStep.voice));
    final follow = tester.getTopLeft(_step(FirstStep.follow));
    expect(voice.dy, photo.dy);
    expect(voice.dx, greaterThan(photo.dx + 300));
    expect(follow.dx, voice.dx);
    expect(tester.takeException(), isNull);
  });

  group('desktop', () {
    testWidgets('1440: the card heads the secondary column', (tester) async {
      // The shell's content slot at a 1440 window (rail 264).
      _view(tester, const Size(1176, 900));
      final taps = FirstStepsTaps();
      final world = FirstStepsWorld();
      await tester.runAsync(world.seed);
      await tester.pumpWidget(_app(world.desktopHome(taps: taps)));
      await _settle(tester);

      final column = find.byKey(const ValueKey('home-secondary-column'));
      expect(column, findsOneWidget);
      expect(find.descendant(of: column, matching: _card), findsOneWidget);
      final card = tester.getRect(_card);
      final columnRect = tester.getRect(column);
      expect(card.left, columnRect.left);
      expect(card.right, columnRect.right);
      final record = tester.getRect(
        find.byKey(const ValueKey('home-record-moment')),
      );
      expect(record.top, card.bottom + AppRhythm.item);
      // One column of rows in the 300 px column.
      expect(
        tester.getTopLeft(_step(FirstStep.voice)).dx,
        tester.getTopLeft(_step(FirstStep.photo)).dx,
      );

      await tester.tap(_step(FirstStep.friend));
      await tester.tap(_step(FirstStep.server));
      await tester.tap(_step(FirstStep.voice));
      await tester.tap(_step(FirstStep.follow));
      expect(taps.log, ['friends', 'servers', 'record', 'content']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow slot (one column): under the greeting, two columns '
        'of rows', (tester) async {
      _view(tester, const Size(900, 900));
      final world = FirstStepsWorld();
      await tester.runAsync(world.seed);
      await tester.pumpWidget(_app(world.desktopHome()));
      await _settle(tester);

      expect(find.byKey(const ValueKey('home-secondary-column')), findsNothing);
      final card = tester.getRect(_card);
      final greeting = tester.getRect(
        find.byKey(const ValueKey('home-greeting-card')),
      );
      final people = tester.getRect(find.byType(HomePeopleStrip));
      expect(card.top, greeting.bottom);
      expect(people.top, greaterThanOrEqualTo(card.bottom));
      expect(
        tester.getTopLeft(_step(FirstStep.voice)).dy,
        tester.getTopLeft(_step(FirstStep.photo)).dy,
      );
    });

    testWidgets('the host keeps its state across the column switch', (
      tester,
    ) async {
      _view(tester, const Size(1176, 900));
      final world = FirstStepsWorld();
      await tester.runAsync(world.seed);
      final home = world.desktopHome();
      await tester.pumpWidget(_app(home));
      await _settle(tester);
      expect(_card, findsOneWidget);

      // The window narrows below the two-column threshold: the same card,
      // immediately, with nothing re-read.
      tester.view.physicalSize = const Size(900, 900);
      await tester.pump();
      expect(_card, findsOneWidget);
      expect((world.store as MemoryFirstStepsStore).writes, [
        FirstStepsOutcome.started,
      ]);
    });

    testWidgets('a hidden card leaves the secondary column as it was', (
      tester,
    ) async {
      _view(tester, const Size(1176, 900));
      final world = FirstStepsWorld(
        store: MemoryFirstStepsStore(FirstStepsOutcome.completed),
      );
      await tester.runAsync(world.seed);
      await tester.pumpWidget(_app(world.desktopHome()));
      await _settle(tester);
      expect(_card, findsNothing);
      final column = tester.getRect(
        find.byKey(const ValueKey('home-secondary-column')),
      );
      final record = tester.getRect(
        find.byKey(const ValueKey('home-record-moment')),
      );
      expect(record.top, column.top + AppRhythm.section);
    });
  });
}
