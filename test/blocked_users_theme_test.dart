import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/presentation/screens/blocked_users_screen.dart';

void main() {
  const me = 'current-user';
  const blockedUser = 'blocked-user';

  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late FriendService service;

  setUp(() async {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: me));
    service = FriendService(
      firestore: db,
      auth: auth,
      mutationInvoker: (_, __) async => const {'changed': true},
    );
    await db
        .collection('users')
        .doc(me)
        .collection('blocked')
        .doc(blockedUser)
        .set({'blockedAt': DateTime.now()});
    await db.collection('publicProfiles').doc(blockedUser).set({
      'uid': blockedUser,
      'displayName': 'Blocked Person',
    });
  });

  Widget app(ThemeData theme, {TextScaler textScaler = TextScaler.noScaling}) {
    return MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: BlockedUsersScreen(friendService: service),
    );
  }

  testWidgets('blocked-user list follows Pearl and dark semantic palettes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final themeCase in <({ThemeData theme, AppPalette palette})>[
      (theme: AppTheme.lightTheme, palette: AppPalette.light),
      (theme: AppTheme.darkTheme, palette: AppPalette.dark),
    ]) {
      await tester.pumpWidget(app(themeCase.theme));
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(
        find.byKey(const ValueKey('blocked-users-screen')),
      );
      expect(scaffold.backgroundColor, themeCase.palette.background);

      final card = tester.widget<Container>(
        find.byKey(const ValueKey('blocked-user-blocked-user')),
      );
      final decoration = card.decoration! as BoxDecoration;
      expect(decoration.color, themeCase.palette.surface);
      expect(
        (decoration.border! as Border).top.color,
        themeCase.palette.border,
      );

      final name = tester.widget<Text>(find.text('Blocked Person'));
      expect(name.style!.color, themeCase.palette.textPrimary);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Unblock'),
      );
      expect(
        button.style!.foregroundColor!.resolve(<WidgetState>{}),
        themeCase.palette.interactiveForeground,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Pearl blocked row stacks at 320px and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      app(AppTheme.lightTheme, textScaler: const TextScaler.linear(2)),
    );
    await tester.pumpAndSettle();

    final name = find.text('Blocked Person');
    final unblock = find.widgetWithText(OutlinedButton, 'Unblock');
    expect(
      tester.getTopLeft(unblock).dy,
      greaterThan(tester.getTopLeft(name).dy),
    );
    expect(tester.getSize(unblock).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });
}
