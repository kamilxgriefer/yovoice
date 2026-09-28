// The comment heart of owner variant B, on its own (ADR-230): on/off is the
// node's toggled state as well as the verb; keyboard focus is a 2 px
// palette.focus ring on the heart and on the count; the VIP count's spoken
// name starts with the words it shows; the glyph grows with the text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/likers/data/models/comment_like.dart';
import 'package:yovoice/features/likers/presentation/widgets/comment_like_controls.dart';

import 'support/likers_fixtures.dart';

const _heart = ValueKey('moment-comment-like-c1');
const _heartRing = ValueKey('moment-comment-like-focus-c1');
const _count = ValueKey('moment-comment-likers-c1');

void main() {
  Future<void> pumpControls(
    WidgetTester tester, {
    required CommentLikeState state,
    bool showWhoLiked = false,
    double textScale = 1,
    VoidCallback? onToggle,
  }) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      likersHost(
        Scaffold(
          body: Center(
            child: CommentLikeControls(
              commentId: 'c1',
              keyPrefix: 'moment-comment',
              state: state,
              onToggle: onToggle ?? () {},
              onShowLikers: (_) {},
              showWhoLiked: showWhoLiked,
            ),
          ),
        ),
        textScale: textScale,
      ),
    );
    await tester.pump();
  }

  AppPalette paletteOf(WidgetTester tester) =>
      tester.element(find.byKey(_heart)).appPalette;

  testWidgets('the heart reports on/off as toggled state', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpControls(
      tester,
      state: const CommentLikeState(likeCount: 3, callerLiked: false),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Like comment. Likes: 3')),
      isSemantics(
        isButton: true,
        hasTapAction: true,
        hasToggledState: true,
        isToggled: false,
      ),
    );
    await pumpControls(
      tester,
      state: const CommentLikeState(likeCount: 4, callerLiked: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Unlike comment. Likes: 4')),
      isSemantics(hasToggledState: true, isToggled: true),
    );
    semantics.dispose();
  });

  testWidgets('keyboard focus rings the heart and the count in 2 px '
      'palette.focus', (tester) async {
    await pumpControls(
      tester,
      state: const CommentLikeState(likeCount: 3, callerLiked: false),
    );
    final palette = paletteOf(tester);

    BoxDecoration ring() =>
        tester.widget<Container>(find.byKey(_heartRing)).foregroundDecoration!
            as BoxDecoration;

    expect(ring().border, isNull);
    Focus.of(tester.element(find.byKey(_heartRing))).requestFocus();
    await tester.pumpAndSettle();
    final heart = ring().border! as Border;
    expect(heart.top.color, palette.focus);
    expect(heart.top.width, 2);

    BorderSide countSide() {
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byKey(_count),
          matching: find.byType(Material),
        ),
      );
      return (material.shape! as OutlinedBorder).side;
    }

    expect(countSide().style, BorderStyle.none);
    Focus.of(
      tester.element(
        find.descendant(of: find.byKey(_count), matching: find.text('3')),
      ),
    ).requestFocus();
    await tester.pumpAndSettle();
    expect(countSide().color, palette.focus);
    expect(countSide().width, 2);
    expect(ring().border, isNull);
  });

  testWidgets('the VIP count is named by what it shows first', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpControls(
      tester,
      state: const CommentLikeState(likeCount: 3, callerLiked: false),
      showWhoLiked: true,
    );
    expect(find.text('Who liked'), findsOneWidget);
    expect(find.bySemanticsLabel('Who liked. Likes: 3'), findsOneWidget);
    expect(find.bySemanticsLabel('See who liked. Likes: 3'), findsNothing);

    await pumpControls(
      tester,
      state: const CommentLikeState(likeCount: 3, callerLiked: false),
    );
    expect(find.bySemanticsLabel('See who liked. Likes: 3'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the glyph grows with the text, up to 1.5x, inside a 44 px '
      'target', (tester) async {
    await pumpControls(
      tester,
      state: const CommentLikeState(likeCount: 3, callerLiked: false),
      textScale: 2,
    );
    final icon = tester.widget<Icon>(
      find.descendant(of: find.byKey(_heart), matching: find.byType(Icon)),
    );
    expect(icon.size, closeTo(19 * 1.5, .01));
    expect(tester.getSize(find.byKey(_heartRing)).width, 44);
    expect(tester.takeException(), isNull);

    await pumpControls(
      tester,
      state: const CommentLikeState(likeCount: 3, callerLiked: false),
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(_heart),
              matching: find.byType(Icon),
            ),
          )
          .size,
      19,
    );
  });
}
