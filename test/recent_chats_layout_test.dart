import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:image/image.dart' as img;

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
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

MemoryImage _solidWhiteImage() {
  final raster = img.Image(width: 4, height: 4, numChannels: 4);
  for (var y = 0; y < raster.height; y++) {
    for (var x = 0; x < raster.width; x++) {
      raster.setPixelRgba(x, y, 255, 255, 255, 255);
    }
  }
  return MemoryImage(Uint8List.fromList(img.encodePng(raster)));
}

ProfileMediaService _profileMediaService({
  String grantUrl =
      'https://storage.googleapis.com/yovoice-private/avatar.jpg?sig=test',
  bool available = true,
  void Function(int call, Map<String, Object?> request)? onCall,
}) {
  var calls = 0;
  return ProfileMediaService(
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'me', email: 'me@example.invalid'),
    ),
    invoker: (name, request) async {
      calls += 1;
      onCall?.call(calls, request);
      expect(name, 'getProfileMediaAccess');
      return {
        'schemaVersion': 1,
        'available': available,
        'expiresAtMillis': DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 80))
            .millisecondsSinceEpoch,
        if (available) ...{
          'url': grantUrl,
          'generation': '$calls',
          'contentType': 'image/jpeg',
          'size': 4096,
        },
      };
    },
  );
}

