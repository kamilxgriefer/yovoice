import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';

Message _message() => Message(
  id: 'm1',
  conversationId: 'c1',
  senderId: 'friend',
  type: MessageType.text,
  content: 'Hello from a friend',
  sentAt: DateTime(2026, 8, 16, 12),
  readBy: const [],
  reactions: const {},
);

void main() {
  testWidgets('message actions open from keyboard, screen reader and mouse', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var opens = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: MessageBubble(
              message: _message(),
              currentUserId: 'me',
              onLongPress: () => opens += 1,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.bySemanticsLabel('Open actions for this message'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Hello from a friend')),
      findsOneWidget,
    );

    final content = find.text('Hello from a friend');
    Focus.of(tester.element(content)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opens, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(opens, 2);

    await tester.tap(content, buttons: kSecondaryMouseButton);
    expect(opens, 3);

    await tester.longPress(content);
    expect(opens, 4);
  });
}
