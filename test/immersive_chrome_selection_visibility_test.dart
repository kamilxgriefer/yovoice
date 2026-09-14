// Regression tests for the three blocking defects the principal reviewer
// found in the immersive chrome, plus the focus-state gap beside them.
//
// These are widget-level on purpose. All three are properties of the two
// controls' own layout, not of any screen that mounts them, and pinning them
// here means they hold for Voice and Reels at once and for any future host.
//
// B-1 / B-2: both chrome rows scroll horizontally and neither carried a
// controller, so both always rendered at offset 0 and the SELECTED item could
// sit entirely outside the viewport -- the format segment at 200 % text on a
// 390 px phone, and the filter chip at default text size once four Polish
// pool labels are present.
//
// B-3: the text tabs must remain equal width so their active glow line stays
// visually balanced across locales whose labels differ in width.
//
// These tests do not constitute device or screen-reader evidence.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_feed_chrome.dart';

const _chrome = ValueKey<String>('chrome-under-test');
const _formatA = ValueKey<String>('chrome-format-a');
const _formatB = ValueKey<String>('chrome-format-b');

const _phoneWidths = <double>[320, 390, 430];
const _scales = <double>[1.0, 2.0];

/// Four real Polish pool labels: the configuration the accessibility audit
/// measured as failing at DEFAULT text size on every phone width.
const _polishFilters = <String>[
  'Wszystkie',
  'Obserwowani',
  'Najpopularniejsze',
  'Najnowsze',
];

