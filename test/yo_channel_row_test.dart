import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/badges/yo_badge.dart';
import 'package:yovoice/shared/widgets/rows/yo_channel_row.dart';

/// The one channel row (Slim redesign, phase 0). The server panel, the
/// management sheet and every later channel list draw through it, so the
/// contracts their finders rest on — the key landing on the `ListTile`, the
/// selected chrome, the lock's voice, one live marker per live row and
/// ADR-177's "no face before joining" — are pinned here once.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget row, {
    double width = 320,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: width, child: row),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const key = ValueKey('server-channel-lounge');

  /// What a screen reader would be handed, read off the widget that declares
  /// it — `find.bySemanticsLabel` needs a live semantics tree and the roster's
  /// faces are `ExcludeSemantics` children under one annotated node.
  Finder labelled(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );

  group('YoChannelRow', () {
    testWidgets('the caller key lands on the ListTile itself', (tester) async {
      await pump(
        tester,
        const YoChannelRow(
          tileKey: key,
          label: 'Salon',
          icon: Icons.tag_rounded,
        ),
      );
      final tile = tester.widget<ListTile>(find.byKey(key));
      expect(tile.minTileHeight, 48);
      expect(tile.contentPadding, const EdgeInsets.symmetric(horizontal: 12));
      expect(
        tile.shape,
        const RoundedRectangleBorder(borderRadius: AppRadius.md),
      );
    });

    testWidgets('selection passes the template ink and wash through', (
      tester,
    ) async {
      await pump(
        tester,
        const YoChannelRow(
          tileKey: key,
          label: 'Salon',
          icon: Icons.tag_rounded,
          selected: true,
          selectedForeground: AppColors.primary,
          selectedWash: AppColors.secondary,
        ),
      );
      final tile = tester.widget<ListTile>(find.byKey(key));
      expect(tile.selected, isTrue);
      expect(tile.selectedColor, AppColors.primary);
      expect(tile.selectedTileColor, AppColors.secondary);
    });

    testWidgets('the row draws no Material of its own, so the list surface '
        'is what the wash composites over', (tester) async {
      await pump(
        tester,
        const YoChannelRow(
          tileKey: key,
          label: 'Salon',
          icon: Icons.tag_rounded,
        ),
      );
      expect(
        find.descendant(
          of: find.byType(YoChannelRow),
          matching: find.byType(Material),
        ),
        findsNothing,
      );
    });

    testWidgets('a restricted channel voices its lock', (tester) async {
      await pump(
        tester,
        const YoChannelRow(
          tileKey: key,
          label: 'HR',
          icon: Icons.lock_outline,
          iconSemanticLabel: 'Ograniczony dostęp',
        ),
      );
      final glyph = find.descendant(
        of: find.byKey(key),
        matching: find.byIcon(Icons.lock_outline),
      );
      expect(glyph, findsOneWidget);
      expect(tester.widget<Icon>(glyph).semanticLabel, 'Ograniczony dostęp');
    });

    testWidgets('a null onTap leaves an inert row', (tester) async {
      await pump(
        tester,
        const YoChannelRow(
          tileKey: key,
          label: 'Salon',
          icon: Icons.tag_rounded,
        ),
      );
      expect(tester.widget<ListTile>(find.byKey(key)).onTap, isNull);
      await tester.tap(find.byKey(key));
      expect(tester.takeException(), isNull);
    });
  });

  group('YoVoiceChannelRow', () {
    testWidgets('an idle row says nothing at all: no marker, no clock, '
        'no quiet copy', (tester) async {
      await pump(
        tester,
        YoVoiceChannelRow(
          tileKey: key,
          label: 'Salon',
          icon: Icons.volume_up_outlined,
          onTap: () {},
        ),
      );
      final tile = tester.widget<ListTile>(find.byKey(key));
      expect(tile.trailing, isNull);
      expect(tile.subtitle, isNull);
    });

    testWidgets('a live row carries the caller marker exactly once and the '
        'clock under the name', (tester) async {
      await pump(
        tester,
        YoVoiceChannelRow(
          tileKey: key,
          label: 'Salon',
          icon: Icons.volume_up_outlined,
          liveBadge: const SizedBox(
            key: ValueKey('server-live-pill'),
            width: 40,
            height: 16,
          ),
          liveSince: 'od 19:40',
          onTap: () {},
        ),
      );
      expect(find.byKey(const ValueKey('server-live-pill')), findsOneWidget);
      expect(find.text('od 19:40'), findsOneWidget);
    });

    testWidgets('ADR-177: no face and no count before joining, even when a '
        'roster is handed in', (tester) async {
      await pump(
        tester,
        YoVoiceChannelRow(
          tileKey: key,
          label: 'Salon',
          icon: Icons.volume_up_outlined,
          participants: const [
            YoVoiceRowParticipant(userId: 'u1', displayName: 'Maja'),
            YoVoiceRowParticipant(userId: 'u2', displayName: 'Ola'),
          ],
          onTap: () {},
        ),
      );
      expect(tester.widget<ListTile>(find.byKey(key)).subtitle, isNull);
      expect(labelled('Maja'), findsNothing);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('the connected channel draws the roster, the speaking ring '
        'and the muted microphone', (tester) async {
      await pump(
        tester,
        YoVoiceChannelRow(
          tileKey: key,
          label: 'Salon',
          icon: Icons.volume_up_outlined,
          connected: true,
          connectedLabel: 'połączono',
          participants: const [
            YoVoiceRowParticipant(
              userId: 'u1',
              displayName: 'Maja',
              isSpeaking: true,
              isMicrophoneEnabled: true,
              semanticLabel: 'Maja, mówi',
            ),
            YoVoiceRowParticipant(userId: 'u2', displayName: 'Ola'),
          ],
          onTap: () {},
        ),
      );
      expect(labelled('Maja, mówi'), findsOneWidget);
      expect(labelled('Ola'), findsOneWidget);
      expect(
        tester
            .widget<Icon>(find.byIcon(Icons.graphic_eq_rounded))
            .semanticLabel,
        'połączono',
      );
      expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);
      final rings = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(Container),
            ),
          )
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.shape == BoxShape.circle)
          .map((decoration) => decoration.border?.top.color)
          .toList();
      expect(rings, contains(AppColors.success));
      expect(rings, contains(AppPalette.dark.border));
    });

    testWidgets('more faces than fit collapse into a real overflow count', (
      tester,
    ) async {
      await pump(
        tester,
        YoVoiceChannelRow(
          tileKey: key,
          label: 'Salon',
          icon: Icons.volume_up_outlined,
          connected: true,
          participants: <YoVoiceRowParticipant>[
            for (var i = 0; i < 7; i++)
              YoVoiceRowParticipant(userId: 'u$i', displayName: 'P$i'),
          ],
          onTap: () {},
        ),
      );
      expect(find.text('+3'), findsOneWidget);
    });

    testWidgets('no join control without a join path', (tester) async {
      await pump(
        tester,
        YoVoiceChannelRow(
          tileKey: key,
          label: 'Salon',
          icon: Icons.volume_up_outlined,
          joinLabel: 'Dołącz do rozmowy',
          joinKey: const ValueKey('server-channel-join-lounge'),
          onTap: () {},
        ),
      );
      expect(
        find.byKey(const ValueKey('server-channel-join-lounge')),
        findsNothing,
      );
    });

    testWidgets('the join control keeps its 44 px target and its own key, '
        'never the scene CTA key', (tester) async {
      var joined = 0;
      await pump(
        tester,
        YoVoiceChannelRow(
          tileKey: key,
          label: 'Salon',
          icon: Icons.volume_up_outlined,
          joinLabel: 'Dołącz do rozmowy',
          joinKey: const ValueKey('server-channel-join-lounge'),
          onJoin: () => joined++,
          onTap: () {},
        ),
      );
      final join = find.byKey(const ValueKey('server-channel-join-lounge'));
      expect(join, findsOneWidget);
      expect(find.byKey(const ValueKey('server-join')), findsNothing);
      final size = tester.getSize(join);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      await tester.tap(join);
      expect(joined, 1);
    });

    testWidgets('the row itself only selects: tapping it never joins', (
      tester,
    ) async {
      var joined = 0;
      var selected = 0;
      await pump(
        tester,
        YoVoiceChannelRow(
          tileKey: key,
          label: 'Salon',
          icon: Icons.volume_up_outlined,
          joinLabel: 'Dołącz do rozmowy',
          joinKey: const ValueKey('server-channel-join-lounge'),
          onJoin: () => joined++,
          onTap: () => selected++,
        ),
      );
      await tester.tap(find.byKey(key));
      expect(selected, 1);
      expect(joined, 0);
    });

    testWidgets('the join control steps aside where the name would be left '
        'with two letters', (tester) async {
      Widget row() => YoVoiceChannelRow(
        tileKey: key,
        label: 'Salon',
        icon: Icons.volume_up_outlined,
        joinLabel: 'Dołącz do rozmowy',
        joinKey: const ValueKey('server-channel-join-lounge'),
        onJoin: () {},
        onTap: () {},
      );
      final join = find.byKey(const ValueKey('server-channel-join-lounge'));

      await pump(tester, row(), width: 200);
      expect(join, findsNothing);

      await pump(tester, row(), width: 320, textScale: 2);
      expect(join, findsNothing);

      await pump(tester, row(), width: 240);
      expect(join, findsOneWidget);
    });
  });

  group('YoVoiceChannelRow measure', () {
    const liveKey = ValueKey('server-live-pill');
    const joinKey = ValueKey('server-channel-join-lounge');
    const name = 'Spotkanie zespołu';

    Widget liveRow() => YoVoiceChannelRow(
      tileKey: key,
      label: name,
      icon: Icons.volume_up_outlined,
      liveBadge: const YoBadge(
        key: liveKey,
        label: 'NA ŻYWO',
        variant: YoBadgeVariant.live,
      ),
      liveSince: 'od 19:40',
      joinLabel: 'Dołącz do rozmowy',
      joinKey: joinKey,
      onJoin: () {},
      onTap: () {},
    );

    // 240 / 256: the desktop panel (264 / 280) inside its 12 + 12 list
    // padding; 296: the phone sheet; 340+: where the join control fits too.
    for (final (width, scale) in [
      (240.0, 1.0),
      (256.0, 1.0),
      (296.0, 1.0),
      (340.0, 1.0),
      (420.0, 1.0),
      (296.0, 1.5),
      (420.0, 1.5),
      (296.0, 2.0),
    ]) {
      testWidgets('a live channel keeps a readable name with the marker and '
          'the join path at $width px, ${scale}x', (tester) async {
        await pump(tester, liveRow(), width: width, textScale: scale);
        expect(tester.takeException(), isNull);
        expect(find.byKey(liveKey), findsOneWidget);
        expect(find.text('od 19:40'), findsOneWidget);
        expect(
          tester.getSize(find.text(name)).width,
          greaterThanOrEqualTo(YoVoiceChannelRow.minLabelWidth),
        );
      });
    }

    testWidgets('the join control rides beside a live marker only where both '
        'fit next to the name', (tester) async {
      final join = find.byKey(joinKey);
      await pump(tester, liveRow(), width: 296);
      expect(join, findsNothing);
      await pump(tester, liveRow(), width: 340);
      expect(join, findsOneWidget);
      expect(
        tester.getSize(find.text(name)).width,
        greaterThanOrEqualTo(YoVoiceChannelRow.minLabelWidth),
      );
    });

    Widget connectedRow(int people, {bool speaking = false}) =>
        YoVoiceChannelRow(
          tileKey: key,
          label: 'Salon',
          icon: Icons.volume_up_outlined,
          connected: true,
          connectedLabel: 'połączono',
          participants: <YoVoiceRowParticipant>[
            for (var i = 0; i < people; i++)
              YoVoiceRowParticipant(
                userId: 'u$i',
                displayName: 'P$i',
                isSpeaking: speaking,
                isMicrophoneEnabled: speaking,
              ),
          ],
          onTap: () {},
        );

    int faces(WidgetTester tester) => tester
        .widgetList<Semantics>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.properties.label ?? '').startsWith('P'),
          ),
        )
        .length;

    // 216: the tablet column (240) inside the panel's list padding; 240 /
    // 248: the desktop panel.
    for (final width in [216.0, 240.0, 248.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final speaking in [false, true]) {
          for (final people in [4, 5, 16]) {
            testWidgets('the roster fits $width px at ${scale}x with $people '
                'people${speaking ? ' speaking' : ''}', (tester) async {
              await pump(
                tester,
                connectedRow(people, speaking: speaking),
                width: width,
                textScale: scale,
              );
              expect(tester.takeException(), isNull);
              final shown = faces(tester);
              final hidden = people - shown;
              expect(shown, lessThanOrEqualTo(YoVoiceChannelRow.maxAvatars));
              if (hidden > 0) {
                expect(find.text('+$hidden'), findsOneWidget);
              } else {
                expect(find.textContaining('+'), findsNothing);
              }
            });
          }
        }
      }
    }

    testWidgets('speaking changes the ring colour, never the face size', (
      tester,
    ) async {
      Size face() => tester.getSize(
        find
            .ancestor(
              of: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.label == 'P0',
              ),
              matching: find.byType(Padding),
            )
            .first,
      );
      await pump(tester, connectedRow(2));
      final silent = face();
      await pump(tester, connectedRow(2, speaking: true));
      expect(face(), silent);
    });
  });

  group('keyboard focus', () {
    testWidgets('a focused channel row draws a 2 px focus edge; an '
        'unfocused one keeps its plain shape', (tester) async {
      for (final (theme, palette) in [
        (AppTheme.darkTheme, AppPalette.dark),
        (AppTheme.lightTheme, AppPalette.light),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: YoChannelRow(
                tileKey: key,
                label: 'Salon',
                icon: Icons.tag_rounded,
                onTap: () {},
              ),
            ),
          ),
        );
        expect(
          tester.widget<ListTile>(find.byKey(key)).shape,
          const RoundedRectangleBorder(borderRadius: AppRadius.md),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final shape =
            tester.widget<ListTile>(find.byKey(key)).shape!
                as RoundedRectangleBorder;
        expect(shape.side.color, palette.focus);
        expect(shape.side.width, greaterThanOrEqualTo(2));
        expect(shape.borderRadius, AppRadius.md);
        // Reset focus between themes.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
