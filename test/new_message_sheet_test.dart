import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';

const String _me = 'me';

FriendUser _friend(String id, String name) => FriendUser(
  id: id,
  displayName: name,
  email: '$id@yovoice.app',
  photoUrl: null,
  isOnline: false,
  lastSeen: null,
);

Conversation _conversation(String id, String name) => Conversation(
  id: id,
  participantIds: [_me, id],
  participantNames: {_me: 'Me', id: name},
  participantEmails: {_me: 'me@yovoice.app', id: '$id@yovoice.app'},
  participantPhotoUrls: const {},
  unreadCounts: const {},
  lastMessage: 'Hey there',
  lastMessageType: MessageType.text,
  lastMessageSenderId: id,
  updatedAt: DateTime(2026, 8, 8),
  createdAt: DateTime(2026, 8, 1),
  archivedBy: const [],
  mutedBy: const [],
);

/// Pumps the sheet the same way `MessagesScreen` does: the streams are
/// created once and are ALREADY being listened to by another widget before
/// the sheet mounts. That second subscription is what used to blow up.
Future<void> _pumpSheet(
  WidgetTester tester, {
  required Stream<List<FriendUser>> friends,
  required Stream<List<Conversation>> conversations,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Column(
          children: [
            // Stands in for _FriendsRow: the first subscriber.
            StreamBuilder<List<FriendUser>>(
              stream: friends,
              builder: (context, snapshot) =>
                  Text('friends: ${snapshot.data?.length ?? 0}'),
            ),
            Expanded(
              child: NewMessageSheet(
                friendsStream: friends,
                conversationsStream: conversations,
                currentUserId: _me,
                onFriendSelected: (_) {},
                onConversationSelected: (_) {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('NewMessageSheet', () {
    testWidgets('survives a second subscription to the shared friends stream', (
      tester,
    ) async {
      // Regression test for the "huge light-grey panel" bug: FriendService
      // .watchFriends() handed back a single-subscription stream, so the
      // sheet's StreamBuilder threw "Stream has already been listened to"
      // and Flutter swapped the whole content area for a bare grey
      // ErrorWidget (invisible as an error in release web builds).
      final friendService = _FakeFriendsSource([
        _friend('ava', 'Ava Stone'),
        _friend('ben', 'Ben Carter'),
      ]);
      addTearDown(friendService.dispose);

      await _pumpSheet(
        tester,
        friends: friendService.stream,
        conversations: Stream<List<Conversation>>.value([
          _conversation('ava', 'Ava Stone'),
        ]).asBroadcastStream(),
      );
      await tester.pump(const Duration(milliseconds: 10));

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
    });

    testWidgets('renders friends and recent conversations', (tester) async {
      final friendService = _FakeFriendsSource([
        _friend('ava', 'Ava Stone'),
        _friend('ben', 'Ben Carter'),
      ]);
      addTearDown(friendService.dispose);

      await _pumpSheet(
        tester,
        friends: friendService.stream,
        conversations: Stream<List<Conversation>>.value([
          _conversation('cleo', 'Cleo Nakamura'),
        ]).asBroadcastStream(),
      );
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('New message'), findsOneWidget);
      expect(find.text('Ava Stone'), findsOneWidget);
      expect(find.text('Cleo Nakamura'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the dark empty state when there are no friends', (
      tester,
    ) async {
      final friendService = _FakeFriendsSource(const []);
      addTearDown(friendService.dispose);

      await _pumpSheet(
        tester,
        friends: friendService.stream,
        conversations: Stream<List<Conversation>>.value(
          const [],
        ).asBroadcastStream(),
      );
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Add friends to start messaging them here.'), findsOne);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stays on a dark surface when the friends stream errors', (
      tester,
    ) async {
      final friendService = _FakeFriendsSource(
        const [],
        error: Exception('permission-denied'),
      );
      addTearDown(friendService.dispose);

      await _pumpSheet(
        tester,
        friends: friendService.stream,
        conversations: Stream<List<Conversation>>.error(
          Exception('permission-denied'),
        ).asBroadcastStream(),
      );
      await tester.pump(const Duration(milliseconds: 10));

      // A stream error must not produce Flutter's grey ErrorWidget, and it
      // must not be mistaken for "you have no friends".
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text("We couldn't load your people"), findsOne);
      expect(
        find.text('Add friends to start messaging them here.'),
        findsNothing,
      );
    });

    testWidgets('owns its surface with a dark Material', (tester) async {
      // The sheet must paint its own Material: showModalBottomSheet is
      // called with a transparent background, and ListTile ink/background
      // resolve against the nearest Material ancestor.
      final friendService = _FakeFriendsSource([_friend('ava', 'Ava Stone')]);
      addTearDown(friendService.dispose);

      await _pumpSheet(
        tester,
        friends: friendService.stream,
        conversations: Stream<List<Conversation>>.value(
          const [],
        ).asBroadcastStream(),
      );
      await tester.pump(const Duration(milliseconds: 10));

      final surface = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(NewMessageSheet),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(surface.color, const Color(0xFF120D1A));

      // Nothing in the sheet may paint a light surface.
      final lightSurfaces = tester.widgetList<Material>(
        find.descendant(
          of: find.byType(NewMessageSheet),
          matching: find.byType(Material),
        ),
      );
      for (final material in lightSurfaces) {
        final color = material.color;
        if (color == null || color.a == 0) continue;
        expect(
          color.computeLuminance(),
          lessThan(0.5),
          reason: 'Found a light Material surface inside the sheet: $color',
        );
      }
    });
  });
}

/// Mirrors the shape of `FriendService.watchFriends()` — a controller with
/// onListen/onCancel lifecycle whose stream gets handed to more than one
/// widget.
class _FakeFriendsSource {
  _FakeFriendsSource(this._friends, {Object? error}) : _error = error {
    _controller = StreamController<List<FriendUser>>.broadcast();
    _controller.onListen = _emit;
  }

  final List<FriendUser> _friends;
  final Object? _error;
  late final StreamController<List<FriendUser>> _controller;
  List<FriendUser>? _latest;

  void _emit() {
    if (_controller.isClosed) return;
    if (_error != null) {
      _controller.addError(_error);
      return;
    }
    _latest = _friends;
    _controller.add(_friends);
  }

  /// Replays the last value to late subscribers, the same contract the real
  /// service now provides.
  Stream<List<FriendUser>> get stream =>
      Stream<List<FriendUser>>.multi((subscriber) {
        final cached = _latest;
        if (cached != null) subscriber.add(cached);
        final subscription = _controller.stream.listen(
          subscriber.add,
          onError: subscriber.addError,
          onDone: subscriber.close,
        );
        subscriber.onCancel = subscription.cancel;
      });

  void dispose() => _controller.close();
}
