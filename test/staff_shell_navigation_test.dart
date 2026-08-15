// The navigation contract this repo broke once: every More destination
// opens inside the SAME desktop content viewport — Staff Center
// included — and the staff screens adapt their chrome to how they were
// opened instead of shifting the shell.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/screens/staff_center_screen.dart';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

class _FakeCapabilities extends StaffCapabilityService {
  _FakeCapabilities(this.capabilities);
  final StaffCapabilities capabilities;
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async => capabilities;
}

void useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

({ModerationService service, FakeFirebaseFirestore db}) _staffModeration() {
  final db = FakeFirebaseFirestore();
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'mod-uid', customClaim: const {'role': 'moderator'}),
  );
  db.collection('users').doc('mod-uid').set({'role': 'moderator'});
  return (service: ModerationService(firestore: db, auth: auth), db: db);
}

void main() {
  group('desktop slot contract', () {
    test('every More destination except friends and profile owns a slot — '
        'Staff Center may never fall back to a pushed route again', () {
      final slotted = MainShell.desktopSlots.values.toSet();
      final expected = MoreDestination.values.toSet().difference({
        // Primary tab index 2 — the rail selects it directly.
        MoreDestination.friends,
        // Pushes on purpose: it keeps a real Back button.
        MoreDestination.profile,
      });
      expect(slotted, expected);
      // Slot indices are unique and contiguous above the three shared
      // tabs, so the IndexedStack cannot alias two destinations.
      expect(
        MainShell.desktopSlots.keys.toList()..sort(),
        List.generate(MainShell.desktopSlots.length, (i) => i + 3),
      );
    });
  });

  group('slot rendering (desktop content viewport)', () {
    testWidgets('Staff Center in the slot draws NO app bar and shows its '
        'context label — the shell keeps the chrome', (tester) async {
      useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: StaffCenterScreen(
            isRootTab: true,
            capabilityService: _FakeCapabilities(
              const StaffCapabilities(
                staffRole: 'superAdmin',
                isOwner: true,
                manageRoles: true,
                fullAuditAccess: true,
              ),
            ),
            currentUid: 'owner-uid',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(find.text('Staff tools / Staff Center'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Moderation in the slot draws NO app bar and shows its '
        'breadcrumb header', (tester) async {
      useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: ModerationCenterScreen(
            isRootTab: true,
            moderationService: _staffModeration().service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Staff tools / Moderation'), findsOneWidget);
      expect(find.text('Review community reports and take action.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('pushed rendering (mobile route)', () {
    testWidgets('pushed Staff Center carries Back and Home — never a dead '
        'end', (tester) async {
      useSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => StaffCenterScreen(
                        capabilityService: _FakeCapabilities(
                          StaffCapabilities.none,
                        ),
                        currentUid: 'x',
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byTooltip('Home'), findsOneWidget);

      // Back returns to the actual previous screen.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pushed Moderation carries Back, the shield title, the '
        'human role badge and Home', (tester) async {
      useSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ModerationCenterScreen(
                        moderationService: _staffModeration().service,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byTooltip('Home'), findsOneWidget);
      expect(find.text('Moderation'), findsOneWidget);
      expect(find.text('Moderator'), findsOneWidget);
      expect(find.text('moderator'), findsNothing,
          reason: 'internal claim names never reach the interface');

      // Home pops to the first route.
      await tester.tap(find.byTooltip('Home'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone Moderation is single-column: selecting a report '
        'swaps to detail and its Back returns to the queue', (tester) async {
      useSize(tester, const Size(390, 844));
      final harness = _staffModeration();
      await harness.db.collection('reports').doc('r1').set({
        'status': 'open',
        'targetType': 'globalMessage',
        'targetId': 'm1',
        'reportedUserId': 'u1',
        'reporterId': 'u2',
        'reason': 'spam',
        'note': 'context here',
        'createdAt': DateTime.now(),
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ModerationCenterScreen(moderationService: harness.service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Spam or scam'), findsOneWidget);
      await tester.tap(find.text('Spam or scam'));
      await tester.pumpAndSettle();

      // Detail took over the single pane, with its own way back.
      expect(find.text('context here'), findsWidgets);
      expect(find.byTooltip('Back to the queue'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to the queue'));
      await tester.pumpAndSettle();
      expect(find.text('Spam or scam'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
