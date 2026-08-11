import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/widgets/desktop/global_chat_panel.dart';
import 'package:yovoice/features/messages/data/services/global_chat_service.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_message_sheet.dart';

/// Global Chat: the client half of the community channel.
///
/// The AUTHORIZATION half — who may read, who may send, spoofing,
/// validation, the rate limiter, moderator deletion — is covered against
/// the real rules in `firestore-tests/rules.test.js`, because that is the
/// only place those guarantees actually live. What is worth pinning here
/// is the behaviour this code owns: the canonical path it reads, how the
/// growing history window pages, and what the panel renders.
void main() {
  const uid = 'me-uid';
  late FakeFirebaseFirestore db;

  MockFirebaseAuth auth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: 'me@yovoice.app', displayName: 'Kamil'),
  );

  GlobalChatService service() =>
      GlobalChatService(firestore: db, auth: auth());

  Future<void> seed({
    required String id,
    required String senderId,
    required String senderName,
    required String content,
    required Duration age,
    bool isDeleted = false,
    String? deletedBy,
    bool isCreator = false,
    bool isStaff = false,
  }) async {
    await db
        .collection('globalChat')
        .doc(GlobalChatService.channelId)
        .collection('messages')
        .doc(id)
        .set({
          'senderId': senderId,
          'senderName': senderName,
          'senderPhotoUrl': null,
          'senderIsCreator': isCreator,
          'senderIsStaff': isStaff,
          'content': content,
          'sentAt': Timestamp.fromDate(DateTime.now().subtract(age)),
          'isDeleted': isDeleted,
          'deletedBy': deletedBy,
          'deletedAt': null,
        });
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Kamil',
      'email': 'me@yovoice.app',
      'accountType': 'personal',
    });
  });

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 760, child: child)),
  );

  group('canonical path', () {
    test('reads and writes the ONE shared channel, not a per-user one', () async {
      await service().sendMessage('hello community');

      final direct = await db
          .collection('globalChat')
          .doc('main')
          .collection('messages')
          .get();
      expect(direct.docs, hasLength(1));
      expect(direct.docs.first.data()['senderId'], uid);
      expect(direct.docs.first.data()['content'], 'hello community');

      // The rate-limit companion doc lands in the same commit — it is
      // what firestore.rules checks with getAfter().
      final state = await db
          .collection('globalChat')
          .doc('main')
          .collection('senders')
          .doc(uid)
          .get();
      expect(state.exists, isTrue);
      expect(state.data()!['lastMessageId'], direct.docs.first.id);

      // And nothing was written into the private-message collections.
      expect((await db.collection('conversations').get()).docs, isEmpty);
    });

    test('identity is copied from the profile document, never from the '
        'caller', () async {
      await service().sendMessage('hi');
      final message = (await db
              .collection('globalChat')
              .doc('main')
              .collection('messages')
              .get())
          .docs
          .first
          .data();
      expect(message['senderName'], 'Kamil');
      expect(message['senderIsCreator'], isFalse);
      expect(message['senderIsStaff'], isFalse);
    });

    test('blank and oversized messages are refused before they leave the '
        'client too', () async {
      await expectLater(service().sendMessage('   '), throwsStateError);
      await expectLater(
        service().sendMessage('x' * (GlobalChatService.maxMessageLength + 1)),
        throwsStateError,
      );
      expect(
        (await db
                .collection('globalChat')
                .doc('main')
                .collection('messages')
                .get())
            .docs,
        isEmpty,
      );
    });

    test('deleting soft-deletes: the record survives, the text does not',
        () async {
      await seed(
        id: 'g1',
        senderId: uid,
        senderName: 'Kamil',
        content: 'oops',
        age: const Duration(minutes: 1),
      );
      await service().deleteMessage('g1');

      final message = await db
          .collection('globalChat')
          .doc('main')
          .collection('messages')
          .doc('g1')
          .get();
      expect(message.exists, isTrue, reason: 'never a hard delete');
      expect(message.data()!['isDeleted'], isTrue);
      expect(message.data()!['deletedBy'], uid);
      expect(message.data()!['content'], '');
    });
  });

  group('blocking is a UI filter, not a read boundary', () {
    test('Firestore DELIVERS a blocked sender\'s messages; the service '
        'reports the block list separately and the UI is what hides them',
        () async {
      await seed(
        id: 'g1',
        senderId: 'blocked-1',
        senderName: 'Blocked Person',
        content: 'public and delivered',
        age: const Duration(minutes: 1),
      );
      await db
          .collection('users')
          .doc(uid)
          .collection('blocked')
          .doc('blocked-1')
          .set({'userId': 'blocked-1', 'createdAt': Timestamp.now()});

      // The query itself is unfiltered — Global Chat is public to every
      // active account, and rules cannot filter one shared query per
      // reader. This is the honest statement of the boundary.
      final feed = await service().watchMessages().first;
      expect(feed.messages.map((m) => m.senderId), contains('blocked-1'));

      final blocked = await service().watchBlockedUserIds().first;
      expect(blocked, contains('blocked-1'));
    });
  });

  group('send limits', () {
    test('the allowance names the 3s floor while it is running', () async {
      await service().sendMessage('first');
      final allowance = await service().sendAllowance();

      expect(allowance.canSend, isFalse);
      expect(allowance.reason, GlobalSendBlock.cooldown);
      expect(allowance.retryAfter.inSeconds, lessThanOrEqualTo(3));
    });

    test('the allowance names the hourly cap once the window is full',
        () async {
      await db
          .collection('globalChat')
          .doc(GlobalChatService.channelId)
          .collection('senders')
          .doc(uid)
          .set({
            'lastMessageAt': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(minutes: 5)),
            ),
            'lastMessageId': 'earlier',
            'windowStartAt': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(minutes: 10)),
            ),
            'windowCount': GlobalChatService.fixedWindowLimit,
          });

      final allowance = await service().sendAllowance();
      expect(allowance.canSend, isFalse);
      expect(allowance.reason, GlobalSendBlock.hourlyLimit);
      expect(allowance.retryAfter.inMinutes, greaterThan(40));
    });

    test('a send advances the window counter rather than resetting it',
        () async {
      await db
          .collection('globalChat')
          .doc(GlobalChatService.channelId)
          .collection('senders')
          .doc(uid)
          .set({
            'lastMessageAt': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(minutes: 5)),
            ),
            'lastMessageId': 'earlier',
            'windowStartAt': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(minutes: 10)),
            ),
            'windowCount': 7,
          });

      await service().sendMessage('another one');

      final state = await db
          .collection('globalChat')
          .doc(GlobalChatService.channelId)
          .collection('senders')
          .doc(uid)
          .get();
      expect(state.data()!['windowCount'], 8);
    });

    test('an elapsed window opens a fresh one at a count of one', () async {
      await db
          .collection('globalChat')
          .doc(GlobalChatService.channelId)
          .collection('senders')
          .doc(uid)
          .set({
            'lastMessageAt': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(minutes: 90)),
            ),
            'lastMessageId': 'earlier',
            'windowStartAt': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(minutes: 90)),
            ),
            'windowCount': 200,
          });

      await service().sendMessage('new hour');

      final state = await db
          .collection('globalChat')
          .doc(GlobalChatService.channelId)
          .collection('senders')
          .doc(uid)
          .get();
      expect(state.data()!['windowCount'], 1);
    });
  });

  group('reporting', () {
    ReportService reports() => ReportService(firestore: db, auth: auth());

    /// The message menu is hover-revealed, as it is in the product, so
    /// the test has to actually put a mouse over the row.
    Future<void> hoverOver(WidgetTester tester, Finder target) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(target));
      await tester.pumpAndSettle();
    }

    Future<void> openPanelWithMessage(WidgetTester tester) async {
      await seed(
        id: 'g1',
        senderId: 'rude-1',
        senderName: 'Rude Person',
        content: 'something reportable',
        age: const Duration(minutes: 1),
      );
      await tester.pumpWidget(
        host(
          GlobalChatPanel(
            currentUserId: uid,
            chatService: service(),
            reportService: reports(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      await hoverOver(tester, find.text('something reportable'));
      await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report message'));
      await tester.pumpAndSettle();
    }

    testWidgets('the picker offers every reason rules accept, and Send is '
        'disabled until one is chosen', (tester) async {
      await openPanelWithMessage(tester);

      for (final reason in ReportReason.values) {
        expect(
          find.text(reportReasonLabel(reason)),
          findsOneWidget,
          reason: '${reason.name} missing from the picker',
        );
      }
      // No reason yet: the action is inert, so an unreasoned report
      // cannot be filed.
      final send = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(send.onPressed, isNull);

      // The note only appears once a reason is chosen.
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );
    });

    testWidgets('choosing a reason files it with that reason and an '
        'optional note', (tester) async {
      await openPanelWithMessage(tester);

      await tester.tap(find.text(reportReasonLabel(ReportReason.harassment)));
      await tester.pumpAndSettle();

      // Note field appears, with the remaining-character budget.
      final noteField = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      expect(noteField, findsOneWidget);
      expect(
        find.text('${ReportService.maxNoteLength} left'),
        findsOneWidget,
      );
      await tester.enterText(noteField, 'kept it up all evening');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();

      final filed = await db
          .collection('reports')
          .doc(
            ReportService.reportIdFor(
              reporterId: uid,
              targetType: ReportTargetType.globalMessage,
              targetId: 'g1',
            ),
          )
          .get();
      expect(filed.exists, isTrue);
      expect(filed.data()!['reason'], 'harassment');
      expect(filed.data()!['note'], 'kept it up all evening');
      expect(filed.data()!['reporterId'], uid);
      expect(filed.data()!['reportedUserId'], 'rude-1');
      // The ONE workflow field a client may write, pinned to 'open' by
      // rules. Everything else about triage belongs to the
      // moderateReport Function.
      expect(filed.data()!['status'], 'open');
      expect(filed.data()!.containsKey('assignedTo'), isFalse);
      expect(filed.data()!.containsKey('resolution'), isFalse);
      expect(filed.data()!.containsKey('resolvedBy'), isFalse);
    });

    testWidgets('cancelling files nothing', (tester) async {
      await openPanelWithMessage(tester);

      await tester.tap(find.text(reportReasonLabel(ReportReason.spam)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect((await db.collection('reports').get()).docs, isEmpty);
    });

    test('a note longer than the server limit is truncated, never sent '
        'oversized', () async {
      await seed(
        id: 'g1',
        senderId: 'rude-1',
        senderName: 'Rude',
        content: 'x',
        age: const Duration(minutes: 1),
      );
      await reports().report(
        targetType: ReportTargetType.globalMessage,
        targetId: 'g1',
        reportedUserId: 'rude-1',
        reason: ReportReason.spam,
        note: 'y' * (ReportService.maxNoteLength + 50),
      );

      final filed = (await db.collection('reports').get()).docs.first;
      expect(
        (filed.data()['note'] as String).length,
        ReportService.maxNoteLength,
      );
    });

    test('the allowance reports the cooldown right after a report', () async {
      await seed(
        id: 'g1',
        senderId: 'rude-1',
        senderName: 'Rude',
        content: 'x',
        age: const Duration(minutes: 1),
      );
      await reports().report(
        targetType: ReportTargetType.globalMessage,
        targetId: 'g1',
        reportedUserId: 'rude-1',
        reason: ReportReason.spam,
      );

      final allowance = await reports().allowance();
      expect(allowance.canReport, isFalse);
      expect(allowance.atDailyLimit, isFalse);
      expect(allowance.retryAfter.inSeconds, lessThanOrEqualTo(30));
    });

    test('the allowance reports the fixed-window cap once it is full',
        () async {
      await db.collection('reportLimits').doc(uid).set({
        'lastReportAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(hours: 2)),
        ),
        'lastReportId': 'earlier',
        'windowStartAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(hours: 3)),
        ),
        'windowCount': ReportService.dailyLimit,
      });

      final allowance = await reports().allowance();
      expect(allowance.canReport, isFalse);
      expect(allowance.atDailyLimit, isTrue);
      expect(allowance.retryAfter.inHours, greaterThan(19));
    });

    test('the report id is deterministic, so a duplicate addresses the '
        'same document', () async {
      final first = ReportService.reportIdFor(
        reporterId: uid,
        targetType: ReportTargetType.globalMessage,
        targetId: 'g1',
      );
      final second = ReportService.reportIdFor(
        reporterId: uid,
        targetType: ReportTargetType.globalMessage,
        targetId: 'g1',
      );
      expect(first, second);
      expect(first, '${uid}_globalMessage_g1');
    });
  });

  group('pagination', () {
    test('the growing window never duplicates or reorders a message',
        () async {
      for (var i = 0; i < 12; i++) {
        await seed(
          id: 'g$i',
          senderId: 'sender-$i',
          senderName: 'Sender $i',
          content: 'message $i',
          // g0 is the newest, g11 the oldest.
          age: Duration(minutes: i + 1),
        );
      }

      final firstPage = await service().watchMessages(limit: 5).first;
      expect(firstPage.messages.map((m) => m.id).toList(), [
        'g0',
        'g1',
        'g2',
        'g3',
        'g4',
      ]);
      expect(firstPage.hasMore, isTrue);

      final secondPage = await service().watchMessages(limit: 10).first;
      final ids = secondPage.messages.map((m) => m.id).toList();
      // The already-seen head is unchanged and in the same order...
      expect(ids.take(5).toList(), firstPage.messages.map((m) => m.id));
      // ...older messages are appended, and nothing repeats.
      expect(ids, ['g0', 'g1', 'g2', 'g3', 'g4', 'g5', 'g6', 'g7', 'g8', 'g9']);
      expect(ids.toSet(), hasLength(ids.length));

      final everything = await service().watchMessages(limit: 50).first;
      expect(everything.messages, hasLength(12));
      expect(everything.hasMore, isFalse);
    });
  });

  group('panel', () {
    testWidgets('renders real messages with their real badges, and marks a '
        'moderator removal as such', (tester) async {
      await seed(
        id: 'g1',
        senderId: 'creator-1',
        senderName: 'Marta',
        content: 'Doors open in ten minutes',
        age: const Duration(minutes: 3),
        isCreator: true,
      );
      await seed(
        id: 'g2',
        senderId: 'staff-1',
        senderName: 'Ola',
        content: 'Keep it kind, everyone',
        age: const Duration(minutes: 5),
        isStaff: true,
      );
      await seed(
        id: 'g3',
        senderId: 'spammer',
        senderName: 'Spammer',
        content: '',
        age: const Duration(minutes: 8),
        isDeleted: true,
        deletedBy: 'mod-1',
      );

      await tester.pumpWidget(
        host(
          GlobalChatPanel(
            currentUserId: uid,
            chatService: service(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Doors open in ten minutes'), findsOneWidget);
      expect(find.text('Marta'), findsOneWidget);
      expect(find.text('Creator'), findsOneWidget);
      expect(find.text('Ola'), findsOneWidget);
      expect(find.text('Team'), findsOneWidget);
      // A removed message keeps its slot and says who removed it.
      expect(find.text('Message removed by a moderator'), findsOneWidget);
      expect(find.text('Spammer'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty channel invites the first message', (tester) async {
      await tester.pumpWidget(
        host(GlobalChatPanel(currentUserId: uid, chatService: service())),
      );
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        find.text('No one has said anything yet. Start the conversation.'),
        findsOneWidget,
      );
      expect(find.text('Message the YO Voice community'), findsOneWidget);
    });

    testWidgets('the composer sends to the real channel and clears',
        (tester) async {
      await tester.pumpWidget(
        host(GlobalChatPanel(currentUserId: uid, chatService: service())),
      );
      await tester.pump(const Duration(milliseconds: 150));

      await tester.enterText(find.byType(TextField), 'hello everyone');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump(const Duration(milliseconds: 300));

      final stored = await db
          .collection('globalChat')
          .doc('main')
          .collection('messages')
          .get();
      expect(stored.docs, hasLength(1));
      expect(stored.docs.first.data()['content'], 'hello everyone');
      expect(find.text('hello everyone'), findsWidgets);
    });

    testWidgets('a blocked sender NEVER flashes before the block list '
        'resolves — nothing renders until both streams are in hand',
        (tester) async {
      await seed(
        id: 'g1',
        senderId: 'blocked-1',
        senderName: 'Blocked Person',
        content: 'must never be painted',
        age: const Duration(minutes: 2),
      );
      await db
          .collection('users')
          .doc(uid)
          .collection('blocked')
          .doc('blocked-1')
          .set({'userId': 'blocked-1', 'createdAt': Timestamp.now()});

      await tester.pumpWidget(
        host(GlobalChatPanel(currentUserId: uid, chatService: service())),
      );

      // Frame by frame from the very first paint: the message must not
      // appear in ANY of them, including the window where the feed has
      // arrived but the block list has not.
      for (var frame = 0; frame < 12; frame++) {
        expect(
          find.text('must never be painted'),
          findsNothing,
          reason: 'blocked content rendered on frame $frame',
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('must never be painted'), findsNothing);
    });

    testWidgets('messages from a blocked account are hidden from the reader',
        (tester) async {
      await seed(
        id: 'g1',
        senderId: 'blocked-1',
        senderName: 'Blocked Person',
        content: 'you should not see this',
        age: const Duration(minutes: 2),
      );
      await seed(
        id: 'g2',
        senderId: 'friendly-1',
        senderName: 'Friendly',
        content: 'you should see this',
        age: const Duration(minutes: 3),
      );
      await db
          .collection('users')
          .doc(uid)
          .collection('blocked')
          .doc('blocked-1')
          .set({'userId': 'blocked-1', 'createdAt': Timestamp.now()});

      await tester.pumpWidget(
        host(GlobalChatPanel(currentUserId: uid, chatService: service())),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('you should see this'), findsOneWidget);
      expect(find.text('you should not see this'), findsNothing);
      expect(find.text('Blocked Person'), findsNothing);
    });

    testWidgets('offers "Load earlier messages" only while older history '
        'exists', (tester) async {
      for (var i = 0; i < GlobalChatService.pageSize + 3; i++) {
        await seed(
          id: 'g$i',
          senderId: 'sender-$i',
          senderName: 'Sender $i',
          content: 'message $i',
          age: Duration(minutes: i + 1),
        );
      }

      await tester.pumpWidget(
        host(GlobalChatPanel(currentUserId: uid, chatService: service())),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // The feed opens on the NEWEST message, as a chat should — the
      // affordance lives at the far end of the history, reached by
      // scrolling back through it.
      expect(find.text('message 0'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Load earlier messages'),
        find.byType(ListView),
        const Offset(0, 90),
      );
      await tester.pump();

      await tester.tap(find.text('Load earlier messages'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      // The window grew past the end of the channel, so the affordance
      // retires itself instead of paging into nothing.
      expect(find.text('Load earlier messages'), findsNothing);
      // ...and the oldest message is now inside the window.
      final feed = await service()
          .watchMessages(limit: GlobalChatService.pageSize * 2)
          .first;
      expect(feed.messages, hasLength(GlobalChatService.pageSize + 3));
      expect(feed.hasMore, isFalse);
    });
  });
}
