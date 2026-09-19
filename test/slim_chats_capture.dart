// Developer-only visual capture for the Slim redesign, phase 3 (Czaty):
// the Chats list (`MessagesScreen`) and one populated conversation
// (`ChatScreen`), at 390 and 1440 px, Dark and Pearl, Polish, text 1.0.
//
// Technique of `test/moderation_screenshot.dart`: real widgets, fixtures
// through the screens' own constructor seams, an exact viewport and the real
// product fonts (Inter + Material Icons), so the "look at it" step proves
// something. There is no Firebase app behind it: the message and friend
// services are the real classes over a fake Firestore with only the streams
// the two screens read scripted.
//
// It is NOT a test and deliberately does not end in `_test.dart`, so the
// regular suite never writes artifacts. Run it explicitly:
//
//   flutter test test/slim_chats_capture.dart
//
// PNGs land OUTSIDE git, in the evidence folder named below, or in the
// directory given by the SLIM_FRAMES_DIR environment variable.

import 'dart:io';
import 'dart:ui' as ui;

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

const String _me = 'me-uid';
const String _defaultOut =
    r'C:\Users\mfvon\Documents\GitHub\yovoice-evidence\2026-09-19\slim-p3-frames\after';

final _captureKey = GlobalKey();

String _outDir() {
  final configured = Platform.environment['SLIM_FRAMES_DIR'];
  return configured == null || configured.trim().isEmpty
      ? _defaultOut
      : configured.trim();
}

String _resolveMaterialFontRoot() {
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null) {
    final configured = '$configuredRoot/bin/cache/artifacts/material_fonts';
    if (File('$configured/MaterialIcons-Regular.otf').existsSync()) {
      return configured;
    }
  }
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final candidate = '${directory.path}/bin/cache/artifacts/material_fonts';
    if (File('$candidate/MaterialIcons-Regular.otf').existsSync()) {
      return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate Flutter material fonts.');
}

