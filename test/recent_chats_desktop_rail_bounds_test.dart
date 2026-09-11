// The desktop recent-chats rail lives in Home's narrow social column, which
// has no page gutter beside it. Whatever the rail lays out must therefore
// stay inside its own box: this suite measures the PAINTED pixels, not only
// the layout rects, because the regression it guards (two 220 px cards plus
// `Clip.none`) painted the third card 135 px past the column and 115 px past
// a 1440 px viewport.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

import 'voice_moment_test_doubles.dart';

/// A colour no card, scrim, gradient or fallback in this rail can paint, so
/// every pixel that differs from it is content the rail actually drew.
const _canvas = Color(0xFF00FF00);
const _margin = 60.0;

Conversation _conversation(int index) => Conversation(
  id: 'conversation-$index',
  participantIds: ['me', 'friend-$index'],
  participantNames: {
    'me': 'Me',
    'friend-$index': 'A very long display name for a close friend $index',
  },
  participantEmails: const {},
  participantPhotoUrls: const {},
  unreadCounts: {'me': 3, 'friend-$index': 0},
  lastMessage: 'A longer preview that must remain readable at 200% text.',
  lastMessageType: MessageType.text,
  lastMessageSenderId: 'friend-$index',
  updatedAt: DateTime(2026, 8, 16),
  createdAt: DateTime(2026, 8, 16),
  archivedBy: const [],
  mutedBy: const [],
);

/// The horizontal span of every pixel the rail painted, in coordinates
/// relative to the surrounding canvas.
Future<({double left, double right})> _paintedSpan(
  WidgetTester tester,
  GlobalKey boundaryKey,
) async {
  late double left;
  late double right;
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixels = Uint8List.view(data!.buffer);
      var minX = image.width.toDouble();
      var maxX = 0.0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final offset = ((y * image.width) + x) * 4;
          // Pure green at any coverage keeps both other channels at zero;
          // every colour this rail can paint carries some red and blue.
          final isCanvas = pixels[offset] <= 6 && pixels[offset + 2] <= 6;
          if (isCanvas) continue;
          if (x < minX) minX = x.toDouble();
          if (x + 1 > maxX) maxX = x + 1;
        }
      }
      left = minX;
      right = maxX;
    } finally {
      image.dispose();
    }
  });
  return (left: left, right: right);
}

