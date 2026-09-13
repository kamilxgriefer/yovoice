// "Rozmowa" on the expanded Moment: real replies, voice replies with their
// own mini-player, an honest flat-thread "Reply", real paging — and no
// heart, because comments carry no like edge on the server.

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_conversation_thread.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mention_composer.dart';
import 'package:yovoice/features/moments/presentation/widgets/voice_reply_mini_player.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'moment_listen_test_support.dart';

void main() {
  late PublicIdentityRepository originalIdentity;

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: listenViewerUid),
      ),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  testWidgets('a text reply is plain text and a voice reply is a mini-player', (
    tester,
  ) async {
    await pumpListenDetail(
      tester,
      moment: listenMoment('m1', comments: 2),
      size: const Size(900, 900),
      seed: (db) async {
        await seedListenComment(
          db,
          momentId: 'm1',
          id: 'c1',
          authorName: 'Bartek',
          text: 'This calm is staying with me.',
          minutesAgo: 40,
        );
        await seedListenComment(
          db,
          momentId: 'm1',
          id: 'c2',
          authorName: 'Ola',
          voice: true,
          durationSeconds: 12,
          minutesAgo: 20,
        );
      },
    );

    expect(find.text('Conversation · 2'), findsOneWidget);
    expect(find.text('This calm is staying with me.'), findsOneWidget);
    expect(find.text('Bartek'), findsOneWidget);
    expect(find.byType(VoiceReplyMiniPlayer), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);

    // No like edge exists on a comment, so no heart is drawn on one.
    expect(
      find.descendant(
        of: find.byType(MomentConversationThread),
        matching: find.byIcon(Icons.favorite_border_rounded),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(MomentConversationThread),
        matching: find.byIcon(Icons.favorite_rounded),
      ),
      findsNothing,
    );
  });

  testWidgets('"Reply" prefills the composer with the mention, because the '
      'thread is flat', (tester) async {
    await pumpListenDetail(
      tester,
      moment: listenMoment('m1', comments: 1),
      size: const Size(900, 900),
      seed: (db) =>
          seedListenComment(db, momentId: 'm1', id: 'c1', authorName: 'Ola'),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('reply-to-comment-c1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reply-to-comment-c1')));
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('moment-detail-comment-field')),
    );
    expect(field.controller!.text, '@Ola ');
    expect(field.focusNode?.hasFocus, isTrue);

    // Tapping twice does not stack the mention.
    await tester.ensureVisible(
      find.byKey(const ValueKey('reply-to-comment-c1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reply-to-comment-c1')));
    await tester.pump();
    expect(field.controller!.text, '@Ola ');
  });

  testWidgets('the mention picker is still the composer this page had', (
    tester,
  ) async {
    await pumpListenDetail(tester, moment: listenMoment('m1'));

    expect(find.byType(MentionComposerField), findsOneWidget);
    expect(
      find.byKey(const ValueKey('moment-detail-comment-send')),
      findsOneWidget,
    );
  });

  testWidgets('the composer mic opens the recorder — and only the recorder '
      'may start the microphone', (tester) async {
    final harness = await pumpListenDetail(
      tester,
      moment: listenMoment('m1'),
      size: const Size(900, 900),
    );

    await tester.tap(find.byKey(const ValueKey('moment-detail-composer-mic')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final recorder = find.byType(RecordVoiceMomentScreen);
    expect(recorder, findsOneWidget);
    final screen = tester.widget<RecordVoiceMomentScreen>(recorder);
    expect(screen.replyToMomentId, 'm1');
    expect(screen.replyToAuthorName, 'Nadia Rutkowska');
    expect(identical(screen.momentService, harness.moments), isTrue);

    harness.navigatorKey.currentState!.pop(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(RecordVoiceMomentScreen), findsNothing);
  });

  testWidgets('the filled CTA opens the same recorder and reports a published '
      'reply', (tester) async {
    final harness = await pumpListenDetail(
      tester,
      moment: listenMoment('m1'),
      size: const Size(900, 900),
    );

    await tester.tap(find.byKey(const ValueKey('moment-detail-reply-voice')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(RecordVoiceMomentScreen), findsOneWidget);

    harness.navigatorKey.currentState!.pop(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Voice reply published.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the page loads one real page of replies and can ask for more', (
    tester,
  ) async {
    await pumpListenDetail(
      tester,
      moment: listenMoment('m1', comments: 9),
      size: const Size(900, 900),
      seed: (db) async {
        for (var index = 0; index < 9; index++) {
          await seedListenComment(
            db,
            momentId: 'm1',
            id: 'c$index',
            authorName: 'Ola',
            text: 'Reply $index',
            minutesAgo: 90 - index,
          );
        }
      },
    );

    expect(find.text('Reply 0'), findsOneWidget);
    expect(find.text('Reply 6'), findsOneWidget);
    expect(find.text('Reply 8'), findsNothing);

    final more = find.byKey(const ValueKey('moment-thread-load-more'));
    await tester.scrollUntilVisible(
      more,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('moment-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.text('Reply 8'), findsOneWidget);
  });

  testWidgets('report is offered on someone else\'s reply and never on your '
      'own', (tester) async {
    await pumpListenDetail(
      tester,
      moment: listenMoment('m1', comments: 2),
      size: const Size(900, 900),
      seed: (db) async {
        await seedListenComment(
          db,
          momentId: 'm1',
          id: 'c-theirs',
          authorId: 'ola',
          authorName: 'Ola',
          minutesAgo: 40,
        );
        await seedListenComment(
          db,
          momentId: 'm1',
          id: 'c-mine',
          authorId: listenViewerUid,
          authorName: 'Me',
          minutesAgo: 20,
        );
      },
    );

    expect(
      find.byKey(const ValueKey('report-comment-c-theirs')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('report-comment-c-mine')), findsNothing);
  });

  testWidgets('an expired Moment keeps its thread readable and says why the '
      'composer is closed', (tester) async {
    await pumpListenDetail(
      tester,
      moment: listenMoment(
        'm1',
        age: const Duration(hours: 30),
        lifetime: const Duration(hours: 24),
      ),
      size: const Size(900, 900),
    );

    expect(find.byKey(const ValueKey('moment-detail-gone')), findsOneWidget);
    expect(find.text('This Moment is no longer available'), findsOneWidget);
    expect(find.byKey(const ValueKey('moment-detail-play')), findsNothing);
    expect(
      find.byKey(const ValueKey('moment-detail-composer-closed')),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('moment-detail-comment-field')),
    );
    expect(field.enabled, isFalse);
    // The player card — with its transport and its reply CTA — is replaced
    // by the explanation; nothing pretends the audio is still there.
    expect(
      find.byKey(const ValueKey('moment-detail-reply-voice')),
      findsNothing,
    );
    final mic = tester.widget<IconButton>(
      find.byKey(const ValueKey('moment-detail-composer-mic')),
    );
    expect(mic.onPressed, isNull);
  });
}
