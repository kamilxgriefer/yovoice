import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/shared/widgets/navigation/yo_moments_icon.dart';

void main() {
  for (final theme in <ThemeData>[AppTheme.darkTheme, AppTheme.lightTheme]) {
    testWidgets('Frame Echo Clean exposes all states without rotation', (
      tester,
    ) async {
      for (final state in YoMomentsIconState.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Center(child: YoMomentsIcon(state: state, size: 32)),
          ),
        );
        await tester.pumpAndSettle();

        final paint = tester.widget<CustomPaint>(
          find.byKey(const ValueKey<String>('yo-moments-frame-echo-clean')),
        );
        final painter = paint.painter! as FrameEchoCleanPainter;
        expect(
          painter.active,
          state == YoMomentsIconState.active ||
              state == YoMomentsIconState.pressed,
        );
        expect(painter.pressed, state == YoMomentsIconState.pressed);

        final scale = tester.widget<AnimatedScale>(
          find.byKey(const ValueKey<String>('yo-moments-frame-echo-scale')),
        );
        expect(
          scale.scale,
          state == YoMomentsIconState.pressed ? .92 : 1,
          reason: 'feedback is a uniform scale; no rotation/skew is present',
        );
      }
    });
  }

  testWidgets('disabled state is visibly muted and keeps exact geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Center(
          child: YoMomentsIcon(
            state: YoMomentsIconState.disabled,
            animationDuration: Duration.zero,
          ),
        ),
      ),
    );

    final opacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byKey(const ValueKey<String>('yo-moments-frame-echo-clean')),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(opacity.opacity, .38);
    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('yo-moments-frame-echo-clean')),
      ),
      const Size.square(24),
    );
  });

  testWidgets('desktop hover stays axis-aligned and press uses uniform scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: DesktopSidebar.width,
              height: 900,
              child: DesktopSidebar(
                active: DesktopNavItem.moments,
                unreadConversationCount: 0,
                unreadNotificationCount: 0,
                onSelect: (_) {},
                onCreateRoom: () {},
                onCreateMoment: () {},
                onOpenProfile: () {},
                onOpenProfileSettings: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final mark = find.byKey(
      const ValueKey<String>('yo-moments-frame-echo-clean'),
    );
    FrameEchoCleanPainter painter() =>
        tester.widget<CustomPaint>(mark).painter! as FrameEchoCleanPainter;

    expect(painter().active, isTrue);
    expect(painter().pressed, isFalse);
    expect(
      find.ancestor(of: mark, matching: find.byType(RotationTransition)),
      findsNothing,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final target = tester.getCenter(find.text('YO Moments'));
    await mouse.moveTo(target);
    await tester.pump(const Duration(milliseconds: 200));
    expect(painter().pressed, isFalse, reason: 'hover must not tilt the mark');

    await mouse.down(target);
    await tester.pump(const Duration(milliseconds: 200));
    expect(painter().pressed, isTrue);
    final scale = tester.widget<AnimatedScale>(
      find.byKey(const ValueKey<String>('yo-moments-frame-echo-scale')),
    );
    expect(scale.scale, .92);
    expect(
      find.ancestor(of: mark, matching: find.byType(RotationTransition)),
      findsNothing,
    );
    await mouse.up();
  });
}
