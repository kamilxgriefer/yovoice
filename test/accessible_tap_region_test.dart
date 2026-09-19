import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_conversation_thread.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mentions.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
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

  group('a commenter is as reachable as the moment author', () {
    late PublicIdentityRepository originalIdentity;

    setUp(() {
      originalIdentity = PublicIdentityRepository.instance;
      PublicIdentityRepository.instance = PublicIdentityRepository(
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
        fetchOverride: (uids) async => <String, dynamic>{
          for (final uid in uids)
            uid: {'role': 'user', 'vip': false, 'uid': uid},
        },
        flushDelay: const Duration(milliseconds: 1),
      );
    });

    tearDown(() {
      PublicIdentityRepository.instance = originalIdentity;
    });

    MomentComment commentBy(String authorId, String authorName) =>
        MomentComment(
          id: 'c-$authorName',
          type: 'text',
          authorId: authorId,
          authorName: authorName,
          authorPhotoUrl: null,
          text: 'This one stayed with me.',
          durationSeconds: 0,
          createdAt: DateTime(2026, 9, 18, 10),
        );

    Future<void> pumpThread(
      WidgetTester tester, {
      required List<MomentComment> comments,
      void Function(MentionCandidate candidate)? onMentionTap,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MomentConversationThread(
                momentId: 'moment',
                comments: comments,
                commentCount: comments.length,
                currentUserId: 'me',
                mentions: MentionDirectory.empty,
                onMentionTap: onMentionTap,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('a comment avatar is a named 44px profile action', (
      tester,
    ) async {
      final opened = <String>[];
      await pumpThread(
        tester,
        comments: <MomentComment>[commentBy('nina-uid', 'Nina')],
        onMentionTap: (candidate) => opened.add(candidate.userId),
      );

      final avatar = find.bySemanticsLabel('Open profile of Nina');
      expect(
        avatar,
        findsOneWidget,
        reason: 'the commenter must be reachable, not only an @mention',
      );
      expect(tester.getSize(avatar).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(avatar).height, greaterThanOrEqualTo(44));
      expect(opened, isEmpty, reason: 'rendering opens nobody');

      await tester.tap(avatar);
      await tester.pump();

      expect(opened, <String>['nina-uid']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an authorless comment row stays inert', (tester) async {
      await pumpThread(
        tester,
        comments: <MomentComment>[commentBy('', 'Nina')],
        onMentionTap: (_) => fail('an empty uid must open nothing'),
      );

      expect(
        find.bySemanticsLabel('Open profile of Nina'),
        findsNothing,
        reason: 'the preview asserts on an empty document id',
      );
      expect(find.text('Nina'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
