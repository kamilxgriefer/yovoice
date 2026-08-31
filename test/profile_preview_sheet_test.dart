import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

typedef _OpenConversation =
    Future<String> Function({
      required String otherUserId,
      required String otherDisplayName,
      required String otherEmail,
      required String otherPhotoUrl,
    });

class _PreviewMessageService extends MessageService {
  _PreviewMessageService({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required _OpenConversation openConversation,
    MessageOutbox? outbox,
  }) : _openConversation = openConversation,
       super(
         firestore: firestore,
         auth: auth,
         outbox: outbox ?? MessageOutbox(preferences: null),
       );

  final _OpenConversation _openConversation;

  @override
  Future<String> openOrCreateConversation({
    required String otherUserId,
    required String otherDisplayName,
    required String otherEmail,
    required String otherPhotoUrl,
  }) => _openConversation(
    otherUserId: otherUserId,
    otherDisplayName: otherDisplayName,
    otherEmail: otherEmail,
    otherPhotoUrl: otherPhotoUrl,
  );

  @override
  Future<OutboxEntry> queueTextMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    Message? replyTo,
  }) {
    return outbox.enqueue(
      conversationId: conversationId,
      recipientId: recipientId,
      text: text,
      replyToMessageId: replyTo?.id,
    );
  }
}

Future<FocusNode> _openPreview(
  WidgetTester tester, {
  required Size size,
  TextScaler textScaler = TextScaler.noScaling,
  ThemeData? theme,
  FriendMutationInvoker? friendMutationInvoker,
  _OpenConversation? openConversation,
  String statusMessage =
      'Recording a new episode https://open.spotify.com/episode/123',
  String accountType = 'creator',
  bool isFriend = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final firestore = FakeFirebaseFirestore();
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
  );
  await firestore.collection('users').doc('me').set({
    'uid': 'me',
    'displayName': 'Me',
  });
  await firestore.collection('publicProfiles').doc('creator').set({
    'uid': 'creator',
    'displayName': 'Maya Voice With A Deliberately Long Creator Name',
    'username': 'mayavoice',
    'bio':
        'Independent interviews, culture, music, design and thoughtful '
        'conversations from communities around the world.',
    'statusMessage': statusMessage,
    'accountType': accountType,
    'premiumIdentity': true,
    'isOnline': true,
    'followerCount': 1842,
  });
  if (isFriend) {
    await firestore
        .collection('users')
        .doc('me')
        .collection('friends')
        .doc('creator')
        .set({'uid': 'creator'});
  }

  final launcherFocus = FocusNode(debugLabel: 'profile-preview-launcher');
  addTearDown(launcherFocus.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              focusNode: launcherFocus,
              onPressed: () => unawaited(
                showProfilePreview(
                  context,
                  userId: 'creator',
                  displayName: 'Maya Voice',
                  firestore: firestore,
                  auth: auth,
                  friendService: friendMutationInvoker == null
                      ? null
                      : FriendService(
                          firestore: firestore,
                          auth: auth,
                          mutationInvoker: friendMutationInvoker,
                        ),
                  messageService: openConversation == null
                      ? null
                      : _PreviewMessageService(
                          firestore: firestore,
                          auth: auth,
                          openConversation: openConversation,
                        ),
                ),
              ),
              child: const Text('Open profile preview'),
            ),
          ),
        ),
      ),
    ),
  );

  launcherFocus.requestFocus();
  await tester.pump();
  await tester.tap(find.text('Open profile preview'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return launcherFocus;
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + .05) / (darker + .05);
}

void _expectProfileFactChipContrast(
  WidgetTester tester, {
  required String kind,
  required String label,
  required Color expectedSurface,
  required Color expectedForeground,
  required Color expectedBorder,
  required Color expectedAdjacentSurface,
}) {
  final chip = find.byKey(ValueKey<String>('profile-preview-$kind-chip'));
  expect(chip, findsOneWidget);

  final container = tester.widget<Container>(chip);
  final decoration = container.decoration! as BoxDecoration;
  final border = decoration.border! as Border;
  final text = tester.widget<Text>(
    find.descendant(of: chip, matching: find.text(label)),
  );
  final icon = tester.widget<Icon>(
    find.descendant(of: chip, matching: find.byType(Icon)),
  );

  expect(decoration.color, expectedSurface);
  expect(text.style!.color, expectedForeground);
  expect(icon.color, expectedForeground);
  expect(border.top.color, expectedBorder);
  expect(
    _contrastRatio(text.style!.color!, decoration.color!),
    greaterThanOrEqualTo(4.5),
    reason: '$label text must meet WCAG 2.1 AA',
  );
  expect(
    _contrastRatio(icon.color!, decoration.color!),
    greaterThanOrEqualTo(3),
    reason: '$label icon must meet WCAG 1.4.11',
  );
  expect(
    _contrastRatio(border.top.color, decoration.color!),
    greaterThanOrEqualTo(3),
    reason: '$label inner boundary must meet WCAG 1.4.11',
  );
  expect(
    _contrastRatio(border.top.color, expectedAdjacentSurface),
    greaterThanOrEqualTo(3),
    reason: '$label outer boundary must meet WCAG 1.4.11',
  );
  expect(text.style!.fontSize, greaterThanOrEqualTo(12));
}