void main() {
  const uid = 'me-uid';

  group('the rail paints inside its own box', () {
    // 330 px is the narrowest social column Home can produce (its two-column
    // split starts at 850 px); 379 and 443 are the columns the desktop shell
    // hands it at 1280 and 1440; 548.8 is the column measured in the defect
    // report at 1440x900.
    for (final width in [330.4, 379.2, 443.2, 548.8]) {
      testWidgets('nothing escapes a ${width.toStringAsFixed(1)} px column', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width + (_margin * 2), 320);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final boundaryKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: Container(
                    color: _canvas,
                    padding: const EdgeInsets.all(_margin),
                    child: SizedBox(
                      width: width,
                      child: RecentChats(
                        snapshot: AsyncSnapshot.withData(
                          ConnectionState.active,
                          [
                            _conversation(0),
                            _conversation(1),
                            _conversation(2),
                          ],
                        ),
                        currentUserId: 'me',
                        onOpenConversation: (_) {},
                        onFindFriends: () {},
                        style: RecentChatsStyle.desktopBackdrop,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.getSize(find.byType(RecentChats)), Size(width, 116));
        final painted = await _paintedSpan(tester, boundaryKey);
        // One pixel of tolerance for the cards' antialiased rounded corners.
        expect(
          painted.left,
          greaterThanOrEqualTo(_margin - 1),
          reason: 'the rail painted left of its box',
        );
        expect(
          painted.right,
          lessThanOrEqualTo(_margin + width + 1),
          reason: 'the rail painted right of its box',
        );
        // A peek is still a peek: the rail fills the column rather than
        // stopping short of it.
        expect(painted.right, greaterThan(_margin + width - 40));
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Home keeps its two-column overview until 160% text, so the rail still
  // has to hold a narrow column at the scales in between.
  for (final scale in [1.25, 1.5]) {
    for (final width in [379.2, 548.8]) {
      testWidgets('a ${width.toStringAsFixed(1)} px column survives '
          '${(scale * 100).round()}% text', (tester) async {
        tester.view.physicalSize = Size(width + (_margin * 2), 400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final boundaryKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: Container(
                      color: _canvas,
                      padding: const EdgeInsets.all(_margin),
                      child: SizedBox(
                        width: width,
                        child: RecentChats(
                          snapshot: AsyncSnapshot.withData(
                            ConnectionState.active,
                            [
                              _conversation(0),
                              _conversation(1),
                              _conversation(2),
                            ],
                          ),
                          currentUserId: 'me',
                          onOpenConversation: (_) {},
                          onFindFriends: () {},
                          style: RecentChatsStyle.desktopBackdrop,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getSize(find.byType(RecentChats)).height,
          closeTo(116 + ((scale - 1) * 96), 0.01),
        );
        final painted = await _paintedSpan(tester, boundaryKey);
        expect(painted.left, greaterThanOrEqualTo(_margin - 1));
        expect(painted.right, lessThanOrEqualTo(_margin + width + 1));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the third chat stays reachable from the peek', (tester) async {
    // 443.2 px is the shell column at 1440 — too narrow for three readable
    // cards, so the rail peeks and scrolls. Keyboard focus must bring the
    // third card fully inside the box.
    const width = 443.2;
    tester.view.physicalSize = const Size(width + 120, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: RecentChats(
                snapshot: AsyncSnapshot.withData(ConnectionState.active, [
                  _conversation(0),
                  _conversation(1),
                  _conversation(2),
                ]),
                currentUserId: 'me',
                onOpenConversation: (_) {},
                onFindFriends: () {},
                style: RecentChatsStyle.desktopBackdrop,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rail = tester.getRect(find.byType(RecentChats));
    final scroller = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(RecentChats),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scroller.clipBehavior, Clip.hardEdge);

    final cards = find.descendant(
      of: find.byType(RecentChats),
      matching: find.byType(AccessibleTapRegion),
    );
    expect(cards, findsNWidgets(3));
    final peek = rail.right - tester.getRect(cards.at(2)).left;
    expect(peek, greaterThan(24), reason: 'the third card must be visible');

    // Scrolling the rail brings the whole third card inside the column, and
    // `ensureVisible` is the same call keyboard focus traversal makes.
    await tester.drag(find.byType(RecentChats), const Offset(-260, 0));
    await tester.pumpAndSettle();
    final dragged = tester.getRect(cards.at(2));
    expect(dragged.right, lessThanOrEqualTo(rail.right + 0.5));
    expect(dragged.left, greaterThanOrEqualTo(rail.left - 0.5));

    await tester.drag(find.byType(RecentChats), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(cards.at(2)).left, greaterThan(rail.right - 40));
    await Scrollable.ensureVisible(tester.element(cards.at(2)));
    await tester.pumpAndSettle();
    final revealed = tester.getRect(cards.at(2));
    expect(revealed.right, lessThanOrEqualTo(rail.right + 0.5));
    expect(revealed.left, greaterThanOrEqualTo(rail.left - 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide column keeps three whole cards, no scrolling', (
    tester,
  ) async {
    const width = 548.8;
    tester.view.physicalSize = const Size(width + 120, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: RecentChats(
                snapshot: AsyncSnapshot.withData(ConnectionState.active, [
                  _conversation(0),
                  _conversation(1),
                  _conversation(2),
                ]),
                currentUserId: 'me',
                onOpenConversation: (_) {},
                onFindFriends: () {},
                style: RecentChatsStyle.desktopBackdrop,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(RecentChats),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    final rail = tester.getRect(find.byType(RecentChats));
    final cards = find.descendant(
      of: find.byType(RecentChats),
      matching: find.byType(AccessibleTapRegion),
    );
    expect(cards, findsNWidgets(3));
    for (var index = 0; index < 3; index++) {
      final card = tester.getRect(cards.at(index));
      expect(card.left, greaterThanOrEqualTo(rail.left - 0.5));
      expect(card.right, lessThanOrEqualTo(rail.right + 0.5));
      expect(card.width, closeTo((width - 24) / 3, 0.01));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone rail keeps its gutter overhang', (tester) async {
    // The mobile presentation deliberately paints past its box so the third
    // card peeks over the page gutter. Nothing above may change that.
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentChats(
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
    );
    await tester.pump();

    final scroller = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(RecentChats),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scroller.clipBehavior, Clip.none);
    final cards = find.descendant(
      of: find.byType(RecentChats),
      matching: find.byType(InkWell),
    );
    // (390 - AppRhythm.item) / 2: one rail pitch for both presentations
    // now, so the phone card is 189 rather than the old 190.
    expect(tester.getSize(cards.first).width, (390 - AppRhythm.item) / 2);
    expect(tester.getSize(find.byType(RecentChats)).height, 148);
    expect(tester.takeException(), isNull);
  });

  group('inside the real desktop Home', () {
    late FakeFirebaseFirestore db;

    MockFirebaseAuth auth() => MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: uid,
        email: 'me@yovoice.app',
        displayName: 'Kamil',
      ),
    );

    setUp(() async {
      db = FakeFirebaseFirestore();
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'displayName': 'Kamil',
        'email': 'me@yovoice.app',
      });
      for (var index = 0; index < 3; index++) {
        await db.collection('conversations').doc('c$index').set({
          'participantIds': [uid, 'friend-$index'],
          'participantNames': {uid: 'Kamil', 'friend-$index': 'Friend $index'},
          'participantEmails': {
            uid: 'me@yovoice.app',
            'friend-$index': 'friend$index@yovoice.app',
          },
          'participantPhotoUrls': <String, String>{},
          'unreadCounts': {uid: 3, 'friend-$index': 0},
          'lastMessage': 'Message $index',
          'lastMessageType': 'text',
          'lastMessageSenderId': 'friend-$index',
          'updatedAt': Timestamp.fromDate(
            DateTime.now().subtract(Duration(minutes: 9 - index)),
          ),
          'createdAt': Timestamp.now(),
          'archivedBy': <String>[],
          'mutedBy': <String>[],
        });
      }
    });

    tearDown(ProfileService.resetCurrentProfileCache);

    DesktopHome buildHome() {
      final firebaseAuth = auth();
      final notifications = NotificationService(
        firestore: db,
        auth: firebaseAuth,
      );
      return DesktopHome(
        currentUserId: uid,
        onOpenRoom: (_) {},
        onSeeAllRooms: () {},
        onViewAllFriends: () {},
        onStartRoom: () {},
        onOpenMoment: (_) {},
        onCreateMoment: () {},
        onSeeAllMoments: () {},
        onOpenConversation: (_) {},
        onOpenClub: (_) {},
        onSeeAllChats: () {},
        onOpenClubs: () {},
        roomService: RoomService(firestore: db, auth: firebaseAuth),
        friendService: FriendService(firestore: db, auth: firebaseAuth),
        followService: FollowService(firestore: db, auth: firebaseAuth),
        profileService: ProfileService(firestore: db, auth: firebaseAuth),
        feedService: HomeFeedService(
          firestore: db,
          auth: firebaseAuth,
          voiceMomentReadService: VoiceMomentReadService(
            feedInvoker: fakeVoiceMomentFeedInvoker(firestore: db),
          ),
        ),
        messageService: MessageService(
          firestore: db,
          auth: firebaseAuth,
          notificationService: notifications,
        ),
        clubService: ClubService(
          firestore: db,
          auth: firebaseAuth,
          storage: MockFirebaseStorage(),
          notificationService: notifications,
        ),
        clubChatService: ClubChatService(firestore: db, auth: firebaseAuth),
        firebaseAuth: firebaseAuth,
      );
    }

    for (final width in [1100.0, 1280.0, 1440.0]) {
      testWidgets('no chat card leaves the column at ${width.toInt()}x900', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(home: Scaffold(body: buildHome())));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }

        final rail = tester.getRect(find.byType(RecentChats));
        expect(rail.right, lessThanOrEqualTo(width));
        final cards = find.descendant(
          of: find.byType(RecentChats),
          matching: find.byType(AccessibleTapRegion),
        );
        expect(cards, findsNWidgets(3));

        final scrollers = find.descendant(
          of: find.byType(RecentChats),
          matching: find.byType(SingleChildScrollView),
        );
        if (scrollers.evaluate().isEmpty) {
          // Three whole cards: every one of them ends inside the column.
          for (var index = 0; index < 3; index++) {
            expect(
              tester.getRect(cards.at(index)).right,
              lessThanOrEqualTo(rail.right + 0.5),
            );
          }
        } else {
          // A peeking rail: the overflow belongs to a clipped scroll view,
          // so the pixels stop at the column edge and the last card is
          // still partly visible inside it.
          expect(
            tester.widget<SingleChildScrollView>(scrollers).clipBehavior,
            Clip.hardEdge,
          );
          final last = tester.getRect(cards.at(2));
          expect(last.left, lessThan(rail.right - 24));
          expect(last.left, greaterThanOrEqualTo(rail.left));
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
