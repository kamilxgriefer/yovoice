import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/models/club_chat_authority.dart';
import 'package:yovoice/features/clubs/data/models/club_member.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/server_localized_copy.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_text_channel_scene.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/inputs/yo_composer_panel.dart';

import 'support/fake_gif_transport.dart';

/// A chat service whose viewer authority is driven by the test, so the
/// moment BEFORE the membership row arrives can be held open.
class _ScriptedAuthorityService extends ClubChatService {
  _ScriptedAuthorityService({required super.firestore, required super.auth});

  final authority = StreamController<ClubChatAuthority>.broadcast();

  @override
  Stream<ClubChatAuthority> watchAuthority(String clubId) => authority.stream;
}

/// The emoji input lives in the server channel composer and must not vanish
/// while the viewer's membership is merely not known yet. It used to: the
/// whole composer was swapped for the read-only sentence on the very first
/// frame, and for good when the membership snapshot was slow or never came.
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
  });

  tearDown(() {
    PublicIdentityRepository.instance = identities;
    catalog.dispose();
  });

  Future<void> pump(
    WidgetTester tester,
    ClubChatService service, {
    ServerChannelKind kind = ServerChannelKind.text,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
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
            chatService: service,
            gifService: catalog,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder composer() => find.byKey(const ValueKey('server-composer'));
  Finder emojiButton() => find.byType(YoEmojiComposerButton);

  test('an unresolved membership is not a read-only verdict', () {
    const pending = ClubChatAuthority(
      viewerId: 'me',
      viewerEmailVerified: true,
      membershipResolved: false,
    );
    expect(pending.canSendToChannel(announcement: false), isFalse);
    expect(pending.showsReadOnlyNotice(announcement: false), isFalse);
    const guest = ClubChatAuthority(
      viewerId: 'me',
      role: ClubRole.guest,
      viewerEmailVerified: true,
    );
    expect(guest.showsReadOnlyNotice(announcement: false), isTrue);
    const member = ClubChatAuthority(
      viewerId: 'me',
      role: ClubRole.member,
      viewerEmailVerified: true,
    );
    expect(member.showsReadOnlyNotice(announcement: false), isFalse);
    expect(member.showsReadOnlyNotice(announcement: true), isTrue);
  });

  testWidgets(
    'the emoji input stays in the composer while the membership is loading',
    (tester) async {
      final service = _ScriptedAuthorityService(firestore: db, auth: auth);
      addTearDown(service.authority.close);
      await pump(tester, service);
      // No authority snapshot has arrived at all.
      expect(composer(), findsOneWidget);
      expect(emojiButton(), findsOneWidget);
      final copy = AppLocalizations.of(tester.element(composer()));
      expect(find.text(copy.serverReadOnlyBody), findsNothing);

      // The emoji panel opens from the composer and inserts at the caret.
      await tester.tap(emojiButton());
      await tester.pumpAndSettle();
      expect(find.byType(YoComposerPanel), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('emoji-cell-😀')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.descendant(of: composer(), matching: find.byType(TextField)),
      );
      expect(field.controller!.text, '😀');

      // A resolved member keeps it; nothing flickers away.
      service.authority.add(
        const ClubChatAuthority(
          viewerId: 'me',
          role: ClubRole.member,
          viewerEmailVerified: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(emojiButton(), findsOneWidget);
      expect(find.byType(YoComposerPanel), findsOneWidget);
    },
  );

  testWidgets('a resolved read-only verdict still shows the notice', (
    tester,
  ) async {
    final service = _ScriptedAuthorityService(firestore: db, auth: auth);
    addTearDown(service.authority.close);
    await pump(tester, service);
    expect(emojiButton(), findsOneWidget);
    service.authority.add(
      const ClubChatAuthority(
        viewerId: 'me',
        role: ClubRole.guest,
        viewerEmailVerified: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(composer(), findsNothing);
    expect(emojiButton(), findsNothing);
    final copy = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    expect(find.text(copy.serverReadOnlyBody), findsOneWidget);
  });

  testWidgets('an announcements channel is read-only for a resolved member', (
    tester,
  ) async {
    final service = _ScriptedAuthorityService(firestore: db, auth: auth);
    addTearDown(service.authority.close);
    await pump(tester, service, kind: ServerChannelKind.announcements);
    service.authority.add(
      const ClubChatAuthority(
        viewerId: 'me',
        role: ClubRole.member,
        viewerEmailVerified: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(composer(), findsNothing);
    final copy = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    expect(find.text(copy.serverAnnouncementsOnlyBody), findsOneWidget);
    // A moderator's composer, emoji input included, is there.
    service.authority.add(
      const ClubChatAuthority(
        viewerId: 'me',
        role: ClubRole.moderator,
        viewerEmailVerified: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(emojiButton(), findsOneWidget);
  });

  testWidgets('the real service resolves the membership and keeps it', (
    tester,
  ) async {
    await db.doc('clubs/club').set({'ownerId': 'owner', 'name': 'Club'});
    await db.doc('clubs/club/members/me').set({
      'userId': 'me',
      'role': 'member',
    });
    await pump(tester, ClubChatService(firestore: db, auth: auth));
    expect(composer(), findsOneWidget);
    expect(emojiButton(), findsOneWidget);
  });
}
