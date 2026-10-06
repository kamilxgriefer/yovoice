// Chats at 200 % text with the real product font (refine-look B7 review).
//
// The default test font draws every glyph a full em wide, so it cannot say
// whether Polish copy fits. These tests load Inter and pin that, at the
// reader's largest text, the friend rail's labels read in full instead of
// as clipped stubs and the composer's placeholder is never cut, while the
// composer's discs share one centre line with the field's text. At 1.0 the
// rail is the build 42 "Równy rytm 48" rail (one line, 76 px; its geometry
// is pinned in test/chats_rail_rhythm_test.dart) and the composer is
// exactly as before.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

const _me = 'me-uid';
const _them = 'them-uid';
const _conversationId = 'me-uid_them-uid';

Conversation _conversation() => Conversation(
  id: _conversationId,
  participantIds: const [_me, _them],
  participantNames: const {_me: 'Ja', _them: 'Kuba Wiśniewski'},
  participantEmails: const {_me: '', _them: ''},
  participantPhotoUrls: const {_me: '', _them: ''},
  unreadCounts: const {_me: 0, _them: 0},
  archivedBy: const <String>[],
  mutedBy: const <String>[],
  lastMessage: 'Do zobaczenia',
  lastMessageType: MessageType.text,
  lastMessageSenderId: _them,
  updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
  createdAt: DateTime.now().subtract(const Duration(days: 3)),
);

class _Service extends MessageService {
  _Service()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      );

  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) => Stream<List<Conversation>>.value([_conversation()]);

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream<List<Message>>.value(const <Message>[]);

  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => Stream<bool>.value(false);

  @override
  Stream<ChatPresence> watchUserPresence(String userId) =>
      Stream<ChatPresence>.value(
        const ChatPresence(isOnline: true, lastSeen: null),
      );

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}
}

/// Two friends with the long Polish surnames that used to clip.
const _friendNames = ['Kuba Wiśniewski', 'Marta Zielińska'];

class _Friends extends FriendService {
  _Friends()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      );

  @override
  Stream<List<FriendUser>> watchFriends() => Stream<List<FriendUser>>.value([
    for (final (index, name) in _friendNames.indexed)
      FriendUser(
        id: 'friend-$index',
        displayName: name,
        email: '',
        photoUrl: null,
        isOnline: true,
        lastSeen: null,
      ),
  ]);
}

Widget _host(Widget child, double textScale) => MaterialApp(
  theme: AppTheme.darkTheme,
  locale: const Locale('pl'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, navigator) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: navigator!,
  ),
  home: child,
);

void _surface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

RenderParagraph _paragraph(
  WidgetTester tester,
  String text, {
  Finder? within,
}) => tester.renderObject<RenderParagraph>(
  find.descendant(
    of: within == null
        ? find.text(text, skipOffstage: false)
        : find.descendant(
            of: within,
            matching: find.text(text, skipOffstage: false),
            skipOffstage: false,
          ),
    matching: find.byType(RichText, skipOffstage: false),
  ),
);

/// The friend rail's horizontal list.
Finder _rail() => find
    .ancestor(
      of: find.byKey(const ValueKey('messages-add-friend')),
      matching: find.byType(ListView),
    )
    .first;

