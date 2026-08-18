import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_chat_sheet.dart';

void main() {
  for (final size in const [Size(320, 620), Size(390, 720), Size(350, 760)]) {
    testWidgets(
      'embedded room chat fits ${size.width.toInt()}px at 200% text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);

        var closed = false;
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
        );
        final service = RoomService(
          firestore: FakeFirebaseFirestore(),
          auth: auth,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(12),
                child: RoomChatPanel(
                  roomId: 'room',
                  isHost: true,
                  accent: const Color(0xFFC026FF),
                  currentUserId: 'me',
                  service: service,
                  onClose: () => closed = true,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 80));

        expect(find.byKey(const ValueKey('room-chat-surface')), findsOneWidget);
        expect(find.text('Room chat'), findsOneWidget);
        expect(find.text('Say something…'), findsOneWidget);
        expect(
          tester.getSize(find.byType(TextField)).height,
          greaterThanOrEqualTo(44),
        );
        await tester.tap(find.byTooltip('Back to stage'));
        expect(closed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