Future<ByteData> _read(String path) async {
  final bytes = Uint8List.fromList(File(path).readAsBytesSync());
  return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
}

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(_read('assets/fonts/InterVariable.ttf'))
    ..addFont(_read('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(_read('${_resolveMaterialFontRoot()}/MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> _capturePng(
  WidgetTester tester,
  String filename, {
  required double pixelRatio,
}) async {
  await tester.runAsync(() async {
    final boundary =
        _captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    // Prime the glyph atlases; a headless engine can omit a glyph on the
    // very first raster pass.
    final warmup = await boundary.toImage(pixelRatio: pixelRatio);
    warmup.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${_outDir()}/$filename.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

/// Bounded settle: enough frames for the streams and the identity badges to
/// land, without hanging on an indefinite animation.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

// ---------------------------------------------------------------- fixtures

class _Person {
  const _Person(this.id, this.name, {this.online = false, this.availability});

  final String id;
  final String name;
  final bool online;
  final String? availability;
}

const _people = <_Person>[
  _Person('ola', 'Ola Nowak', online: true, availability: 'available'),
  _Person('kuba', 'Kuba Wiśniewski', online: true, availability: 'away'),
  _Person('marta', 'Marta Zielińska', online: true, availability: 'busy'),
  _Person('tomek', 'Tomek Kowalczyk'),
  _Person('ania', 'Ania Lewandowska', online: true),
  _Person('piotr', 'Piotr Wójcik'),
  _Person('zosia', 'Zosia Kamińska'),
];

_Person _person(String id) => _people.firstWhere((p) => p.id == id);

Conversation _conversation(
  String otherId, {
  required String lastMessage,
  required Duration ago,
  MessageType type = MessageType.text,
  int unread = 0,
  bool muted = false,
  bool fromMe = false,
}) {
  final other = _person(otherId);
  final at = DateTime.now().subtract(ago);
  return Conversation(
    id: '${_me}_$otherId',
    participantIds: [_me, otherId],
    participantNames: {_me: 'Kamil', otherId: other.name},
    participantEmails: {_me: '', otherId: ''},
    participantPhotoUrls: {_me: '', otherId: ''},
    unreadCounts: {_me: unread, otherId: 0},
    archivedBy: const <String>[],
    mutedBy: muted ? const [_me] : const <String>[],
    lastMessage: lastMessage,
    lastMessageType: type,
    lastMessageSenderId: fromMe ? _me : otherId,
    updatedAt: at,
    createdAt: at.subtract(const Duration(days: 30)),
  );
}

List<Conversation> _conversations() => [
  _conversation(
    'ola',
    lastMessage: 'To co, widzimy się dziś na serwerze o 20?',
    ago: const Duration(minutes: 3),
    unread: 2,
  ),
  _conversation(
    'kuba',
    lastMessage: 'voice',
    type: MessageType.voice,
    ago: const Duration(minutes: 42),
    unread: 1,
  ),
  _conversation(
    'marta',
    lastMessage: 'Dzięki, odsłucham wieczorem.',
    ago: const Duration(hours: 3),
    fromMe: true,
  ),
  _conversation(
    'tomek',
    lastMessage: 'image',
    type: MessageType.image,
    ago: const Duration(hours: 20),
    muted: true,
  ),
  _conversation(
    'ania',
    lastMessage: 'Wrzuciłam nowy Moment, daj znać co myślisz',
    ago: const Duration(days: 2),
    unread: 14,
  ),
  _conversation(
    'piotr',
    lastMessage: 'Jasne, podeślę link do kanału jutro rano.',
    ago: const Duration(days: 4),
    fromMe: true,
  ),
  _conversation(
    'zosia',
    lastMessage: 'Haha, to było świetne!',
    ago: const Duration(days: 12),
  ),
];

List<FriendUser> _friends() => [
  for (final person in _people)
    FriendUser(
      id: person.id,
      displayName: person.name,
      email: '',
      photoUrl: null,
      isOnline: person.online,
      lastSeen: person.online
          ? null
          : DateTime.now().subtract(const Duration(hours: 5)),
      availability: person.availability,
    ),
];

List<Message> _thread() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 9, 12);
  final yesterday = today.subtract(const Duration(days: 1));
  const conversationId = '${_me}_ola';
  Message message(
    String id,
    String sender,
    String content,
    DateTime at, {
    bool read = true,
    Map<String, String> reactions = const <String, String>{},
    DateTime? editedAt,
    String? replyTo,
  }) => Message(
    id: id,
    conversationId: conversationId,
    senderId: sender,
    type: MessageType.text,
    content: content,
    sentAt: at,
    readBy: read ? const [_me, 'ola'] : const [_me],
    reactions: reactions,
    editedAt: editedAt,
    replyToMessageId: replyTo == null ? null : 'm-reply',
    replyToSenderId: replyTo == null ? null : 'ola',
    replyToContent: replyTo,
  );

  // Newest first, the order the service streams and the reversed list reads.
  return [
    message(
      'm9',
      'ola',
      'To co, widzimy się dziś na serwerze o 20?',
      today.add(const Duration(hours: 3, minutes: 5)),
    ),
    message(
      'm8',
      _me,
      'Jasne, będę trochę wcześniej, żeby ustawić kanał sceny.',
      today.add(const Duration(hours: 2, minutes: 51)),
      read: false,
    ),
    message(
      'm7',
      _me,
      'Odsłuchałem Twój Moment, świetny klimat!',
      today.add(const Duration(hours: 2, minutes: 50)),
      replyTo: 'Wrzuciłam nowy Moment z próby.',
      reactions: const {'ola': '❤️'},
    ),
    message(
      'm6',
      'ola',
      'Wrzuciłam nowy Moment z próby.',
      today.add(const Duration(minutes: 40)),
    ),
    message(
      'm5',
      'ola',
      'Hej! Masz chwilę po południu?',
      today,
      editedAt: today.add(const Duration(minutes: 2)),
    ),
    message(
      'm4',
      _me,
      'Dobranoc!',
      yesterday.add(const Duration(hours: 13, minutes: 30)),
    ),
    message(
      'm3',
      'ola',
      'Super, to do jutra. Przygotuję listę utworów na podcast.',
      yesterday.add(const Duration(hours: 13, minutes: 28)),
      reactions: const {_me: '❤️'},
    ),
    message(
      'm2',
      _me,
      'Zróbmy nagranie w piątek, wszyscy mają wtedy czas.',
      yesterday.add(const Duration(hours: 13, minutes: 20)),
    ),
    message(
      'm1',
      'ola',
      'Kiedy nagrywamy kolejny odcinek?',
      yesterday.add(const Duration(hours: 13, minutes: 12)),
    ),
  ];
}

class _FixtureFriendService extends FriendService {
  _FixtureFriendService()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      );

  @override
  Stream<List<FriendUser>> watchFriends() =>
      Stream<List<FriendUser>>.value(_friends());
}

class _FixtureMessageService extends MessageService {
  _FixtureMessageService()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      );

  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) => Stream<List<Conversation>>.value(_conversations());

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream<List<Message>>.value(_thread());

  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => Stream<bool>.value(false);

  @override
  Stream<ChatPresence> watchUserPresence(String userId) {
    final person = _people.where((p) => p.id == userId).firstOrNull;
    return Stream<ChatPresence>.value(
      ChatPresence(
        isOnline: person?.online ?? false,
        lastSeen: person?.online == true
            ? null
            : DateTime.now().subtract(const Duration(hours: 5)),
        availability: person?.availability,
      ),
    );
  }

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}
}

