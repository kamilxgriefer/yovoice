import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/shared/widgets/avatars/yo_avatar.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

void main() {
  testWidgets(
    'AccessibleTapRegion exposes semantics, a 44px target, Enter and Space',
    (tester) async {
      var activations = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AccessibleTapRegion(
                onTap: () => activations += 1,
                semanticLabel: 'Open accessible target',
                tooltip: 'Open target',
                child: const SizedBox(width: 20, height: 20, child: Text('Go')),
              ),
            ),
          ),
        ),
      );

      final region = find.byType(AccessibleTapRegion);
      expect(tester.getSize(region), const Size(44, 44));
      expect(find.bySemanticsLabel('Open accessible target'), findsOneWidget);

      Focus.of(tester.element(find.text('Go'))).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(activations, 2);

      final focusRing = tester.widget<AnimatedContainer>(
        find.descendant(of: region, matching: find.byType(AnimatedContainer)),
      );
      final decoration = focusRing.decoration! as BoxDecoration;
      expect((decoration.border! as Border).top.color, AppPalette.light.focus);
    },
  );

  testWidgets('interactive YoAvatar names and activates the profile action', (
    tester,
  ) async {
    var opens = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: YoAvatar(name: 'Ada', size: 24, onTap: () => opens += 1),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(YoAvatar)), const Size(44, 44));
    expect(find.bySemanticsLabel('Open profile for Ada'), findsOneWidget);
    Focus.of(tester.element(find.text('A'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opens, 1);
  });

  testWidgets('Moment author avatar is a named 44px profile action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MomentCard(
            moment: VoiceMoment(
              id: 'moment',
              authorId: 'author',
              authorName: 'Ada Lovelace',
              authorPhotoUrl: null,
              caption: 'A short voice update',
              audioUrl: null,
              durationSeconds: 12,
              likeCount: 1,
              commentCount: 2,
              isPublished: true,
              createdAt: DateTime(2026, 8, 16),
            ),
            onComments: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final author = find.bySemanticsLabel('Open profile for Ada Lovelace');
    expect(author, findsOneWidget);
    expect(tester.getSize(author).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(author).width, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });
}
