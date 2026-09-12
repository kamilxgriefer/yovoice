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
// B-3: the thumb was sized 1/count of the track while the segments were
// content-sized, so it landed on the neighbour in every locale whose two
// labels differ in width. English is the one case where "Voice" and "Reels"
// measure alike, which is why every earlier run missed it.
//
// These tests do not constitute device or screen-reader evidence.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  List<String> formatLabels = const <String>['Voice', 'Reels'],
  List<String> filterLabels = _polishFilters,
}) {
  final formatKeys = <Key>[_formatA, _formatB];
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: SizedBox(
            width: width,
            child: ImmersiveFeedChrome(
              key: _chrome,
              gutter: 12,
              formatSwitch: ImmersiveSegmentedSwitch(
                selectedIndex: selectedFormat,
                onSelected: (_) {},
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
              'The white thumb is the only non-colour indicator of the '
              'selected format. Off-screen, a reader sees the other label '
              'with no thumb and concludes the wrong format is selected.',
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

  group(
    'B-3 segments are equal width, so the 1/count thumb cannot misalign',
    () {
      // Pairs whose rendered widths differ. The last is the English pair that
      // happens to measure alike, which is exactly why the bug survived.
      const pairs = <List<String>>[
        <String>['Głos', 'Reels'],
        <String>['音声', 'Reels'],
        <String>['Stimme', 'Reels'],
        <String>['Voice', 'Reels'],
      ];
      for (final pair in pairs) {
        for (final scale in _scales) {
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
                  'Unequal segments put the thumb on the neighbour, and the '
                  'selected label is painted in contrast ink with no shadow '
                  'because it is assumed to sit on the white thumb. '
                  'a=${a.width} b=${b.width}',
            );
          });
        }
      }
    },
  );

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
