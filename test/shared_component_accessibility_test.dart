import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/badges/yo_badge.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_social_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/inputs/yo_text_field.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

void main() {
  for (final themeCase in <({String name, ThemeData theme})>[
    (name: 'dark', theme: AppTheme.darkTheme),
    (name: 'Pearl', theme: AppTheme.lightTheme),
  ]) {
    testWidgets('${themeCase.name} status badges use AA-safe paired roles', (
      tester,
    ) async {
      for (final variant in YoBadgeVariant.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: themeCase.theme,
            home: Scaffold(
              body: Center(
                child: YoBadge(label: variant.name, variant: variant),
              ),
            ),
          ),
        );

        final badge = find.byType(YoBadge);
        final container = tester.widget<Container>(
          find.descendant(of: badge, matching: find.byType(Container)).first,
        );
        final decoration = container.decoration! as BoxDecoration;
        final label = tester.widget<Text>(find.text(variant.name));
        expect(
          _contrast(label.style!.color!, decoration.color!),
          greaterThanOrEqualTo(4.5),
          reason: '${themeCase.name} ${variant.name}',
        );
      }
    });

    testWidgets(
      '${themeCase.name} shared controls survive 320px at 200 percent text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: themeCase.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  YoButton(
                    label: 'A deliberately long primary action label',
                    onPressed: () {},
                  ),
                  const SizedBox(height: 12),
                  const YoButton(label: 'Unavailable action', onPressed: null),
                  const SizedBox(height: 12),
                  YoSocialButton(
                    label: 'Continue securely with this provider',
                    icon: Icons.lock_rounded,
                    onPressed: () {},
                  ),
                  const SizedBox(height: 12),
                  const YoTextField(
                    label: 'Display name',
                    helperText: 'This helper remains readable when enlarged.',
                  ),
                  const SizedBox(height: 12),
                  YoCard(
                    selected: true,
                    onTap: () {},
                    child: const Text(
                      'A selected card with content that wraps over lines.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(YoButton).first).height,
          greaterThan(58),
        );
        expect(
          tester.getSize(find.byType(YoSocialButton)).height,
          greaterThanOrEqualTo(58),
        );
      },
    );
  }

  testWidgets('disabled primary is quiet and focus contrasts with its fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Column(
            children: [
              YoButton(label: 'Focusable', onPressed: () {}),
              const YoButton(label: 'Disabled', onPressed: null),
            ],
          ),
        ),
      ),
    );

    final disabled = find.widgetWithText(YoButton, 'Disabled');
    final disabledDecoration =
        tester
                .widget<AnimatedContainer>(
                  find
                      .descendant(
                        of: disabled,
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(disabledDecoration.gradient, isNull);
    expect(disabledDecoration.color, AppPalette.light.surfaceMuted);

    final enabledDecoration =
        tester
                .widget<AnimatedContainer>(
                  find
                      .descendant(
                        of: find.widgetWithText(YoButton, 'Focusable'),
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(enabledDecoration.gradient, isNotNull);
    expect((enabledDecoration.gradient! as LinearGradient).colors, <Color>[
      AppTheme.lightTheme.colorScheme.primary,
      AppTheme.lightTheme.colorScheme.secondary,
    ]);
    expect(
      enabledDecoration.color,
      isNull,
      reason: 'A transparent fill suppresses the primary gradient raster.',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focusedDecoration =
        tester
                .widget<AnimatedContainer>(
                  find
                      .descendant(
                        of: find.widgetWithText(YoButton, 'Focusable'),
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(
      (focusedDecoration.border! as Border).top.color,
      AppTheme.lightTheme.colorScheme.onPrimary,
    );
    expect(
      _contrast(
        (focusedDecoration.border! as Border).top.color,
        AppTheme.lightTheme.colorScheme.secondary,
      ),
      greaterThanOrEqualTo(3),
    );
  });

  testWidgets(
    'shared controls clamp targets, honor Reduce Motion and announce states',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: ListView(
                children: [
                  YoButton(
                    key: const ValueKey('small-button'),
                    label: 'Small visual request',
                    height: 20,
                    onPressed: () {},
                  ),
                  YoSocialButton(
                    label: 'Provider',
                    icon: Icons.login_rounded,
                    onPressed: () {},
                  ),
                  const YoTextField(
                    label: 'Display name',
                    errorText: 'A display name is required',
                  ),
                  const YoEmptyState(
                    compact: true,
                    icon: Icons.inbox_outlined,
                    title: 'Nothing here yet',
                  ),
                  const YoErrorState(
                    compact: true,
                    message: 'Please retry later',
                  ),
                  const YoLoadingIndicator(message: 'Loading your profile'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSize(find.byKey(const ValueKey('small-button'))).height,
        greaterThanOrEqualTo(44),
      );
      expect(
        tester
            .widget<AnimatedContainer>(
              find
                  .descendant(
                    of: find.byType(YoButton),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            )
            .duration,
        Duration.zero,
      );
      expect(
        tester
            .widget<AnimatedSwitcher>(
              find
                  .descendant(
                    of: find.byType(YoSocialButton),
                    matching: find.byType(AnimatedSwitcher),
                  )
                  .first,
            )
            .duration,
        Duration.zero,
      );
      expect(
        tester
            .widget<AnimatedContainer>(
              find
                  .descendant(
                    of: find.byType(YoTextField),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            )
            .duration,
        Duration.zero,
      );
      for (final type in <Type>[
        YoEmptyState,
        YoErrorState,
        YoLoadingIndicator,
      ]) {
        expect(
          tester
              .widget<TweenAnimationBuilder<double>>(
                find
                    .descendant(
                      of: find.byType(type),
                      matching: find.byType(TweenAnimationBuilder<double>),
                    )
                    .first,
              )
              .duration,
          Duration.zero,
        );
      }

      final input = tester.widget<InputDecorator>(find.byType(InputDecorator));
      expect(input.decoration.errorText, 'A display name is required');
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.liveRegion == true &&
              widget.properties.label ==
                  'Something went wrong. Please retry later',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.liveRegion == true &&
              widget.properties.label == 'Loading your profile',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  for (final themeCase
      in <({String name, ThemeData theme, AppPalette palette})>[
        (name: 'dark', theme: AppTheme.darkTheme, palette: AppPalette.dark),
        (name: 'Pearl', theme: AppTheme.lightTheme, palette: AppPalette.light),
      ]) {
    testWidgets(
      '${themeCase.name} loading social action is one named blocked state',
      (tester) async {
        var presses = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: themeCase.theme,
            home: Scaffold(
              body: YoSocialButton(
                label: 'Continue with provider',
                icon: Icons.login_rounded,
                isLoading: true,
                onPressed: () => presses++,
              ),
            ),
          ),
        );

        final outlined = tester.widget<OutlinedButton>(
          find.byType(OutlinedButton),
        );
        const disabled = <WidgetState>{WidgetState.disabled};
        expect(outlined.onPressed, isNull);
        expect(
          outlined.style!.backgroundColor!.resolve(disabled),
          themeCase.palette.surfaceMuted,
        );
        expect(
          outlined.style!.foregroundColor!.resolve(disabled),
          themeCase.palette.textTertiary,
        );
        expect(
          outlined.style!.side!.resolve(disabled),
          BorderSide(color: themeCase.palette.border),
        );
        expect(
          tester
              .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator),
              )
              .color,
          themeCase.palette.textTertiary,
        );

        final namedLoadingState = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.excludeSemantics &&
              widget.properties.button == true &&
              widget.properties.enabled == false &&
              widget.properties.label == 'Continue with provider, loading',
        );
        expect(namedLoadingState, findsOneWidget);

        await tester.tap(find.byType(YoSocialButton));
        await tester.pump();
        expect(presses, 0);
      },
    );
  }
}

double _contrast(Color first, Color second) {
  final high = first.computeLuminance() > second.computeLuminance()
      ? first
      : second;
  final low = identical(high, first) ? second : first;
  return (high.computeLuminance() + .05) / (low.computeLuminance() + .05);
}
