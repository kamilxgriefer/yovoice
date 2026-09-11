import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card_skeleton.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

/// Every state the Reels stage can be in, at the widths and appearances that
/// change its shape.
///
/// The stage sits on the destination's own canvas, so a state that painted a
/// surface of its own — or overflowed a short window at an accessibility text
/// size — would break the composition rather than merely look wrong.
void main() {
  const narrow = Size(390, 844);
  const wide = Size(1440, 900);

  group('loading', () {
    testWidgets('the first load holds the card geometry and says so once', (
      tester,
    ) async {
      final service = _service(
        (_) => Completer<Map<Object?, Object?>>().future,
      );
      await _pump(tester, service, settle: false);

      // The skeleton is the card that is coming, at the same size, so nothing
      // jumps when the page lands.
      expect(find.byType(ReelCardSkeleton), findsOneWidget);
      // Exactly one polite live region for the state.
      expect(find.byType(YoLoadingIndicator), findsOneWidget);
      expect(find.text('Loading Reels'), findsOneWidget);

      // Refreshing while a load is already running is not an action.
      final refresh = tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('reels-refresh')),
      );
      expect(refresh.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the skeleton fits every width and appearance', (tester) async {
      for (final theme in <ThemeData>[
        AppTheme.darkTheme,
        AppTheme.lightTheme,
      ]) {
        for (final size in const <Size>[
          Size(320, 568),
          narrow,
          Size(768, 1024),
          Size(1100, 800),
          wide,
        ]) {
          final service = _service(
            (_) => Completer<Map<Object?, Object?>>().future,
          );
          await _pump(tester, service, size: size, theme: theme, settle: false);
          expect(find.byType(ReelCardSkeleton), findsOneWidget);
          expect(tester.takeException(), isNull);
          // The skeleton is the card, so it never exceeds the stage it stands
          // in — a skeleton that overflows teaches the wrong geometry.
          final skeleton = tester.getSize(find.byType(ReelCardSkeleton));
          expect(skeleton.width, lessThanOrEqualTo(size.width));
          expect(skeleton.height, lessThanOrEqualTo(size.height));
        }
      }
    });
  });

  group('empty', () {
    testWidgets('an empty catalogue offers the composer and nothing else', (
      tester,
    ) async {
      var creates = 0;
      final service = _service((_) async => _page(const <Object?>[]));
      await _pump(tester, service, onCreate: () async => creates += 1);

      expect(find.byType(YoEmptyState), findsOneWidget);
      expect(find.text('No Reels yet'), findsOneWidget);
      expect(find.byType(ReelCardSkeleton), findsNothing);
      expect(find.text('Loading Reels'), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byType(YoEmptyState),
          matching: find.text('Create Reel'),
        ),
      );
      await tester.pumpAndSettle();
      expect(creates, 1);
    });

    testWidgets('a host with no composer still shows the state, without a '
        'button that cannot work', (tester) async {
      final service = _service((_) async => _page(const <Object?>[]));
      await _pump(tester, service);

      expect(find.byType(YoEmptyState), findsOneWidget);
      expect(find.text('Create Reel'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the empty state survives a short window at 200% text', (
      tester,
    ) async {
      for (final theme in <ThemeData>[
        AppTheme.darkTheme,
        AppTheme.lightTheme,
      ]) {
        final service = _service((_) async => _page(const <Object?>[]));
        await _pump(
          tester,
          service,
          size: const Size(320, 568),
          theme: theme,
          textScale: 2,
          onCreate: () async {},
        );
        expect(find.byType(YoEmptyState), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('error', () {
    testWidgets('a failed first load explains itself and retries', (
      tester,
    ) async {
      var calls = 0;
      final service = _service((_) async {
        calls += 1;
        if (calls == 1) throw StateError('feed unavailable');
        return _page(const <Object?>[]);
      });
      await _pump(tester, service);

      expect(find.byType(YoErrorState), findsOneWidget);
      expect(find.text('Loading Reels'), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      // The successful empty retry also checks the authorized includeSeen
      // page before deciding between an empty library and caught-up content.
      expect(calls, 3);
      // The retry succeeded into an empty catalogue: the state that replaces
      // the failure is the truth about the catalogue, not another failure.
      expect(find.byType(YoErrorState), findsNothing);
      expect(find.byType(YoEmptyState), findsOneWidget);
    });

    testWidgets('the error state fits both appearances at the panel width', (
      tester,
    ) async {
      for (final theme in <ThemeData>[
        AppTheme.darkTheme,
        AppTheme.lightTheme,
      ]) {
        final service = _service((_) async => throw StateError('down'));
        await _pump(tester, service, size: wide, theme: theme);
        expect(find.byType(YoErrorState), findsOneWidget);
        // No Reel to talk about, so no docked panel talks about one.
        expect(
          find.byKey(const ValueKey<String>('reel-panel-thread-closed')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    });
  });

  testWidgets('no state paints a surface over the destination canvas', (
    tester,
  ) async {
    final states = <String, Future<Map<Object?, Object?>> Function(String?)>{
      'empty': (_) async => _page(const <Object?>[]),
      'error': (_) async => throw StateError('down'),
    };
    for (final entry in states.entries) {
      await _pump(tester, _service(entry.value));
      final stage = tester.widget<Material>(
        find.byKey(const ValueKey<String>('reels-stage')),
      );
      expect(
        stage.type,
        MaterialType.transparency,
        reason: '${entry.key} must not paint its own canvas',
      );
      expect(stage.color, isNull);
    }
  });
}

Map<Object?, Object?> _page(List<Object?> items, [String? cursor]) =>
    <Object?, Object?>{
      'schemaVersion': 2,
      'items': items,
      'nextCursor': cursor,
    };

ReelService _service(
  Future<Map<Object?, Object?>> Function(String? cursor) list,
) => ReelService(
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
  ),
  callableInvoker: (name, payload) async {
    if (name == 'listReelsV2') return list(payload['cursor'] as String?);
    throw StateError('Unexpected callable $name');
  },
);

Future<void> _pump(
  WidgetTester tester,
  ReelService service, {
  Size size = const Size(390, 844),
  ThemeData? theme,
  double textScale = 1,
  Future<void> Function()? onCreate,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: ReelsFeedScreen(
        embedded: true,
        service: service,
        onCreate: onCreate,
        videoBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}
