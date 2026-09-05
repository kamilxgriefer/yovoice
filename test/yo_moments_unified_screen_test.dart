import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_destination_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';

void main() {
  testWidgets('YO Moments unifies Voice and Reels and routes create choice', (
    tester,
  ) async {
    var reelCreates = 0;
    await _pump(
      tester,
      locale: const Locale('pl'),
      child: MomentsScreen(
        isRootTab: true,
        initialFormat: YoMomentsFormat.reels,
        reelService: _emptyReelService(),
        onCreateReel: () async => reelCreates += 1,
      ),
    );

    expect(find.text('YO Moments'), findsOneWidget);
    expect(find.text('Głos'), findsOneWidget);
    expect(find.text('Reels'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('yo-moments-format-tabs')),
      findsOneWidget,
    );
    expect(find.text('Nie ma jeszcze Reels'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('moments-create-cta')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('yo-moments-create-sheet')),
      findsOneWidget,
    );
    expect(find.text('Nagraj Voice Moment'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('create-reel-choice')),
        matching: find.text('Utwórz Reel'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('create-reel-choice')));
    await tester.pumpAndSettle();
    expect(reelCreates, 1);
    expect(find.text('YO Moments'), findsOneWidget);
  });

  testWidgets('create choices expose one named button each to assistive tech', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(
        tester,
        locale: const Locale('pl'),
        child: MomentsScreen(
          isRootTab: true,
          initialFormat: YoMomentsFormat.reels,
          reelService: _emptyReelService(),
          onCreateReel: () async {},
        ),
      );

      await tester.tap(find.byKey(const ValueKey('moments-create-cta')));
      await tester.pumpAndSettle();

      for (final (key, label) in <(String, String)>[
        ('create-voice-moment-choice', 'Nagraj Voice Moment'),
        ('create-reel-choice', 'Utwórz Reel'),
      ]) {
        final data = tester
            .getSemantics(find.byKey(ValueKey<String>(key)))
            .getSemanticsData();
        expect(data.label, label);
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('header survives narrow, wide and enlarged-text layouts', (
    tester,
  ) async {
    for (final theme in <ThemeData>[AppTheme.darkTheme, AppTheme.lightTheme]) {
      for (final size in <Size>[
        const Size(320, 640),
        const Size(390, 844),
        const Size(768, 900),
        const Size(1280, 900),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await _pump(
          tester,
          theme: theme,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: MomentsScreen(
              isRootTab: true,
              initialFormat: YoMomentsFormat.reels,
              reelService: _emptyReelService(),
              onCreateReel: () async {},
            ),
          ),
        );

        expect(find.text('YO Moments'), findsOneWidget);
        if (size.width <= 390) {
          final title = find.byKey(const ValueKey<String>('yo-moments-title'));
          final text = tester.widget<Text>(title);
          expect(text.maxLines, isNull);
          expect(text.overflow, TextOverflow.visible);
          _expectTextFullyLaidOut(tester, title);
        }
        expect(tester.takeException(), isNull);
      }
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('Pearl create chooser scrolls at 200% and keeps AA contrast', (
    tester,
  ) async {
    const size = Size(320, 640);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      theme: AppTheme.lightTheme,
      child: MediaQuery(
        data: const MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(2),
          disableAnimations: true,
        ),
        child: MomentsScreen(
          isRootTab: true,
          initialFormat: YoMomentsFormat.reels,
          reelService: _emptyReelService(),
          onCreateReel: () async {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('moments-create-cta')));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);

    final context = tester.element(
      find.byKey(const ValueKey<String>('yo-moments-create-sheet')),
    );
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    expect(
      _contrast(palette.textPrimary, palette.surfaceRaised),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(scheme.onSecondaryContainer, scheme.secondaryContainer),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets(
    'Reel playback follows host, format and pushed route visibility',
    (tester) async {
      final hostVisible = ValueNotifier<bool>(true);
      addTearDown(hostVisible.dispose);
      await _pump(
        tester,
        child: MomentsScreen(
          isRootTab: true,
          isVisible: hostVisible,
          initialFormat: YoMomentsFormat.reels,
          reelService: _reelServiceWithItem(),
          onCreateReel: () async {},
        ),
      );
      final reel = find.byType(ReelCard, skipOffstage: false);
      expect(tester.widget<ReelCard>(reel).isActive, isTrue);

      hostVisible.value = false;
      await tester.pump();
      expect(tester.widget<ReelCard>(reel).isActive, isFalse);
      hostVisible.value = true;
      await tester.pump();
      expect(tester.widget<ReelCard>(reel).isActive, isTrue);

      await tester.tap(find.text('Voice'));
      await tester.pump();
      expect(tester.widget<ReelCard>(reel).isActive, isFalse);
      await tester.tap(find.text('Reels'));
      await tester.pump();
      expect(tester.widget<ReelCard>(reel).isActive, isTrue);

      final navigator = Navigator.of(tester.element(find.text('YO Moments')));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Pushed route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<ReelCard>(reel).isActive, isFalse);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(tester.widget<ReelCard>(reel).isActive, isTrue);
    },
  );

  testWidgets('legacy Reels destination opens unified route-aware screen', (
    tester,
  ) async {
    await _pump(
      tester,
      child: ReelsDestinationScreen(
        isRootTab: true,
        reelService: _emptyReelService(),
      ),
    );
    expect(find.text('YO Moments'), findsOneWidget);
    expect(find.text('Reels'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('yo-moments-format-stack')),
      findsOneWidget,
    );
  });
}

void _expectTextFullyLaidOut(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'the actual rendered paragraph must not clip or ellipsize',
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: <NavigatorObserver>[appRouteObserver],
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

ReelService _reelServiceWithItem() {
  return ReelService(
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'viewer')),
    callableInvoker: (name, payload) async {
      if (name == 'listReelsV2') {
        return <Object?, Object?>{
          'schemaVersion': 2,
          'items': <Object?>[
            <String, Object?>{
              'id': 'route_reel',
              'authorId': 'creator',
              'authorName': 'Creator',
              'media': <String, Object?>{
                'kind': 'image',
                'contentType': 'image/jpeg',
                'size': 1024,
                'generation': '1',
                'durationMs': 0,
              },
              'backingAudio': null,
              'composition': const ReelComposition(
                originalAudioVolume: 0,
              ).toWire(),
              'publishedAtMillis': 1900000000000,
              'sortKey': '1900000000000_route_reel',
              'availability': <String, Object?>{
                'schemaVersion': 1,
                'availabilityHours': 'permanent',
                'expiresAtMillis': null,
              },
            },
          ],
          'nextCursor': null,
        };
      }
      if (name == 'getReelMediaAccessV2') {
        return <Object?, Object?>{
          'schemaVersion': 2,
          'url': 'https://storage.googleapis.com/yovoice/route-reel.jpg',
          'expiresAtMillis': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'generation': '1',
          'availabilityHours': 'permanent',
          'contentExpiresAtMillis': null,
        };
      }
      throw StateError('Unexpected callable $name with $payload');
    },
  );
}

double _contrast(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first.computeLuminance()
      : second.computeLuminance();
  final darker = first.computeLuminance() > second.computeLuminance()
      ? second.computeLuminance()
      : first.computeLuminance();
  return (lighter + .05) / (darker + .05);
}

ReelService _emptyReelService() {
  return ReelService(
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'viewer')),
    callableInvoker: (name, payload) async {
      if (name == 'listReelsV2') {
        return <Object?, Object?>{
          'schemaVersion': 2,
          'items': const <Object?>[],
          'nextCursor': null,
        };
      }
      throw StateError('Unexpected callable $name with $payload');
    },
  );
}