Widget _host({
  required double width,
  required double scale,
  required int selectedFormat,
  required int selectedFilter,
  List<String> formatLabels = const <String>['Voice', 'Yeels'],
  List<String> filterLabels = _polishFilters,
  bool onCanvas = false,
  bool disableAnimations = false,
  Brightness brightness = Brightness.dark,
  Widget? leading,
  Widget? trailing,
}) {
  final formatKeys = <Key>[_formatA, _formatB];
  final palette = brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
  return MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      extensions: <ThemeExtension>[palette],
    ),
    home: Scaffold(
      body: Center(
        child: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            disableAnimations: disableAnimations,
          ),
          child: SizedBox(
            width: width,
            child: ImmersiveFeedChrome(
              key: _chrome,
              gutter: 12,
              leading: leading,
              trailing: trailing,
              formatSwitch: ImmersiveSegmentedSwitch(
                selectedIndex: selectedFormat,
                onSelected: (_) {},
                onCanvas: onCanvas,
                segments: <ImmersiveChromeOption>[
                  for (var i = 0; i < formatLabels.length; i++)
                    ImmersiveChromeOption(
                      key: i < formatKeys.length ? formatKeys[i] : null,
                      label: formatLabels[i],
                    ),
                ],
              ),
              filters: <ImmersiveChromeOption>[
                for (var i = 0; i < filterLabels.length; i++)
                  ImmersiveChromeOption(
                    key: ValueKey<String>('chrome-filter-$i'),
                    label: filterLabels[i],
                  ),
              ],
              selectedFilterIndex: selectedFilter,
              onFilterSelected: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

void _expectInsideChrome(WidgetTester tester, Finder target, String because) {
  final chrome = tester.getRect(find.byKey(_chrome));
  final rect = tester.getRect(target);
  expect(
    rect.left >= chrome.left - 0.5 && rect.right <= chrome.right + 0.5,
    isTrue,
    reason:
        '$because\nchrome=${chrome.left}..${chrome.right} '
        'item=${rect.left}..${rect.right}',
  );
}

void main() {
  testWidgets(
    'format tabs use larger text and a line instead of black/white tiles',
    (tester) async {
      await tester.pumpWidget(
        _host(width: 390, scale: 1, selectedFormat: 0, selectedFilter: 0),
      );
      await tester.pumpAndSettle();

      final voice = tester.widget<Text>(find.text('Voice'));
      final yeels = tester.widget<Text>(find.text('Yeels'));
      expect(voice.style?.fontSize, 17);
      expect(voice.style?.fontWeight, FontWeight.w800);
      expect(voice.style?.color, AppPalette.dark.interactiveForeground);
      expect(yeels.style?.fontSize, 17);
      expect(yeels.style?.fontWeight, FontWeight.w600);
      expect(yeels.style?.color, Colors.white);
      final crispOutline = voice.style!.shadows!.where(
        (shadow) => shadow.blurRadius == 0 && shadow.offset != Offset.zero,
      );
      expect(
        crispOutline.length,
        greaterThanOrEqualTo(8),
        reason:
            'The selected violet word needs a glyph-local dark outline on '
            'bright media now that the full-width scrim is gone.',
      );
      expect(
        _contrast(voice.style!.color!, Colors.black),
        greaterThanOrEqualTo(4.5),
      );

      final active = find.byKey(
        const ValueKey<String>('immersive-format-indicator-Voice'),
      );
      final inactive = find.byKey(
        const ValueKey<String>('immersive-format-indicator-Yeels'),
      );
      expect(tester.getSize(active).width, 30);
      expect(tester.getSize(inactive).width, 0);
      final indicator =
          tester.widget<AnimatedContainer>(active).decoration as BoxDecoration;
      expect(
        indicator.boxShadow,
        contains(
          isA<BoxShadow>()
              .having((shadow) => shadow.color.a, 'alpha', greaterThan(.8))
              .having((shadow) => shadow.spreadRadius, 'spread', 2),
        ),
        reason:
            'The violet selection line needs a local dark edge on bright '
            'media without bringing back the full header block.',
      );

      final switcher = find.byType(ImmersiveSegmentedSwitch);
      final tileFills = tester
          .widgetList<DecoratedBox>(
            find.descendant(of: switcher, matching: find.byType(DecoratedBox)),
          )
          .map((widget) => widget.decoration)
          .whereType<BoxDecoration>()
          .where(
            (decoration) =>
                decoration.color == Colors.black ||
                decoration.color == Colors.white,
          );
      expect(
        tileFills,
        isEmpty,
        reason: 'The format selector must not restore a black track or thumb.',
      );
    },
  );

  testWidgets('immersive chrome has no full-width black header scrim', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(width: 390, scale: 1, selectedFormat: 1, selectedFilter: 0),
    );
    await tester.pumpAndSettle();

    final blackGradients = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(_chrome),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<LinearGradient>()
        .where(
          (gradient) => gradient.colors.any(
            (color) =>
                color.r == 0 && color.g == 0 && color.b == 0 && color.a > .25,
          ),
        );

    expect(
      blackGradients,
      isEmpty,
      reason:
          'Głos and Yeels must sit directly over the media; a chrome-wide '
          'black gradient is the reported black block.',
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('canvas active violet adapts to ${brightness.name}', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          width: 390,
          scale: 1,
          selectedFormat: 1,
          selectedFilter: 0,
          onCanvas: true,
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();

      final palette = brightness == Brightness.dark
          ? AppPalette.dark
          : AppPalette.light;
      expect(
        tester.widget<Text>(find.text('Yeels')).style?.color,
        palette.interactiveForeground,
      );
      expect(
        tester.widget<Text>(find.text('Voice')).style?.color,
        palette.textSecondary,
      );
    });
  }

  testWidgets('Reduce Motion removes the active-line transition', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        width: 390,
        scale: 1,
        selectedFormat: 0,
        selectedFilter: 0,
        disableAnimations: true,
      ),
    );

    final indicator = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('immersive-format-indicator-Voice')),
    );
    expect(indicator.duration, Duration.zero);
  });

  for (final width in _phoneWidths) {
    testWidgets(
      '${width.toInt()} px honors the full 200 % format-label scale with '
      'both edge actions',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(
            width: width,
            scale: 2,
            selectedFormat: 0,
            selectedFilter: 0,
            formatLabels: const <String>['Głos', 'Yeels'],
            // This is the tightest real header: pushed routes retain Back
            // while Create remains visible on the other edge.
            leading: const SizedBox.square(dimension: 48),
            trailing: const SizedBox.square(dimension: 48),
          ),
        );
        await tester.pumpAndSettle();

        for (final (index, label) in const <String>['Głos', 'Yeels'].indexed) {
          final finder = find.text(label);
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          expect(
            paragraph.textScaler.scale(17),
            closeTo(34, .01),
            reason: '$label must receive the full 2.0 system text scale.',
          );
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason:
                '$label must remain complete at 200% on $width px. '
                'text=${paragraph.size}, '
                'intrinsic=${paragraph.getMaxIntrinsicWidth(double.infinity)}, '
                'segment=${tester.getSize(index == 0 ? find.byKey(_formatA) : find.byKey(_formatB))}',
          );
          _expectInsideChrome(
            tester,
            finder,
            '$label must remain inside the phone header at 200%.',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  group('B-1 the selected format segment stays inside the viewport', () {
    for (final width in _phoneWidths) {
      for (final scale in _scales) {
        for (var selected = 0; selected < 2; selected++) {
          testWidgets('${width.toInt()} px, ${scale}x, segment $selected', (
            tester,
          ) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(
              _host(
                width: width,
                scale: scale,
                selectedFormat: selected,
                selectedFilter: 0,
              ),
            );
            await tester.pumpAndSettle();

            _expectInsideChrome(
              tester,
              find.byKey(selected == 0 ? _formatA : _formatB),
              'The active glow line is the non-colour indicator of the '
              'selected format. It must remain inside the visible chrome.',
            );
          });
        }
      }
    }
  });

  group('B-2 the selected pool filter stays inside the viewport', () {
    for (final width in _phoneWidths) {
      for (final scale in _scales) {
        testWidgets(
          '${width.toInt()} px, ${scale}x, last of four Polish filters',
          (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(
              _host(
                width: width,
                scale: scale,
                selectedFormat: 0,
                selectedFilter: _polishFilters.length - 1,
              ),
            );
            await tester.pumpAndSettle();

            _expectInsideChrome(
              tester,
              find.byKey(
                ValueKey<String>('chrome-filter-${_polishFilters.length - 1}'),
              ),
              'A user may legitimately select the last pool. The active pool '
              'must be visible, or the feed appears unfiltered.',
            );
          },
        );
      }
    }
  });

  testWidgets('selection gained after mount is revealed, not left off-screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(width: 390, scale: 2.0, selectedFormat: 0, selectedFilter: 0),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _host(width: 390, scale: 2.0, selectedFormat: 1, selectedFilter: 3),
    );
    await tester.pumpAndSettle();

    _expectInsideChrome(
      tester,
      find.byKey(_formatB),
      'Switching format must bring the newly selected segment into view.',
    );
    _expectInsideChrome(
      tester,
      find.byKey(const ValueKey<String>('chrome-filter-3')),
      'Switching pool must bring the newly selected chip into view.',
    );
  });

  group('B-3 text tabs remain equal width across locales', () {
    // Pairs whose rendered widths differ. The last is the English pair that
    // happens to measure alike, which is exactly why the bug survived.
    const pairs = <List<String>>[
      <String>['Głos', 'Yeels'],
      <String>['音声', 'Yeels'],
      <String>['Stimme', 'Yeels'],
      <String>['Voice', 'Yeels'],
    ];
    for (final pair in pairs) {
      for (final scale in const <double>[1.0]) {
        testWidgets('${pair.first} / ${pair.last} at ${scale}x', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(390, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            _host(
              width: 390,
              scale: scale,
              selectedFormat: 1,
              selectedFilter: 0,
              formatLabels: pair,
            ),
          );
          await tester.pumpAndSettle();

          final a = tester.getRect(find.byKey(_formatA));
          final b = tester.getRect(find.byKey(_formatB));
          expect(
            (a.width - b.width).abs() < 0.5,
            isTrue,
            reason:
                'Unequal text tabs make the active line and labels look '
                'visually unbalanced. '
                'a=${a.width} b=${b.width}',
          );
        });
      }
    }
  });

  testWidgets('F-1 segments and chips expose enabled and focusable state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(width: 390, scale: 1.0, selectedFormat: 0, selectedFilter: 0),
    );
    await tester.pumpAndSettle();

    for (final finder in <Finder>[
      find.byKey(_formatA),
      find.byKey(const ValueKey<String>('chrome-filter-0')),
    ]) {
      final data = tester.getSemantics(finder).getSemanticsData();
      // isEnabled is a Tristate, and `none` is the telling value: it means the
      // control never declared an enabled state at all, which is exactly what
      // excludeSemantics caused by discarding the InkWell's own node. The ring
      // was drawn and never spoken.
      expect(
        data.flagsCollection.isEnabled,
        ui.Tristate.isTrue,
        reason: 'A control that draws a focus ring must also speak its state.',
      );
      expect(
        data.flagsCollection.isFocused,
        isNot(ui.Tristate.none),
        reason: 'A focusable control must participate in the focus tree.',
      );
    }
    handle.dispose();
  });
}

double _contrast(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + .05) / (darker + .05);
}
