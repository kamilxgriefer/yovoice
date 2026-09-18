import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/active_conversation_registry.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/inputs/yo_composer_panel.dart';

/// "Nie można zniżać klawiatury podczas pisania czasami" (2026-09-18).
///
/// The keyboard in a direct chat has to go away when the person says so and
/// stay away until they ask for it back. Each test here is one way the
/// composer either put the keyboard back on its own or never offered a way
/// to put it away. `TestTextInput.isVisible` is the keyboard: it follows the
/// `TextInput.show` / `TextInput.hide` / `TextInput.clearClient` traffic the
/// framework sends to the platform, which is exactly what a phone acts on.
void main() {
  const currentUserId = 'me-uid';
  const otherUserId = 'them-uid';
  const conversationId = 'me-uid_them-uid';
  const phone = Size(390, 844);

  late PublicIdentityRepository originalIdentityRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await YoComposerPanelTabStore.instance.remember(YoComposerPanelTab.emoji);
    ActiveConversationRegistry.instance.clear();
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
    ActiveConversationRegistry.instance.clear();
    debugDefaultTargetPlatformOverride = null;
  });

  Message messageFrom({
    required String id,
    required String senderId,
    required String content,
  }) => Message(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    type: MessageType.text,
    content: content,
    sentAt: DateTime.utc(2026, 9, 18, 12),
    readBy: const [currentUserId],
    reactions: const <String, String>{},
  );

  final thread = <Message>[
    messageFrom(id: 'm2', senderId: otherUserId, content: 'How are you?'),
    messageFrom(id: 'm1', senderId: currentUserId, content: 'Hi there'),
  ];

  Future<void> pumpChat(
    WidgetTester tester,
    _StubMessageService service, {
    DirectMessageVoiceRecorderPresenter? voiceRecorderPresenter,
  }) async {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
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
          voiceRecorderPresenter: voiceRecorderPresenter,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The composer's own field, never a search field inside a panel.
  final composer = find.descendant(
    of: find.byKey(const ValueKey('chat-composer')),
    matching: find.byType(TextField),
  );
  final panel = find.byKey(const ValueKey('composer-panel'));
  final thread2 = find.text('How are you?');

  FocusNode focusOf(WidgetTester tester) =>
      tester.widget<TextField>(composer).focusNode!;

  bool keyboardVisible(WidgetTester tester) => tester.testTextInput.isVisible;

  List<String> textInputCallsSince(WidgetTester tester, int mark) => tester
      .testTextInput
      .log
      .skip(mark)
      .map((call) => call.method)
      .toList(growable: false);

  Future<void> focusComposer(WidgetTester tester) async {
    await tester.tap(composer);
    await tester.pumpAndSettle();
    expect(focusOf(tester).hasFocus, isTrue);
    expect(keyboardVisible(tester), isTrue);
  }

  testWidgets('a send never puts the keyboard away', (tester) async {
    final service = _BlockingQueueMessageService(thread);
    await pumpChat(tester, service);
    await focusComposer(tester);
    await tester.enterText(composer, 'hello');
    await tester.pump();
    final mark = tester.testTextInput.log.length;

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.runAsync(
      () => service.started.future.timeout(const Duration(seconds: 2)),
    );
    await tester.pump();
    await tester.pump();

    // In flight: the field is paused, not read-only. A read-only field closes
    // its input connection on Android and iOS — that is the keyboard dipping
    // on every send, and climbing back once the enqueue ends.
    expect(
      keyboardVisible(tester),
      isTrue,
      reason: 'the in-flight enqueue must not close the keyboard connection',
    );
    expect(tester.widget<TextField>(composer).readOnly, isFalse);
    expect(
      textInputCallsSince(tester, mark),
      isNot(
        anyOf(contains('TextInput.hide'), contains('TextInput.clearClient')),
      ),
    );
    await tester.enterText(composer, 'typed while saving');
    await tester.pump();
    expect(
      tester.widget<TextField>(composer).controller!.text,
      isEmpty,
      reason: 'no keystroke lands between "send" and the durable enqueue',
    );

    await tester.runAsync(() async {
      service.result.complete(
        await service.outbox.enqueue(
          conversationId: conversationId,
          recipientId: otherUserId,
          text: 'hello',
        ),
      );
    });
    await tester.pumpAndSettle();

    expect(keyboardVisible(tester), isTrue);
    expect(focusOf(tester).hasFocus, isTrue);
    expect(
      textInputCallsSince(tester, mark),
      isNot(
        anyOf(contains('TextInput.hide'), contains('TextInput.clearClient')),
      ),
      reason: 'the whole send cycle sends no hide at all',
    );
    await tester.enterText(composer, 'again');
    expect(tester.widget<TextField>(composer).controller!.text, 'again');
  });

  testWidgets('tapping the thread puts the keyboard away', (tester) async {
    await pumpChat(tester, _StubMessageService(thread));
    await focusComposer(tester);

    await tester.tap(thread2);
    await tester.pumpAndSettle();

    expect(focusOf(tester).hasFocus, isFalse);
    expect(keyboardVisible(tester), isFalse);
  });

  testWidgets('dragging the thread puts the keyboard away', (tester) async {
    await pumpChat(tester, _StubMessageService(thread));
    await focusComposer(tester);

    expect(
      tester.widget<ListView>(find.byType(ListView)).keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.onDrag,
    );
    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pumpAndSettle();

    expect(focusOf(tester).hasFocus, isFalse);
    expect(keyboardVisible(tester), isFalse);
  });

  testWidgets('the composer itself is not "outside": send keeps the keyboard', (
    tester,
  ) async {
    final service = _StubMessageService(thread);
    await pumpChat(tester, service);
    await focusComposer(tester);
    await tester.enterText(composer, 'hello');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(focusOf(tester).hasFocus, isTrue);
    expect(keyboardVisible(tester), isTrue);
  });

  testWidgets('a typing or presence update never brings a dismissed keyboard '
      'back', (tester) async {
    final service = _StubMessageService(thread);
    await pumpChat(tester, service);
    await focusComposer(tester);

    // The OS hid the keyboard (Android Back): focus stays, the field must
    // not ask for it back when the thread rebuilds around it.
    tester.testTextInput.hide();
    final mark = tester.testTextInput.log.length;
    service.typing.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    service.presence.add(const ChatPresence(isOnline: true, lastSeen: null));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    service.typing.add(false);
    await tester.pumpAndSettle();

    expect(keyboardVisible(tester), isFalse);
    expect(
      textInputCallsSince(tester, mark),
      isNot(contains('TextInput.show')),
    );

    // Same after a deliberate dismissal.
    await tester.tap(thread2);
    await tester.pumpAndSettle();
    service.typing.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    service.typing.add(false);
    await tester.pumpAndSettle();

    expect(focusOf(tester).hasFocus, isFalse);
    expect(keyboardVisible(tester), isFalse);
  });

  testWidgets('opening the panel from an idle composer leaves the keyboard '
      'down', (tester) async {
    await pumpChat(tester, _StubMessageService(thread));
    expect(focusOf(tester).hasFocus, isFalse);
    final mark = tester.testTextInput.log.length;

    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pumpAndSettle();

    expect(panel, findsOneWidget);
    expect(focusOf(tester).hasFocus, isTrue, reason: 'the caret survives');
    expect(
      keyboardVisible(tester),
      isFalse,
      reason: 'the panel replaces the keyboard; both at once is the bug',
    );
    final calls = textInputCallsSince(tester, mark);
    expect(
      calls.lastIndexOf('TextInput.show'),
      lessThan(calls.lastIndexOf('TextInput.hide')),
      reason: 'the focus change shows first, then the hide wins: $calls',
    );
  });

  testWidgets('closing the panel from its button brings the keyboard back', (
    tester,
  ) async {
    await pumpChat(tester, _StubMessageService(thread));
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pumpAndSettle();
    expect(keyboardVisible(tester), isFalse);
    final mark = tester.testTextInput.log.length;

    await tester.tap(find.byIcon(Icons.keyboard_alt_outlined));
    await tester.pumpAndSettle();

    expect(panel, findsNothing);
    expect(focusOf(tester).hasFocus, isTrue);
    expect(keyboardVisible(tester), isTrue);
    expect(textInputCallsSince(tester, mark), contains('TextInput.show'));
  });

  testWidgets('Android Back closes the panel and keeps the chat', (
    tester,
  ) async {
    // Reset inside the body: the binding checks foundation debug variables
    // before any tearDown runs.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpChat(tester, _StubMessageService(thread));
      await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      final mark = tester.testTextInput.log.length;

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue, reason: 'Back was consumed by the panel');
      expect(panel, findsNothing);
      expect(find.byKey(const ValueKey('chat-screen')), findsOneWidget);
      expect(focusOf(tester).hasFocus, isTrue);
      expect(
        keyboardVisible(tester),
        isFalse,
        reason: 'Back puts things away; it never raises the keyboard',
      );
      expect(
        textInputCallsSince(tester, mark),
        isNot(contains('TextInput.show')),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS keeps the route poppable while the panel is open', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpChat(tester, _StubMessageService(thread));
      await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);

      expect(
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop,
        isTrue,
        reason:
            'no Back button on iOS; canPop false would only kill swipe-back',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the media sheet does not hand the keyboard back', (
    tester,
  ) async {
    await pumpChat(tester, _StubMessageService(thread));
    await focusComposer(tester);

    await tester.tap(find.byIcon(Icons.camera_alt_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Add media'), findsOneWidget);
    // Dismiss through the barrier, as a change of mind would.
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(find.text('Add media'), findsNothing);

    expect(focusOf(tester).hasFocus, isFalse);
    expect(
      keyboardVisible(tester),
      isFalse,
      reason: 'the route must not restore focus to the composer on pop',
    );
  });

  testWidgets('the voice recorder opens with the keyboard already away', (
    tester,
  ) async {
    var keyboardVisibleWhenPresented = true;
    var composerFocusedWhenPresented = true;
    await pumpChat(
      tester,
      _StubMessageService(thread),
      voiceRecorderPresenter: (_) async {
        // `unfocus()` is applied by the focus manager one microtask later,
        // exactly as it would be under the real sheet's route push; read the
        // state the sheet would see, not the one the tap handler sees.
        await Future<void>.value();
        keyboardVisibleWhenPresented = tester.testTextInput.isVisible;
        composerFocusedWhenPresented = focusOf(tester).hasFocus;
      },
    );
    await focusComposer(tester);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pumpAndSettle();

    expect(composerFocusedWhenPresented, isFalse);
    expect(keyboardVisibleWhenPresented, isFalse);
    expect(keyboardVisible(tester), isFalse);
  });
}

class _StubMessageService extends MessageService {
  _StubMessageService(this.messages)
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me-uid'),
        ),
      );

  final List<Message> messages;
  final StreamController<bool> typing = StreamController<bool>.broadcast();
  final StreamController<ChatPresence> presence =
      StreamController<ChatPresence>.broadcast();

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream<List<Message>>.value(messages);

  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => typing.stream;

  @override
  Stream<ChatPresence> watchUserPresence(String userId) => presence.stream;

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}

  /// The durable enqueue only — never the dispatcher, whose retry timer
  /// would outlive the test.
  @override
  Future<OutboxEntry> queueTextMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    Message? replyTo,
  }) => outbox.enqueue(
    conversationId: conversationId,
    recipientId: recipientId,
    text: text,
    replyToMessageId: replyTo?.id,
  );
}

class _BlockingQueueMessageService extends _StubMessageService {
  _BlockingQueueMessageService(super.messages);

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
