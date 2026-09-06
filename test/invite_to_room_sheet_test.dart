import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/presentation/widgets/invite_to_room_sheet.dart';

const _link = 'https://yovoice.app/?room=room-1';

/// Records the two calls the production delivery makes, without a backend.
class _RecordingMessages extends MessageService {
  _RecordingMessages({this.failWith})
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
        ),
        outbox: MessageOutbox(preferences: null),
      );

  final Object? failWith;
  final List<Map<String, String>> opened = [];
  final List<({String conversationId, String recipientId, String text})> sent =
      [];

  @override
  Future<String> openOrCreateConversation({
    required String otherUserId,
    required String otherDisplayName,
    required String otherEmail,
    required String otherPhotoUrl,
  }) async {
    opened.add({
      'otherUserId': otherUserId,
      'otherDisplayName': otherDisplayName,
      'otherEmail': otherEmail,
      'otherPhotoUrl': otherPhotoUrl,
    });
    if (failWith != null) throw failWith!;
    return 'conv-$otherUserId';
  }

  @override
  Future<void> sendTextMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    Message? replyTo,
  }) async {
    sent.add((
      conversationId: conversationId,
      recipientId: recipientId,
      text: text,
    ));
  }
}

FriendUser _friend(String id, String name, {bool online = false}) => FriendUser(
  id: id,
  displayName: name,
  username: id,
  email: '$id@yovoice.app',
  photoUrl: null,
  isOnline: online,
  lastSeen: null,
);

VoiceRoom _room({
  String visibility = 'public',
  String experience = 'community',
}) => VoiceRoom(
  id: 'room-1',
  hostId: 'host',
  hostName: 'Host',
  hostPhotoUrl: null,
  name: 'The Family Lounge',
  description: '',
  category: 'talk',
  visibility: visibility,
  language: 'English',
  maxParticipants: null,
  participantCount: 0,
  memberCount: 0,
  isLive: true,
  roomType: RoomType.community,
  status: RoomStatus.active,
  imageUrl: null,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: false,
  membersCanStartVoice: true,
  createdAt: null,
  updatedAt: null,
  experience: experience,
);

final _friends = <FriendUser>[
  _friend('ada', 'Ada Lovelace', online: true),
  _friend('bartek', 'Bartek Nowak'),
  _friend('celina', 'Celina Kowalska'),
];

