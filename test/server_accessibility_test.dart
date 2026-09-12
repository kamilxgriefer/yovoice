import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_create_channel_sheet.dart';

import 'server_independent_qa_support.dart';
import 'server_test_support.dart';

/// The accessibility contract of the controls a live conversation depends on.
///
/// The dock and the round controls declare `button`, a name and an enabled
/// state on an outer `Semantics` and then exclude the `IconButton` under it.
/// Excluding it also removes `SemanticsAction.tap`, which is the only thing a
/// screen reader on the web build, Android Switch Access (which scans
/// *clickable* nodes) and Voice Access / Voice Control can press. Every one of
/// these assertions therefore checks the ACTION, not just the label — a
/// correct name on an unpressable node is the defect.
void main() {
  Future<FakeServerMediaLink> joinFriends(
    WidgetTester tester,
    FakeServerMediaConnector c,
  ) => qaJoinAndSettle(tester, c, roster: qaRoster);

  /// The control's OWN semantics node.
  ///
  /// `getSemantics` walks up from the widget to the nearest enclosing node, and
  /// the keyed `_DockControl` / `ServerRoundControl` wrappers are not
  /// themselves nodes — the dock's own `container: true` wrapper above them is.
  /// Starting from the `IconButton` (which `excludeSemantics` leaves without a
  /// node of its own) lands on exactly the node the control publishes.
  Finder glyph(String key) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(IconButton),
  );

  SemanticsData dataOf(WidgetTester tester, String key) =>
      tester.getSemantics(glyph(key)).getSemanticsData();

  group('a live conversation can be driven by assistive technology', () {
    testWidgets('every dock control carries a real tap action', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final handle = tester.ensureSemantics();
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.company)]
        ..channels = qaChannels(ServerType.company)
        ..permittedTrackSources = const [
          'microphone',
          'camera',
          'screen_share',
        ];
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'meeting', connector: connector),
        size: const Size(1440, 900),
      );
      await joinFriends(tester, connector);

      for (final key in const [
        'server-dock-microphone',
        'server-dock-headphones',
        'server-dock-leave',
      ]) {
        final node = dataOf(tester, key);
        expect(
          node.hasAction(ui.SemanticsAction.tap),
          isTrue,
          reason: '$key is a button nothing can press',
        );
        expect(node.label, isNotEmpty, reason: '$key has no name');
      }
      // The camera is deliberately unavailable: it must still be announced,
      // and it must still say so rather than being silently absent.
      final camera = dataOf(tester, 'server-dock-camera');
      expect(camera.label, contains('—'));
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: find.byKey(const ValueKey('server-dock-camera')),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      handle.dispose();
    });

    testWidgets('activating the dock leave control through the accessibility '
        'API really leaves', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final handle = tester.ensureSemantics();
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'lounge', connector: connector),
        size: const Size(1440, 900),
      );
      final link = await joinFriends(tester, connector);
      expect(qaDock, findsOneWidget);

      final leave = tester.getSemantics(glyph('server-dock-leave'));
      leave.owner!.performAction(leave.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(link.disconnects, 1, reason: 'the API press did nothing');
      expect(qaDock, findsNothing);
      handle.dispose();
    });

    testWidgets('the round controls of the Salon boards are pressable too', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final handle = tester.ensureSemantics();
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'lounge', connector: connector),
        size: const Size(1440, 900),
      );
      final link = await joinFriends(tester, connector);

      for (final key in const [
        'server-session-microphone',
        'server-session-headphones',
        'server-session-leave',
      ]) {
        final node = dataOf(tester, key);
        expect(
          node.hasAction(ui.SemanticsAction.tap),
          isTrue,
          reason: '$key is a button nothing can press',
        );
      }
      final mic = tester.getSemantics(glyph('server-session-microphone'));
      mic.owner!.performAction(mic.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(link.microphoneCalls, [true]);
      handle.dispose();
    });
  });

  group('a focus ring that can be seen on an identity fill', () {
    /// WCAG 1.4.11 asks 3:1 of a focus indicator. `docs/UI.md` promises it by
    /// painting the control's own on-colour; the slice used to leave `side`
    /// unset and inherit a theme ring measured against a different fill.
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return la > lb ? (la + .05) / (lb + .05) : (lb + .05) / (la + .05);
    }

    testWidgets('the dock and round controls ring in their own ink', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'lounge', connector: connector),
        size: const Size(1440, 900),
      );
      await joinFriends(tester, connector);

      for (final key in const [
        'server-dock-leave',
        'server-dock-microphone',
        'server-session-leave',
      ]) {
        final button = tester.widget<IconButton>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(IconButton),
          ),
        );
        const focused = <WidgetState>{WidgetState.focused};
        final side = button.style!.side!.resolve(focused);
        final fill = button.style!.backgroundColor!.resolve(focused)!;
        expect(side, isNotNull, reason: '$key has no focus ring of its own');
        expect(
          contrast(side!.color, fill),
          greaterThanOrEqualTo(3),
          reason: '$key rings at ${contrast(side.color, fill)}:1 on its fill',
        );
        expect(
          button.style!.side!.resolve(const <WidgetState>{}),
          isNull,
          reason: '$key paints a border when it is not focused',
        );
      }
    });

    testWidgets('the hang-up glyph clears 3:1 on the danger fill', (
      tester,
    ) async {
      // `AppColors.white` on `AppColors.error` is 2.95:1, and on a phone this
      // control draws no text at all.
      expect(
        contrast(AppColors.contrastInk, AppColors.error),
        greaterThanOrEqualTo(3),
      );
      expect(contrast(AppColors.white, AppColors.error), lessThan(3));
    });

    testWidgets('every template CTA rings in its own on-colour', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final type in ServerType.values) {
        final repository = TestServerRepository()
          ..servers = [qaServer(type)]
          ..channels = qaChannels(type);
        await pumpServers(
          tester,
          qaWorkspace(repository, channelId: qaJoinableChannel(type)),
          size: const Size(1440, 900),
        );
        final joins = qaJoin.evaluate();
        if (joins.isEmpty) continue;
        final button = tester.widget<FilledButton>(qaJoin);
        const focused = <WidgetState>{WidgetState.focused};
        final side = button.style!.side!.resolve(focused);
        final fill = button.style!.backgroundColor!.resolve(focused)!;
        expect(side, isNotNull, reason: '$type CTA has no ring');
        expect(
          contrast(side!.color, fill),
          greaterThanOrEqualTo(3),
          reason: '$type CTA rings at ${contrast(side.color, fill)}:1',
        );
      }
    });
  });

  group('the channel-name field is named and its error is attached', () {
    testWidgets('the editable node carries the visible label', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final handle = tester.ensureSemantics();
      final repository = TestServerRepository();
      await pumpServers(
        tester,
        Scaffold(
          body: ServerCreateChannelSheet(
            server: qaServer(ServerType.company),
            repository: repository,
            role: ServerMemberRole.owner,
          ),
        ),
        size: const Size(390, 844),
      );
      final field = find.byKey(const ValueKey('server-channel-name'));
      expect(
        tester.getSemantics(field).label,
        contains('Nazwa kanału'),
        reason: 'the input has no accessible name',
      );

      await tester.tap(find.byKey(const ValueKey('server-channel-submit')));
      await tester.pumpAndSettle();
      // The message is attached to the field, not printed under the chips.
      final data = tester.getSemantics(field);
      expect(data.label + data.value + data.hint, contains('nazw'));
      expect(repository.calls, isEmpty);
      handle.dispose();
    });
  });
}