void main() {
  setUp(ProfileMediaService.clearAllMediaAccessCaches);

  testWidgets('standard recent chat uses the live profile avatar', (
    tester,
  ) async {
    final profilePhotos = StreamController<String>();
    addTearDown(profilePhotos.close);
    var mediaCalls = 0;
    final media = _profileMediaService(
      available: false,
      onCall: (call, request) {
        mediaCalls = call;
        expect(request['userId'], 'friend-0');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: RecentChats(
              snapshot: AsyncSnapshot.withData(ConnectionState.active, [
                _conversation(0, photoUrl: 'fixture://stale-photo'),
              ]),
              currentUserId: 'me',
              onOpenConversation: (_) {},
              onFindFriends: () {},
              photoStreamForUser: (_) => profilePhotos.stream,
              profileMediaService: media,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    UserAvatar avatar() => tester.widget<UserAvatar>(
      find.byKey(const ValueKey('recent-chat-avatar-friend-0')),
    );
    expect(avatar().photoUrl, isEmpty);
    expect(mediaCalls, 1);

    profilePhotos.add('revision-2');
    await tester.pumpAndSettle();
    expect(avatar().photoUrl, isEmpty);
    expect(avatar().mediaRevision, 'revision-2');
    expect(mediaCalls, 2);
  });

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

  testWidgets('recent chats uses a sharp full-card portrait, not a small '
      'avatar', (tester) async {
    tester.view.physicalSize = const Size(1440, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const decodedProfilePhoto = AssetImage(
      'assets/images/home page assets.jpg',
    );
    final media = _profileMediaService();

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
              profileMediaService: media,
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

    expect(find.byType(ImageFiltered), findsNothing);
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
    final portrait = tester.widget<Image>(
      find.byKey(const ValueKey('recent-chat-photo-conversation-0')),
    );
    expect(portrait.fit, BoxFit.cover);
    expect(portrait.alignment, const Alignment(0, -.20));
    expect(portrait.filterQuality, FilterQuality.medium);
    expect(
      find.descendant(
        of: find.byType(RecentChats),
        matching: find.byIcon(Icons.chat_bubble_rounded),
      ),
      findsNothing,
    );
    final chat = find.bySemanticsLabel(
      'Open chat with A very long display name for a close friend number 0. '
      '123 unread messages. Last message: A longer preview that must remain '
      'readable at increased text scale.',
    );
    expect(chat, findsOneWidget);
    expect(tester.getSize(chat).height, 116);
    expect(find.bySemanticsLabel(RegExp(r'^123$')), findsNothing);

    final textSeat = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .where((box) {
          final decoration = box.decoration;
          return decoration is BoxDecoration &&
              decoration.gradient is LinearGradient &&
              (decoration.gradient! as LinearGradient).colors.length == 2 &&
              (decoration.gradient! as LinearGradient).colors.first ==
                  const Color(0xC4090712);
        })
        .single;
    final gradient =
        (textSeat.decoration as BoxDecoration).gradient! as LinearGradient;
    // The seat grows with the actual text, so its lightest top color remains
    // behind every possible name/preview line at both 100% and 200%.
    final brightestNameBackdrop = Color.alphaBlend(
      gradient.colors.first,
      Colors.white,
    );
    final whiteNameContrast =
        (Colors.white.computeLuminance() + .05) /
        (brightestNameBackdrop.computeLuminance() + .05);
    expect(whiteNameContrast, greaterThanOrEqualTo(4.5));
    final previewContrast =
        (const Color(0xFFD8CEE1).computeLuminance() + .05) /
        (brightestNameBackdrop.computeLuminance() + .05);
    expect(previewContrast, greaterThanOrEqualTo(4.5));

    await tester.tap(find.textContaining('A very long display name'));
    await tester.pump();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop backdrop replaces stale conversation artwork with the live '
    'public profile photo',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final profilePhotos = StreamController<String>();
      addTearDown(profilePhotos.close);
      const decodedProfilePhoto = AssetImage(
        'assets/images/home page assets.jpg',
      );
      String? requestedUserId;
      String? resolvedUrl;
      var mediaCalls = 0;
      final media = _profileMediaService(
        onCall: (call, request) {
          mediaCalls = call;
          expect(request['userId'], 'friend-0');
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecentChats(
              snapshot: AsyncSnapshot.withData(ConnectionState.active, [
                _conversation(0),
              ]),
              currentUserId: 'me',
              onOpenConversation: (_) {},
              onFindFriends: () {},
              style: RecentChatsStyle.desktopBackdrop,
              photoStreamForUser: (userId) {
                requestedUserId = userId;
                return profilePhotos.stream;
              },
              backdropImageProvider: (url) {
                resolvedUrl = url;
                return decodedProfilePhoto;
              },
              profileMediaService: media,
            ),
          ),
        ),
      );
      expect(requestedUserId, 'friend-0');
      expect(
        find.byKey(const ValueKey('recent-chat-fallback-conversation-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('recent-chat-photo-conversation-0')),
        findsNothing,
      );

      await tester.runAsync(
        () => precacheImage(
          decodedProfilePhoto,
          tester.element(find.byType(RecentChats)),
        ),
      );
      profilePhotos.add('revision-2');
      await tester.pumpAndSettle();

      expect(
        resolvedUrl,
        'https://storage.googleapis.com/yovoice-private/avatar.jpg?sig=test',
      );
      expect(mediaCalls, 2);
      expect(
        find.byKey(const ValueKey('recent-chat-photo-conversation-0')),
        findsOneWidget,
      );
      expect(find.byType(ImageFiltered), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
            profileMediaService: _profileMediaService(),
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
    final focusColors = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: firstRegion,
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map(
          (ring) =>
              ((ring.decoration! as BoxDecoration).border! as Border).top.color,
        );
    expect(focusColors, contains(Colors.black));
    expect(focusColors, contains(Colors.white));

    double contrast(Color foreground, Color background) {
      final lighter =
          foreground.computeLuminance() > background.computeLuminance()
          ? foreground
          : background;
      final darker = identical(lighter, foreground) ? background : foreground;
      return (lighter.computeLuminance() + .05) /
          (darker.computeLuminance() + .05);
    }

    // A black/white pair has 21:1 mutual contrast. Therefore every possible
    // image pixel has >= sqrt(21):1 contrast against at least one ring. Pin a
    // middle luminance explicitly — the former dark/violet pair failed here.
    expect(contrast(Colors.black, Colors.white), greaterThanOrEqualTo(9));
    const middleArtwork = Color(0xFF5A5A5A);
    expect(
      [
        contrast(Colors.black, middleArtwork),
        contrast(Colors.white, middleArtwork),
      ].reduce((best, value) => best > value ? best : value),
      greaterThanOrEqualTo(3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop 200% text stays inside its guaranteed dark seat over white art',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final whitePixel = _solidWhiteImage();
      final media = _profileMediaService();

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: RecentChats(
                snapshot: AsyncSnapshot.withData(ConnectionState.active, [
                  _conversation(0, photoUrl: 'fixture://white-pixel'),
                ]),
                currentUserId: 'me',
                onOpenConversation: (_) {},
                onFindFriends: () {},
                style: RecentChatsStyle.desktopBackdrop,
                backdropImageProvider: (_) => whitePixel,
                profileMediaService: media,
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () =>
            precacheImage(whitePixel, tester.element(find.byType(RecentChats))),
      );
      await tester.pumpAndSettle();

      final seat = find.byKey(
        const ValueKey('recent-chat-text-seat-conversation-0'),
      );
      final name = find.text(
        'A very long display name for a close friend number 0',
      );
      final preview = find.text(
        'A longer preview that must remain readable at increased text scale.',
      );
      final seatRect = tester.getRect(seat);
      expect(tester.getRect(name).top, greaterThanOrEqualTo(seatRect.top));
      expect(
        tester.getRect(preview).bottom,
        lessThanOrEqualTo(seatRect.bottom),
      );
      expect(tester.getSize(find.byType(RecentChats)).height, 212);
      expect(tester.takeException(), isNull);
    },
  );

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
        'Otwórz czat: A very long display name for a close friend number 0. '
        '2 nieprzeczytane wiadomości. Ostatnia wiadomość: $preview',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Otwórz czat: A very long display name for a close friend number 1. '
        '12 nieprzeczytanych wiadomości. Ostatnia wiadomość: $preview',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
