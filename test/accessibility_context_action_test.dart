import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_context_action.dart';

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

  testWidgets(
    'a tooltip inside the context action yields the touch long-press and '
    'still shows on hover',
    (tester) async {
      // A Tooltip registers its own LongPressGestureRecognizer on every
      // touch pointer-down. Nested inside the action it sits deeper in the
      // hit-test path, so its deadline fires first and wins the arena — the
      // owner saw the photo bubble's "View photo" hint instead of message
      // reactions. The action must keep the long-press; hover keeps the hint.
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AccessibleContextAction(
                onOpen: () => opens += 1,
                child: const Tooltip(
                  message: 'View photo',
                  child: SizedBox(width: 120, height: 80, child: Text('Photo')),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.longPress(find.text('Photo'));
      await tester.pump();
      expect(
        opens,
        1,
        reason:
            'the enclosing action, not the tooltip, owns a touch long-press',
      );
      expect(find.text('View photo'), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Photo')));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('View photo'),
        findsOneWidget,
        reason: 'a mouse still gets the hint on hover',
      );
      expect(opens, 1);
    },
  );

  group('the context action draws one focus ring', () {
    void traditionalFocus() {
      final strategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
    }

    /// The action's own ring: the last overlay it paints over its child.
    Border ring(WidgetTester tester) {
      final overlay = find
          .descendant(
            of: find.byType(AccessibleContextAction),
            matching: find.byType(IgnorePointer),
          )
          .last;
      final box = tester.widget<AnimatedContainer>(
        find.descendant(of: overlay, matching: find.byType(AnimatedContainer)),
      );
      return (box.decoration! as BoxDecoration).border! as Border;
    }

    testWidgets('a focused child keeps its own ring; the action rings only '
        'when it is focused itself', (tester) async {
      traditionalFocus();
      final theme = ThemeData.dark();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AccessibleContextAction(
                onOpen: () {},
                child: SizedBox(
                  width: 240,
                  height: 96,
                  child: Column(
                    children: [
                      const Text('A voice message'),
                      TextButton(onPressed: () {}, child: const Text('Play')),
                    ],
                  ),
                ),
              ),
            ),
          ),
          theme: theme,
        ),
      );
      final focus = tester
          .element(find.text('A voice message'))
          .appPalette
          .focus;
      expect(ring(tester).top.color, Colors.transparent);

      // The action itself: its ring.
      Focus.of(tester.element(find.text('A voice message'))).requestFocus();
      await tester.pumpAndSettle();
      expect(ring(tester).top.color, focus);
      expect(ring(tester).top.width, 2);

      // A focusable child inside it: the child's own indicator alone.
      Focus.of(tester.element(find.text('Play'))).requestFocus();
      await tester.pumpAndSettle();
      expect(
        Focus.of(tester.element(find.text('Play'))).hasPrimaryFocus,
        isTrue,
      );
      expect(ring(tester).top.color, isNot(focus));
      expect(ring(tester).top.width, 1);
    });

    for (final (sender, name) in const [
      ('friend', 'incoming'),
      ('me', 'outgoing'),
    ]) {
      testWidgets('a $name bubble is ringed where the message is, not around '
          'its 48 px gutter', (tester) async {
        traditionalFocus();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: Message(
                  id: 'm1',
                  conversationId: 'c1',
                  senderId: sender,
                  type: MessageType.text,
                  content: 'Hello from a friend',
                  sentAt: DateTime(2026, 8, 16, 12),
                  readBy: const [],
                  reactions: const {},
                ),
                currentUserId: 'me',
                onLongPress: () {},
              ),
            ),
          ),
        );
        Focus.of(
          tester.element(find.text('Hello from a friend')),
        ).requestFocus();
        await tester.pumpAndSettle();
        final overlay = find
            .descendant(
              of: find.byType(AccessibleContextAction),
              matching: find.byType(IgnorePointer),
            )
            .last;
        final ringRect = tester.getRect(
          find.descendant(
            of: overlay,
            matching: find.byType(AnimatedContainer),
          ),
        );
        final action = tester.getRect(find.byType(AccessibleContextAction));
        final message = tester.getRect(
          find
              .descendant(
                of: find.byType(AccessibleContextAction),
                matching: find.byType(Column),
              )
              .first,
        );
        expect(ring(tester).top.width, 2, reason: 'the bubble is focused');
        expect(ringRect, message, reason: 'the ring hugs the message');
        expect(action.width - ringRect.width, 48, reason: 'not the gutter');
      });
    }
  });
}
