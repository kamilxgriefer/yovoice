import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';
import 'package:yovoice/features/messages/presentation/widgets/room_link_message_card.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

const _link = 'https://yovoice.app/?room=room-1';
const _invite = 'Join me in The Family Lounge on YO Voice: $_link';

Message _text(String content, {String senderId = 'other'}) => Message(
  id: 'm-${content.hashCode}',
  conversationId: 'c1',
  senderId: senderId,
  type: MessageType.text,
  content: content,
  sentAt: DateTime(2026, 9, 6, 12),
  readBy: const [],
  reactions: const {},
);

VoiceRoom _room({
  String experience = 'community',
  RoomStatus status = RoomStatus.active,
  bool isLive = true,
}) => VoiceRoom(
  id: 'room-1',
  hostId: 'host',
  hostName: 'Host Hania',
  hostPhotoUrl: null,
  name: 'The Family Lounge',
  description: '',
  category: 'talk',
  visibility: 'public',
  language: 'English',
  maxParticipants: null,
  participantCount: 0,
  memberCount: 0,
  isLive: isLive,
  roomType: RoomType.community,
  status: status,
  imageUrl: null,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: false,
  membersCanStartVoice: true,
  createdAt: null,
  updatedAt: null,
  experience: experience,
);

Future<void> _pump(
  WidgetTester tester,
  Message message, {
  RoomLinkResolver? resolver,
  RoomLinkOpener? opener,
  VoidCallback? onLongPress,
  double width = 390,
  ThemeData? theme,
  String currentUserId = 'me',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: Scaffold(
        body: ListView(
          children: [
            MessageBubble(
              message: message,
              currentUserId: currentUserId,
              onLongPress: onLongPress ?? () {},
              roomLinkResolver: resolver,
              roomLinkOpener: opener,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(resetRoomLinkCache);

  group('a text message with a canonical room link', () {
    testWidgets('keeps the text and adds a room card with Join', (
      tester,
    ) async {
      final requested = <String>[];
      final opened = <VoiceRoom>[];
      await _pump(
        tester,
        _text(_invite),
        resolver: (id) async {
          requested.add(id);
          return _room();
        },
        opener: (_, room) => opened.add(room),
      );
      await tester.pumpAndSettle();

      expect(find.text(_invite), findsOneWidget, reason: 'text as sent');
      expect(requested, ['room-1']);
      expect(find.byKey(const ValueKey('room-link-card')), findsOneWidget);
      expect(find.text('The Family Lounge'), findsOneWidget);
      expect(
        find.text('Community room · hosted by Host Hania'),
        findsOneWidget,
      );
      expect(find.text('Join room'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('incoming-message-bubble')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('room-link-card-join')));
      await tester.pump();
      expect(opened.single.id, 'room-1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders inside an outgoing bubble too', (tester) async {
      await _pump(
        tester,
        _text(_invite, senderId: 'me'),
        resolver: (_) async => _room(experience: 'broadcast'),
        opener: (_, _) {},
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('outgoing-message-bubble')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('room-link-card')), findsOneWidget);
      expect(find.text('Podcast · hosted by Host Hania'), findsOneWidget);
      expect(find.text('Join podcast'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a loading line until the room resolves', (tester) async {
      final gate = Completer<VoiceRoom?>();
      await _pump(tester, _text(_invite), resolver: (_) => gate.future);
      expect(
        find.byKey(const ValueKey('room-link-card-loading')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('room-link-card')), findsNothing);

      gate.complete(_room());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('room-link-card-loading')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('room-link-card')), findsOneWidget);
    });

    testWidgets('a deleted or inaccessible room hides the card and never '
        'navigates', (tester) async {
      var opened = 0;
      await _pump(
        tester,
        _text(_invite),
        resolver: (_) async => null,
        opener: (_, _) => opened++,
      );
      await tester.pumpAndSettle();

      expect(find.text(_invite), findsOneWidget);
      expect(find.byKey(const ValueKey('room-link-card')), findsNothing);
      expect(find.byKey(const ValueKey('room-link-card-join')), findsNothing);
      expect(
        find.byKey(const ValueKey('room-link-card-loading')),
        findsNothing,
      );
      expect(opened, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a legacy /rooms/{id} link gets the same card', (tester) async {
      await _pump(
        tester,
        _text('Come listen: https://yovoice.app/rooms/room-1'),
        resolver: (_) async => _room(),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('room-link-card')), findsOneWidget);
    });

    testWidgets('long-press still opens the message actions', (tester) async {
      var longPressed = 0;
      await _pump(
        tester,
        _text(_invite),
        resolver: (_) async => _room(),
        onLongPress: () => longPressed++,
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text(_invite));
      await tester.pump();
      expect(longPressed, 1);
    });

    for (final width in const [320.0, 390.0, 1440.0]) {
      for (final entry in <String, ThemeData>{
        'dark': AppTheme.darkTheme,
        'pearl': AppTheme.lightTheme,
      }.entries) {
        testWidgets('${entry.key} fits ${width.toInt()} px without overflow', (
          tester,
        ) async {
          await _pump(
            tester,
            _text(
              'A rather long invitation sentence that wraps across several '
              'lines before the link: $_link — see you there!',
            ),
            resolver: (_) async => _room(),
            width: width,
            theme: entry.value,
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('room-link-card')), findsOneWidget);
          final card = tester.getSize(
            find.byKey(const ValueKey('room-link-card')),
          );
          expect(card.width, lessThanOrEqualTo(340));
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('anything else renders exactly as today', () {
    for (final content in const [
      'See you in the room at eight',
      'https://example.com/?room=room-1',
      'https://yovoice.app/?room=../room-1',
      'https://yovoice.app/?moment=m1',
      'https://yovoice.app/download',
      'yovoice.app/?room=room-1',
    ]) {
      testWidgets('"$content" is plain text with no card and no read', (
        tester,
      ) async {
        var resolved = 0;
        await _pump(
          tester,
          _text(content),
          resolver: (_) async {
            resolved++;
            return _room();
          },
        );
        await tester.pumpAndSettle();

        expect(find.text(content), findsOneWidget);
        expect(find.byKey(const ValueKey('room-link-card')), findsNothing);
        expect(
          find.byKey(const ValueKey('room-link-card-loading')),
          findsNothing,
        );
        expect(resolved, 0);
      });
    }
  });

  group('the production resolver', () {
    late FakeFirebaseFirestore db;

    setUp(() {
      db = FakeFirebaseFirestore();
      resetRoomLinkCache(
        service: RoomService(
          firestore: db,
          auth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
          ),
        ),
      );
    });

    Future<void> seed({String status = 'active'}) =>
        db.collection('rooms').doc('room-1').set({
          'hostId': 'host',
          'hostName': 'Host Hania',
          'name': 'The Family Lounge',
          'description': '',
          'category': 'talk',
          'visibility': 'public',
          'language': 'English',
          'participantCount': 0,
          'memberCount': 0,
          'isLive': true,
          'status': status,
          'experience': 'community',
        });

    test('resolves an active room', () async {
      await seed();
      final room = await defaultRoomLinkResolver('room-1');
      expect(room?.name, 'The Family Lounge');
    });

    test('fails closed for a missing room', () async {
      expect(await defaultRoomLinkResolver('room-1'), isNull);
    });

    test('fails closed for a closed room', () async {
      await seed(status: 'closed');
      expect(await defaultRoomLinkResolver('room-1'), isNull);
    });

    test('memoises the read for the same id', () async {
      await seed();
      final first = defaultRoomLinkResolver('room-1');
      final second = defaultRoomLinkResolver('room-1');
      expect(identical(first, second), isTrue);
    });
  });
}
