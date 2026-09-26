import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_text_channel_scene.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/interactions/message_reactions.dart';

import 'support/fake_gif_transport.dart';

/// Emoji reactions on a server channel message: the direct-message pill under
/// the bubble, the direct-message long-press / right-click actions sheet with
/// the six reactions, and the one-per-person toggle through the callable.
void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late PublicIdentityRepository identities;
  late GifCatalogService catalog;
  late List<(String, Map<String, Object?>)> calls;

  const messagePath = 'clubs/club/channels/general/messages/m1';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
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
    calls = [];
    await db.doc('clubs/club').set({'ownerId': 'owner', 'name': 'Club'});
    await db.doc('clubs/club/members/me').set({
      'userId': 'me',
      'role': 'member',
    });
    await db.doc(messagePath).set({
      'clubId': 'club',
      'channelId': 'general',
      'senderId': 'other',
      'senderName': 'Ola',
      'content': 'Kto dziś gra?',
      'sentAt': Timestamp.fromDate(DateTime(2026, 9, 19, 19, 14)),
      'editedAt': null,
      'isDeleted': false,
      'reactions': {'u2': '❤️', 'u3': '❤️', 'me': '😂'},
    });
  });

  tearDown(() {
    PublicIdentityRepository.instance = identities;
    catalog.dispose();
  });

  ClubChatService service({Object? failWith}) => ClubChatService(
    firestore: db,
    auth: auth,
    requestIdFactory: () => 'reaction-request-1',
    serverMessageInvoker: (name, request) async {
      calls.add((name, request));
      if (failWith != null) throw failWith;
      return <Object?, Object?>{'changed': true};
    },
  );

  Future<void> pump(
    WidgetTester tester, {
    ClubChatService? chatService,
    Size size = const Size(390, 844),
    ServerChannelKind kind = ServerChannelKind.text,
  }) async {
    tester.view.physicalSize = size;
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
        home: Scaffold(
          body: ServerTextChannelScene(
            server: const Server(
              id: 'club',
              name: 'Friends server',
              description: '',
              ownerId: 'owner',
              type: ServerType.friends,
              privacy: ServerPrivacy.inviteOnly,
              defaultChannelId: 'general',
              schemaVersion: 1,
              activationState: 'active',
            ),
            channel: ServerChannel(
              id: 'general',
              serverId: 'club',
              name: 'General',
              kind: kind,
              schemaVersion: 1,
            ),
            currentUserId: 'me',
            chatService: chatService ?? service(),
            gifService: catalog,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final bubble = find.text('Kto dziś gra?');

  test('the summary is the direct-message one: counts only past one', () {
    expect(messageReactionSummary(['❤️', '😂', '❤️', ' ']), '❤️ 2 😂');
    expect(messageReactionSummary(const <String>[]), isEmpty);
    expect(kMessageReactionEmojis, ['❤️', '😂', '🔥', '😮', '😢', '👍']);
  });

  test(
    'ClubMessage reads reactions and drops them on a removed message',
    () async {
      final live = ClubMessage.fromFirestore(
        clubId: 'club',
        channelId: 'general',
        document: await db.doc(messagePath).get(),
      );
      expect(live.reactions, {'u2': '❤️', 'u3': '❤️', 'me': '😂'});
      await db.doc(messagePath).update({'isDeleted': true, 'reactions.x': 1});
      final removed = ClubMessage.fromFirestore(
        clubId: 'club',
        channelId: 'general',
        document: await db.doc(messagePath).get(),
      );
      expect(removed.reactions, isEmpty);
      await db.doc('clubs/club/channels/general/messages/old').set({
        'senderId': 'other',
        'content': 'before reactions existed',
      });
      final old = ClubMessage.fromFirestore(
        clubId: 'club',
        channelId: 'general',
        document: await db
            .doc('clubs/club/channels/general/messages/old')
            .get(),
      );
      expect(old.reactions, isEmpty);
      expect(old.type, isNull);
    },
  );

  testWidgets('the reaction pill under the bubble shows the summary', (
    tester,
  ) async {
    await pump(tester);
    expect(bubble, findsOneWidget);
    final pill = find.byKey(const ValueKey('server-message-reactions-m1'));
    expect(pill, findsOneWidget);
    expect(
      find.descendant(of: pill, matching: find.text('❤️ 2 😂')),
      findsOneWidget,
    );
  });

  testWidgets('long-press opens the six reactions; the current one removes', (
    tester,
  ) async {
    await pump(tester);
    await tester.longPress(bubble);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('server-message-actions')),
      findsOneWidget,
    );
    for (final emoji in kMessageReactionEmojis) {
      expect(find.byKey(ValueKey('message-reaction-$emoji')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('message-reaction-😂')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-message-actions')), findsNothing);
    expect(calls.single.$1, 'setServerChannelMessageReactionV1');
    expect(calls.single.$2, {
      'serverId': 'club',
      'channelId': 'general',
      'messageId': 'm1',
      'emoji': null,
      'requestId': 'reaction-request-1',
    });
  });

  testWidgets('a different emoji replaces, and right-click opens on desktop', (
    tester,
  ) async {
    await pump(tester, size: const Size(1440, 900));
    await tester.tap(bubble, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message-reaction-🔥')));
    await tester.pumpAndSettle();
    expect(calls.single.$2['emoji'], '🔥');
  });

  testWidgets('members react in an announcements channel they cannot post in', (
    tester,
  ) async {
    await pump(tester, kind: ServerChannelKind.announcements);
    expect(find.byKey(const ValueKey('server-composer')), findsNothing);
    await tester.longPress(bubble);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message-reaction-👍')));
    await tester.pumpAndSettle();
    expect(calls.single.$2['emoji'], '👍');
  });

  testWidgets('a guest is not offered reactions', (tester) async {
    await db.doc('clubs/club/members/me').set({
      'userId': 'me',
      'role': 'guest',
    });
    await pump(tester);
    await tester.longPress(bubble);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-message-actions')), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('a removed message offers no actions and shows no pill', (
    tester,
  ) async {
    await db.doc(messagePath).update({'isDeleted': true, 'content': ''});
    await pump(tester);
    expect(
      find.byKey(const ValueKey('server-message-reactions-m1')),
      findsNothing,
    );
    await tester.longPress(find.text('Message deleted'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-message-actions')), findsNothing);
  });

  testWidgets('a refused reaction says so in the direct-message words', (
    tester,
  ) async {
    await pump(tester, chatService: service(failWith: StateError('boom')));
    await tester.longPress(bubble);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message-reaction-❤️')));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    // A StateError carries intentional copy; anything else falls back.
    expect(find.text('boom'), findsNothing);
    expect(find.text('Could not update your reaction.'), findsOneWidget);
  });
}
