import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/models/club_channel.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_chat_screen.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_text_channel_scene.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/inputs/yo_composer_panel.dart';

import 'support/fake_gif_transport.dart';

/// The channel composers share the direct chat's keyboard contract: a tap on
/// the thread puts the keyboard away, a drag puts it away, and opening the
/// emoji/GIF panel from an idle composer never leaves the keyboard standing
/// under the panel. See `chat_composer_keyboard_test.dart` for the why.
void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late PublicIdentityRepository identities;
  late GifCatalogService catalog;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await YoComposerPanelTabStore.instance.remember(YoComposerPanelTab.emoji);
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'me', isEmailVerified: true),
    );
    identities = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: auth,
      fetchOverride: (uids) async => {
        for (final uid in uids)
          uid: {'uid': uid, 'staffRole': 'user', 'isVip': false},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
    catalog = GifCatalogService(transport: FakeGifTransport());
    await db.doc('clubs/club').set({'ownerId': 'me', 'name': 'Club'});
    await db.doc('clubs/club/members/me').set({
      'userId': 'me',
      'role': 'owner',
    });
    await db.doc('clubs/club/channels/general/messages/welcome').set({
      'type': 'text',
      'senderId': 'other',
      'senderName': 'A member',
      'content': 'Welcome aboard',
      'text': 'Welcome aboard',
      'sentAt': Timestamp.now(),
      'createdAt': Timestamp.now(),
      'isDeleted': false,
      'reactions': <String, String>{},
    });
  });

  tearDown(() {
    PublicIdentityRepository.instance = identities;
    catalog.dispose();
  });

  Widget host(String surface, {ClubChatService? chatService}) {
    final service = chatService ?? ClubChatService(firestore: db, auth: auth);
    final Widget screen = switch (surface) {
      'club' => ClubChatScreen(
        clubId: 'club',
        clubName: 'Club',
        channel: const ClubChannel(
          id: 'general',
          clubId: 'club',
          name: 'General',
          type: ClubChannelType.chat,
          position: 0,
          isPrivate: false,
          createdBy: 'me',
          createdAt: null,
        ),
        firestore: db,
        auth: auth,
        chatService: service,
        gifService: catalog,
      ),
      _ => Scaffold(
        body: ServerTextChannelScene(
          server: const Server(
            id: 'club',
            name: 'Friends server',
            description: '',
            ownerId: 'me',
            type: ServerType.friends,
            privacy: ServerPrivacy.inviteOnly,
            defaultChannelId: 'general',
            schemaVersion: 1,
            activationState: 'active',
          ),
          channel: const ServerChannel(
            id: 'general',
            serverId: 'club',
            name: 'General',
            kind: ServerChannelKind.text,
            schemaVersion: 1,
          ),
          currentUserId: 'me',
          chatService: service,
          gifService: catalog,
        ),
      ),
    };
    return MaterialApp(
      theme: AppTheme.darkTheme,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: screen,
    );
  }

  Future<void> pumpSurface(
    WidgetTester tester,
    String surface, {
    ClubChatService? chatService,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(surface, chatService: chatService));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Welcome aboard', findRichText: true),
      findsOneWidget,
      reason: 'the thread rendered, so there is something to tap',
    );
  }

  // The composer's own field, never a search field inside a panel: the
  // composer is built above the panel, so it is always first in tree order.
  Finder composerOn(String surface) => surface == 'server'
      ? find.descendant(
          of: find.byKey(const ValueKey('server-composer')),
          matching: find.byType(TextField),
        )
      : find.byType(TextField).first;

  FocusNode focusOf(WidgetTester tester, String surface) =>
      tester.widget<TextField>(composerOn(surface)).focusNode!;

  // The two surfaces draw different send glyphs.
  Finder sendButtonOn(String surface) => find.byIcon(
    surface == 'server' ? Icons.send_rounded : Icons.arrow_upward_rounded,
  );

  Future<void> focusComposer(WidgetTester tester, String surface) async {
    await tester.tap(composerOn(surface));
    await tester.pumpAndSettle();
    expect(focusOf(tester, surface).hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  }

  for (final surface in const ['club', 'server']) {
    testWidgets('$surface: tapping the thread puts the keyboard away', (
      tester,
    ) async {
      await pumpSurface(tester, surface);
      await focusComposer(tester, surface);

      await tester.tap(
        find.textContaining('Welcome aboard', findRichText: true),
      );
      await tester.pumpAndSettle();

      expect(focusOf(tester, surface).hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('$surface: dragging the thread puts the keyboard away', (
      tester,
    ) async {
      await pumpSurface(tester, surface);
      await focusComposer(tester, surface);

      expect(
        tester.widget<ListView>(find.byType(ListView)).keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
      await tester.drag(find.byType(ListView), const Offset(0, 120));
      await tester.pumpAndSettle();

      expect(focusOf(tester, surface).hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('$surface: the send button is not "outside" the composer', (
      tester,
    ) async {
      await pumpSurface(tester, surface);
      await focusComposer(tester, surface);
      await tester.enterText(composerOn(surface), 'hello');
      await tester.pumpAndSettle();

      await tester.tap(sendButtonOn(surface));
      await tester.pumpAndSettle();

      expect(focusOf(tester, surface).hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets(
      '$surface: opening the panel from an idle composer leaves the keyboard '
      'down',
      (tester) async {
        await pumpSurface(tester, surface);
        expect(focusOf(tester, surface).hasFocus, isFalse);
        final mark = tester.testTextInput.log.length;

        await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('composer-panel')), findsOneWidget);
        expect(focusOf(tester, surface).hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isFalse);
        final calls = tester.testTextInput.log
            .skip(mark)
            .map((call) => call.method)
            .toList(growable: false);
        expect(
          calls.lastIndexOf('TextInput.show'),
          lessThan(calls.lastIndexOf('TextInput.hide')),
          reason: 'show first, then the hide wins: $calls',
        );
      },
    );

    testWidgets('$surface: closing the panel from its button brings the '
        'keyboard back', (tester) async {
      await pumpSurface(tester, surface);
      await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.tap(find.byIcon(Icons.keyboard_alt_outlined));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('composer-panel')), findsNothing);
      expect(focusOf(tester, surface).hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('$surface: a slow send does not resurrect a dismissed '
        'keyboard', (tester) async {
      final service = _BlockingClubChatService(db, auth);
      await pumpSurface(tester, surface, chatService: service);
      await focusComposer(tester, surface);
      await tester.enterText(composerOn(surface), 'hello');
      await tester.pumpAndSettle();

      await tester.tap(sendButtonOn(surface));
      await tester.pump();
      expect(service.started.isCompleted, isTrue);

      // Mid-send — the network is slow — the person puts the keyboard away.
      // (Plain pumps: the in-flight spinner never settles.)
      await tester.tap(
        find.textContaining('Welcome aboard', findRichText: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(focusOf(tester, surface).hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);

      service.release.complete();
      await tester.pumpAndSettle();

      expect(
        focusOf(tester, surface).hasFocus,
        isFalse,
        reason: 'a completed send leaves focus where the person put it',
      );
      expect(tester.testTextInput.isVisible, isFalse);
    });
  }
}

class _BlockingClubChatService extends ClubChatService {
  _BlockingClubChatService(FakeFirebaseFirestore db, MockFirebaseAuth auth)
    : super(firestore: db, auth: auth);

  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<void> sendTextMessage({
    required String clubId,
    required String channelId,
    required String text,
  }) async {
    if (!started.isCompleted) started.complete();
    await release.future;
  }
}
