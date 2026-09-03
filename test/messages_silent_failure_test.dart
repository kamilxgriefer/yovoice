import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/profile/profile_media_image.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// User actions stay recoverable while background bookkeeping stays quiet.
///
/// Reactions and un-archiving have actionable failure presentation. Typing
/// presence is deliberately best-effort: the sender cannot repair a rejected
/// heartbeat, so it remains diagnostic-only and must never cover the composer.
/// These tests pin both sides of that boundary and keep the real send recovery
/// path intact at narrow, medium and wide widths.
void main() {
  const currentUserId = 'me-uid';
  const otherUserId = 'them-uid';
  const conversationId = 'me-uid_them-uid';

  const narrow = Size(390, 844);
  const medium = Size(834, 1112);
  const wide = Size(1440, 900);

  late PublicIdentityRepository originalIdentityRepository;

  Widget host(
    Widget child, {
    ThemeData? theme,
    Locale locale = const Locale('en'),
  }) => MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: theme ?? AppTheme.darkTheme,
    home: child,
  );

  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Message messageFrom({
    required String id,
    required String senderId,
    required String content,
  }) {
    return Message(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      type: MessageType.text,
      content: content,
      sentAt: DateTime.utc(2026, 3, 1, 12),
      readBy: const [currentUserId],
      reactions: const <String, String>{},
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    // ChatScreen's header resolves identity badges through the shared
    // singleton; point it at a scripted fetcher so no Firebase app is
    // needed and the header settles deterministically.
    originalIdentityRepository = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: currentUserId),
      ),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
  });

  Future<void> pumpChat(
    WidgetTester tester,
    _StubMessageService service, {
    required Size size,
    TextScaler textScaler = TextScaler.noScaling,
    ThemeData? theme,
    Locale locale = const Locale('en'),
    ProfileService? profileService,
    DateTime? otherProfileUpdatedAt,
  }) async {
    useSurface(tester, size);
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: ChatScreen(
              conversationId: conversationId,
              otherUserId: otherUserId,
              otherDisplayName: 'Them',
              otherEmail: '',
              otherPhotoUrl: '',
              otherProfileUpdatedAt: otherProfileUpdatedAt,
              messageService: service,
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: currentUserId),
              ),
              profileService: profileService,
            ),
          ),
        ),
        theme: theme,
        locale: locale,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> sendAndWaitForQueuedMessage(
    WidgetTester tester,
    _StubMessageService service,
  ) async {
    // A tap does not await an async VoidCallback. Subscribe before tapping,
    // then wait for the outbox's post-persistence change notification rather
    // than merely observing the in-memory entry halfway through enqueue().
    final queued = service.outbox.changes.firstWhere(
      (entries) => entries.isNotEmpty,
    );
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.runAsync(() => queued.timeout(const Duration(seconds: 2)));
    await tester.pump();
  }

  Future<void> reactTo(WidgetTester tester, String messageText) async {
    await tester.longPress(find.text(messageText));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🔥'));
    await tester.pumpAndSettle();
  }

  group('direct messaging semantic themes', () {
    testWidgets('open chat invalidates avatar grants on profile revision', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: currentUserId),
      );
      final firstRevision = DateTime.utc(2026, 9, 1, 8);
      final secondRevision = DateTime.utc(2026, 9, 1, 9);
      await firestore.collection('publicProfiles').doc(otherUserId).set({
        'displayName': 'Them',
        'updatedAt': Timestamp.fromDate(firstRevision),
      });

      await pumpChat(
        tester,
        _StubMessageService(messages: const <Message>[]),
        size: narrow,
        profileService: ProfileService(firestore: firestore, auth: auth),
      );

      Iterable<ProfileMediaImage> avatarImages() => tester
          .widgetList<ProfileMediaImage>(find.byType(ProfileMediaImage))
          .where((image) => image.userId == otherUserId);

      expect(avatarImages(), isNotEmpty);
      expect(
        avatarImages().map(
          (image) => (image.revision! as DateTime).millisecondsSinceEpoch,
        ),
        everyElement(firstRevision.millisecondsSinceEpoch),
      );

      await firestore.collection('publicProfiles').doc(otherUserId).update({
        'updatedAt': Timestamp.fromDate(secondRevision),
      });
      await tester.pumpAndSettle();

      expect(
        avatarImages().map(
          (image) => (image.revision! as DateTime).millisecondsSinceEpoch,
        ),
        everyElement(secondRevision.millisecondsSinceEpoch),
      );
      expect(tester.takeException(), isNull);
    });

    for (final entry in <String, ThemeData>{
      'dark': AppTheme.darkTheme,
      'light': AppTheme.lightTheme,
    }.entries) {
      testWidgets(
        '${entry.key} chat pairs shell, header, composer and bubble',
        (tester) async {
          final service = _StubMessageService(
            messages: [
              messageFrom(
                id: 'theme-${entry.key}',
                senderId: otherUserId,
                content: 'Readable incoming message',
              ),
            ],
          );
          await pumpChat(tester, service, size: narrow, theme: entry.value);

          final palette = entry.value.extension<AppPalette>()!;
          final scaffold = tester.widget<Scaffold>(
            find.byKey(const ValueKey('chat-screen')),
          );
          expect(scaffold.backgroundColor, palette.background);

          final header = tester.widget<Container>(
            find.byKey(const ValueKey('chat-header')),
          );
          final headerDecoration = header.decoration! as BoxDecoration;
          expect(
            headerDecoration.color,
            palette.navigationSurface.withValues(alpha: .96),
          );

          final composer = tester.widget<Container>(
            find.byKey(const ValueKey('chat-composer')),
          );
          final composerDecoration = composer.decoration! as BoxDecoration;
          expect(composerDecoration.color, palette.navigationSurface);

          final bubble = tester.widget<Container>(
            find.byKey(const ValueKey('incoming-message-bubble')),
          );
          final bubbleDecoration = bubble.decoration! as BoxDecoration;
          expect(bubbleDecoration.color, palette.surfaceRaised);
          final copy = tester.widget<Text>(
            find.text('Readable incoming message'),
          );
          expect(copy.style?.color, palette.textPrimary);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final size in const <Size>[Size(320, 780), Size(768, 900)]) {
      testWidgets('light chat supports 200% text at ${size.width.toInt()}px', (
        tester,
      ) async {
        final service = _StubMessageService(
          messages: [
            messageFrom(
              id: 'scaled-${size.width}',
              senderId: otherUserId,
              content: 'A readable message at increased text size',
            ),
          ],
        );
        await pumpChat(
          tester,
          service,
          size: size,
          textScaler: const TextScaler.linear(2),
          theme: AppTheme.lightTheme,
        );

        expect(
          find.text('A readable message at increased text size'),
          findsOne,
        );
        expect(find.byTooltip('Start voice call'), findsOneWidget);
        expect(find.byTooltip('Add photo or video'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('light chat empty and history-error states remain readable', (
      tester,
    ) async {
      await pumpChat(
        tester,
        _StubMessageService(messages: const <Message>[]),
        size: narrow,
        theme: AppTheme.lightTheme,
      );
      expect(find.text('You are friends on YO Voice'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pumpAndSettle();
      await pumpChat(
        tester,
        _StubMessageService(
          messages: const <Message>[],
          messageStreamError: StateError('offline'),
        ),
        size: narrow,
        theme: AppTheme.lightTheme,
      );
      expect(find.text('Could not load this conversation.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('light chat loading state uses the themed primary', (
      tester,
    ) async {
      useSurface(tester, narrow);
      final service = _CancellableMessageService();
      addTearDown(service.close);
      await tester.pumpWidget(
        host(
          ChatScreen(
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
          ),
          theme: AppTheme.lightTheme,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2));

      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator).first,
      );
      expect(spinner.color, AppTheme.lightTheme.colorScheme.primary);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pumpAndSettle();
    });
  });

  group('a rejected reaction is reported, not swallowed', () {
    for (final entry in <String, Size>{
      'narrow': narrow,
      'medium': medium,
      'wide': wide,
    }.entries) {
      testWidgets('at ${entry.key} width', (tester) async {
        final service = _StubMessageService(
          messages: [
            messageFrom(
              id: 'm1',
              senderId: otherUserId,
              content: 'react to me',
            ),
          ],
          reactionFailure: FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'Missing or insufficient permissions.',
          ),
        );

        await pumpChat(tester, service, size: entry.value);
        await reactTo(tester, 'react to me');

        expect(service.reactionCalls, 1);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.text("You don't have permission to do that."),
          findsOneWidget,
        );
        // NOTE: no takeException() here — _MessageActionsSheet puts its
        // ListTiles inside a coloured Container with no Material ancestor,
        // which trips a pre-existing Flutter debug check unrelated to this
        // fix (reported separately).
      });
    }

    testWidgets('intentional copy is preserved verbatim', (tester) async {
      final service = _StubMessageService(
        messages: [
          messageFrom(id: 'm1', senderId: otherUserId, content: 'react to me'),
        ],
        reactionFailure: StateError('You must be signed in to use messages.'),
      );

      await pumpChat(tester, service, size: narrow);
      await reactTo(tester, 'react to me');

      expect(
        find.text('You must be signed in to use messages.'),
        findsOneWidget,
      );
    });

    testWidgets('an unrecognized failure still says something useful', (
      tester,
    ) async {
      final service = _StubMessageService(
        messages: [
          messageFrom(id: 'm1', senderId: otherUserId, content: 'react to me'),
        ],
        reactionFailure: Exception('boxed interop noise'),
      );

      await pumpChat(tester, service, size: narrow);
      await reactTo(tester, 'react to me');

      expect(find.text('Could not update your reaction.'), findsOneWidget);
      expect(
        find.textContaining('boxed interop noise'),
        findsNothing,
        reason: 'raw exception text must never reach the UI',
      );
    });

    testWidgets('a reaction that succeeds says nothing at all', (tester) async {
      final service = _StubMessageService(
        messages: [
          messageFrom(id: 'm1', senderId: otherUserId, content: 'react to me'),
        ],
      );

      await pumpChat(tester, service, size: narrow);
      await reactTo(tester, 'react to me');

      expect(service.reactionCalls, 1);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('typing presence is best-effort and never blocks the composer', () {
    testWidgets('a rejected heartbeat stays silent across later keystrokes', (
      tester,
    ) async {
      final service = _StubMessageService(
        messages: const <Message>[],
        typingFailure: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
          message: 'backend unavailable',
        ),
      );

      await pumpChat(tester, service, size: narrow);

      await tester.enterText(find.byType(TextField), 'h');
      await tester.pumpAndSettle();

      expect(service.typingCalls, greaterThanOrEqualTo(1));
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'typing is not an actionable failure for the sender',
      );

      final callsSoFar = service.typingCalls;
      await tester.enterText(find.byType(TextField), 'hello there');
      await tester.pumpAndSettle();

      expect(
        service.typingCalls,
        callsSoFar,
        reason: 'typing is a state transition, not one write per keystroke',
      );
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'presence failures stay silent for the whole visit',
      );
    });

    testWidgets('sending still works after a silent presence failure', (
      tester,
    ) async {
      final service = _StubMessageService(
        messages: const <Message>[],
        typingFailure: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
          message: 'backend unavailable',
        ),
      );

      await pumpChat(tester, service, size: wide);

      await tester.enterText(find.byType(TextField), 'still sendable');
      await tester.pumpAndSettle();

      await sendAndWaitForQueuedMessage(tester, service);

      expect(
        service.sentTexts,
        ['still sendable'],
        reason: 'a broken presence signal must not block the actual send',
      );
      expect(
        (tester.widget<TextField>(find.byType(TextField))).controller?.text,
        isEmpty,
        reason: 'the composer acknowledges the local queue, not network RTT',
      );
      expect(find.text('still sendable'), findsOneWidget);
      expect(find.text('Sending…'), findsOneWidget);
    });

    testWidgets('leaving serializes the final not-typing state', (
      tester,
    ) async {
      final service = _BlockingTypingMessageService();
      await pumpChat(tester, service, size: narrow);

      await tester.enterText(find.byType(TextField), 'hello');
      await service.firstStarted.future;

      // Dispose the route while the `true` write is still in flight. The
      // final `false` must wait behind it rather than racing in parallel.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      service.releaseFirst.complete();
      await tester.pumpAndSettle();

      expect(service.states, <bool>[true, false]);
      expect(service.maxInFlight, 1);
    });

    testWidgets('opening and leaving an unused chat sends no typing writes', (
      tester,
    ) async {
      final service = _StubMessageService(messages: const <Message>[]);
      await pumpChat(tester, service, size: narrow);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(service.typingCalls, 0);
    });

    testWidgets('a completed not-typing transition is not repeated on exit', (
      tester,
    ) async {
      final service = _BlockingTypingMessageService();
      service.releaseFirst.complete();
      await pumpChat(tester, service, size: narrow);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(service.states, <bool>[true, false]);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      expect(service.states, <bool>[true, false]);
    });

    testWidgets(
      'a terminal queued message stays visible with recovery actions',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final service = _StubMessageService(messages: const <Message>[]);
        await pumpChat(tester, service, size: narrow);

        await tester.enterText(find.byType(TextField), 'keep my words');
        await tester.pump();
        await sendAndWaitForQueuedMessage(tester, service);
        final entry = service.outbox.entries.single;
        await service.outbox.markFailed(
          entry.id,
          'permission denied internals',
        );
        await tester.pumpAndSettle();

        expect(find.text('keep my words'), findsOneWidget);
        expect(find.text('Not sent'), findsOneWidget);
        expect(
          find.text(
            "Messaging isn't available for this conversation. "
            "Check the person's profile or remove this message.",
          ),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Message status: Not sent'))
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Retry'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Remove'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(
          find.textContaining('permission denied internals'),
          findsNothing,
        );

        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(find.text('keep my words'), findsNothing);
        semantics.dispose();
      },
    );

    testWidgets(
      'terminal guidance is actionable Polish and never exposes backend text',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final service = _StubMessageService(messages: const <Message>[]);
        await pumpChat(
          tester,
          service,
          size: const Size(320, 720),
          textScaler: const TextScaler.linear(2),
          locale: const Locale('pl'),
        );

        final entry = await service.outbox.enqueue(
          conversationId: conversationId,
          recipientId: otherUserId,
          text: 'zachowaj tę wiadomość',
        );
        await service.outbox.markFailed(
          entry.id,
          'unavailable:private socket diagnostics',
        );
        await tester.pumpAndSettle();

        const guidance =
            'YO Voice nie może teraz połączyć się z usługą wiadomości. '
            'Sprawdź internet i spróbuj ponownie.';
        expect(find.text(guidance), findsOneWidget);
        expect(find.text('Nie wysłano'), findsOneWidget);
        expect(find.text('Spróbuj ponownie'), findsOneWidget);
        expect(find.text('Usuń'), findsOneWidget);
        expect(find.textContaining('private socket diagnostics'), findsNothing);
        expect(
          tester
              .getSemantics(
                find.bySemanticsLabel('Dlaczego nie wysłano: $guidance'),
              )
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );

    testWidgets('text Retry targets one entry and preserves its requestId', (
      tester,
    ) async {
      final service = _StubMessageService(messages: const <Message>[]);
      final entry = await service.outbox.enqueue(
        conversationId: conversationId,
        recipientId: otherUserId,
        text: 'retry this exact message',
      );
      final requestId = entry.requestId;
      await service.outbox.markFailed(entry.id, 'offline');
      await pumpChat(tester, service, size: narrow);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(service.retriedEntryIds, <String>[entry.id]);
      final retried = service.outbox.entries.single;
      expect(retried.id, entry.id);
      expect(retried.requestId, requestId);
      expect(retried.state, OutboxState.retrying);
      expect(tester.takeException(), isNull);
    });

    testWidgets('retry status and empty state reflow at 320px and 200% text', (
      tester,
    ) async {
      final emptyService = _StubMessageService(messages: const <Message>[]);
      await pumpChat(
        tester,
        emptyService,
        size: const Size(320, 640),
        textScaler: const TextScaler.linear(2),
      );

      expect(find.text('Say hello 👋'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), 'wait for the network');
      await tester.pump();
      await sendAndWaitForQueuedMessage(tester, emptyService);
      final entry = emptyService.outbox.entries.single;
      await emptyService.outbox.markRetry(entry.id, 'offline');
      await tester.pump();

      expect(find.text('Waiting for connection'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a local message never hides a server-history failure', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final service = _StubMessageService(
        messages: const <Message>[],
        messageStreamError: StateError('private Firestore diagnostics'),
      );
      final entry = await service.outbox.enqueue(
        conversationId: conversationId,
        recipientId: otherUserId,
        text: 'saved on this device',
      );
      await service.outbox.markFailed(entry.id, 'offline internals');

      await pumpChat(tester, service, size: narrow);

      expect(find.text('saved on this device'), findsOneWidget);
      expect(find.text('Could not load this conversation.'), findsOneWidget);
      expect(
        find.text('Your unsent messages are still shown.'),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(
              find.bySemanticsLabel(
                'Could not load this conversation. '
                'Your unsent messages are still shown.',
              ),
            )
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(
        find.textContaining('private Firestore diagnostics'),
        findsNothing,
      );
      semantics.dispose();
    });

    testWidgets('an enqueue rejection cannot lose an earlier draft', (
      tester,
    ) async {
      final service = _BlockingQueueMessageService();
      await pumpChat(tester, service, size: narrow);

      await tester.enterText(find.byType(TextField), 'first draft');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.runAsync(
        () => service.started.future.timeout(const Duration(seconds: 2)),
      );
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.readOnly,
        isTrue,
        reason: 'editing is paused only until the local durable enqueue ends',
      );

      // Defend against a late platform edit already in flight even though
      // the field is read-only for the normal interaction path.
      field.controller!.text = 'second draft';
      service.result.completeError(const OutboxFullException(50));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'first draft\nsecond draft',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).readOnly,
        isFalse,
      );
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving the screen mid-failure throws nothing', (
      tester,
    ) async {
      final service = _StubMessageService(
        messages: const <Message>[],
        typingFailure: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
          message: 'backend unavailable',
        ),
      );

      await pumpChat(tester, service, size: narrow);
      await tester.enterText(find.byType(TextField), 'abandon ship');
      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving cancels the one shared server-history listener', (
      tester,
    ) async {
      final service = _CancellableMessageService();
      addTearDown(service.close);
      service.controller.add(const <Message>[]);
      await pumpChat(tester, service, size: narrow);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(service.cancelCalls, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('a rejected un-archive is reported and still opens the chat', () {
    Future<void> pumpMessages(
      WidgetTester tester,
      _StubMessageService service, {
      required Size size,
      ThemeData? theme,
      TextScaler textScaler = TextScaler.noScaling,
      FriendService? friendService,
    }) async {
      useSurface(tester, size);
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: MessagesScreen(
                messageService: service,
                friendService: friendService ?? _StubFriendService(),
                auth: MockFirebaseAuth(
                  signedIn: true,
                  mockUser: MockUser(uid: currentUserId),
                ),
              ),
            ),
          ),
          theme: theme,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('chat list overlays the current friend avatar immediately', (
      tester,
    ) async {
      final friends = StreamController<List<FriendUser>>();
      addTearDown(friends.close);
      final service = _StubMessageService(
        messages: const <Message>[],
        conversations: [
          _archivedConversation().withParticipantIdentity(
            userId: otherUserId,
            displayName: 'Stale identity',
            photoUrl: 'fixture://stale-avatar',
          ),
        ],
      );
      await pumpMessages(
        tester,
        service,
        size: narrow,
        friendService: _StubFriendService(stream: friends.stream),
      );
      await tester.tap(find.byTooltip('Show archived conversations'));
      await tester.pump();

      friends.add(const [
        FriendUser(
          id: otherUserId,
          displayName: 'Fresh identity',
          email: '',
          photoUrl: null,
          isOnline: false,
          lastSeen: null,
        ),
      ]);
      await tester.pump();

      final listAvatar = tester
          .widgetList<UserAvatar>(find.byType(UserAvatar))
          .singleWhere((avatar) => avatar.radius == 29);
      expect(listAvatar.photoUrl, '');
      expect(find.text('Fresh identity'), findsWidgets);
      expect(find.bySemanticsLabel('Fresh identity, offline'), findsOneWidget);
      expect(find.bySemanticsLabel('New message'), findsOneWidget);
      final storyAvatar = tester
          .widgetList<UserAvatar>(find.byType(UserAvatar))
          .singleWhere(
            (avatar) =>
                avatar.radius == 27 && avatar.displayName == 'Fresh identity',
          );
      expect(storyAvatar.photoUrl, isNull);
      expect(storyAvatar.backgroundColor, const Color(0xFF64258E));

      final semanticFriend = find.semantics.byLabel('Fresh identity, offline');
      expect(
        semanticFriend.evaluate().single.getSemanticsData().hasAction(
          SemanticsAction.tap,
        ),
        isTrue,
      );
      tester.semantics.tap(semanticFriend);
      await tester.pumpAndSettle();
      final headerAvatar = tester
          .widgetList<UserAvatar>(find.byType(UserAvatar))
          .firstWhere((avatar) => avatar.radius == 20);
      expect(headerAvatar.photoUrl, '');
    });

    for (final size in const <Size>[Size(320, 780), Size(768, 900)]) {
      testWidgets(
        'light chats list is themed at ${size.width.toInt()}px / 200%',
        (tester) async {
          final service = _StubMessageService(
            messages: const <Message>[],
            conversations: [_archivedConversation()],
          );
          await pumpMessages(
            tester,
            service,
            size: size,
            theme: AppTheme.lightTheme,
            textScaler: const TextScaler.linear(2),
          );
          await tester.tap(find.byTooltip('Show archived conversations'));
          await tester.pumpAndSettle();

          final palette = AppTheme.lightTheme.extension<AppPalette>()!;
          final scaffold = tester.widget<Scaffold>(
            find.byKey(const ValueKey('messages-screen')),
          );
          expect(scaffold.backgroundColor, palette.background);
          final name = tester.widget<Text>(find.text('Them'));
          expect(name.style?.color, palette.textPrimary);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final entry in <String, Size>{
      'narrow': narrow,
      'wide': wide,
    }.entries) {
      testWidgets('at ${entry.key} width', (tester) async {
        final service = _StubMessageService(
          messages: const <Message>[],
          conversations: [_archivedConversation()],
          unarchiveFailure: FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'Missing or insufficient permissions.',
          ),
        );

        await pumpMessages(tester, service, size: entry.value);
        await tester.tap(find.byTooltip('Show archived conversations'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Them'));
        await tester.pumpAndSettle();

        expect(service.unarchiveCalls, 1);
        expect(
          find.text("You don't have permission to do that."),
          findsOneWidget,
          reason: 'the tap used to do nothing and say nothing',
        );
        expect(
          find.byType(ChatScreen),
          findsOneWidget,
          reason: 'opening was the intent; un-archiving was the side effect',
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a successful un-archive opens the chat silently', (
      tester,
    ) async {
      final service = _StubMessageService(
        messages: const <Message>[],
        conversations: [_archivedConversation()],
      );

      await pumpMessages(tester, service, size: narrow);
      await tester.tap(find.byTooltip('Show archived conversations'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Them'));
      await tester.pumpAndSettle();

      expect(service.unarchiveCalls, 1);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}

Conversation _archivedConversation() {
  return Conversation(
    id: 'me-uid_them-uid',
    participantIds: const ['me-uid', 'them-uid'],
    participantNames: const {'me-uid': 'Me', 'them-uid': 'Them'},
    participantEmails: const {'me-uid': '', 'them-uid': ''},
    participantPhotoUrls: const {'me-uid': '', 'them-uid': ''},
    unreadCounts: const {'me-uid': 0, 'them-uid': 0},
    archivedBy: const ['me-uid'],
    mutedBy: const <String>[],
    lastMessage: 'an archived thread',
    lastMessageType: MessageType.text,
    lastMessageSenderId: 'them-uid',
    updatedAt: DateTime.utc(2026, 3, 1, 12),
    createdAt: DateTime.utc(2026, 3, 1, 11),
  );
}

/// The friends list is not under test here; MessagesScreen only needs the
/// stream so the "new message" sheet has something to show.
class _StubFriendService extends FriendService {
  _StubFriendService({Stream<List<FriendUser>>? stream})
    : _stream = stream,
      super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me-uid'),
        ),
      );

  final Stream<List<FriendUser>>? _stream;

  @override
  Stream<List<FriendUser>> watchFriends() =>
      _stream ?? Stream<List<FriendUser>>.value(const <FriendUser>[]);
}

/// A [MessageService] whose individual operations can be failed on demand.
///
/// It extends the real service (over a fake Firestore that nothing here
/// reads) so the screens keep their real types and only the calls under
/// test are scripted.
class _StubMessageService extends MessageService {
  _StubMessageService({
    required this.messages,
    this.conversations = const <Conversation>[],
    this.messageStreamError,
    this.reactionFailure,
    this.typingFailure,
    this.unarchiveFailure,
  }) : super(
         firestore: FakeFirebaseFirestore(),
         auth: MockFirebaseAuth(
           signedIn: true,
           mockUser: MockUser(uid: 'me-uid'),
         ),
       );

  final List<Message> messages;
  final List<Conversation> conversations;
  final Object? messageStreamError;
  final Object? reactionFailure;
  final Object? typingFailure;
  final Object? unarchiveFailure;

  int reactionCalls = 0;
  int typingCalls = 0;
  int unarchiveCalls = 0;
  final List<String> sentTexts = <String>[];
  final List<String> retriedEntryIds = <String>[];

  @override
  Stream<List<Message>> watchMessages(String conversationId) {
    final error = messageStreamError;
    return error == null
        ? Stream<List<Message>>.value(messages)
        : Stream<List<Message>>.error(error);
  }

  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) => Stream<List<Conversation>>.value(conversations);

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
  }) async {
    typingCalls++;
    if (typingFailure != null) throw typingFailure!;
  }

  @override
  Future<void> toggleReaction({
    required String conversationId,
    required String messageId,
    required String emoji,
  }) async {
    reactionCalls++;
    if (reactionFailure != null) throw reactionFailure!;
  }

  @override
  Future<void> unarchiveConversation(String conversationId) async {
    unarchiveCalls++;
    if (unarchiveFailure != null) throw unarchiveFailure!;
  }

  @override
  Future<void> retryFailedMessage(String entryId) async {
    retriedEntryIds.add(entryId);
    await outbox.markRetry(entryId, 'manual retry');
  }

  @override
  Future<OutboxEntry> queueTextMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    Message? replyTo,
  }) async {
    sentTexts.add(text);
    return outbox.enqueue(
      conversationId: conversationId,
      recipientId: recipientId,
      text: text,
      replyToMessageId: replyTo?.id,
    );
  }
}

class _BlockingTypingMessageService extends _StubMessageService {
  _BlockingTypingMessageService() : super(messages: const <Message>[]);

  final Completer<void> firstStarted = Completer<void>();
  final Completer<void> releaseFirst = Completer<void>();
  final List<bool> states = <bool>[];
  int _inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {
    states.add(isTyping);
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      if (isTyping && !firstStarted.isCompleted) {
        firstStarted.complete();
        await releaseFirst.future;
      }
    } finally {
      _inFlight--;
    }
  }
}

class _BlockingQueueMessageService extends _StubMessageService {
  _BlockingQueueMessageService() : super(messages: const <Message>[]);

  final Completer<void> started = Completer<void>();
  final Completer<OutboxEntry> result = Completer<OutboxEntry>();

  @override
  Future<OutboxEntry> queueTextMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    Message? replyTo,
  }) {
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

class _CancellableMessageService extends _StubMessageService {
  _CancellableMessageService() : super(messages: const <Message>[]) {
    controller = StreamController<List<Message>>(onCancel: () => cancelCalls++);
  }

  late final StreamController<List<Message>> controller;
  int cancelCalls = 0;

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      controller.stream;

  Future<void> close() => controller.close();
}