Future<void> _pumpOpener(
  WidgetTester tester, {
  required VoiceRoom room,
  required Size size,
  Stream<List<FriendUser>>? friends,
  MessageService? messages,
  RoomInviteShare? share,
  ThemeData? theme,
  Locale locale = const Locale('en'),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showInviteToRoomSheet(
                context,
                room: room,
                friendsStream: friends ?? Stream.value(_friends),
                messageService: messages,
                share: share,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  const narrow = Size(390, 844);
  const wide = Size(1440, 900);

  group('narrow (bottom sheet)', () {
    testWidgets('lists friends with search and no dialog', (tester) async {
      await _pumpOpener(tester, room: _room(), size: narrow);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Invite to the room'), findsOneWidget);
      expect(find.text('The Family Lounge'), findsOneWidget);
      for (final friend in _friends) {
        expect(find.text(friend.displayName), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('invite-share-link')), findsOneWidget);
      expect(find.byKey(const ValueKey('invite-copy-link')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('invite-search')),
        'bart',
      );
      await tester.pumpAndSettle();
      expect(find.text('Bartek Nowak'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsNothing);
      expect(find.text('Celina Kowalska'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('invite-search')),
        'zzz',
      );
      await tester.pumpAndSettle();
      expect(find.text('No friends match your search.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Send opens the conversation and sends the localized text', (
      tester,
    ) async {
      final messages = _RecordingMessages();
      await _pumpOpener(
        tester,
        room: _room(),
        size: narrow,
        messages: messages,
      );

      await tester.tap(find.byKey(const ValueKey('invite-send-ada')));
      await tester.pumpAndSettle();

      expect(messages.opened, hasLength(1));
      expect(messages.opened.single, {
        'otherUserId': 'ada',
        'otherDisplayName': 'Ada Lovelace',
        'otherEmail': 'ada@yovoice.app',
        'otherPhotoUrl': '',
      });
      expect(messages.sent, hasLength(1));
      expect(messages.sent.single.conversationId, 'conv-ada');
      expect(messages.sent.single.recipientId, 'ada');
      expect(
        messages.sent.single.text,
        'Join me in The Family Lounge on YO Voice: $_link',
      );
      expect(find.byKey(const ValueKey('invite-sent-ada')), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
      // The other rows are untouched.
      expect(find.byKey(const ValueKey('invite-send-bartek')), findsOneWidget);

      // A second tap on a sent row does nothing.
      await tester.tap(
        find.byKey(const ValueKey('invite-sent-ada')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(messages.sent, hasLength(1));
    });

    testWidgets('a pending send shows a busy row and blocks re-entry', (
      tester,
    ) async {
      final gate = Completer<void>();
      final calls = <String>[];
      await _pumpOpener(
        tester,
        room: _room(),
        size: narrow,
        messages: _GatedMessages(gate.future, calls),
      );

      await tester.tap(find.byKey(const ValueKey('invite-send-ada')));
      await tester.pump();
      expect(find.byKey(const ValueKey('invite-busy-ada')), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('invite-busy-ada')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(calls, ['ada']);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('invite-sent-ada')), findsOneWidget);
    });

    testWidgets(
      'a server refusal surfaces friendly copy, never the raw message',
      (tester) async {
        final messages = _RecordingMessages(
          failWith: FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'RAW SERVER DETAIL',
          ),
        );
        await _pumpOpener(
          tester,
          room: _room(),
          size: narrow,
          messages: messages,
        );

        await tester.tap(find.byKey(const ValueKey('invite-send-bartek')));
        await tester.pumpAndSettle();

        expect(
          find.text("You can't message this person right now."),
          findsOneWidget,
        );
        expect(find.textContaining('RAW SERVER DETAIL'), findsNothing);
        expect(find.textContaining('Exception'), findsNothing);
        expect(find.text('Retry'), findsOneWidget);
        expect(messages.sent, isEmpty);
      },
    );

    testWidgets('a rate limit gets its own copy and the row stays retryable', (
      tester,
    ) async {
      await _pumpOpener(
        tester,
        room: _room(),
        size: narrow,
        messages: _RecordingMessages(
          failWith: FirebaseFunctionsException(
            code: 'resource-exhausted',
            message: 'quota',
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('invite-send-ada')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "You're sending invitations too quickly. Try again in a moment.",
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('invite-send-ada')), findsOneWidget);
    });

    testWidgets('a private room explains and offers no friend list', (
      tester,
    ) async {
      var listened = false;
      final friends = Stream<List<FriendUser>>.multi((subscriber) {
        listened = true;
        subscriber.add(_friends);
      });
      await _pumpOpener(
        tester,
        room: _room(visibility: 'private'),
        size: narrow,
        friends: friends,
      );

      expect(find.byKey(const ValueKey('invite-private-note')), findsOneWidget);
      expect(find.textContaining('This room is private'), findsOneWidget);
      expect(find.byKey(const ValueKey('invite-search')), findsNothing);
      expect(find.byKey(const ValueKey('invite-friend-list')), findsNothing);
      expect(find.byKey(const ValueKey('invite-share-link')), findsNothing);
      expect(find.byKey(const ValueKey('invite-copy-link')), findsNothing);
      for (final friend in _friends) {
        expect(find.text(friend.displayName), findsNothing);
      }
      expect(listened, isFalse, reason: 'no friend read for a private room');
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty and error friend states use friendly copy', (
      tester,
    ) async {
      await _pumpOpener(
        tester,
        room: _room(),
        size: narrow,
        friends: Stream.value(const <FriendUser>[]),
      );
      expect(
        find.text('Add friends first, then invite them here.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('modal-sheet-close')));
      await tester.pumpAndSettle();

      await _pumpOpener(
        tester,
        room: _room(),
        size: narrow,
        friends: Stream.error(StateError('boom')),
      );
      expect(
        find.text("Couldn't load your friends. Please try again."),
        findsOneWidget,
      );
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('Copy link puts the canonical link on the clipboard', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pumpOpener(tester, room: _room(), size: narrow);

      await tester.tap(find.byKey(const ValueKey('invite-copy-link')));
      await tester.pumpAndSettle();
      expect(copied, _link);
      expect(find.text('Link copied.'), findsOneWidget);
    });

    testWidgets('Share link hands the invitation text to the share seam', (
      tester,
    ) async {
      final shared = <(String, String)>[];
      await _pumpOpener(
        tester,
        room: _room(experience: 'broadcast'),
        size: narrow,
        share: (text, subject) async => shared.add((text, subject)),
      );
      expect(find.text('Invite to the podcast'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('invite-share-link')));
      await tester.pumpAndSettle();
      expect(shared, [
        (
          'Join me in The Family Lounge on YO Voice: $_link',
          'Join The Family Lounge on YO Voice',
        ),
      ]);
    });

    testWidgets('a failing system share falls back to friendly copy', (
      tester,
    ) async {
      await _pumpOpener(
        tester,
        room: _room(),
        size: narrow,
        share: (_, _) async => throw UnimplementedError('no share here'),
      );
      await tester.tap(find.byKey(const ValueKey('invite-share-link')));
      await tester.pumpAndSettle();
      expect(
        find.text('Sharing is not available here. Copy the link instead.'),
        findsOneWidget,
      );
      expect(find.textContaining('UnimplementedError'), findsNothing);
    });

    testWidgets('Polish wording for both products', (tester) async {
      final messages = _RecordingMessages();
      await _pumpOpener(
        tester,
        room: _room(),
        size: narrow,
        locale: const Locale('pl'),
        messages: messages,
      );
      expect(find.text('Zaproś do pokoju'), findsOneWidget);
      expect(find.text('Szukaj znajomych'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('invite-send-ada')));
      await tester.pumpAndSettle();
      expect(
        messages.sent.single.text,
        'Dołącz do mnie w The Family Lounge w YO Voice: $_link',
      );
      expect(find.text('Wysłano'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('modal-sheet-close')));
      await tester.pumpAndSettle();

      await _pumpOpener(
        tester,
        room: _room(experience: 'broadcast'),
        size: narrow,
        locale: const Locale('pl'),
      );
      expect(find.text('Zaproś do podcastu'), findsOneWidget);
    });
  });

  group('wide (dialog)', () {
    for (final entry in <String, ThemeData>{
      'dark': AppTheme.darkTheme,
      'pearl': AppTheme.lightTheme,
    }.entries) {
      testWidgets('${entry.key}: opens as a dialog with the same list', (
        tester,
      ) async {
        final messages = _RecordingMessages();
        await _pumpOpener(
          tester,
          room: _room(),
          size: wide,
          theme: entry.value,
          messages: messages,
        );

        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(
          find.byKey(const ValueKey('invite-to-room-panel')),
          findsOneWidget,
        );
        // Desktop presentation keeps the explicit close, drops the drag cue.
        expect(find.byKey(const ValueKey('modal-sheet-close')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('modal-sheet-drag-handle')),
          findsNothing,
        );
        for (final friend in _friends) {
          expect(find.text(friend.displayName), findsOneWidget);
        }

        await tester.tap(find.byKey(const ValueKey('invite-send-celina')));
        await tester.pumpAndSettle();
        expect(messages.sent.single.recipientId, 'celina');
        expect(
          find.byKey(const ValueKey('invite-sent-celina')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a private room opens as a short dialog', (tester) async {
      await _pumpOpener(
        tester,
        room: _room(visibility: 'private'),
        size: wide,
      );
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byKey(const ValueKey('invite-private-note')), findsOneWidget);
      expect(find.byKey(const ValueKey('invite-friend-list')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('medium widths keep the sheet, bounded to the modal width', (
    tester,
  ) async {
    await _pumpOpener(tester, room: _room(), size: const Size(800, 1000));
    expect(find.byType(BottomSheet), findsOneWidget);
    final panel = tester.getSize(
      find.byKey(const ValueKey('invite-to-room-panel')),
    );
    expect(panel.width, lessThanOrEqualTo(560));
    expect(tester.takeException(), isNull);
  });
}

/// Holds the first send until [gate] completes, so the busy state can be
/// observed and re-entry proven blocked.
class _GatedMessages extends MessageService {
  _GatedMessages(this.gate, this.calls)
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
        ),
        outbox: MessageOutbox(preferences: null),
      );

  final Future<void> gate;
  final List<String> calls;

  @override
  Future<String> openOrCreateConversation({
    required String otherUserId,
    required String otherDisplayName,
    required String otherEmail,
    required String otherPhotoUrl,
  }) async {
    calls.add(otherUserId);
    await gate;
    return 'conv-$otherUserId';
  }

  @override
  Future<void> sendTextMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    Message? replyTo,
  }) async {}
}
