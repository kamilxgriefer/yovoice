import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart';

const _pillKey = ValueKey('yo-server-rail-item-pill');

Widget _host(
  Widget child, {
  ThemeData? theme,
  double textScale = 1,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: Scaffold(
        body: Align(alignment: AlignmentDirectional.topStart, child: child),
      ),
    ),
  ),
);

YoServerRailItem _item({
  bool selected = false,
  VoidCallback? onTap,
  ServerType type = ServerType.community,
}) => YoServerRailItem(
  key: const ValueKey('server-rail-s1'),
  initial: 'K',
  type: type,
  semanticLabel: 'Kamil club',
  selected: selected,
  onTap: onTap ?? () {},
);

double _pillHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(_pillKey)).height;

void main() {
  testWidgets('a 44 px squircle with radius 14 inside a 48 px target', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_item()));
    final tile = find.byType(YoServerTile);
    expect(tester.getSize(tile), const Size.square(YoServerRailItem.tileSize));
    final decoration =
        tester
                .widget<Container>(
                  find.descendant(of: tile, matching: find.byType(Container)),
                )
                .decoration!
            as BoxDecoration;
    expect(decoration.borderRadius, AppRadius.md);
    expect(AppRadius.md.topLeft.x, 14);
    expect(
      tester.getSize(find.byKey(const ValueKey('server-rail-s1'))),
      const Size(YoServerRailItem.railWidth, YoServerRailItem.targetSize),
    );
    final tapTarget = tester.getSize(find.byType(InkWell));
    expect(tapTarget.width, greaterThanOrEqualTo(44));
    expect(tapTarget.height, greaterThanOrEqualTo(44));
    // The initial stays a Text, so finders keep working.
    expect(find.descendant(of: tile, matching: find.text('K')), findsOneWidget);
  });

  for (final themeCase in <({String name, ThemeData theme, Brightness b})>[
    (name: 'dark', theme: AppTheme.darkTheme, b: Brightness.dark),
    (name: 'Pearl', theme: AppTheme.lightTheme, b: Brightness.light),
  ]) {
    testWidgets('${themeCase.name}: colours come from ServerIdentity', (
      tester,
    ) async {
      for (final type in ServerType.values) {
        await tester.pumpWidget(
          _host(_item(type: type, selected: true), theme: themeCase.theme),
        );
        final visuals = ServerIdentity.of(type).resolve(themeCase.b);
        final decoration =
            tester
                    .widget<Container>(
                      find.descendant(
                        of: find.byType(YoServerTile),
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration!
                as BoxDecoration;
        expect(decoration.color, visuals.iconSurface, reason: type.name);
        expect(
          tester.widget<Text>(find.text('K')).style!.color,
          visuals.foreground,
          reason: type.name,
        );
        final pill =
            tester.widget<AnimatedContainer>(find.byKey(_pillKey)).decoration!
                as BoxDecoration;
        final palette = themeCase.theme.extension<AppPalette>()!;
        expect(pill.color, palette.textPrimary);
      }
    });
  }

  testWidgets('the selection pill: 32 selected, 16 on hover, 0 idle', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_item(selected: true)));
    await tester.pumpAndSettle();
    expect(_pillHeight(tester), YoServerRailItem.pillSelectedHeight);
    expect(
      tester.getSize(find.byKey(_pillKey)).width,
      YoServerRailItem.pillWidth,
    );
    // The pill sits on the rail's start edge.
    expect(
      tester.getTopLeft(find.byKey(_pillKey)).dx,
      tester.getTopLeft(find.byKey(const ValueKey('server-rail-s1'))).dx,
    );

    await tester.pumpWidget(_host(_item()));
    await tester.pumpAndSettle();
    expect(_pillHeight(tester), 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(YoServerTile)));
    await tester.pumpAndSettle();
    expect(_pillHeight(tester), YoServerRailItem.pillHoverHeight);
  });

  testWidgets('no animation under Reduce Motion', (tester) async {
    await tester.pumpWidget(_host(_item(), disableAnimations: true));
    await tester.pumpWidget(
      _host(_item(selected: true), disableAnimations: true),
    );
    await tester.pump();
    expect(_pillHeight(tester), YoServerRailItem.pillSelectedHeight);
    expect(
      tester.widget<AnimatedContainer>(find.byKey(_pillKey)).duration,
      Duration.zero,
    );
  });

  testWidgets('semantics: label, button, selected; tap and tooltip', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(_host(_item(selected: true, onTap: () => taps++)));
    final node = tester.getSemantics(find.bySemanticsLabel('Kamil club'));
    expect(
      node,
      isSemantics(
        label: 'Kamil club',
        isButton: true,
        isSelected: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.byType(YoServerTile));
    expect(taps, 1);
    expect(
      find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Kamil club'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('has no unread badge, counter or dot', (tester) async {
    await tester.pumpWidget(_host(_item(selected: true)));
    final item = find.byKey(const ValueKey('server-rail-s1'));
    expect(
      find.descendant(of: item, matching: find.byType(Badge)),
      findsNothing,
    );
    // The only text inside the item is the initial.
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: item, matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .toList();
    expect(texts, ['K']);
    // Every decorated box is the tile, the pill or the tap region's
    // (transparent) focus ring — nothing circular is drawn.
    for (final box in tester.widgetList<Container>(
      find.descendant(of: item, matching: find.byType(Container)),
    )) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration) {
        expect(decoration.shape, BoxShape.rectangle);
      }
    }
  });

  testWidgets('200 percent text keeps the rail slot and the glyph inside', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_item(), textScale: 2));
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('server-rail-s1'))).width,
      lessThanOrEqualTo(68),
    );
    final glyph = tester.renderObject<RenderParagraph>(find.text('K'));
    expect(glyph.textScaler.scale(10), 10 * YoServerTile.maxTextScale);
    final tile = tester.getRect(find.byType(YoServerTile));
    final text = tester.getRect(find.text('K'));
    expect(
      tile.contains(text.topLeft) && tile.contains(text.bottomRight),
      isTrue,
    );
  });
}
