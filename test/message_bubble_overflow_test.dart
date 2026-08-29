import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
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
  ThemeData? theme,
  String currentUserId = 'other',
}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: Scaffold(
        body: MessageBubble(
          message: message,
          currentUserId: currentUserId,
          onLongPress: () {},
        ),
      ),
    ),
  );
}

void main() {
  for (final entry in <String, ThemeData>{
    'dark': AppTheme.darkTheme,
    'light': AppTheme.lightTheme,
  }.entries) {
    testWidgets('${entry.key} incoming bubble uses paired semantic colours', (
      tester,
    ) async {
      await _pump(
        tester,
        _textMessage('Readable incoming message'),
        theme: entry.value,
      );

      final palette = entry.value.extension<AppPalette>()!;
      final bubble = tester.widget<Container>(
        find.byKey(const ValueKey('incoming-message-bubble')),
      );
      final decoration = bubble.decoration! as BoxDecoration;
      final text = tester.widget<Text>(find.text('Readable incoming message'));
      expect(decoration.color, palette.surfaceRaised);
      expect(text.style?.color, palette.textPrimary);
    });
  }

  testWidgets(
    'light outgoing bubble preserves the brand gradient and white copy',
    (tester) async {
      await _pump(
        tester,
        _textMessage('Outgoing message'),
        theme: AppTheme.lightTheme,
        currentUserId: 'sender',
      );

      final bubble = tester.widget<Container>(
        find.byKey(const ValueKey('outgoing-message-bubble')),
      );
      final decoration = bubble.decoration! as BoxDecoration;
      final text = tester.widget<Text>(find.text('Outgoing message'));
      expect(decoration.gradient, isA<LinearGradient>());
      expect(decoration.color, isNull);
      expect(text.style?.color, Colors.white);
    },
  );

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