void main() {
  for (final variant in <({String name, ThemeData theme, AppPalette palette})>[
    (name: 'Dark', theme: AppTheme.darkTheme, palette: AppPalette.dark),
    (name: 'Pearl', theme: AppTheme.lightTheme, palette: AppPalette.light),
  ]) {
    testWidgets(
      '${variant.name} Creator and Friends preview chips use AA semantic pairs',
      (tester) async {
        await _openPreview(
          tester,
          size: const Size(390, 844),
          theme: variant.theme,
          statusMessage: '',
          isFriend: true,
        );

        _expectProfileFactChipContrast(
          tester,
          kind: 'creator',
          label: 'Creator',
          expectedSurface: variant.palette.surfaceMuted,
          expectedForeground: variant.palette.interactiveForeground,
          expectedBorder: variant.palette.interactiveForeground,
          expectedAdjacentSurface: variant.palette.surface,
        );
        _expectProfileFactChipContrast(
          tester,
          kind: 'friends',
          label: 'Friends',
          expectedSurface: variant.palette.successSurface,
          expectedForeground: variant.palette.successForeground,
          expectedBorder: variant.palette.successForeground,
          expectedAdjacentSurface: variant.palette.surface,
        );
      },
    );

    testWidgets(
      '${variant.name} Official preview chip uses an AA semantic info pair',
      (tester) async {
        await _openPreview(
          tester,
          size: const Size(390, 844),
          theme: variant.theme,
          statusMessage: '',
          accountType: 'official',
        );

        _expectProfileFactChipContrast(
          tester,
          kind: 'official',
          label: 'Official',
          expectedSurface: variant.palette.infoSurface,
          expectedForeground: variant.palette.infoForeground,
          expectedBorder: variant.palette.infoForeground,
          expectedAdjacentSurface: variant.palette.surface,
        );
      },
    );
  }

  for (final size in const <Size>[
    Size(320, 640),
    Size(390, 844),
    Size(430, 900),
    Size(768, 900),
    Size(1100, 900),
    Size(1440, 900),
    Size(2560, 1440),
  ]) {
    testWidgets('profile preview stays reachable at 200% and ${size.width}', (
      tester,
    ) async {
      await _openPreview(
        tester,
        size: size,
        textScaler: const TextScaler.linear(2),
      );

      expect(find.byType(ProfilePreviewSheet), findsOneWidget);
      expect(find.text('Recording a new episode'), findsOneWidget);
      final vibeLink = find.bySemanticsLabel(
        'Open in Spotify, open.spotify.com',
      );
      expect(vibeLink, findsOneWidget);
      expect(tester.getSize(vibeLink).height, greaterThanOrEqualTo(48));
      final close = find.bySemanticsLabel('Close profile preview');
      expect(close, findsOneWidget);
      expect(
        find.byKey(const ValueKey('modal-sheet-drag-handle')),
        size.width < 1100 ? findsOneWidget : findsNothing,
      );
      final closeTopBefore = tester.getTopLeft(close).dy;

      final fullProfile = find.text('View full profile');
      await tester.ensureVisible(fullProfile);
      await tester.pump(const Duration(milliseconds: 300));

      final fullProfileRect = tester.getRect(fullProfile);
      expect(fullProfileRect.top, greaterThanOrEqualTo(0));
      expect(fullProfileRect.bottom, lessThanOrEqualTo(size.height));
      expect(tester.getTopLeft(close).dy, closeTo(closeTopBefore, .1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Close dismisses profile preview and restores launcher focus', (
    tester,
  ) async {
    final launcherFocus = await _openPreview(
      tester,
      size: const Size(390, 844),
      theme: AppTheme.lightTheme,
    );

    await tester.tap(find.bySemanticsLabel('Close profile preview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ProfilePreviewSheet), findsNothing);
    expect(launcherFocus.hasFocus, isTrue);
  });

  testWidgets('profile preview keeps bio as the fallback when Vibe is empty', (
    tester,
  ) async {
    await _openPreview(tester, size: const Size(390, 844), statusMessage: '');

    expect(
      find.text(
        'Independent interviews, culture, music, design and thoughtful '
        'conversations from communities around the world.',
      ),
      findsOneWidget,
    );
    expect(find.text('VIBE'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^Open in ')), findsNothing);
  });

  testWidgets('reciprocal request immediately renders Friends, not Requested', (
    tester,
  ) async {
    final calls = <({String name, Map<String, dynamic> data})>[];
    await _openPreview(
      tester,
      size: const Size(390, 844),
      friendMutationInvoker: (name, data) async {
        calls.add((name: name, data: data));
        return const <String, dynamic>{'changed': true, 'outcome': 'accepted'};
      },
    );

    final addFriend = find.text('Add friend');
    await tester.ensureVisible(addFriend);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(addFriend);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls, hasLength(1));
    expect(calls.single.name, 'sendFriendRequest');
    expect(calls.single.data, {'targetUserId': 'creator'});
    expect(find.text('Friends'), findsWidgets);
    expect(find.text('Requested'), findsNothing);
  });

  testWidgets(
    'Message from a nested sheet closes the preview and opens one chat',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
      );
      await firestore.collection('users').doc('me').set({
        'uid': 'me',
        'displayName': 'Me',
      });
      await firestore.collection('publicProfiles').doc('creator').set({
        'uid': 'creator',
        'displayName': 'Otee',
        'username': 'Otee',
        'email': 'otee@yovoice.app',
        'accountType': 'user',
        'isOnline': false,
      });
      await firestore.collection('conversations').doc('me_creator').set({
        'participantIds': ['me', 'creator'],
        'unreadCounts': {'me': 0, 'creator': 0},
        'typing': <String, Object?>{},
      });

      var openCalls = 0;
      final openConversation = Completer<String>();
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final messages = _PreviewMessageService(
        firestore: firestore,
        auth: auth,
        outbox: MessageOutbox(preferences: preferences, storageKey: null),
        openConversation:
            ({
              required otherUserId,
              required otherDisplayName,
              required otherEmail,
              required otherPhotoUrl,
            }) async {
              openCalls += 1;
              expect(otherUserId, 'creator');
              return openConversation.future;
            },
      );
      addTearDown(messages.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => unawaited(
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (parentSheetContext) => Material(
                      child: Center(
                        child: FilledButton(
                          onPressed: () => unawaited(
                            showProfilePreview(
                              parentSheetContext,
                              userId: 'creator',
                              displayName: 'Otee',
                              firestore: firestore,
                              auth: auth,
                              messageService: messages,
                            ),
                          ),
                          child: const Text('Open nested profile'),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('Open parent sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open parent sheet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open nested profile'));
      await tester.pumpAndSettle();

      final message = find.widgetWithText(FilledButton, 'Message');
      expect(message, findsOneWidget);
      await tester.tap(message);
      await tester.tap(message);
      await tester.pump();

      expect(openCalls, 1);
      expect(find.byType(ProfilePreviewSheet), findsOneWidget);
      expect(find.text('Opening…'), findsOneWidget);
      expect(find.bySemanticsLabel('Opening chat…'), findsOneWidget);

      openConversation.complete('me_creator');
      await tester.pumpAndSettle();

      expect(openCalls, 1);
      expect(find.byType(ProfilePreviewSheet), findsNothing);
      expect(find.byType(ChatScreen), findsOneWidget);

      final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
      expect(identical(chat.messageService, messages), isTrue);
      expect(identical(chat.auth, auth), isTrue);

      // The routed Chat must reconcile optimistic and server messages under
      // the same injected UID. Using global Auth here would leave two bubbles
      // (and could render the committed one as somebody else's message).
      const text = 'same injected identity';
      final entry = await messages.queueTextMessage(
        conversationId: 'me_creator',
        recipientId: 'creator',
        text: text,
      );
      await tester.pump();
      expect(find.text(text), findsOneWidget);
      final messageId = messages.messageIdForQueuedText(entry, senderId: 'me');
      await firestore
          .collection('conversations')
          .doc('me_creator')
          .collection('messages')
          .doc(messageId)
          .set({
            'conversationId': 'me_creator',
            'senderId': 'me',
            'type': 'text',
            'content': text,
            'sentAt': Timestamp.fromDate(DateTime.utc(2026, 8, 27)),
            'readBy': ['me'],
            'reactions': <String, String>{},
            'isDeleted': false,
          });
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      expect(
        find.bySemanticsLabel('Open actions for your message'),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Open nested profile'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('Message failure remains visible inside the profile preview', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var openCalls = 0;
    await _openPreview(
      tester,
      size: const Size(320, 640),
      textScaler: const TextScaler.linear(2),
      openConversation:
          ({
            required otherUserId,
            required otherDisplayName,
            required otherEmail,
            required otherPhotoUrl,
          }) async {
            openCalls += 1;
            throw Exception('network connection unavailable');
          },
    );

    final message = find.widgetWithText(FilledButton, 'Message');
    await tester.ensureVisible(message);
    await tester.tap(message);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    const error = 'This is taking longer than expected. Please try again.';
    expect(openCalls, 1);
    expect(find.byType(ProfilePreviewSheet), findsOneWidget);
    expect(find.text(error), findsOneWidget);
    expect(find.bySemanticsLabel(error), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    await tester.scrollUntilVisible(
      find.text(error),
      120,
      scrollable: find.descendant(
        of: find.byType(ProfilePreviewSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final errorRect = tester.getRect(find.text(error));
    final sheetRect = tester.getRect(find.byType(ProfilePreviewSheet));
    expect(errorRect.top, greaterThanOrEqualTo(0));
    expect(
      errorRect.bottom,
      lessThanOrEqualTo(640),
      reason: 'error=$errorRect sheet=$sheetRect',
    );
    semantics.dispose();
  });
}
