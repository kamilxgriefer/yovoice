import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

Future<FocusNode> _openPreview(
  WidgetTester tester, {
  required Size size,
  TextScaler textScaler = TextScaler.noScaling,
  ThemeData? theme,
  FriendMutationInvoker? friendMutationInvoker,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final firestore = FakeFirebaseFirestore();
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
  );
  await firestore.collection('users').doc('me').set({
    'uid': 'me',
    'displayName': 'Me',
  });
  await firestore.collection('publicProfiles').doc('creator').set({
    'uid': 'creator',
    'displayName': 'Maya Voice With A Deliberately Long Creator Name',
    'username': 'mayavoice',
    'bio':
        'Independent interviews, culture, music, design and thoughtful '
        'conversations from communities around the world.',
    'statusMessage': 'Recording a new long-form conversation this week.',
    'accountType': 'creator',
    'premiumIdentity': true,
    'isOnline': true,
    'followerCount': 1842,
  });

  final launcherFocus = FocusNode(debugLabel: 'profile-preview-launcher');
  addTearDown(launcherFocus.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              focusNode: launcherFocus,
              onPressed: () => unawaited(
                showProfilePreview(
                  context,
                  userId: 'creator',
                  displayName: 'Maya Voice',
                  firestore: firestore,
                  auth: auth,
                  friendService: friendMutationInvoker == null
                      ? null
                      : FriendService(
                          firestore: firestore,
                          auth: auth,
                          mutationInvoker: friendMutationInvoker,
                        ),
                ),
              ),
              child: const Text('Open profile preview'),
            ),
          ),
        ),
      ),
    ),
  );

  launcherFocus.requestFocus();
  await tester.pump();
  await tester.tap(find.text('Open profile preview'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return launcherFocus;
}

void main() {
  for (final size in const <Size>[
    Size(320, 640),
    Size(390, 844),
    Size(430, 900),
    Size(768, 900),
    Size(1100, 900),
    Size(1440, 900),
    Size(2560, 1440),
  ]) {
    testWidgets('profile preview stays reachable at 200% and ${size.width}', (
      tester,
    ) async {
      await _openPreview(
        tester,
        size: size,
        textScaler: const TextScaler.linear(2),
      );

      expect(find.byType(ProfilePreviewSheet), findsOneWidget);
      final close = find.bySemanticsLabel('Close profile preview');
      expect(close, findsOneWidget);
      expect(
        find.byKey(const ValueKey('modal-sheet-drag-handle')),
        size.width < 1100 ? findsOneWidget : findsNothing,
      );
      final closeTopBefore = tester.getTopLeft(close).dy;

      final fullProfile = find.text('View full profile');
      await tester.ensureVisible(fullProfile);
      await tester.pump(const Duration(milliseconds: 300));

      final fullProfileRect = tester.getRect(fullProfile);
      expect(fullProfileRect.top, greaterThanOrEqualTo(0));
      expect(fullProfileRect.bottom, lessThanOrEqualTo(size.height));
      expect(tester.getTopLeft(close).dy, closeTo(closeTopBefore, .1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Close dismisses profile preview and restores launcher focus', (
    tester,
  ) async {
    final launcherFocus = await _openPreview(
      tester,
      size: const Size(390, 844),
      theme: AppTheme.lightTheme,
    );

    await tester.tap(find.bySemanticsLabel('Close profile preview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ProfilePreviewSheet), findsNothing);
    expect(launcherFocus.hasFocus, isTrue);
  });

  testWidgets('reciprocal request immediately renders Friends, not Requested', (
    tester,
  ) async {
    final calls = <({String name, Map<String, dynamic> data})>[];
    await _openPreview(
      tester,
      size: const Size(390, 844),
      friendMutationInvoker: (name, data) async {
        calls.add((name: name, data: data));
        return const <String, dynamic>{'changed': true, 'outcome': 'accepted'};
      },
    );

    final addFriend = find.text('Add friend');
    await tester.ensureVisible(addFriend);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(addFriend);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls, hasLength(1));
    expect(calls.single.name, 'sendFriendRequest');
    expect(calls.single.data, {'targetUserId': 'creator'});
    expect(find.text('Friends'), findsWidgets);
    expect(find.text('Requested'), findsNothing);
  });
}
