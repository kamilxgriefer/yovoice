import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';

/// Tester bug (2026-09-18, verbatim PL): "pokazuje się historia na samej
/// górze w czatach ludzi z którymi nie pisał nawet jeszcze, dziwnie ich
/// 'winduje' do góry bez sensu".
///
/// Someone opening MY profile creates an empty conversation root for both
/// of us with `updatedAt = now` (`openDirectConversation`,
/// `functions/messaging/direct_integrity.js`). Chats and the Home rail must
/// not show it; the empty thread I opened myself must stay visible; and the
/// order must follow the last message, never a bare root touch.
void main() {
  const me = 'me-uid';
  const writer = 'writer-uid';
  const lurker = 'lurker-uid';
  const friend = 'friend-uid';

  final now = DateTime.utc(2026, 9, 18, 12);

  late FakeFirebaseFirestore db;

  MockFirebaseAuth auth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: me, email: 'me@yovoice.app', displayName: 'Me'),
  );

  Map<String, Object?> root({
    required String other,
    required String otherName,
    required DateTime createdAt,
    required DateTime updatedAt,
    String lastMessage = '',
    String lastMessageSenderId = '',
    int lastMessageSequence = 0,
  }) {
    final participants = <String>[me, other]..sort();
    return <String, Object?>{
      'schemaVersion': 2,
      'pairKey': participants.join('_'),
      'participantIds': participants,
      'participantNames': <String, String>{me: 'Me', other: otherName},
      'participantEmails': <String, String>{me: '', other: ''},
      'participantPhotoUrls': <String, String>{me: '', other: ''},
      'unreadCounts': <String, int>{me: 0, other: 0},
      'readSequences': <String, int>{me: 0, other: 0},
      'typing': <String, Object?>{},
      'archivedBy': <String>[],
      'mutedBy': <String>[],
      'lastMessage': lastMessage,
      'lastMessageId': lastMessageSequence == 0 ? null : 'm$lastMessageSequence',
      'lastMessageSequence': lastMessageSequence,
      'lastMessageType': 'text',
      'lastMessageSenderId': lastMessageSenderId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Future<void> seed() async {
    final conversations = db.collection('conversations');
    await conversations.doc('dm_writer').set(
      root(
        other: writer,
        otherName: 'Wanda Writer',
        createdAt: now.subtract(const Duration(hours: 5)),
        updatedAt: now.subtract(const Duration(hours: 2)),
        lastMessage: 'hello from Wanda',
        lastMessageSenderId: writer,
        lastMessageSequence: 1,
      ),
    );
    await conversations.doc('dm_lurker').set(
      root(
        other: lurker,
        otherName: 'Larry Lurker',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await conversations.doc('dm_friend').set(
      root(
        other: friend,
        otherName: 'Frida Friend',
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now,
      ),
    );
  }

  Widget host(Widget child) => MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.darkTheme,
    home: child,
  );

  void useViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<MessageService> pumpChats(
    WidgetTester tester, {
    required Size size,
  }) async {
    useViewport(tester, size);
    final service = MessageService(
      firestore: db,
      auth: auth(),
      functions: _OpenFunctions('dm_friend'),
    );
    addTearDown(service.dispose);
    await tester.pumpWidget(
      host(
        MessagesScreen(
          messageService: service,
          friendService: _EmptyFriendService(),
          auth: auth(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    await seed();
  });

  for (final viewport in const <(String, Size)>[
    ('phone', Size(390, 844)),
    ('tablet', Size(834, 1194)),
    ('desktop', Size(1440, 900)),
  ]) {
    testWidgets('${viewport.$1}: Chats hides the empty thread someone else '
        'opened and keeps the one I opened, ordered by last message', (
      tester,
    ) async {
      final service = await pumpChats(tester, size: viewport.$2);

      expect(find.text('Wanda Writer'), findsOneWidget);
      expect(
        find.text('Larry Lurker'),
        findsNothing,
        reason:
            'a root someone else opened without writing has the newest '
            'updatedAt but no message, and must not appear at all',
      );
      expect(
        find.text('Frida Friend'),
        findsNothing,
        reason: 'not opened from this device yet, so it is an empty root too',
      );

      final opened = await service.openOrCreateConversation(
        otherUserId: friend,
        otherDisplayName: 'Frida Friend',
        otherEmail: '',
        otherPhotoUrl: '',
      );
      await tester.pumpAndSettle();

      expect(opened, 'dm_friend');
      expect(find.text('Frida Friend'), findsOneWidget);
      expect(find.text('Larry Lurker'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Wanda Writer')).dy,
        lessThan(tester.getTopLeft(find.text('Frida Friend')).dy),
        reason:
            'the 2 h old message outranks my empty thread created 3 h ago '
            'whose root was touched just now — createdAt, never updatedAt',
      );
    });
  }

  testWidgets('the Home recent-chats rail is fed by the same stream and '
      'matches', (tester) async {
    useViewport(tester, const Size(390, 844));
    final service = MessageService(
      firestore: db,
      auth: auth(),
      functions: _OpenFunctions('dm_friend'),
    );
    addTearDown(service.dispose);
    final stream = service.watchConversations();

    await tester.pumpWidget(
      host(
        Scaffold(
          body: StreamBuilder<List<Conversation>>(
            stream: stream,
            builder: (context, snapshot) => RecentChats(
              snapshot: snapshot,
              currentUserId: me,
              onOpenConversation: (_) {},
              onFindFriends: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wanda Writer'), findsOneWidget);
    expect(find.text('Larry Lurker'), findsNothing);
    expect(find.text('Frida Friend'), findsNothing);

    await service.openOrCreateConversation(
      otherUserId: friend,
      otherDisplayName: 'Frida Friend',
      otherEmail: '',
      otherPhotoUrl: '',
    );
    await tester.pumpAndSettle();

    expect(find.text('Frida Friend'), findsOneWidget);
    expect(find.text('Larry Lurker'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Wanda Writer')).dx,
      lessThan(tester.getTopLeft(find.text('Frida Friend')).dx),
      reason: 'the rail keeps the list order: newest message first',
    );
  });

  testWidgets('only empty roots vanish: the empty state still appears when '
      'nothing carries a message', (tester) async {
    await db.collection('conversations').doc('dm_writer').delete();
    await pumpChats(tester, size: const Size(390, 844));

    expect(find.text('Larry Lurker'), findsNothing);
    expect(find.text('Frida Friend'), findsNothing);
    // The Chats empty state, not a list of "Start a conversation" rows.
    expect(find.text('Your inbox is quiet'), findsOneWidget);
    expect(find.text('Start a conversation'), findsNothing);
  });
}

class _EmptyFriendService extends FriendService {
  _EmptyFriendService()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me-uid'),
        ),
      );

  @override
  Stream<List<FriendUser>> watchFriends() =>
      Stream<List<FriendUser>>.value(const <FriendUser>[]);
}

/// Stands in for the deployed `openDirectConversation`: the root already
/// exists, so the server answers with its id and writes nothing.
class _OpenFunctions implements FirebaseFunctions {
  _OpenFunctions(this.conversationId);

  final String conversationId;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub(
        (_) async => <Object?, Object?>{
          'conversationId': conversationId,
          'created': false,
        },
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CallableStub implements HttpsCallable {
  _CallableStub(this.handler);

  final Future<Object?> Function(Object? parameters) handler;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    final result = await handler(parameters);
    return _CallableResult<T>(result as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CallableResult<T> implements HttpsCallableResult<T> {
  _CallableResult(this.data);

  @override
  final T data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
