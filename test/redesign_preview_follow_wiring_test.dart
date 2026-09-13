import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/dev/redesign_preview.dart' as preview;
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_follow_panel.dart';

void main() {
  testWidgets(
    'live preview keeps its signed-in follow fixture from Voice into Reels',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(preview.buildRedesignPreviewForTesting());
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final moments = tester.widget<MomentsScreen>(find.byType(MomentsScreen));
      expect(moments.friendService, isNotNull);
      expect(moments.followService, isNotNull);
      expect(moments.creatorAudienceService, isNotNull);

      await tester.tap(
        find.byKey(const ValueKey<String>('yo-moments-format-reels')),
      );
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final followButtons = find.byType(MomentsFollowButton);
      expect(followButtons, findsWidgets);
      expect(
        tester
            .widgetList<MomentsFollowButton>(followButtons)
            .every((button) => button.viewerUid == 'preview-me'),
        isTrue,
      );
      final renderedFollow = find.descendant(
        of: find.byKey(const ValueKey<String>('reel-follow-author_1')),
        matching: find.byType(OutlinedButton),
      );
      expect(renderedFollow, findsOneWidget);

      await tester.tap(renderedFollow);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Following'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
