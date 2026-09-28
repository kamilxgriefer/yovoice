// The Voice comment action line of owner render B, "Odpowiedz · ♡ 3 ⚑"
// (ADR-230): the separator dot is drawn exactly while "Reply" and the heart
// share a row, at every width; after a bare count the report flag's glyph
// sits as close as in the render while its target stays 48 px.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/likers/data/models/comment_like.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_conversation_thread.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mentions.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'support/likers_fixtures.dart';

const _heart = ValueKey('moment-comment-like-c1');
const _count = ValueKey('moment-comment-likers-c1');
const _reply = ValueKey('reply-to-comment-c1');
const _flag = ValueKey('report-comment-c1');

final _comment = MomentComment(
  id: 'c1',
  type: 'text',
  authorId: 'julia',
  authorName: 'Julia Nowak',
  authorPhotoUrl: null,
  text: 'To brzmi jak mój poranek.',
  durationSeconds: 0,
  createdAt: DateTime(2026, 9, 28, 9),
);

void main() {
  late PublicIdentityRepository originalIdentity;

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = identityRepository();
  });

  tearDown(() => PublicIdentityRepository.instance = originalIdentity);

  Future<void> pumpRow(
    WidgetTester tester, {
    required double width,
    required bool vip,
    Locale locale = const Locale('pl'),
  }) async {
    tester.view.physicalSize = Size(width, 400) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      likersHost(
        locale: locale,
        Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MomentCommentRow(
              comment: _comment,
              momentId: 'm1',
              isOwn: false,
              mentions: MentionDirectory.empty,
              onReplyTo: (_) {},
              onReport: (_) {},
              likeState: const CommentLikeState(
                likeCount: 3,
                callerLiked: false,
              ),
              onToggleLike: (_) {},
              onShowLikers: (_, _) {},
              showWhoLiked: vip,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final vip in <bool>[false, true]) {
    testWidgets('${vip ? 'VIP' : 'non-VIP'}: the dot is drawn exactly while '
        'Reply and the heart share a row, at every width', (tester) async {
      for (var width = 200.0; width <= 420; width += 2) {
        await pumpRow(tester, width: width, vip: vip);
        expect(tester.takeException(), isNull, reason: '$width px');
        final reply = tester.getRect(find.byKey(_reply));
        final heart = tester.getRect(find.byKey(_heart));
        final sameRow = (reply.center.dy - heart.center.dy).abs() < 1;
        final dot = find.text('·');
        expect(
          dot.evaluate().isNotEmpty,
          sameRow,
          reason:
              '$width px: ${sameRow ? 'one row without its dot' : 'a dot on a broken line'}',
        );
        if (sameRow) {
          final flag = tester.getRect(find.byKey(_flag));
          expect((flag.center.dy - heart.center.dy).abs(), lessThan(1));
        }
        // The targets never shrink.
        expect(heart.width, greaterThanOrEqualTo(44));
        expect(
          tester.getSize(find.byKey(_count)).width,
          greaterThanOrEqualTo(44),
        );
        expect(reply.height, greaterThanOrEqualTo(44));
      }
      // The identity repository's batching timer.
      await tester.pump(const Duration(milliseconds: 20));
    });
  }

  testWidgets('after a bare count the flag glyph sits close, its 48 px '
      'target unchanged', (tester) async {
    await pumpRow(tester, width: 390, vip: false);
    final digits = tester.getRect(
      find.descendant(of: find.byKey(_count), matching: find.text('3')),
    );
    final flagTarget = tester.getRect(find.byKey(_flag));
    final flagGlyph = tester.getRect(
      find.descendant(
        of: find.byKey(_flag),
        matching: find.byIcon(Icons.flag_outlined),
      ),
    );
    expect(flagTarget.shortestSide, greaterThanOrEqualTo(48));
    // Render B: about 40 px from the count to the flag, not 63.
    expect(flagGlyph.left - digits.right, lessThanOrEqualTo(44));
    expect(flagGlyph.left, greaterThanOrEqualTo(flagTarget.left));
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('with "Kto polubił" the flag keeps its centred glyph', (
    tester,
  ) async {
    await pumpRow(tester, width: 390, vip: true);
    final flagTarget = tester.getRect(find.byKey(_flag));
    final flagGlyph = tester.getRect(
      find.descendant(
        of: find.byKey(_flag),
        matching: find.byIcon(Icons.flag_outlined),
      ),
    );
    expect((flagGlyph.center.dx - flagTarget.center.dx).abs(), lessThan(1));
    // The identity repository's batching timer.
    await tester.pump(const Duration(milliseconds: 20));
  });
}
