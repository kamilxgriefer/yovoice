import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/dev/redesign_preview.dart' as preview;
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';

void main() {
  test('live preview exposes all bundled YO Voice Originals', () async {
    final service = preview.buildRedesignPreviewGifServiceForTesting();
    addTearDown(service.dispose);

    await service.start();

    expect(service.state.status, GifQueryStatus.ready);
    expect(service.state.items, hasLength(16));
    expect(
      service.state.items.every(
        (asset) =>
            asset.provider == 'yovoice' && asset.bundledAssetPath != null,
      ),
      isTrue,
    );
  });

  testWidgets(
    'fixture direct chat reaches the local YO Voice Originals picker',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(preview.buildRedesignPreviewChatsForTesting());
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(MessagesScreen), findsOneWidget);
      await tester.tap(find.text('Masz chwilę na rozmowę?'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(ChatScreen), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('emoji-picker-toggle')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('composer-panel-tab-gif')),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.byKey(const ValueKey<String>('gif-unavailable')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('gif-cell-yoLove01')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'live preview keeps Voice follow and gives Yeels the friend action',
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

      await tester.tap(
        find.byKey(const ValueKey<String>('yo-moments-format-reels')),
      );
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.byKey(const ValueKey<String>('reel-follow-author_1')),
        findsNothing,
      );
      final addFriend = find.byKey(
        const ValueKey<String>('reel-friend-author_1'),
      );
      expect(addFriend, findsOneWidget);
      expect(find.text('Add friend'), findsOneWidget);

      await tester.tap(addFriend);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Requested'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
