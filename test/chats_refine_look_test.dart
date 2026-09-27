// Refine-look B7 (spec §8.3): the Chats list, thread and composer finish.
//
// Pins the behaviour the batch adds — run grouping that never hides
// information, unread carried by weight and count, the one CTA lift, the
// first-run logo, the shared outgoing finish of sent and queued bubbles, the
// composer discs, the reaction discs at 200 % and the date pill — so a later
// restyle cannot quietly lose any of it.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/badges/yo_count_badge.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/inputs/yo_emoji_picker.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';

import 'voice_moment_test_doubles.dart';

const _me = 'me-uid';
const _them = 'them-uid';
const _conversationId = 'me-uid_them-uid';

Message _message(
  String id,
  String sender,
  String content,
  DateTime at, {
  bool read = true,
  DateTime? editedAt,
  Map<String, String> reactions = const <String, String>{},
}) => Message(
  id: id,
  conversationId: _conversationId,
  senderId: sender,
  type: MessageType.text,
  content: content,
  sentAt: at,
  readBy: read ? const [_me, _them] : const [_me],
  reactions: reactions,
  editedAt: editedAt,
);

Conversation _conversation({
  String id = _conversationId,
  int unread = 0,
  MessageType type = MessageType.text,
  String lastMessage = 'hello there',
}) => Conversation(
  id: id,
  participantIds: const [_me, _them],
  participantNames: const {_me: 'Me', _them: 'Them'},
  participantEmails: const {_me: '', _them: ''},
  participantPhotoUrls: const {_me: '', _them: ''},
  unreadCounts: {_me: unread, _them: 0},
  archivedBy: const <String>[],
  mutedBy: const <String>[],
  lastMessage: lastMessage,
  lastMessageType: type,
  lastMessageSenderId: _them,
  updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
  createdAt: DateTime.now().subtract(const Duration(days: 3)),
);

class _Service extends MessageService {
  _Service({
    this.messages = const <Message>[],
    this.conversations = const <Conversation>[],
    this.typing = false,
    super.outbox,
  }) : super(
         firestore: FakeFirebaseFirestore(),
         auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
       );

  final List<Message> messages;
  final List<Conversation> conversations;
  final bool typing;

  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) => Stream<List<Conversation>>.value(conversations);

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream<List<Message>>.value(messages);

  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => Stream<bool>.value(typing);

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

class _Friends extends FriendService {
  _Friends()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      );

  @override
  Stream<List<FriendUser>> watchFriends() =>
      Stream<List<FriendUser>>.value(const <FriendUser>[]);
}

Widget _host(
  Widget child, {
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
  bool highContrast = false,
  bool disableAnimations = false,
  TextDirection? textDirection,
}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, navigator) {
    final Widget content = MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: textScaler,
        highContrast: highContrast,
        disableAnimations: disableAnimations,
      ),
      child: navigator!,
    );
    return textDirection == null
        ? content
        : Directionality(textDirection: textDirection, child: content);
  },
  home: child,
);

/// Hosts [child] under a [TickerMode] the test can switch, the way the
/// preserving tab host and a covering opaque route do.
Widget _tickerHost(ValueNotifier<bool> tickers, Widget child) =>
    ValueListenableBuilder<bool>(
      valueListenable: tickers,
      builder: (context, enabled, child) =>
          TickerMode(enabled: enabled, child: child!),
      child: child,
    );

void _surface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

ChatScreen _chat(
  _Service service, {
  DirectMessageVoiceRecorderFactory? recorderFactory,
}) => ChatScreen(
  conversationId: _conversationId,
  otherUserId: _them,
  otherDisplayName: 'Them',
  otherEmail: '',
  otherPhotoUrl: '',
  messageService: service,
  auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
  voiceRecorderFactory: recorderFactory,
);

/// One text message a minute ago, so a thread has something in it.
List<Message> _oneMessage([Map<String, String> reactions = const {}]) => [
  _message(
    'm1',
    _them,
    'hello there',
    DateTime.now().subtract(const Duration(minutes: 1)),
    reactions: reactions,
  ),
];

/// The three typing dots, oldest delay first.
List<ScaleTransition> _typingDots(WidgetTester tester) => tester
    .widgetList<ScaleTransition>(
      find.descendant(
        of: find
            .ancestor(of: find.text('typing…'), matching: find.byType(Row))
            .first,
        matching: find.byType(ScaleTransition),
      ),
    )
    .toList();

MessagesScreen _list(_Service service) => MessagesScreen(
  messageService: service,
  friendService: _Friends(),
  auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
);

MessageBubble _bubbleOf(WidgetTester tester, String id) => tester
    .widgetList<MessageBubble>(find.byType(MessageBubble))
    .singleWhere((bubble) => bubble.message.id == id);

