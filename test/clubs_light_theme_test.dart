import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/models/club_channel.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_chat_screen.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_created_screen.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_invite_response_screen.dart';
import 'package:yovoice/features/clubs/presentation/screens/create_club_screen.dart';
import 'package:yovoice/features/clubs/presentation/widgets/family_check_in_panel.dart';

const _club = Club(
  id: 'club-1',
  name: 'Pearl listeners',
  description: 'A permanent voice community.',
  ownerId: 'owner',
  ownerName: 'Owner',
  avatarUrl: null,
  bannerUrl: null,
  privacy: ClubPrivacy.public,
  defaultLanguage: 'English',
  memberCount: 2,
  onlineCount: 1,
  defaultChatChannelId: 'general',
  defaultVoiceChannelId: 'lounge',
  announcementChannelId: 'announcements',
  createdAt: null,
  updatedAt: null,
);

const _channel = ClubChannel(
  id: 'general',
  clubId: 'club-1',
  name: 'general',
  type: ClubChannelType.chat,
  position: 0,
  isPrivate: false,
  createdBy: 'owner',
  createdAt: null,
);

ThemeData _theme(Brightness brightness) =>
    brightness == Brightness.light ? AppTheme.lightTheme : AppTheme.darkTheme;

AppPalette _palette(Brightness brightness) =>
    brightness == Brightness.light ? AppPalette.light : AppPalette.dark;

Widget _host({required Brightness brightness, required Widget child}) {
  return MaterialApp(
    theme: _theme(brightness),
    builder: (context, built) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(2)),
      child: built!,
    ),
    home: child,
  );
}

void _useNarrowRetinaView(WidgetTester tester) {
  tester.view.physicalSize = const Size(640, 1400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Club created and create flow use ${brightness.name} semantics at '
      '320px/200%',
      (tester) async {
        _useNarrowRetinaView(tester);

        await tester.pumpWidget(
          _host(
            brightness: brightness,
            child: const ClubCreatedScreen(club: _club),
          ),
        );
        final created = tester.widget<Scaffold>(
          find.byKey(const ValueKey('club-created-screen')),
        );
        expect(created.backgroundColor, _palette(brightness).background);
        expect(tester.takeException(), isNull);

        final db = FakeFirebaseFirestore();
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'owner'),
        );
        final service = ClubService(
          firestore: db,
          auth: auth,
          storage: MockFirebaseStorage(),
        );
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            child: CreateClubScreen(clubService: service),
          ),
        );
        await tester.pump();
        final create = tester.widget<Scaffold>(
          find.byKey(const ValueKey('create-club-screen')),
        );
        expect(create.backgroundColor, _palette(brightness).background);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          _host(
            brightness: brightness,
            child: ClubInviteResponseScreen(
              clubId: _club.id,
              firestore: db,
              auth: auth,
              clubService: service,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final invite = tester.widget<Scaffold>(
          find.byKey(const ValueKey('club-invite-response-screen')),
        );
        expect(invite.backgroundColor, _palette(brightness).background);
        expect(
          find.text('This invitation is no longer pending.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          _host(
            brightness: brightness,
            child: Scaffold(
              body: SingleChildScrollView(
                child: FamilyCheckInPanel(
                  clubId: _club.id,
                  currentUserId: 'owner',
                  canManage: true,
                  clubService: service,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final panel = tester.widget<Container>(
          find.byKey(const ValueKey('family-check-in-panel')),
        );
        expect(
          (panel.decoration! as BoxDecoration).color,
          _palette(brightness).successSurface,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Club chat uses ${brightness.name} semantics at 320px/200%', (
      tester,
    ) async {
      _useNarrowRetinaView(tester);
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'owner'),
      );
      await db.collection('clubs').doc(_club.id).set(<String, Object?>{
        'ownerId': 'owner',
        'name': _club.name,
      });
      await db
          .collection('clubs')
          .doc(_club.id)
          .collection('members')
          .doc('owner')
          .set(<String, Object?>{
            'userId': 'owner',
            'displayName': 'Owner',
            'role': 'owner',
          });

      await tester.pumpWidget(
        _host(
          brightness: brightness,
          child: ClubChatScreen(
            clubId: _club.id,
            clubName: _club.name,
            channel: _channel,
            firestore: db,
            auth: auth,
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      final chat = tester.widget<Scaffold>(
        find.byKey(const ValueKey('club-chat-screen')),
      );
      expect(chat.backgroundColor, _palette(brightness).background);
      expect(find.text('Start the club conversation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
