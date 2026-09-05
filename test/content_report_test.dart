import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// Reporting a MESSAGE.
///
/// Before this, `createContentReport` was deployed and live and no Dart
/// file called it: the only report action in the product was on a
/// person, from a profile menu, with the reason hardcoded. Someone who
/// saw one abusive message could report the account and hope a moderator
/// found the message.
///
/// These tests pin two things that are easy to lose again: the exact
/// contract the deployed callable validates, and the fact that the action
/// is REACHABLE from the surface where the abuse appears.
void main() {
  const conversationId = 'me-uid_them-uid';
  const currentUserId = 'me-uid';
  const otherUserId = 'them-uid';

  group('callable contract', () {
    test('sends only the ids the target type expects', () {
      // The server refuses a payload whose id fields conflict with its
      // targetType ("The report target fields conflict"), so a direct
      // message report must not carry momentId/commentId keys at all.
      expect(
        const ReportedContent.directMessage(
          conversationId: 'c1',
          messageId: 'm1',
        ).callablePayload,
        <String, Object?>{
          'targetType': 'directMessage',
          'conversationId': 'c1',
          'messageId': 'm1',
        },
      );
      expect(
        const ReportedContent.voiceMoment(momentId: 'v1').callablePayload,
        <String, Object?>{'targetType': 'voiceMoment', 'momentId': 'v1'},
      );
      expect(
        const ReportedContent.voiceMomentComment(
          momentId: 'v1',
          commentId: 'k1',
        ).callablePayload,
        <String, Object?>{
          'targetType': 'voiceMomentComment',
          'momentId': 'v1',
          'commentId': 'k1',
        },
      );
    });

    test('every targetType it can build is one the server accepts', () {
      // The deployed allowlist, copied from functions/moments/integrity.js.
      // Room and club messages are deliberately NOT here — adding a case
      // to ReportedContentType without the Functions change would produce
      // an invalid-argument, and this test is what would catch it.
      const serverAccepts = {
        'directMessage',
        'voiceMoment',
        'voiceMomentComment',
      };
      expect(
        ReportedContentType.values.map((type) => type.name).toSet(),
        serverAccepts,
      );
    });

    test('the request id is derived from the target, not from the attempt', () {
      const target = ReportedContent.directMessage(
        conversationId: 'c1',
        messageId: 'm1',
      );

      // Stable across attempts: this is what makes a repeat tap replay
      // the server's operation ledger instead of creating a second
      // report document for the same reporter and the same message.
      expect(
        ContentReportService.requestIdFor(target),
        ContentReportService.requestIdFor(target),
      );

      // ...and distinct per target, so reporting a different message is
      // a different operation rather than a swallowed duplicate.
      expect(
        ContentReportService.requestIdFor(target),
        isNot(
          ContentReportService.requestIdFor(
            const ReportedContent.directMessage(
              conversationId: 'c1',
              messageId: 'm2',
            ),
          ),
        ),
      );
      expect(
        ContentReportService.requestIdFor(target),
        isNot(
          ContentReportService.requestIdFor(
            const ReportedContent.voiceMoment(momentId: 'm1'),
          ),
        ),
      );
    });

    test('a Voice receipt is forwarded but does not change retry identity', () {
      const receipt = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const withoutReceipt = ReportedContent.voiceMoment(momentId: 'v1');
      const withReceipt = ReportedContent.voiceMoment(
        momentId: 'v1',
        reportReceipt: receipt,
      );

      expect(withReceipt.callablePayload, <String, Object?>{
        'targetType': 'voiceMoment',
        'momentId': 'v1',
        'reportReceipt': receipt,
      });
      expect(
        ContentReportService.requestIdFor(withReceipt),
        ContentReportService.requestIdFor(withoutReceipt),
        reason: 'receipt rotation must replay one report operation',
      );
    });

    test('the request id matches the server regex', () {
      // requireRequestId: /^[A-Za-z0-9_-]{8,128}$/
      final pattern = RegExp(r'^[A-Za-z0-9_-]{8,128}$');
      for (final target in <ReportedContent>[
        const ReportedContent.directMessage(
          // A conversation id is `{uidA}_{uidB}`; two long provider uids
          // are exactly the case a concatenated key would have burst.
          conversationId:
              'aVeryLongProviderSuppliedUid00000000000001_'
              'aVeryLongProviderSuppliedUid00000000000002',
          messageId: 'aMessageIdThatIsAlsoLong0000000000',
        ),
        const ReportedContent.voiceMoment(momentId: 'v1'),
        const ReportedContent.voiceMomentComment(
          momentId: 'v1',
          commentId: 'k1',
        ),
      ]) {
        expect(
          ContentReportService.requestIdFor(target),
          matches(pattern),
          reason: 'requestId would be rejected as invalid-argument',
        );
      }
    });

    test('the reason is sent as the enum name, keeping the queue sortable', () {
      final functions = _RecordingFunctions();
      final service = ContentReportService(functions: functions);

      return service
          .report(
            content: const ReportedContent.voiceMoment(momentId: 'v1'),
            reason: ReportReason.selfHarm,
          )
          .then((_) {
            expect(functions.calls.single.name, 'createContentReport');
            expect(functions.calls.single.payload['reason'], 'selfHarm');
            // Not a sentence, not free prose: the callable validates only
            // the LENGTH of `reason` (1-500 chars), so the client is the
            // only thing keeping the moderator queue filterable.
            expect(
              functions.calls.single.payload['requestId'],
              ContentReportService.requestIdFor(
                const ReportedContent.voiceMoment(momentId: 'v1'),
              ),
            );
          });
    });
  });

  group('failure copy', () {
    /// Each row is a status code the deployed function can actually
    /// return, and the sentence a reporter should read. A safety path
    /// that answers everything with "something went wrong" teaches
    /// people that reporting does not work.
    final expectations = <String, Matcher>{
      'already-exists': contains('already reported this message'),
      'resource-exhausted': contains('wait a few minutes'),
      'not-found': contains('no longer available'),
      'permission-denied': contains("can't report this message"),
      'failed-precondition': contains('Verify your email'),
      'unauthenticated': contains('sign in again'),
      'unavailable': contains('connection'),
      'unimplemented': contains('unavailable right now'),
      'internal': contains('could not be sent'),
    };

    for (final entry in expectations.entries) {
      test('${entry.key} reads as something the reporter can act on', () async {
        final functions = _RecordingFunctions(
          failure: FirebaseFunctionsException(
            code: entry.key,
            // Deliberately developer-facing, the way the real function
            // words them. None of this may reach the UI.
            message: 'A report exists without its ledger.',
          ),
        );

        await expectLater(
          ContentReportService(functions: functions).report(
            content: const ReportedContent.directMessage(
              conversationId: 'c1',
              messageId: 'm1',
            ),
            reason: ReportReason.harassment,
          ),
          throwsA(
            isA<ContentReportException>().having(
              (error) => error.message,
              'message',
              entry.value,
            ),
          ),
        );
      });
    }

    test('the same failure uses the right noun for each content type', () {
      // "You already reported this Voice Moment", not "...this message".
      final cases = <ReportedContent, String>{
        const ReportedContent.directMessage(
          conversationId: 'c1',
          messageId: 'm1',
        ): 'message',
        const ReportedContent.voiceMoment(momentId: 'v1'): 'Voice Moment',
        const ReportedContent.voiceMomentComment(
          momentId: 'v1',
          commentId: 'k1',
        ): 'comment',
      };
      for (final entry in cases.entries) {
        expect(entry.key.noun, entry.value);
      }
    });

    test('a raw exception code can never reach the reporter', () async {
      final functions = _RecordingFunctions(
        failure: FirebaseFunctionsException(
          code: 'resource-exhausted',
          message: 'Too many requests. Please try again later.',
        ),
      );

      try {
        await ContentReportService(functions: functions).report(
          content: const ReportedContent.voiceMoment(momentId: 'v1'),
          reason: ReportReason.spam,
        );
        fail('expected the report to fail');
      } on ContentReportException catch (error) {
        expect(error.message, isNot(contains('firebase')));
        expect(error.message, isNot(contains('[')));
        expect(error.failure, ContentReportFailure.tooManyReports);
        // The original is kept for logs, never for display.
        expect(error.cause, isA<FirebaseFunctionsException>());
      }
    });
  });

  group('reachable from a direct message', () {
    late PublicIdentityRepository originalIdentityRepository;

    setUp(() {
      originalIdentityRepository = PublicIdentityRepository.instance;
      PublicIdentityRepository.instance = PublicIdentityRepository(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: currentUserId),
        ),
        fetchOverride: (uids) async => <String, dynamic>{
          for (final uid in uids) uid: {'role': 'user', 'vip': false},
        },
        flushDelay: const Duration(milliseconds: 1),
      );
    });

    tearDown(() {
      PublicIdentityRepository.instance = originalIdentityRepository;
    });

    Message messageFrom(String senderId) => Message(
      id: 'm1',
      conversationId: conversationId,
      senderId: senderId,
      type: MessageType.text,
      content: 'something abusive',
      sentAt: DateTime.utc(2026, 3, 1, 12),
      readBy: const [currentUserId],
      reactions: const <String, String>{},
    );

    Future<void> openChat(
      WidgetTester tester,
      _StubMessageService service,
      _RecordingFunctions functions, {
      Size size = const Size(390, 844),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: ChatScreen(
            conversationId: conversationId,
            otherUserId: otherUserId,
            otherDisplayName: 'Them',
            otherEmail: '',
            otherPhotoUrl: '',
            messageService: service,
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: currentUserId),
            ),
            contentReportService: ContentReportService(functions: functions),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('long-pressing their message offers a report action that '
        'reaches the deployed callable', (tester) async {
      final service = _StubMessageService();
      final functions = _RecordingFunctions();
      await openChat(tester, service, functions);

      service.emit([messageFrom(otherUserId)]);
      await tester.pump();

      await tester.longPress(find.text('something abusive'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('report-message')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('report-message')));
      await tester.pumpAndSettle();

      // The reason picker, not a fixed reason.
      expect(find.text('Report this message'), findsOneWidget);
      for (final reason in ReportReason.values) {
        expect(
          find.byKey(ValueKey('report-reason-${reason.name}')),
          findsOneWidget,
        );
      }

      await tester.tap(
        find.byKey(const ValueKey('report-reason-impersonation')),
      );
      await tester.pumpAndSettle();

      expect(functions.calls, hasLength(1));
      expect(functions.calls.single.name, 'createContentReport');
      expect(functions.calls.single.payload, <String, Object?>{
        'targetType': 'directMessage',
        'conversationId': conversationId,
        'messageId': 'm1',
        'reason': 'impersonation',
        'requestId': ContentReportService.requestIdFor(
          const ReportedContent.directMessage(
            conversationId: conversationId,
            messageId: 'm1',
          ),
        ),
      });
      expect(
        find.text('Thanks — your report is with our team.'),
        findsOneWidget,
      );
    });

    testWidgets('backing out of the picker files nothing', (tester) async {
      final service = _StubMessageService();
      final functions = _RecordingFunctions();
      await openChat(tester, service, functions);

      service.emit([messageFrom(otherUserId)]);
      await tester.pump();

      await tester.longPress(find.text('something abusive'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-message')));
      await tester.pumpAndSettle();

      // Dismiss the sheet without choosing.
      Navigator.of(tester.element(find.text('Report this message'))).pop();
      await tester.pumpAndSettle();

      expect(functions.calls, isEmpty);
      expect(find.textContaining('report'), findsNothing);
    });

    testWidgets('your own message offers no report action', (tester) async {
      final service = _StubMessageService();
      final functions = _RecordingFunctions();
      await openChat(tester, service, functions);

      service.emit([messageFrom(currentUserId)]);
      await tester.pump();

      await tester.longPress(find.text('something abusive'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('report-message')), findsNothing);
      // ...and the actions that DO belong on your own message survive.
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('a refused report says which refusal it was', (tester) async {
      final service = _StubMessageService();
      final functions = _RecordingFunctions(
        failure: FirebaseFunctionsException(
          code: 'already-exists',
          message: 'requestId was already used for another operation.',
        ),
      );
      await openChat(tester, service, functions);

      service.emit([messageFrom(otherUserId)]);
      await tester.pump();

      await tester.longPress(find.text('something abusive'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-reason-spam')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('You already reported this message'),
        findsOneWidget,
      );
      // Not the server's developer wording, and not a raw code.
      expect(find.textContaining('requestId'), findsNothing);
      expect(find.textContaining('permission'), findsNothing);
    });

    for (final size in <String, Size>{
      'mobile': Size(390, 844),
      'tablet': Size(834, 1112),
      'desktop': Size(1440, 900),
    }.entries) {
      testWidgets('the report action and its picker fit ${size.key}', (
        tester,
      ) async {
        final service = _StubMessageService();
        final functions = _RecordingFunctions();
        await openChat(tester, service, functions, size: size.value);

        service.emit([messageFrom(otherUserId)]);
        await tester.pump();

        await tester.longPress(find.text('something abusive'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('report-message')));
        await tester.pumpAndSettle();

        // Every reason stays reachable at every width; the sheet is
        // width-capped on tablet/desktop rather than stretched edge to
        // edge, and scrolls rather than overflowing when it cannot fit.
        expect(find.text('Report this message'), findsOneWidget);
        for (final reason in ReportReason.values) {
          await tester.scrollUntilVisible(
            find.byKey(ValueKey('report-reason-${reason.name}')),
            60,
            scrollable: find.byType(Scrollable).last,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('long content and a long name do not break the flow', (
      tester,
    ) async {
      final service = _StubMessageService();
      final functions = _RecordingFunctions();

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MediaQuery(
            // The sheet's subtitle interpolates the other person's
            // display name, so a long name at a large text scale is the
            // case that would push its copy out of the sheet.
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.6),
              size: Size(390, 844),
            ),
            child: ChatScreen(
              conversationId: conversationId,
              otherUserId: otherUserId,
              otherDisplayName:
                  'Aleksandra-Katarzyna Wiśniewska-Kowalczyk the Third',
              otherEmail: '',
              otherPhotoUrl: '',
              messageService: service,
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: currentUserId),
              ),
              contentReportService: ContentReportService(functions: functions),
            ),
          ),
        ),
      );
      await tester.pump();

      service.emit([
        Message(
          id: 'm1',
          conversationId: conversationId,
          senderId: otherUserId,
          type: MessageType.text,
          // Long enough to wrap over many lines while its centre stays
          // on screen, so the gesture under test is the report gesture
          // and not a scrolling problem.
          content: 'abuse ' * 40,
          sentAt: DateTime.utc(2026, 3, 1, 12),
          readBy: const [currentUserId],
          reactions: const <String, String>{},
        ),
      ]);
      await tester.pump();

      await tester.longPress(find.textContaining('abuse').first);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('report-message')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('report-message')));
      await tester.pumpAndSettle();

      // No RenderFlex overflow from either the long name in the subtitle
      // or the enlarged reason rows.
      expect(tester.takeException(), isNull);
      expect(find.text('Report this message'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('report-reason-other')),
        60,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

class _Call {
  _Call(this.name, this.payload);
  final String name;
  final Map<String, dynamic> payload;
}

class _RecordingFunctions implements FirebaseFunctions {
  _RecordingFunctions({this.failure});

  final Object? failure;
  final calls = <_Call>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _RecordingCallable(this, name);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingCallable implements HttpsCallable {
  _RecordingCallable(this.owner, this.name);
  final _RecordingFunctions owner;
  final String name;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    owner.calls.add(_Call(name, Map<String, dynamic>.from(parameters! as Map)));
    final failure = owner.failure;
    if (failure != null) throw failure;
    return _FakeResult<T>({'reportId': 'r1', 'created': true} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResult<T> implements HttpsCallableResult<T> {
  _FakeResult(this.data);
  @override
  final T data;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Same shape as chat_mark_read_test's stub: a real [MessageService] over
/// a fake Firestore, with the message stream driven by the test.
class _StubMessageService extends MessageService {
  _StubMessageService()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me-uid'),
        ),
      );

  final StreamController<List<Message>> _messages =
      StreamController<List<Message>>.broadcast();

  void emit(List<Message> messages) => _messages.add(messages);

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      _messages.stream;

  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => Stream<bool>.value(false);

  @override
  Stream<ChatPresence> watchUserPresence(String userId) =>
      Stream<ChatPresence>.value(
        const ChatPresence(isOnline: false, lastSeen: null),
      );

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}
}
