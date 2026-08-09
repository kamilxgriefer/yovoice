import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_plans_screen.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/widgets/recent_room_messages.dart';

/// Responsive matrix (320 → 1440) for the mockup-pass Premium surfaces
/// and the shared stage message overlay: the REAL screens, pumped at
/// every width in the device matrix, must lay out without overflow
/// exceptions and keep their core content present. This is the
/// repo-established pattern (see profile_header_layout_test.dart) for
/// responsive verification of signed-in surfaces that no headless
/// browser can reach.
const sizes = <Size>[
  Size(320, 568),
  Size(375, 667),
  Size(390, 844),
  Size(430, 932),
  Size(768, 1024),
  Size(1024, 768),
  Size(1440, 900),
];

const _uid = 'matrix-user';

MockFirebaseAuth _auth() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: _uid, email: 'matrix@yovoice.app'),
);

void main() {
  setUp(() {
    EntitlementService.resetCache();
    ProfileService.resetCurrentProfileCache();
  });
  tearDown(() {
    EntitlementService.resetCache();
    ProfileService.resetCurrentProfileCache();
  });

  for (final size in sizes) {
    testWidgets(
      'Premium presentation lays out cleanly at '
      '${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final db = FakeFirebaseFirestore();
        final auth = _auth();
        await tester.pumpWidget(
          MaterialApp(
            home: PremiumScreen(
              entitlementService: EntitlementService(
                firestore: db,
                auth: auth,
              ),
              profileService: ProfileService(firestore: db, auth: auth),
            ),
          ),
        );
        // Fixed pumps only — the premium hero ring animates forever.
        await tester.pump(const Duration(milliseconds: 80));

        expect(find.text('More room\nfor your voice.'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Check plans'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        expect(find.text('Check plans'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Plans screen lays out cleanly at '
      '${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final db = FakeFirebaseFirestore();
        await tester.pumpWidget(
          MaterialApp(
            home: PremiumPlansScreen(
              entitlementService: EntitlementService(
                firestore: db,
                auth: _auth(),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 80));

        expect(find.text('€9.99'), findsOneWidget);
        expect(find.text('€89.99'), findsOneWidget);
        expect(find.text('Best value'), findsOneWidget);
        // Force the full lazy list to lay out — overflow below the fold
        // must fail the matrix too.
        await tester.scrollUntilVisible(
          find.text('Restore purchases'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        expect(find.text('Everything Premium includes:'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'stage message overlay ellipsizes a long message at 320 wide '
    'instead of overflowing',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final db = FakeFirebaseFirestore();
      await db.collection('rooms').doc('room-1').collection('messages').add({
        'senderId': 'other',
        'senderName': 'Someone',
        'senderPhotoUrl': null,
        'text':
            'an extremely long room message that could never fit on one '
            'line of a narrow phone and must be ellipsized cleanly',
        'createdAt': Timestamp.now(),
        'reactions': <String, List<String>>{},
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecentRoomMessages(
              roomId: 'room-1',
              service: RoomService(firestore: db, auth: _auth()),
              onOpenChat: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.byType(RecentRoomMessages), findsOneWidget);
      expect(find.textContaining('extremely long room message'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
