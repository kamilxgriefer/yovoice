import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';

Message _textMessage(String content) {
  return Message(
    id: 'm1',
    conversationId: 'c1',
    senderId: 'sender',
    type: MessageType.text,
    content: content,
    sentAt: DateTime.now(),
    readBy: const [],
    reactions: const {},
  );
}

Future<void> _pump(
  WidgetTester tester,
  Message message, {
  double width = 360,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: message,
          currentUserId: 'other',
          onLongPress: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('long URL with no whitespace does not overflow the bubble', (
    tester,
  ) async {
    final url =
        'https://example.com/a-very-long-path-segment-that-keeps-going-and-going-and-going-with-no-spaces-anywhere-at-all-1234567890abcdefghijklmnopqrstuvwxyz';
    await _pump(tester, _textMessage(url));

    expect(tester.takeException(), isNull);
  });

  testWidgets('long unbroken UUID/token chain does not overflow', (
    tester,
  ) async {
    final token = List.generate(
      8,
      (_) => '550e8400e29b41d4a716446655440000',
    ).join();
    await _pump(tester, _textMessage(token));

    expect(tester.takeException(), isNull);
  });

  testWidgets('150+ char unbroken alpha run does not overflow', (tester) async {
    final run = 'a' * 180;
    await _pump(tester, _textMessage(run));

    expect(tester.takeException(), isNull);
  });

  testWidgets('long mixed unicode run does not overflow', (tester) async {
    final unicode = ('🔥💜🎙️️️️✨🌌' * 40) + ('あ' * 100);
    await _pump(tester, _textMessage(unicode));

    expect(tester.takeException(), isNull);
  });

  testWidgets('long unbroken run on a small phone width does not overflow', (
    tester,
  ) async {
    final run = 'x' * 200;
    await _pump(tester, _textMessage(run), width: 320);

    expect(tester.takeException(), isNull);
  });
}
