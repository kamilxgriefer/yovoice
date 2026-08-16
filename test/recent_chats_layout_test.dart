import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';

Conversation _conversation(int index) {
  const me = 'me';
  final friend = 'friend-$index';
  return Conversation(
    id: 'conversation-$index',
    participantIds: [me, friend],
    participantNames: {
      me: 'Me',
      friend: 'A very long display name for a close friend number $index',
    },
    participantEmails: {me: 'me@example.com', friend: 'friend@example.com'},
    participantPhotoUrls: const {},
    unreadCounts: {me: 123, friend: 0},
    lastMessage:
        'A longer preview that must remain readable at increased text scale.',
    lastMessageType: MessageType.text,
    lastMessageSenderId: friend,
    updatedAt: DateTime(2026, 8, 16),
    createdAt: DateTime(2026, 8, 16),
    archivedBy: const [],
    mutedBy: const [],
  );
}

void main() {
  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    testWidgets('recent chats reflows cleanly at ${width.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: RecentChats(
                snapshot: AsyncSnapshot.withData(ConnectionState.active, [
                  _conversation(0),
                  _conversation(1),
                  _conversation(2),
                ]),
                currentUserId: 'me',
                onOpenConversation: (_) {},
                onFindFriends: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('A very long display name'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('recent chats supports 200% text on a 320 px phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: RecentChats(
                snapshot: AsyncSnapshot.withData(ConnectionState.active, [
                  _conversation(0),
                  _conversation(1),
                  _conversation(2),
                ]),
                currentUserId: 'me',
                onOpenConversation: (_) {},
                onFindFriends: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('A very long display name'), findsNWidgets(3));
    expect(find.text('99+'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
