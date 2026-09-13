import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/dev/redesign_preview.dart' as preview;
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/create_server_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';

void main() {
  for (final width in <double>[1280, 1440]) {
    testWidgets(
      'preview uses the current desktop destinations at ${width.toInt()} px',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(preview.buildRedesignPreviewForTesting());
        await _pumpFixture(tester);

        expect(find.byType(DesktopSidebar), findsOneWidget);
        expect(find.byType(MomentsScreen), findsOneWidget);
        expect(find.text('Yeels'), findsOneWidget);
        expect(find.text('Reels'), findsNothing);
        expect(tester.takeException(), isNull);

        await _selectRailDestination(tester, 'Home');
        expect(find.byType(DesktopHome), findsOneWidget);
        expect(find.byType(MobileHome), findsNothing);
        expect(
          find.byKey(const ValueKey('desktop-home-server-first')),
          findsOneWidget,
        );
        expect(find.text('Rooms'), findsNothing);
        expect(tester.takeException(), isNull);

        await _selectRailDestination(tester, 'Servers');
        expect(find.byType(ServersScreen), findsOneWidget);
        expect(find.byType(CreateServerScreen), findsNothing);
        expect(
          find.byKey(const ValueKey('server-directory-preview-friends')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('server-directory-preview-podcast')),
          findsOneWidget,
        );
        expect(find.text('Clubs'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const ValueKey('servers-create')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(CreateServerScreen), findsOneWidget);
        expect(
          find.byKey(const ValueKey('server-template-friends')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('server-template-podcast')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        Navigator.of(
          tester.element(find.byType(CreateServerScreen)),
        ).pop<void>();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        await _selectRailDestination(tester, 'Chats');
        expect(find.byType(MessagesScreen), findsOneWidget);
        expect(
          find.byKey(const ValueKey('messages-add-friend')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const ValueKey('messages-add-friend')));
        await tester.pump();
        expect(find.byType(FriendsScreen), findsOneWidget);
        expect(find.text('Friends'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _selectRailDestination(tester, 'Moments');
        // The fixture's discovery load has a deliberate 600 ms latency. Let
        // that bounded request finish before unmounting so this test also
        // proves the destination can become visible without orphaning work.
        await tester.pump(const Duration(milliseconds: 700));
        expect(find.byType(MomentsScreen), findsOneWidget);
        expect(find.text('Yeels'), findsOneWidget);
        expect(find.text('Reels'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}

Future<void> _pumpFixture(WidgetTester tester) async {
  for (var index = 0; index < 12; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _selectRailDestination(WidgetTester tester, String label) async {
  final destination = find.descendant(
    of: find.byType(DesktopSidebar),
    matching: find.text(label),
  );
  expect(destination, findsOneWidget);
  await tester.tap(destination);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}
