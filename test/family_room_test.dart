import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/presentation/screens/create_club_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_type_selector_screen.dart';

/// Family Room is a Club with a private data boundary, not a parallel
/// product. These tests cover the client half of that: the Create card
/// itself, its emerald identity, the navigation into the family template,
/// and — as importantly — that the three cards that were already there
/// are byte-for-byte what they were.
///
/// The privacy boundary itself is server-side and is covered where it is
/// actually enforced, in firestore-tests/rules.test.js.
void main() {
  Widget host(Widget child) => MaterialApp(home: child);

  void usePhone(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('Create screen', () {
    testWidgets('offers Family Room with the agreed copy, directly below '
        'Club', (tester) async {
      usePhone(tester, const Size(390, 2400));
      await tester.pumpWidget(host(const RoomTypeSelectorScreen()));
      await tester.pump();

      expect(find.text('PRIVATE FAMILY SPACE'), findsOneWidget);
      expect(find.text('Family Room'), findsOneWidget);
      expect(
        find.text(
          'A permanent, invite-only space for the people closest to you.',
        ),
        findsOneWidget,
      );
      for (final benefit in const [
        'Always-open family voice lounge',
        'Private chat, Moments and announcements',
        'Shared plans and quick check-ins',
      ]) {
        expect(find.text(benefit), findsOneWidget, reason: benefit);
      }

      // Directly below Club, and last.
      double y(String label) => tester.getTopLeft(find.text(label)).dy;
      expect(y('Club'), lessThan(y('Family Room')));
      expect(y('Podcast Room'), lessThan(y('Club')));
      expect(y('Community Room'), lessThan(y('Podcast Room')));
    });

    testWidgets('the three existing choices are unchanged', (tester) async {
      usePhone(tester, const Size(390, 2400));
      await tester.pumpWidget(host(const RoomTypeSelectorScreen()));
      await tester.pump();

      for (final copy in const [
        'Community Room',
        'OPEN CONVERSATION',
        'A relaxed live room where everyone can speak.',
        'Podcast Room',
        'HOST + AUDIENCE',
        'A hosted show with a stage, audience and requests.',
        'Club',
        'PERMANENT COMMUNITY',
        'Members, roles, chat, announcements and a Club Lounge.',
      ]) {
        expect(find.text(copy), findsOneWidget, reason: copy);
      }
    });

    testWidgets('Family Room carries the emerald identity, and no other '
        'card does', (tester) async {
      usePhone(tester, const Size(390, 2400));
      await tester.pumpWidget(host(const RoomTypeSelectorScreen()));
      await tester.pump();

      // The eyebrow and title colours are the card's accent.
      final eyebrow = tester.widget<Text>(find.text('PRIVATE FAMILY SPACE'));
      expect(eyebrow.style?.color, RoomTypeSelectorScreen.familyAccent);

      // Its surface is the dark emerald tint, not the shared violet one.
      final card = find.ancestor(
        of: find.text('Family Room'),
        matching: find.byType(Material),
      );
      final surfaces = tester
          .widgetList<Material>(card)
          .map((material) => material.color)
          .toList();
      expect(
        surfaces,
        contains(RoomTypeSelectorScreen.familySurface),
        reason: 'the family card must use its own dark surface tint',
      );

      // The violet cards must not have picked up the emerald.
      final clubEyebrow = tester.widget<Text>(find.text('PERMANENT COMMUNITY'));
      expect(
        clubEyebrow.style?.color,
        isNot(RoomTypeSelectorScreen.familyAccent),
      );
    });

    testWidgets('every card keeps the same width and padding, so the new '
        'one is the same card', (tester) async {
      usePhone(tester, const Size(390, 2400));
      await tester.pumpWidget(host(const RoomTypeSelectorScreen()));
      await tester.pump();

      double width(String title) => tester
          .getSize(
            find
                .ancestor(of: find.text(title), matching: find.byType(Material))
                .first,
          )
          .width;

      final reference = width('Community Room');
      for (final title in const ['Podcast Room', 'Club', 'Family Room']) {
        expect(width(title), closeTo(reference, 0.5), reason: title);
      }
    });

    testWidgets('tapping Family Room opens the create flow in its family '
        'template', (tester) async {
      usePhone(tester, const Size(390, 2400));
      await tester.pumpWidget(host(const RoomTypeSelectorScreen()));
      await tester.pump();

      await tester.tap(find.text('Family Room'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final screen = tester.widget<CreateClubScreen>(
        find.byType(CreateClubScreen),
      );
      expect(screen.type, ClubType.family);
      expect(screen.isFamily, isTrue);
    });

    for (final size in const [
      Size(320, 2400),
      Size(390, 2400),
      Size(430, 2400),
      Size(1440, 2400),
    ]) {
      testWidgets('lays out without overflow at ${size.width.toInt()}pt', (
        tester,
      ) async {
        usePhone(tester, size);
        await tester.pumpWidget(host(const RoomTypeSelectorScreen()));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Family Room'), findsOneWidget);
      });
    }
  });

  group('Family Room identity', () {
    test('a family room lives at a deterministic, per-account id', () {
      // This id IS the one-per-account limit: firestore.rules refuses
      // every other id, so a second family room has nowhere to go.
      expect(Club.familyRoomIdFor('abc123'), 'family_abc123');
      expect(
        Club.familyRoomIdFor('abc123'),
        isNot(Club.familyRoomIdFor('def456')),
      );
    });

    test('type defaults to community, so every club that already exists '
        'keeps its behaviour', () {
      expect(ClubType.fromValue(null), ClubType.community);
      expect(ClubType.fromValue('community'), ClubType.community);
      expect(ClubType.fromValue('anything else'), ClubType.community);
      expect(ClubType.fromValue('family'), ClubType.family);
    });
  });
}
