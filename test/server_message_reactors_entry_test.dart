// "See who reacted" in a Server channel (ADR-230, owner variant A): the
// reaction summary pill under a message is a control that opens the
// reactors list (VIP) or the U1 upsell (everyone else), with the channel's
// own counts as the list's tabs; the actions sheet carries the same entry.
// A direct-message pill (no onTap) is the static summary it always was.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_text_channel_scene.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/interactions/message_reactions.dart';

import 'support/fake_gif_transport.dart';
import 'support/likers_fixtures.dart';

const _pill = ValueKey('server-message-reactions-m1');
const _messagePath = 'clubs/club/channels/general/messages/m1';

void main() {
  late FakeFirebaseFirestore db;

  Future<void> seedMessage(Map<String, String> reactions) =>
      db.doc(_messagePath).set({
        'clubId': 'club',
        'channelId': 'general',
        'senderId': 'other',
        'senderName': 'Ola',
        'content': 'Kto dziś gra?',
        'sentAt': Timestamp.fromDate(DateTime(2026, 9, 19, 19, 14)),
        'editedAt': null,
        'isDeleted': false,
        'reactions': reactions,
      });

  late MockFirebaseAuth auth;
  late PublicIdentityRepository identities;
  late GifCatalogService catalog;
  late List<String> reactionWrites;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'me', isEmailVerified: true),
    );
    identities = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = identityRepository();
    catalog = GifCatalogService(transport: FakeGifTransport());
    reactionWrites = <String>[];
    await db.doc('clubs/club').set({'ownerId': 'owner', 'name': 'Club'});
    await db.doc('clubs/club/members/me').set({
      'userId': 'me',
      'role': 'member',
    });
    await seedMessage(const {'u2': '❤️', 'u3': '❤️', 'me': '😂'});
  });

  tearDown(() {
    PublicIdentityRepository.instance = identities;
    catalog.dispose();
  });

  Future<ScriptedLikers> pump(
    WidgetTester tester, {
    required bool vip,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final script = ScriptedLikers([
      pageWire([
        likerWire('u2', 'Julia Nowak', reaction: '❤️'),
        likerWire('u3', 'Marta Wiśniewska', reaction: '❤️'),
        likerWire('me', 'Me', reaction: '😂'),
      ]),
    ]);
    await tester.pumpWidget(
      likersHost(
        Scaffold(
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
              kind: ServerChannelKind.text,
              schemaVersion: 1,
            ),
            currentUserId: 'me',
            chatService: ClubChatService(
              firestore: db,
              auth: auth,
              requestIdFactory: () => 'reaction-request-1',
              serverMessageInvoker: (name, request) async {
                reactionWrites.add(name);
                return <Object?, Object?>{'changed': true};
              },
            ),
            gifService: catalog,
            likersLauncher: testLikersLauncher(allowed: vip, script: script),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return script;
  }

  testWidgets('the pill reads as a control and opens the reactors list '
      'with the channel\'s own tabs', (tester) async {
    final script = await pump(tester, vip: true);
    final pill = find.byKey(_pill);
    expect(
      find.descendant(of: pill, matching: find.text('❤️ 2 😂')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: pill,
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('See who reacted. Reactions: 3'),
      findsOneWidget,
    );
    expect(tester.getSize(pill).height, greaterThanOrEqualTo(44));

    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(find.byKey(kLikersListSurface), findsOneWidget);
    expect(find.text('Julia Nowak'), findsOneWidget);
    expect(find.byKey(const ValueKey('likers-tab-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('likers-tab-❤️')), findsOneWidget);
    expect(find.byKey(const ValueKey('likers-tab-😂')), findsOneWidget);
    expect(script.calls.single.name, 'listServerChannelMessageReactorsV1');
    expect(script.calls.single.payload, <String, Object?>{
      'serverId': 'club',
      'channelId': 'general',
      'messageId': 'm1',
    });
    // Opening the list never reacts.
    expect(reactionWrites, isEmpty);
  });

  testWidgets('closing the list hands focus back to the pill, from the pill '
      'and from the actions sheet', (tester) async {
    await pump(tester, vip: true);
    final pill = find.byKey(_pill);
    FocusNode pillFocus() => Focus.of(
      tester.element(find.descendant(of: pill, matching: find.text('❤️ 2 😂'))),
    );

    Future<void> closeList() async {
      Navigator.of(tester.element(find.byKey(kLikersListSurface))).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(kLikersListSurface), findsNothing);
    }

    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(find.byKey(kLikersListSurface), findsOneWidget);
    await closeList();
    expect(pillFocus().hasFocus, isTrue);

    pillFocus().unfocus();
    await tester.pump();
    await tester.longPress(find.text('Kto dziś gra?'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('server-message-reactors')));
    await tester.pumpAndSettle();
    expect(find.byKey(kLikersListSurface), findsOneWidget);
    await closeList();
    expect(pillFocus().hasFocus, isTrue);
  });

  testWidgets('a non-VIP tapping the pill gets the U1 upsell', (tester) async {
    final script = await pump(tester, vip: false);
    await tester.tap(find.byKey(_pill));
    await tester.pumpAndSettle();
    expect(find.byKey(kLikersUpsellSurface), findsOneWidget);
    expect(find.text('3 people reacted to this message'), findsOneWidget);
    expect(script.calls, isEmpty);
  });

  testWidgets('the actions sheet offers "See who reacted" under the '
      'reactions, and it opens the list', (tester) async {
    await pump(tester, vip: true);
    await tester.longPress(find.text('Kto dziś gra?'));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('server-message-reactors'));
    expect(row, findsOneWidget);
    expect(find.text('See who reacted'), findsOneWidget);
    // Below the six reactions.
    expect(
      tester.getTopLeft(row).dy,
      greaterThan(
        tester.getBottomLeft(find.byType(MessageReactionPickerRow)).dy - 1,
      ),
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-message-actions')), findsNothing);
    expect(find.byKey(kLikersListSurface), findsOneWidget);
    expect(reactionWrites, isEmpty);
  });

  testWidgets('no reactions: no pill and no sheet row', (tester) async {
    await seedMessage(const <String, String>{});
    await pump(tester, vip: true);
    expect(find.byKey(_pill), findsNothing);
    await tester.longPress(find.text('Kto dziś gra?'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-message-reactors')), findsNothing);
  });

  testWidgets('without onTap the pill is the static summary (direct '
      'messages)', (tester) async {
    await tester.pumpWidget(
      likersHost(
        const Scaffold(
          body: Center(
            child: MessageReactionSummaryPill(reactions: ['❤️', '❤️', '😂']),
          ),
        ),
      ),
    );
    expect(find.text('❤️ 2 😂'), findsOneWidget);
    expect(find.byType(AccessibleTapRegion), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  for (final size in const [Size(320, 700), Size(1280, 900)]) {
    testWidgets('lays out at ${size.width.toInt()} px', (tester) async {
      await pump(tester, vip: true, size: size);
      expect(find.byKey(_pill), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