void main() {
  late PublicIdentityRepository originalIdentityRepository;

  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
    await inter.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    originalIdentityRepository = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
  });

  group('friend rail', () {
    for (final width in const [390.0, 768.0, 1440.0]) {
      testWidgets('at 200 % every label reads in full, ${width.toInt()} px', (
        tester,
      ) async {
        _surface(tester, Size(width, 900));
        await tester.pumpWidget(
          _host(
            MessagesScreen(
              messageService: _Service(),
              friendService: _Friends(),
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: _me),
              ),
            ),
            2,
          ),
        );
        await tester.pumpAndSettle();

        // Build 42: the actions carry one short word; the full phrase is
        // their spoken name (test/chats_rail_rhythm_test.dart).
        for (final label in ['Dodaj', 'Napisz']) {
          final paragraph = _paragraph(tester, label, within: _rail());
          expect(paragraph.maxLines, 2, reason: label);
          expect(paragraph.didExceedMaxLines, isFalse, reason: label);
        }
        for (final name in _friendNames) {
          final paragraph = _paragraph(tester, name, within: _rail());
          expect(paragraph.maxLines, 2, reason: name);
          expect(paragraph.didExceedMaxLines, isFalse, reason: name);
        }
        // The tiles widen with the reader's text: an action from 64 px to
        // 1.3× (83.2 px), a friend to 2× (128 px), which is what lets a
        // first name and a long surname take one line each. (A surname
        // wider than that widens the friends' shared tile, up to 144 px:
        // test/chats_rail_rhythm_test.dart.)
        final addFriend = find.byKey(const ValueKey('messages-add-friend'));
        expect(tester.getSize(addFriend).width, greaterThan(64));
        expect(tester.getSize(addFriend).width, moreOrLessEquals(83.2));
        for (final name in _friendNames) {
          final tile = find.ancestor(
            of: find.descendant(of: _rail(), matching: find.text(name)),
            matching: find.byType(AccessibleTapRegion),
          );
          expect(
            tester.getSize(tile.first).width,
            moreOrLessEquals(128),
            reason: name,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('at 1.0 the rail takes one line and 76 px', (tester) async {
      _surface(tester, const Size(390, 844));
      await tester.pumpWidget(
        _host(
          MessagesScreen(
            messageService: _Service(),
            friendService: _Friends(),
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: _me),
            ),
          ),
          1,
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['Dodaj', 'Napisz', ..._friendNames]) {
        expect(
          _paragraph(tester, label, within: _rail()).maxLines,
          1,
          reason: label,
        );
      }
      // Build 42 ("Równy rytm 48"): 48 px mark + 6 + one 13.2 px line + 8.8;
      // it was 92 px with the 58 px marks.
      expect(tester.getSize(_rail()).height, 76);
      expect(
        tester.getSize(find.byKey(const ValueKey('messages-add-friend'))).width,
        64,
      );
    });
  });

  group('composer', () {
    ChatScreen chat() => ChatScreen(
      conversationId: _conversationId,
      otherUserId: _them,
      otherDisplayName: 'Kuba Wiśniewski',
      otherEmail: '',
      otherPhotoUrl: '',
      messageService: _Service(),
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
    );

    Offset cameraCentre(WidgetTester tester) => tester.getCenter(
      find.ancestor(
        of: find.byIcon(Icons.camera_alt_outlined),
        matching: find.byType(IconButton),
      ),
    );

    for (final width in const [320.0, 390.0]) {
      testWidgets('at 200 % the placeholder is whole, ${width.toInt()} px', (
        tester,
      ) async {
        _surface(tester, Size(width, 760));
        await tester.pumpWidget(_host(chat(), 2));
        await tester.pumpAndSettle();

        final hint = _paragraph(tester, 'Wiadomość…');
        expect(hint.didExceedMaxLines, isFalse);
        // Never below its 100 % size.
        expect(
          hint.textScaler.scale(hint.text.style?.fontSize ?? 16),
          greaterThanOrEqualTo(16),
        );

        // The camera, emoji and mic discs share one centre line.
        final mic = tester.getCenter(find.byKey(const ValueKey('voice')));
        expect(cameraCentre(tester).dy, moreOrLessEquals(mic.dy, epsilon: .5));
        if (width >= 390) {
          // Where the placeholder fits at full size it sits on that line too.
          final line = tester.getCenter(
            find.descendant(
              of: find.text('Wiadomość…'),
              matching: find.byType(RichText),
            ),
          );
          expect(line.dy, moreOrLessEquals(mic.dy, epsilon: 1.5));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('at 1.0 the composer row is unchanged', (tester) async {
      _surface(tester, const Size(390, 844));
      await tester.pumpWidget(_host(chat(), 1));
      await tester.pumpAndSettle();
      final mic = find.byKey(const ValueKey('voice'));
      expect(tester.getSize(mic), const Size.square(46));
      // Nothing is lifted: the camera and the mic both rest on the row's
      // bottom (the mic inside the field's 1 px outline).
      final composer = find.byKey(const ValueKey('chat-composer'));
      final camera = find.ancestor(
        of: find.byIcon(Icons.camera_alt_outlined),
        matching: find.byType(IconButton),
      );
      expect(tester.getSize(camera), const Size.square(48));
      expect(tester.getBottomLeft(camera).dy, tester.getBottomLeft(mic).dy + 1);
      expect(
        tester.getBottomLeft(composer).dy - tester.getBottomLeft(camera).dy,
        6,
        reason: 'the row\'s own bottom padding',
      );
      expect(cameraCentre(tester).dy, tester.getCenter(mic).dy);
    });
  });
}