void main() {
  late PublicIdentityRepository originalIdentityRepository;

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

  group('run grouping (spec §8.3)', () {
    final base = DateTime(2026, 9, 20, 10, 0, 5);

    test('a run is the same sender, the same day, under two minutes and '
        'no reactions', () {
      final a = _message('a', _them, 'one', base);
      expect(
        MessageBubble.continuesRun(
          a,
          _message('b', _them, 'two', base.add(const Duration(seconds: 90))),
        ),
        isTrue,
      );
      expect(
        MessageBubble.continuesRun(
          a,
          _message('b', _me, 'two', base.add(const Duration(seconds: 10))),
        ),
        isFalse,
        reason: 'another sender starts a new run',
      );
      expect(
        MessageBubble.continuesRun(
          a,
          _message('b', _them, 'two', base.add(const Duration(minutes: 2))),
        ),
        isFalse,
        reason: 'two minutes apart is no longer a run',
      );
      expect(
        MessageBubble.continuesRun(
          _message('a', _them, 'one', DateTime(2026, 9, 20, 23, 59, 30)),
          _message('b', _them, 'two', DateTime(2026, 9, 21, 0, 0, 10)),
        ),
        isFalse,
        reason: 'a date break always ends a run',
      );
      expect(
        MessageBubble.continuesRun(
          _message('a', _them, 'one', base, reactions: const {_me: '🔥'}),
          _message('b', _them, 'two', base.add(const Duration(seconds: 5))),
        ),
        isFalse,
        reason: 'a reaction pill sits between the bubbles',
      );
    });

    testWidgets('the time row is left to the next bubble only when it prints '
        'the identical time, edit state and read state', (tester) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              final same = MessageBubble.sharesMeta(
                context,
                _message('a', _me, 'one', base, read: false),
                _message(
                  'b',
                  _me,
                  'two',
                  base.add(const Duration(seconds: 20)),
                  read: false,
                ),
                _me,
              );
              final readDiffers = MessageBubble.sharesMeta(
                context,
                _message('a', _me, 'one', base),
                _message(
                  'b',
                  _me,
                  'two',
                  base.add(const Duration(seconds: 20)),
                  read: false,
                ),
                _me,
              );
              final editDiffers = MessageBubble.sharesMeta(
                context,
                _message('a', _them, 'one', base, editedAt: base),
                _message(
                  'b',
                  _them,
                  'two',
                  base.add(const Duration(seconds: 20)),
                ),
                _me,
              );
              final minuteDiffers = MessageBubble.sharesMeta(
                context,
                _message('a', _them, 'one', base),
                _message(
                  'b',
                  _them,
                  'two',
                  base.add(const Duration(seconds: 60)),
                ),
                _me,
              );
              return Text('$same $readDiffers $editDiffers $minuteDiffers');
            },
          ),
        ),
      );
      expect(find.text('true false false false'), findsOneWidget);
    });

    testWidgets('the thread joins a run, tightens its corner and gap, and '
        'keeps the hidden time for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      _surface(tester, const Size(390, 844));
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day, 9, 12, 5);
      await tester.pumpWidget(
        _host(
          _chat(
            _Service(
              messages: [
                // Newest first, as the service streams them.
                _message(
                  'late',
                  _them,
                  'much later',
                  start.add(const Duration(minutes: 20)),
                ),
                _message(
                  'second',
                  _them,
                  'second line',
                  start.add(const Duration(seconds: 25)),
                ),
                _message('first', _them, 'first line', start),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final first = _bubbleOf(tester, 'first');
      final second = _bubbleOf(tester, 'second');
      final late = _bubbleOf(tester, 'late');
      expect(first.joinsOlder, isFalse);
      expect(first.joinsNewer, isTrue);
      expect(first.showMeta, isFalse, reason: 'second prints 09:12 too');
      expect(second.joinsOlder, isTrue);
      expect(second.joinsNewer, isFalse);
      expect(second.showMeta, isTrue);
      expect(late.joinsOlder, isFalse);

      // The joined bubble's sender-side top corner tightens to the tail.
      final bubbles = tester
          .widgetList<Container>(
            find.byKey(const ValueKey('incoming-message-bubble')),
          )
          .toList();
      final radii = bubbles
          .map((c) => (c.decoration! as BoxDecoration).borderRadius!)
          .toList();
      expect(
        radii,
        contains(MessageBubble.bubbleRadius(isMine: false, joinsOlder: true)),
      );
      expect(
        MessageBubble.bubbleRadius(isMine: false, joinsOlder: true).topLeft,
        const Radius.circular(MessageBubble.tailRadius),
      );
      expect(
        MessageBubble.bubbleRadius(isMine: false).bottomLeft,
        const Radius.circular(MessageBubble.tailRadius),
      );

      // Visually the time appears once for the run's shared minute...
      final time = MaterialLocalizations.of(
        tester.element(find.byType(ChatScreen)),
      ).formatTimeOfDay(TimeOfDay.fromDateTime(start));
      expect(find.text(time), findsOneWidget);
      // ...and the first bubble still says its time to a screen reader,
      // after its content, exactly as when the row was drawn.
      expect(
        find.bySemanticsLabel(
          RegExp('^first line\\s+${RegExp.escape(time)}\$'),
        ),
        findsOneWidget,
      );
      // The gap inside the run is 2 px (6 px elsewhere).
      Finder bubbleAround(String text) => find.ancestor(
        of: find.text(text),
        matching: find.byKey(const ValueKey('incoming-message-bubble')),
      );
      final gap =
          tester.getTopLeft(bubbleAround('second line')).dy -
          tester.getBottomLeft(bubbleAround('first line')).dy;
      expect(gap, MessageBubble.runGap);
      semantics.dispose();
    });
  });

  group('bubbles and queued sends (R15)', () {
    testWidgets('a queued send paints the sent finish and a failed one adds '
        'a 1.5 px error edge', (tester) async {
      _surface(tester, const Size(390, 844));
      final outbox = MessageOutbox(storageKey: null, ownerId: _me);
      // Enqueued in the test's own zone, so the chat's load of the queue
      // completes inside the pumps below.
      await outbox.enqueue(
        conversationId: _conversationId,
        recipientId: _them,
        text: 'on its way',
      );
      final failedEntry = await outbox.enqueue(
        conversationId: _conversationId,
        recipientId: _them,
        text: 'did not make it',
      );
      final failedId = failedEntry.id;
      await outbox.markFailed(failedId, 'network unavailable');
      await tester.pumpWidget(_host(_chat(_Service(outbox: outbox))));
      await tester.pumpAndSettle();

      final scheme = AppTheme.darkTheme.colorScheme;
      final queued = tester
          .widgetList<Container>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.key is ValueKey<String> &&
                  (widget.key! as ValueKey<String>).value.startsWith(
                    'queued-message-bubble-',
                  ),
            ),
          )
          .toList();
      expect(queued, hasLength(2));
      for (final bubble in queued) {
        final decoration = bubble.decoration! as BoxDecoration;
        expect(
          decoration.gradient,
          MessageBubble.outgoingDecoration(scheme).gradient,
        );
        expect(
          decoration.borderRadius,
          MessageBubble.bubbleRadius(isMine: true),
        );
      }
      final failed = tester.widget<Container>(
        find.byKey(ValueKey('queued-message-bubble-$failedId')),
      );
      final edge = (failed.decoration! as BoxDecoration).border! as Border;
      expect(edge.top.color, scheme.error);
      expect(edge.top.width, 1.5);
      expect(tester.takeException(), isNull);
    });

    testWidgets('under RTL the thread mirrors: your bubbles and their tails '
        'sit at the end of the line, theirs at the start', (tester) async {
      _surface(tester, const Size(390, 844));
      final at = DateTime.now().subtract(const Duration(minutes: 1));
      await tester.pumpWidget(
        _host(
          _chat(
            _Service(
              messages: [
                _message('mine', _me, 'mine', at),
                _message(
                  'theirs',
                  _them,
                  'theirs',
                  at.subtract(const Duration(minutes: 5)),
                ),
              ],
            ),
          ),
          textDirection: TextDirection.rtl,
        ),
      );
      await tester.pumpAndSettle();

      final outgoing = find.byKey(const ValueKey('outgoing-message-bubble'));
      final incoming = find.byKey(const ValueKey('incoming-message-bubble'));
      expect(tester.getCenter(outgoing).dx, lessThan(195));
      expect(tester.getCenter(incoming).dx, greaterThan(195));
      const tail = Radius.circular(MessageBubble.tailRadius);
      final mine =
          (tester.widget<Container>(outgoing).decoration! as BoxDecoration)
                  .borderRadius!
              as BorderRadius;
      expect(mine.bottomLeft, tail, reason: 'the tail follows the sender');
      final theirs =
          (tester.widget<Container>(incoming).decoration! as BoxDecoration)
                  .borderRadius!
              as BorderRadius;
      expect(theirs.bottomRight, tail);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the date separator is a glass pill that reads the day as '
        'written', (tester) async {
      final semantics = tester.ensureSemantics();
      _surface(tester, const Size(390, 844));
      final now = DateTime.now();
      await tester.pumpWidget(
        _host(
          _chat(
            _Service(
              messages: [
                _message(
                  'today',
                  _them,
                  'hi',
                  DateTime(now.year, now.month, now.day, 0, 1),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-date-separator')), findsOne);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.bySemanticsLabel('Today'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('composer (spec §8.3)', () {
    testWidgets('voice, send and saving keep their keys and draw 36 px discs '
        'in a 24 px-radius field', (tester) async {
      _surface(tester, const Size(390, 844));
      await tester.pumpWidget(_host(_chat(_Service())));
      await tester.pumpAndSettle();

      final voice = find.byKey(const ValueKey('voice'));
      expect(voice, findsOneWidget);
      final voiceDisc = tester.widget<YoGradientDisc>(
        find.descendant(of: voice, matching: find.byType(YoGradientDisc)),
      );
      expect(voiceDisc.size, 36);
      expect(voiceDisc.gloss, isTrue, reason: 'the voice bead');
      expect(tester.getSize(voice), const Size.square(46));

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();
      final send = find.byKey(const ValueKey('send'));
      expect(send, findsOneWidget);
      final sendDisc = tester.widget<YoGradientDisc>(
        find.descendant(of: send, matching: find.byType(YoGradientDisc)),
      );
      expect(sendDisc.size, 36);
      expect(sendDisc.gloss, isFalse, reason: 'the R6 icon disc');
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);

      final field = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(TextField),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (field.decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(24),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('long-press sheet (spec §8.3)', () {
    for (final width in const [320.0, 390.0]) {
      testWidgets('reaction discs stay at least 44 px and do not overflow at '
          '200 % text, ${width.toInt()} px', (tester) async {
        _surface(tester, Size(width, 700));
        await tester.pumpWidget(
          _host(
            _chat(
              _Service(
                messages: [
                  _message(
                    'm1',
                    _them,
                    'long press me',
                    DateTime.now().subtract(const Duration(minutes: 1)),
                  ),
                ],
              ),
            ),
            textScaler: const TextScaler.linear(2),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.text('long press me'));
        await tester.pumpAndSettle();

        for (final emoji in const ['❤️', '😂', '🔥', '😮', '😢', '👍']) {
          final glyph = find.text(emoji);
          expect(glyph, findsOneWidget);
          expect(tester.widget<Text>(glyph).textScaler, TextScaler.noScaling);
          final disc = find
              .ancestor(of: glyph, matching: find.byType(SizedBox))
              .first;
          expect(tester.getSize(disc).width, greaterThanOrEqualTo(44));
        }
        final report = tester.widget<ListTile>(
          find.byKey(const ValueKey('report-message')),
        );
        final palette = AppTheme.darkTheme.extension<AppPalette>()!;
        expect(
          (report.leading! as Icon).color,
          palette.warningForeground,
          reason: 'warning literals moved to the palette role',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the list (spec §8.3)', () {
    testWidgets('rows lead voice previews with a silent mic glyph and print '
        'the unread count as the gradient badge', (tester) async {
      final semantics = tester.ensureSemantics();
      _surface(tester, const Size(390, 844));
      await tester.pumpWidget(
        _host(
          _list(
            _Service(
              conversations: [
                _conversation(
                  unread: 3,
                  type: MessageType.voice,
                  lastMessage: 'voice',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final palette = AppTheme.darkTheme.extension<AppPalette>()!;
      final mic = tester.widget<Icon>(find.byIcon(Icons.mic_rounded));
      expect(mic.size, 15);
      expect(mic.color, palette.audioAccent);
      expect(find.text('Voice message'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byIcon(Icons.mic_rounded),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );
      final badge = find.byKey(
        const ValueKey('conversation-unread-badge-me-uid_them-uid'),
      );
      expect(
        find.descendant(of: badge, matching: find.byType(YoCountBadge)),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('3 unread messages')), findsOne);

      final more = tester.widget<Icon>(find.byIcon(Icons.more_horiz_rounded));
      expect(more.color, palette.textTertiary);
      final moreButton = find.ancestor(
        of: find.byIcon(Icons.more_horiz_rounded),
        matching: find.byType(IconButton),
      );
      expect(tester.getSize(moreButton), const Size.square(48));
      semantics.dispose();
    });

    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      testWidgets('the row ring follows the row\'s own focus, never its '
          '"…" button (${size.width.toInt()})', (tester) async {
        _surface(tester, size);
        final strategy = FocusManager.instance.highlightStrategy;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
        await tester.pumpWidget(
          _host(_list(_Service(conversations: [_conversation()]))),
        );
        await tester.pumpAndSettle();

        final palette = AppTheme.darkTheme.extension<AppPalette>()!;
        final row = find.byKey(
          const ValueKey('conversation-row-$_conversationId'),
        );
        Color ring() =>
            ((tester.widget<AnimatedContainer>(row).foregroundDecoration!
                            as BoxDecoration)
                        .border!
                    as Border)
                .top
                .color;
        final more = find.descendant(
          of: row,
          matching: find.byIcon(Icons.more_horiz_rounded),
        );
        final rowRect = tester.getRect(row);
        expect(ring(), Colors.transparent);

        // The row itself: one ring around it.
        // The row InkWell's own Focus (the first under the row).
        tester
            .widget<Focus>(
              find.descendant(of: row, matching: find.byType(Focus)).first,
            )
            .focusNode!
            .requestFocus();
        await tester.pumpAndSettle();
        expect(ring(), palette.focus);

        // The row's "…" button: its own indicator alone.
        Focus.of(tester.element(more)).requestFocus();
        await tester.pumpAndSettle();
        expect(Focus.of(tester.element(more)).hasPrimaryFocus, isTrue);
        expect(ring(), Colors.transparent);
        expect(tester.getRect(row), rowRect, reason: 'focus moves nothing');
      });
    }

    testWidgets('the compose disc is the one CTA lift', (tester) async {
      _surface(tester, const Size(390, 844));
      await tester.pumpWidget(
        _host(_list(_Service(conversations: [_conversation()]))),
      );
      await tester.pumpAndSettle();

      final lifted = tester
          .widgetList<YoGradientDisc>(find.byType(YoGradientDisc))
          .where((disc) => disc.emphasis == YoDiscEmphasis.lift);
      expect(lifted, hasLength(1));
      expect(lifted.single.size, 40);
      expect(find.byTooltip('Start a new message'), findsOneWidget);
    });

    for (final (height, size) in const [(844.0, 88.0), (540.0, 72.0)]) {
      testWidgets('the first-run inbox shows the real logo at ${size.toInt()} '
          'px and a flat gradient CTA', (tester) async {
        _surface(tester, Size(390, height));
        await tester.pumpWidget(_host(_list(_Service())));
        await tester.pumpAndSettle();

        final logo = tester.widget<YoBrandMark>(
          find.byKey(const ValueKey('messages-empty-logo')),
        );
        expect(logo.size, size);
        final cta = tester.widget<YoGradientFilledButton>(
          find.byKey(const ValueKey('messages-empty-new-message')),
        );
        expect(
          cta.emphasis,
          YoActionEmphasis.flat,
          reason: 'the compose disc already owns the screen\'s one lift',
        );
        expect(find.text('Your inbox is quiet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('search and archive empty states keep a quiet glyph, not the '
        'logo', (tester) async {
      _surface(tester, const Size(390, 844));
      await tester.pumpWidget(
        _host(_list(_Service(conversations: [_conversation()]))),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No matching chats'), findsOneWidget);
      expect(find.byType(YoBrandMark), findsNothing);
      expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    });

    for (final (theme, section) in [
      (AppTheme.darkTheme, YoPageSection.chats),
      (AppTheme.lightTheme, null),
    ]) {
      testWidgets('the canvas is the promoted radial; Pearl drops the lounge '
          'photo (${theme.brightness.name})', (tester) async {
        _surface(tester, const Size(390, 844));
        await tester.pumpWidget(
          _host(
            _list(_Service(conversations: [_conversation()])),
            theme: theme,
          ),
        );
        await tester.pumpAndSettle();
        final background = tester.widget<YoPageBackground>(
          find.byKey(const ValueKey('messages-screen-background')),
        );
        expect(background.section, section);
        final palette = theme.extension<AppPalette>()!;
        expect(
          (background.decoration! as BoxDecoration).gradient,
          palette.canvasGlow(theme.colorScheme.primary),
        );
      });
    }

    testWidgets('high contrast returns the incoming bubble to a flat surface '
        'with borderStrong', (tester) async {
      _surface(tester, const Size(390, 844));
      await tester.pumpWidget(
        _host(
          _chat(
            _Service(
              messages: [
                _message(
                  'm1',
                  _them,
                  'contrast',
                  DateTime.now().subtract(const Duration(minutes: 1)),
                ),
              ],
            ),
          ),
          highContrast: true,
        ),
      );
      await tester.pumpAndSettle();
      final palette = AppTheme.darkTheme.extension<AppPalette>()!;
      final bubble = tester.widget<Container>(
        find.byKey(const ValueKey('incoming-message-bubble')),
      );
      final decoration = bubble.decoration! as BoxDecoration;
      expect(decoration.gradient, isNull);
      expect(decoration.color, palette.surface);
      expect((decoration.border! as Border).top.color, palette.borderStrong);
      expect(
        decoration,
        AppFinish.block(
          palette,
          radius: MessageBubble.bubbleRadius(isMine: false),
          highContrast: true,
        ),
      );
    });
  });

  group('motion is honest (spec §2.7)', () {
    Finder entrance() =>
        find.byKey(const ValueKey('messages-empty-logo-entrance'));
    double logoOpacity(WidgetTester tester) =>
        tester.widget<FadeTransition>(entrance()).opacity.value;
    double logoScale(WidgetTester tester) => tester
        .widget<ScaleTransition>(
          find
              .descendant(
                of: entrance(),
                matching: find.byType(ScaleTransition),
              )
              .first,
        )
        .scale
        .value;

    testWidgets('the first-run logo enters once and never replays when '
        'tickers pause and resume (tab return, covering route)', (
      tester,
    ) async {
      _surface(tester, const Size(390, 844));
      final tickers = ValueNotifier<bool>(true);
      addTearDown(tickers.dispose);
      await tester.pumpWidget(_host(_tickerHost(tickers, _list(_Service()))));
      await tester.pump();
      expect(entrance(), findsOneWidget);
      // A real first appearance does enter.
      expect(logoOpacity(tester), lessThan(1));
      await tester.pumpAndSettle();
      expect(logoOpacity(tester), 1);
      expect(logoScale(tester), 1);

      tickers.value = false;
      await tester.pump();
      expect(logoOpacity(tester), 1);
      tickers.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(logoOpacity(tester), 1, reason: 'no replay after a resume');
      expect(logoScale(tester), 1);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('under Reduce Motion the first-run logo is at rest on its '
        'first frame', (tester) async {
      _surface(tester, const Size(390, 844));
      await tester.pumpWidget(
        _host(_list(_Service()), disableAnimations: true),
      );
      await tester.pump();
      expect(entrance(), findsOneWidget);
      expect(logoOpacity(tester), 1);
      expect(logoScale(tester), 1);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('the typing dots stand still under Reduce Motion', (
      tester,
    ) async {
      _surface(tester, const Size(390, 844));
      await tester.pumpWidget(
        _host(
          _chat(_Service(messages: _oneMessage(), typing: true)),
          disableAnimations: true,
        ),
      );
      // Would time out if the dots looped.
      await tester.pumpAndSettle();
      final dots = _typingDots(tester);
      expect(dots, hasLength(3));
      for (final dot in dots) {
        expect(dot.scale.value, 1);
      }
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('the typing dots keep their wave when tickers resume', (
      tester,
    ) async {
      _surface(tester, const Size(390, 844));
      final tickers = ValueNotifier<bool>(true);
      addTearDown(tickers.dispose);
      await tester.pumpWidget(
        _host(
          _tickerHost(
            tickers,
            _chat(_Service(messages: _oneMessage(), typing: true)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tickers.value = false;
      await tester.pump();
      for (final dot in _typingDots(tester)) {
        expect(dot.scale.value, 1, reason: 'paused dots rest at full size');
      }

      tickers.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      var dots = _typingDots(tester);
      expect(dots[0].scale.value, lessThan(1), reason: 'the first dot leads');
      expect(dots[1].scale.value, 1, reason: '180 ms behind');
      expect(dots[2].scale.value, 1, reason: '360 ms behind');
      await tester.pump(const Duration(milliseconds: 100));
      dots = _typingDots(tester);
      expect(dots[1].scale.value, lessThan(1));
      expect(dots[2].scale.value, 1);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final reduceMotion in const [false, true]) {
      testWidgets('the recorder bead rests in the brand tone, is live while '
          'recording, and swaps its glyph '
          '${reduceMotion ? 'instantly under Reduce Motion' : 'over 160 ms'}', (
        tester,
      ) async {
        _surface(tester, const Size(390, 844));
        final clock = FakeStopwatch();
        await tester.pumpWidget(
          _host(
            _chat(
              _Service(messages: _oneMessage()),
              recorderFactory: () => VoiceMomentRecorder(
                backend: FakeRecorderBackend(),
                capture: FakeAudioCapture()..result = FakeRecordedAudio(),
                clock: clock,
              ),
            ),
            disableAnimations: reduceMotion,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Record voice message'));
        await tester.pumpAndSettle();

        final bead = find.byKey(const ValueKey('voice-message-record-bead'));
        YoGradientDisc disc() => tester.widget<YoGradientDisc>(bead);
        expect(disc().tone, YoDiscTone.brand);
        expect(disc().gloss, isTrue);
        // The glyph's own switcher: the nearest one above the mic.
        final switcher = tester.widget<AnimatedSwitcher>(
          find
              .ancestor(
                of: find.descendant(
                  of: bead,
                  matching: find.byIcon(Icons.mic_rounded),
                ),
                matching: find.byType(AnimatedSwitcher),
              )
              .first,
        );
        expect(
          switcher.duration,
          reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
        );
        final title = tester.widget<Text>(
          find.byKey(const ValueKey('voice-message-recorder-title')),
        );
        expect(title.textAlign, TextAlign.center);

        await tester.tap(bead);
        await tester.pump();
        expect(disc().tone, YoDiscTone.live);
        expect(
          find.descendant(of: bead, matching: find.byIcon(Icons.stop_rounded)),
          findsOneWidget,
        );

        clock.value = const Duration(seconds: 3);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(bead);
        await tester.pumpAndSettle();
        expect(find.text('Voice message ready'), findsOneWidget);
        expect(disc().tone, YoDiscTone.brand, reason: 'the bead rests again');
        // The review state's one lift is Send; the bead rests.
        expect(disc().emphasis, YoDiscEmphasis.rest);
        final send = tester.widget<YoGradientFilledButton>(
          find.ancestor(
            of: find.text('Send voice message'),
            matching: find.byType(YoGradientFilledButton),
          ),
        );
        expect(send.emphasis, YoActionEmphasis.lifted);

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    // The bead is opaque and exactly the record button's size, so the
    // button's own theme focus side (painted UNDER its child) is covered.
    // Keyboard focus must be the bead's R14 ring, 3 px outside it, and it
    // must read: the ring pixels change by at least 3:1 from rest.
    for (final (themeName, theme) in [
      ('Dark', AppTheme.darkTheme),
      ('Pearl', AppTheme.lightTheme),
    ]) {
      testWidgets('keyboard focus on the recorder bead paints its ring '
          'outside the bead ($themeName)', (tester) async {
        _surface(tester, const Size(390, 844));
        final strategy = FocusManager.instance.highlightStrategy;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
        // Real blurred shadows, as on a device: the ring must read against
        // the bead's contact shadow as well as the sheet.
        debugDisableShadows = false;
        try {
          await tester.pumpWidget(
            _host(
              _chat(
                _Service(messages: _oneMessage()),
                recorderFactory: () => VoiceMomentRecorder(
                  backend: FakeRecorderBackend(),
                  capture: FakeAudioCapture()..result = FakeRecordedAudio(),
                  clock: FakeStopwatch(),
                ),
              ),
              theme: theme,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Record voice message'));
          await tester.pumpAndSettle();

          final bead = find.byKey(const ValueKey('voice-message-record-bead'));
          YoGradientDisc disc() => tester.widget<YoGradientDisc>(bead);
          final button = find.ancestor(
            of: bead,
            matching: find.byType(IconButton),
          );
          expect(button, findsOneWidget);
          expect(disc().focused, isFalse);
          final beadRect = tester.getRect(bead);

          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find
                .ancestor(of: bead, matching: find.byType(RepaintBoundary))
                .first,
          );
          final origin = boundary.localToGlobal(Offset.zero);
          Future<ByteData> shot() async => (await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              return await image.toByteData();
            } finally {
              image.dispose();
            }
          }))!;
          Color pixel(ByteData bytes, Offset global) {
            final x = (global.dx - origin.dx).floor();
            final y = (global.dy - origin.dy).floor();
            final i = (y * boundary.size.width.round() + x) * 4;
            return Color.fromARGB(
              bytes.getUint8(i + 3),
              bytes.getUint8(i),
              bytes.getUint8(i + 1),
              bytes.getUint8(i + 2),
            );
          }

          double contrast(Color a, Color b) {
            final la = a.computeLuminance();
            final lb = b.computeLuminance();
            return la > lb ? (la + .05) / (lb + .05) : (lb + .05) / (la + .05);
          }

          // 4 px outside the bead: the middle of the 2 px ring.
          final c = beadRect.center;
          final r = beadRect.width / 2 + 4;
          final probes = [
            Offset(c.dx - r, c.dy),
            Offset(c.dx + r - 1, c.dy),
            Offset(c.dx, c.dy - r),
            Offset(c.dx, c.dy + r - 1),
          ];
          final rest = await shot();

          Focus.of(tester.element(bead)).requestFocus();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(disc().focused, isTrue);
          // Focus moves nothing.
          expect(tester.getRect(bead), beadRect);
          final focused = await shot();

          final palette = theme.extension<AppPalette>()!;
          for (final at in probes) {
            final was = pixel(rest, at);
            final now = pixel(focused, at);
            expect(
              contrast(now, palette.focus),
              lessThan(1.1),
              reason: '$at is the focus ring, got $now',
            );
            expect(
              contrast(now, was),
              greaterThanOrEqualTo(3),
              reason: '$at: ring $now against rest $was',
            );
          }

          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(disc().focused, isFalse);
        } finally {
          debugDisableShadows = true;
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    for (final direction in TextDirection.values) {
      testWidgets('the send glyph is nudged only where it points right '
          '(${direction.name})', (tester) async {
        _surface(tester, const Size(390, 844));
        await tester.pumpWidget(
          _host(
            _chat(_Service(messages: _oneMessage())),
            textDirection: direction,
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'hello');
        await tester.pumpAndSettle();
        final disc = tester.widget<YoGradientDisc>(
          find.descendant(
            of: find.byKey(const ValueKey('send')),
            matching: find.byType(YoGradientDisc),
          ),
        );
        expect(disc.nudgePlay, direction == TextDirection.ltr);
      });
    }
  });

  group('the first-run canvas (spec §4)', () {
    Finder quietCanvas() => find.byKey(const ValueKey('messages-quiet-canvas'));

    for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
      testWidgets('the logo is the page\'s only YO: the lounge sign and the '
          'watermark are quieted (${theme.brightness.name})', (tester) async {
        _surface(tester, const Size(390, 844));
        await tester.pumpWidget(_host(_list(_Service()), theme: theme));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('messages-empty-logo')), findsOne);
        final cover = tester.widget<AnimatedOpacity>(quietCanvas());
        expect(cover.opacity, 1);
        final palette = theme.extension<AppPalette>()!;
        final paint = tester.widget<DecoratedBox>(
          find.descendant(
            of: quietCanvas(),
            matching: find.byType(DecoratedBox),
          ),
        );
        expect(
          (paint.decoration as BoxDecoration).gradient,
          palette.canvasGlow(theme.colorScheme.primary),
          reason: 'the bare radial, nothing else',
        );
        // The cover sits above the page art and below every control.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('messages-screen-background')),
            matching: quietCanvas(),
          ),
          findsOne,
        );
      });
    }

    testWidgets('the page art stays for rows, a search without a match and '
        'under high contrast', (tester) async {
      _surface(tester, const Size(390, 844));
      await tester.pumpWidget(
        _host(_list(_Service(conversations: [_conversation()]))),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(quietCanvas()).opacity, 0);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No matching chats'), findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(quietCanvas()).opacity, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_host(_list(_Service()), highContrast: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('messages-empty-logo')), findsOne);
      expect(
        tester.widget<AnimatedOpacity>(quietCanvas()).opacity,
        0,
        reason: 'high contrast draws no page art to quiet',
      );
    });
  });

  group('press feedback and emoji (R2, R15)', () {
    testWidgets(
      'rows and reaction discs ripple only on Android',
      (tester) async {
        _surface(tester, const Size(390, 844));
        final expected = defaultTargetPlatform == TargetPlatform.android
            ? InkSparkle.splashFactory
            : NoSplash.splashFactory;

        await tester.pumpWidget(
          _host(_list(_Service(conversations: [_conversation()]))),
        );
        await tester.pumpAndSettle();
        final row = tester.widget<InkWell>(
          find
              .descendant(
                of: find.byKey(
                  const ValueKey('conversation-row-$_conversationId'),
                ),
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(row.splashFactory, expected);

        await tester.pumpWidget(
          _host(_chat(_Service(messages: _oneMessage()))),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.text('hello there'));
        await tester.pumpAndSettle();
        final disc = tester.widget<InkWell>(
          find
              .ancestor(of: find.text('😂'), matching: find.byType(InkWell))
              .first,
        );
        expect(disc.splashFactory, expected);
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }),
    );

    testWidgets('reaction emoji draw in the colour-emoji family, counts in '
        'the app type', (tester) async {
      _surface(tester, const Size(390, 844));
      await tester.pumpWidget(
        _host(_chat(_Service(messages: _oneMessage({_me: '❤️', _them: '❤️'})))),
      );
      await tester.pumpAndSettle();
      final pill = tester.widget<Text>(find.text('❤️ 2'));
      final spans = (pill.textSpan! as TextSpan).children!.cast<TextSpan>();
      final heart = spans.firstWhere((span) => span.text == '❤️');
      expect(heart.style?.fontFamily, yoEmojiFontFamily);
      final count = spans.firstWhere((span) => span.text == ' 2');
      expect(count.style?.fontFamily, isNull);

      await tester.longPress(find.text('hello there'));
      await tester.pumpAndSettle();
      final disc = tester.widget<Text>(find.text('❤️').last);
      expect(disc.style?.fontFamily, yoEmojiFontFamily);
      expect(disc.textScaler, TextScaler.noScaling);
    });
  });
}