// ------------------------------------------------------------------- host

Widget _host({required ThemeData theme, required Widget child}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('pl'),
  theme: theme,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(_textScale)),
      child: RepaintBoundary(key: _captureKey, child: child),
    ),
  ),
);

/// 1.0 by default (the frame set of record); SLIM_TEXT_SCALE=2 renders the
/// same fixtures at 200 % text for a large-text check.
final double _textScale =
    double.tryParse(Platform.environment['SLIM_TEXT_SCALE'] ?? '') ?? 1.0;

void main() {
  late PublicIdentityRepository originalIdentityRepository;

  setUpAll(_loadFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    // The chat header resolves identity badges through the shared singleton;
    // a scripted fetcher keeps it deterministic without a Firebase app.
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

  for (final (width, height) in const <(double, double)>[
    (390, 844),
    (1440, 900),
  ]) {
    for (final (themeName, theme) in <(String, ThemeData)>[
      ('dark', AppTheme.darkTheme),
      ('pearl', AppTheme.lightTheme),
    ]) {
      final scaleTag = (_textScale * 100).round();
      final suffix = '${width.toInt()}_${themeName}_pl_${scaleTag}_populated';
      final pixelRatio = width < 600 ? 2.0 : 1.0;

      testWidgets('chats $suffix', (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(
            theme: theme,
            child: MessagesScreen(
              messageService: _FixtureMessageService(),
              friendService: _FixtureFriendService(),
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: _me),
              ),
            ),
          ),
        );
        await _settle(tester);
        await _capturePng(tester, 'chats_$suffix', pixelRatio: pixelRatio);
        // Geometry next to the pixels, so the numbers in the report are
        // measured rather than assumed.
        for (final id in const ['ola', 'marta']) {
          final row = find.byKey(ValueKey('conversation-row-${_me}_$id'));
          if (row.evaluate().isEmpty) continue; // lazily off screen
          // ignore: avoid_print
          print('chats $suffix row $id: ${tester.getSize(row)}');
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('conversation $suffix', (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(
            theme: theme,
            child: ChatScreen(
              conversationId: '${_me}_ola',
              otherUserId: 'ola',
              otherDisplayName: 'Ola Nowak',
              otherEmail: '',
              otherPhotoUrl: '',
              messageService: _FixtureMessageService(),
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: _me),
              ),
            ),
          ),
        );
        await _settle(tester);
        await _capturePng(
          tester,
          'conversation_$suffix',
          pixelRatio: pixelRatio,
        );
        for (final key in const [
          'chat-header',
          'chat-composer',
          'emoji-picker-toggle',
          'voice',
        ]) {
          // ignore: avoid_print
          print(
            'conversation $suffix $key: '
            '${tester.getSize(find.byKey(ValueKey(key)))}',
          );
        }
        // ignore: avoid_print
        print(
          'conversation $suffix field: ${tester.getSize(find.byType(TextField))}',
        );
        expect(tester.takeException(), isNull);
        // Dispose the route inside the test so its timers and subscriptions
        // are torn down before the binding checks for pending work.
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
      });
    }
  }
}
