import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/creator/data/services/creator_audience_service.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_studio_screen.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/shared/widgets/profile/profile_media_image.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

import 'server_test_support.dart';

/// Surfaces that could NEVER show a profile photo, whatever the user uploaded.
///
/// Each of these painted the display-name initial unconditionally because it
/// dereferenced `profile.photoUrl` / `member.photoUrl` — denormalized hints
/// the server no longer projects (and which must not be dereferenced anyway,
/// since they bypass the live visibility and block recheck). The fix is the
/// canonical [UserAvatar], resolving from the uid.
void main() {
  setUp(ProfileMediaService.clearAllMediaAccessCaches);

  testWidgets('the incoming-DM notification resolves the sender by uid', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 38,
              height: 38,
              child: incomingMessageNotificationLeading(
                userId: 'sender-uid',
                senderName: 'Maja',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar));
    expect(avatar.userId, 'sender-uid');
    expect(avatar.radius, 19, reason: 'must fill the host 38x38 leading slot');
    expect(
      tester.widget<ProfileMediaImage>(find.byType(ProfileMediaImage)).userId,
      'sender-uid',
    );
    // Without a resolvable grant the canonical fallback still renders.
    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('the Creator Studio hero resolves the creator by uid', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'member', email: 'member@yovoice.app'),
    );
    final storage = MockFirebaseStorage();
    await db.collection('users').doc('member').set({
      'uid': 'member',
      'displayName': 'Maja',
      'email': 'member@yovoice.app',
      'accountType': 'creator',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: CreatorStudioScreen(
          serverRepository: TestServerRepository()..servers = const [],
          profileService: ProfileService(
            firestore: db,
            auth: auth,
            storage: storage,
          ),
          momentService: MomentService(
            firestore: db,
            auth: auth,
            storage: storage,
          ),
          creatorAudienceService: CreatorAudienceService(
            firestore: db,
            mutationInvoker: (_, _) async => const {},
          ),
          entitlementService: EntitlementService(firestore: db, auth: auth),
        ),
      ),
    );
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    final hero = find.byKey(const ValueKey('creator-studio-hero-avatar'));
    expect(hero, findsOneWidget);
    expect(tester.widget<UserAvatar>(hero).userId, 'member');
  });

  testWidgets('server member rows resolve each member by uid', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = const [
        Server(
          id: 'server',
          name: 'Ekipa',
          description: 'Po godzinach',
          ownerId: 'owner',
          type: ServerType.friends,
          privacy: ServerPrivacy.private,
          schemaVersion: 1,
          activationState: 'active',
          revision: 7,
        ),
      ]
      ..channels = const [
        ServerChannel(
          id: 'general',
          serverId: 'server',
          name: 'ogólny',
          kind: ServerChannelKind.text,
          schemaVersion: 1,
          revision: 3,
          aclRevision: 2,
        ),
      ]
      ..members = const [
        ServerMember(
          id: 'owner',
          displayName: 'Kamil',
          role: ServerMemberRole.owner,
          authorizationRevision: 1,
        ),
        ServerMember(
          id: 'friend',
          displayName: 'Maja',
          // A denormalized URL still present on legacy documents. Nothing may
          // dereference it.
          photoUrl: 'https://example.invalid/legacy.jpg',
          role: ServerMemberRole.member,
          authorizationRevision: 1,
        ),
      ];

    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 'server',
        repository: repository,
        channelBuilder: (_, _, _) => const SizedBox(),
      ),
      size: const Size(1200, 900),
    );

    await tester.tap(find.byKey(const ValueKey('server-manage-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Członkowie').last);
    await tester.pumpAndSettle();

    final rows = find.byKey(const ValueKey('server-management-members'));
    expect(rows, findsOneWidget);
    final avatars = find.descendant(of: rows, matching: find.byType(UserAvatar));
    expect(avatars, findsNWidgets(2));
    expect(
      tester.widgetList<UserAvatar>(avatars).map((a) => a.userId),
      ['owner', 'friend'],
    );
    expect(
      find.descendant(of: rows, matching: find.byType(CircleAvatar)),
      findsNothing,
      reason: 'the raw CircleAvatar dereferenced a denormalized URL',
    );
    expect(find.text('M'), findsWidgets, reason: 'the initial still renders');
  });

  test('a legacy member photo URL is never parsed into the model', () async {
    final db = FakeFirebaseFirestore();
    final reference = db
        .collection('servers')
        .doc('server')
        .collection('members')
        .doc('friend');
    await reference.set({
      'userId': 'friend',
      'displayName': 'Maja',
      'photoUrl': 'https://example.invalid/legacy.jpg',
      'role': 'member',
      'authorizationRevision': 1,
    });

    final member = ServerMember.fromFirestore(await reference.get());
    expect(
      member.photoUrl,
      isNull,
      reason: 'a denormalized URL must not survive parsing',
    );
    expect(member.displayName, 'Maja');
  });

  test('the Settings hero resolves the signed-in account by uid', () {
    // SettingsScreen constructs ProfileService/AuthService itself and cannot
    // be pumped without a real Firebase app, so this is a source ratchet
    // rather than a widget test. It still fails on the dead photoUrl branch.
    final source = File(
      'lib/features/settings/presentation/screens/settings_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("key: const ValueKey('settings-profile-hero-avatar')"),
      reason: 'the hero avatar must stay addressable',
    );
    expect(source, contains('userId: profile.uid'));
    expect(
      source,
      isNot(contains("final avatar = profile.photoUrl?.trim();")),
      reason: 'the hero must not dereference a denormalized photo URL again',
    );
  });
}
