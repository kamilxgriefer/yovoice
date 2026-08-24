import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

Conversation _conversation(
  int index, {
  String photoUrl = '',
  int unread = 123,
}) {
  const me = 'me';
  final friend = 'friend-$index';
  return Conversation(
    id: 'conversation-$index',
    participantIds: [me, friend],
    participantNames: {
      me: 'Me',
      friend: 'A very long display name for a close friend number $index',
    },
    participantEmails: {me: 'me@example.com', friend: 'friend@example.com'},
    participantPhotoUrls: {if (photoUrl.isNotEmpty) friend: photoUrl},
    unreadCounts: {me: unread, friend: 0},
    lastMessage:
        'A longer preview that must remain readable at increased text scale.',
    lastMessageType: MessageType.text,
    lastMessageSenderId: friend,
    updatedAt: DateTime(2026, 8, 16),
    createdAt: DateTime(2026, 8, 16),
    archivedBy: const [],
    mutedBy: const [],
  );
}

void main() {
  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    testWidgets('recent chats reflows cleanly at ${width.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: RecentChats(
                snapshot: AsyncSnapshot.withData(ConnectionState.active, [
                  _conversation(0),
                  _conversation(1),
                  _conversation(2),
                ]),
                currentUserId: 'me',
                onOpenConversation: (_) {},
                onFindFriends: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('A very long display name'), findsNWidgets(3));
      expect(find.byType(UserAvatar), findsNWidgets(3));
      expect(tester.getSize(find.byType(RecentChats)).height, 148);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('recent chats supports 200% text on a 320 px phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: RecentChats(
                snapshot: AsyncSnapshot.withData(ConnectionState.active, [
                  _conversation(0),
                  _conversation(1),
                  _conversation(2),
                ]),
                currentUserId: 'me',
                onOpenConversation: (_) {},
                onFindFriends: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('A very long display name'), findsNWidgets(3));
    expect(find.text('99+'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent chats uses a full-card blurred portrait, not a small '
      'avatar', (tester) async {
    tester.view.physicalSize = const Size(1440, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const decodedProfilePhoto = AssetImage(
      'assets/images/home page assets.jpg',
    );

    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: RecentChats(
              snapshot: AsyncSnapshot.withData(ConnectionState.active, [
                _conversation(0, photoUrl: 'fixture://decoded-profile-photo'),
              ]),
              currentUserId: 'me',
              onOpenConversation: (_) => opened += 1,
              onFindFriends: () {},
              style: RecentChatsStyle.desktopBackdrop,
              backdropImageProvider: (_) => decodedProfilePhoto,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        decodedProfilePhoto,
        tester.element(find.byType(RecentChats)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byType(UserAvatar), findsNothing);
    expect(
      find.byKey(const ValueKey('recent-chat-photo-conversation-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('recent-chat-photo-error-conversation-0')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('recent-chat-photo-conversation-0')),
        matching: find.byType(RawImage),
      ),
      findsOneWidget,
    );
    final chat = find.bySemanticsLabel(
      'Open chat with A very long display name for a close friend number 0. '
      '123 unread messages. Last message: A longer preview that must remain '
      'readable at increased text scale.',
    );
    expect(chat, findsOneWidget);
    expect(tester.getSize(chat).height, 116);
    expect(find.bySemanticsLabel(RegExp(r'^123$')), findsNothing);

    final scrim = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .where((box) {
          final decoration = box.decoration;
          return decoration is BoxDecoration &&
              decoration.gradient is LinearGradient &&
              (decoration.gradient! as LinearGradient).colors.length == 3;
        })
        .single;
    final gradient =
        (scrim.decoration as BoxDecoration).gradient! as LinearGradient;
    final brightestNameBackdrop = Color.alphaBlend(
      gradient.colors[1],
      Colors.white,
    );
    final whiteNameContrast =
        (Colors.white.computeLuminance() + .05) /
        (brightestNameBackdrop.computeLuminance() + .05);
    expect(whiteNameContrast, greaterThanOrEqualTo(4.5));

    await tester.tap(find.textContaining('A very long display name'));
    await tester.pump();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop backdrop preserves its loading and stream error states',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Widget subject(AsyncSnapshot<List<Conversation>> snapshot) => MaterialApp(
        home: Scaffold(
          body: RecentChats(
            snapshot: snapshot,
            currentUserId: 'me',
            onOpenConversation: (_) {},
            onFindFriends: () {},
            style: RecentChatsStyle.desktopBackdrop,
          ),
        ),
      );

      await tester.pumpWidget(subject(const AsyncSnapshot.waiting()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.getSize(find.byType(RecentChats)).height, 116);

      await tester.pumpWidget(
        subject(
          AsyncSnapshot.withError(ConnectionState.active, StateError('x')),
        ),
      );
      await tester.pump();
      expect(
        find.text('Your recent chats could not be loaded.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a broken desktop portrait reveals the branded fallback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentChats(
            snapshot: AsyncSnapshot.withData(ConnectionState.active, [
              _conversation(0, photoUrl: 'fixture://broken-photo'),
            ]),
            currentUserId: 'me',
            onOpenConversation: (_) {},
            onFindFriends: () {},
            style: RecentChatsStyle.desktopBackdrop,
            backdropImageProvider: (_) =>
                MemoryImage(Uint8List.fromList(const [0, 1, 2, 3])),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('recent-chat-fallback-conversation-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('recent-chat-photo-error-conversation-0')),
      findsOneWidget,
    );
    expect(find.text('A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop backdrop supports 200% text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: RecentChats(
              snapshot: AsyncSnapshot.withData(ConnectionState.active, [
                _conversation(0),
                _conversation(1),
                _conversation(2),
              ]),
              currentUserId: 'me',
              onOpenConversation: (_) => opened += 1,
              onFindFriends: () {},
              style: RecentChatsStyle.desktopBackdrop,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(RecentChats)).height, 212);
    expect(find.byType(UserAvatar), findsNothing);

    final firstCard = find.bySemanticsLabel(
      'Open chat with A very long display name for a close friend number 0. '
      '123 unread messages. Last message: A longer preview that must remain '
      'readable at increased text scale.',
    );
    expect(firstCard, findsOneWidget);
    expect(tester.getSize(firstCard).height, greaterThanOrEqualTo(44));

    Focus.of(
      tester.element(
        find.text('A very long display name for a close friend number 0'),
      ),
    ).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(opened, 2);

    final firstRegion = find.byType(AccessibleTapRegion).first;
    final focusRing = tester.widget<AnimatedContainer>(
      find.descendant(
        of: firstRegion,
        matching: find.byType(AnimatedContainer),
      ),
    );
    final focusDecoration = focusRing.decoration! as BoxDecoration;
    expect(
      (focusDecoration.border! as Border).top.color,
      const Color(0xFFD28AFF),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop backdrop localizes Polish unread plurals and preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pl'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: RecentChats(
            snapshot: AsyncSnapshot.withData(ConnectionState.active, [
              _conversation(0, unread: 2),
              _conversation(1, unread: 12),
            ]),
            currentUserId: 'me',
            onOpenConversation: (_) {},
            onFindFriends: () {},
            style: RecentChatsStyle.desktopBackdrop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const preview =
        'A longer preview that must remain readable at increased text scale.';
    expect(
      find.bySemanticsLabel(
        'Otwórz czat z A very long display name for a close friend number 0. '
        '2 nieprzeczytane wiadomości. Ostatnia wiadomość: $preview',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Otwórz czat z A very long display name for a close friend number 1. '
        '12 nieprzeczytanych wiadomości. Ostatnia wiadomość: $preview',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
