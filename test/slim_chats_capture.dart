// Developer-only visual capture for Czaty: the Chats list (`MessagesScreen`)
// and a conversation (`ChatScreen`), Polish, at 390, 768 and 1440 px, Dark
// and Pearl, 100 % and 200 % text, plus high-contrast spot frames and the
// states the refine-look Chats batch (B7) changes:
//
//   * list  — populated (unread + read rows, voice / photo / video previews,
//             muted), the empty inbox (first-run logo), a search with no
//             match, an archive with nothing in it;
//   * thread — populated (incoming + outgoing bubbles, grouped runs whose
//             first time row is left to the next bubble, a reply with a
//             reaction, incoming and outgoing voice, a bundled GIF, the date
//             pill), queued + failed sends with the typing bubble, the
//             long-press sheet, the composer with a draft (send disc), the
//             voice-message sheet idle, recording, review and sending, a
//             thread carrying room-link cards, the header's archive-busy
//             spinner, and an empty thread;
//   * sheets — New message (populated, empty, a search) and a row's
//             conversation actions ("…");
//   * checks — RTL spot frames (`-rtl`, Polish copy laid out right to
//             left), keyboard focus on a row and on each disc family
//             (`focus-*`) and pointer hover on a row at 1440 (`hover-row`).
//
// Technique of `test/moderation_screenshot.dart`: real widgets, fixtures
// through the screens' own constructor seams, an exact viewport and the real
// product fonts (Inter + Material Icons + the host's colour-emoji font), so
// the "look at it" step proves something. There is no Firebase app behind
// it: the message and friend services are the real classes over a fake
// Firestore with only the streams the two screens read scripted.
//
// It is NOT a test and deliberately does not end in `_test.dart`, so the
// regular suite never writes artifacts. Run it explicitly:
//
//   SLIM_FRAMES_DIR=<dir> flutter test test/slim_chats_capture.dart
//
// PNGs land OUTSIDE git, in the evidence folder named below, or in the
// directory given by the SLIM_FRAMES_DIR environment variable. Frames are
// named `<screen>_<width>_<dark|pearl>_pl_<text>_<state>[-hc][-rtl].png`.
// SLIM_TEXT_SCALE=1 (or 2) limits the run to one text size; `--name` picks
// states (for example `--name "thread 390"`).

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/gestures.dart';
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
import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';
import 'package:yovoice/features/messages/presentation/widgets/room_link_message_card.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'support/material_icons_font.dart';
import 'voice_moment_test_doubles.dart';

const String _me = 'me-uid';
const String _defaultOut =
    r'C:\Users\mfvon\Documents\GitHub\yovoice-evidence\2026-09-19\slim-p3-frames\after';

/// The host's colour-emoji font (on a Linux capture host, a link to Noto
/// Color Emoji). Without it every emoji is a tofu box.
const _emojiFont = '/System/Library/Fonts/Apple Color Emoji.ttc';

final _captureKey = GlobalKey();

String _outDir() {
  final configured = Platform.environment['SLIM_FRAMES_DIR'];
  return configured == null || configured.trim().isEmpty
      ? _defaultOut
      : configured.trim();
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
  await loadMaterialIconsFont();
  final emoji = File(_emojiFont);
  if (emoji.existsSync()) {
    final bytes = ByteData.sublistView(emoji.readAsBytesSync());
    // The test renderer has no system fallback; register the host's emoji
    // font under its own name and under the generic family that closes the
    // app's own fallback list, exactly as a device resolves it.
    for (final family in const ['Apple Color Emoji', 'sans-serif']) {
      final loader = FontLoader(family)..addFont(Future.value(bytes));
      await loader.load();
    }
  } else {
    // ignore: avoid_print
    print('emoji font NOT available on this host: emoji may show tofu');
  }
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
/// land, without hanging on an indefinite animation (the typing dots, a GIF).
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
    lastMessage: 'video',
    type: MessageType.video,
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

const _gifAsset = GifAsset(
  provider: 'yovoice',
  id: 'yoHey001',
  title: 'Hej',
  rating: 'g',
  previewUrl: 'asset://yovoice/gifs/yoHey001.gif',
  url: 'asset://yovoice/gifs/yoHey001.gif',
  width: 320,
  height: 200,
);

List<Message> _thread() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 9, 12, 5);
  final yesterday = DateTime(now.year, now.month, now.day - 1, 13, 12);
  const conversationId = '${_me}_ola';
  Message message(
    String id,
    String sender,
    String content,
    DateTime at, {
    MessageType type = MessageType.text,
    bool read = true,
    Map<String, String> reactions = const <String, String>{},
    DateTime? editedAt,
    String? replyTo,
    String? mediaUrl,
    int? durationSeconds,
    GifAsset? gif,
  }) => Message(
    id: id,
    conversationId: conversationId,
    senderId: sender,
    type: type,
    content: content,
    sentAt: at,
    readBy: read ? const [_me, 'ola'] : const [_me],
    reactions: reactions,
    editedAt: editedAt,
    replyToMessageId: replyTo == null ? null : 'm-reply',
    replyToSenderId: replyTo == null ? null : 'ola',
    replyToContent: replyTo,
    mediaUrl: mediaUrl,
    durationSeconds: durationSeconds,
    gif: gif,
  );

  // Newest first, the order the service streams and the reversed list reads.
  return [
    message(
      'm14',
      'ola',
      'To co, widzimy się dziś na serwerze o 20?',
      today.add(const Duration(hours: 3, minutes: 5)),
    ),
    message(
      'm13',
      _me,
      'voice',
      today.add(const Duration(hours: 2, minutes: 53)),
      type: MessageType.voice,
      mediaUrl: 'fixture://m13',
      durationSeconds: 18,
    ),
    // A grouped outgoing run: the same minute, both unread, so the first
    // leaves its time row to the second.
    message(
      'm12',
      _me,
      'Do zobaczenia 👋',
      today.add(const Duration(hours: 2, minutes: 51, seconds: 40)),
      read: false,
    ),
    message(
      'm11',
      _me,
      'Jasne, będę trochę wcześniej, żeby ustawić kanał sceny.',
      today.add(const Duration(hours: 2, minutes: 51, seconds: 10)),
      read: false,
    ),
    message(
      'm10',
      _me,
      'Odsłuchałem Twój Moment, świetny klimat!',
      today.add(const Duration(hours: 2, minutes: 50)),
      replyTo: 'Wrzuciłam nowy Moment z próby.',
      reactions: const {'ola': '❤️'},
    ),
    message(
      'm9',
      'ola',
      'gif',
      today.add(const Duration(minutes: 41)),
      type: MessageType.gif,
      gif: _gifAsset,
    ),
    message(
      'm8',
      'ola',
      'Wrzuciłam nowy Moment z próby.',
      today.add(const Duration(minutes: 40)),
    ),
    // A grouped incoming run: 09:12 twice (the first leaves its row), then a
    // voice message at 09:13 that still joins the run but keeps its time.
    message(
      'm7',
      'ola',
      'voice',
      today.add(const Duration(minutes: 1, seconds: 5)),
      type: MessageType.voice,
      mediaUrl: 'fixture://m7',
      durationSeconds: 42,
    ),
    message(
      'm6',
      'ola',
      'Masz chwilę po południu?',
      today.add(const Duration(seconds: 30)),
    ),
    message('m5', 'ola', 'Hej!', today),
    message(
      'm4',
      _me,
      'Dobranoc!',
      yesterday.add(const Duration(minutes: 18)),
      editedAt: yesterday.add(const Duration(minutes: 19)),
    ),
    message(
      'm3',
      'ola',
      'Super, to do jutra. Przygotuję listę utworów na podcast.',
      yesterday.add(const Duration(minutes: 16)),
      reactions: const {_me: '❤️'},
    ),
    message(
      'm2',
      _me,
      'Zróbmy nagranie w piątek, wszyscy mają wtedy czas.',
      yesterday.add(const Duration(minutes: 8)),
    ),
    message('m1', 'ola', 'Kiedy nagrywamy kolejny odcinek?', yesterday),
  ];
}

/// A stream on which every listener receives [value]. The list and the New
/// message sheet listen to the same stream instance, exactly as in
/// production, where both services return multi-listener streams (see
/// `FriendService.watchFriends`).
Stream<T> _replay<T>(T value) => Stream<T>.multi((controller) {
  controller.add(value);
  unawaited(controller.close());
});

/// A room behind the invitation links in [_roomLinkThread].
VoiceRoom _linkedRoom() => VoiceRoom(
  id: 'room-1',
  hostId: 'ola',
  hostName: 'Ola Nowak',
  hostPhotoUrl: null,
  name: 'Wieczór podcastowy',
  description: '',
  category: 'talk',
  visibility: 'public',
  language: 'Polish',
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
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 1),
  experience: 'community',
);

/// An incoming and an outgoing invitation, so the card shows on the themed
/// surface and on the brand gradient.
List<Message> _roomLinkThread() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 18, 4);
  const conversationId = '${_me}_ola';
  Message text(String id, String sender, String content, DateTime at) =>
      Message(
        id: id,
        conversationId: conversationId,
        senderId: sender,
        type: MessageType.text,
        content: content,
        sentAt: at,
        readBy: const [_me, 'ola'],
        reactions: const <String, String>{},
      );
  return [
    text(
      'l3',
      _me,
      'Jasne, wchodzę: https://yovoice.app/?room=room-1',
      today.add(const Duration(minutes: 3)),
    ),
    text(
      'l2',
      'ola',
      'Dołączysz? https://yovoice.app/?room=room-1',
      today.add(const Duration(minutes: 1)),
    ),
    text('l1', 'ola', 'Zaczynamy za 5 minut!', today),
  ];
}

class _FixtureFriendService extends FriendService {
  _FixtureFriendService({this.friends = true})
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      );

  final bool friends;

  @override
  Stream<List<FriendUser>> watchFriends() =>
      _replay<List<FriendUser>>(friends ? _friends() : const []);
}

class _FixtureMessageService extends MessageService {
  _FixtureMessageService({
    this.conversations,
    this.messages,
    this.typing = false,
    super.outbox,
  }) : super(
         firestore: FakeFirebaseFirestore(),
         auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
       );

  final List<Conversation>? conversations;
  final List<Message>? messages;
  final bool typing;

  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) => _replay<List<Conversation>>(conversations ?? _conversations());

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream<List<Message>>.value(messages ?? _thread());

  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => Stream<bool>.value(typing);

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

  /// Held open, so the recorder sheet's Send shows its busy state.
  @override
  Future<String> enqueueVoiceMessage({
    required String conversationId,
    required RecordedAudio audio,
    required int durationSeconds,
  }) => Completer<String>().future;

  /// Held open, so the header shows its archive-busy spinner.
  @override
  Future<void> archiveConversation(String conversationId) =>
      Completer<void>().future;
}

// ------------------------------------------------------------------- host

Widget _host({
  required ThemeData theme,
  required double textScale,
  required bool highContrast,
  required Widget child,
  TextDirection? textDirection,
}) => MaterialApp(
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
  // Above the Navigator, so the modal sheets are in the frame too.
  builder: (context, navigator) {
    final Widget framed = MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        highContrast: highContrast,
      ),
      child: RepaintBoundary(key: _captureKey, child: navigator!),
    );
    // RTL spot frames keep the Polish copy (the host has no Arabic font)
    // and lay it out right to left, which is what mirroring needs to show.
    return textDirection == null
        ? framed
        : Directionality(textDirection: textDirection, child: framed);
  },
  home: child,
);

/// Both text sizes by default; SLIM_TEXT_SCALE=1 or 2 renders one.
List<double> _textScales() {
  final configured = double.tryParse(
    Platform.environment['SLIM_TEXT_SCALE'] ?? '',
  );
  return configured == null ? const [1.0, 2.0] : [configured];
}

double _height(double width) => switch (width) {
  320 => 640,
  390 => 844,
  768 => 1024,
  _ => 900,
};

typedef _Theme = ({String name, ThemeData theme});

final _Theme _dark = (name: 'dark', theme: AppTheme.darkTheme);
final _Theme _pearl = (name: 'pearl', theme: AppTheme.lightTheme);

/// One frame of the matrix.
class _Frame {
  const _Frame(
    this.width,
    this.theme,
    this.textScale, {
    this.hc = false,
    this.rtl = false,
  });

  final double width;
  final _Theme theme;
  final double textScale;
  final bool hc;
  final bool rtl;

  String name(String screen, String state) =>
      '${screen}_${width.toInt()}_${theme.name}_pl_'
      '${(textScale * 100).round()}_$state${hc ? '-hc' : ''}'
      '${rtl ? '-rtl' : ''}';
}

/// Every width × theme × text size.
List<_Frame> _full() => [
  for (final width in const [390.0, 768.0, 1440.0])
    for (final theme in [_dark, _pearl])
      for (final scale in _textScales()) _Frame(width, theme, scale),
];

/// A state's spot frames: 390 in both themes at every text size, one frame
/// at each wider width, and (optionally) the high-contrast pair.
List<_Frame> _spots({bool hc = false}) => [
  for (final theme in [_dark, _pearl])
    for (final scale in _textScales()) _Frame(390, theme, scale),
  _Frame(768, _pearl, 1),
  _Frame(1440, _dark, 1),
  if (hc) _Frame(390, _dark, 1, hc: true),
  if (hc) _Frame(390, _pearl, 1, hc: true),
];

Future<void> _pumpScreen(
  WidgetTester tester,
  _Frame frame,
  Widget screen,
) async {
  // The real device pixel ratio of the capture, so images (avatars, the
  // logo, a GIF) decode at the density they are drawn at.
  final ratio = _pixelRatio(frame);
  tester.view.physicalSize = Size(frame.width, _height(frame.width)) * ratio;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _host(
      theme: frame.theme.theme,
      textScale: frame.textScale,
      highContrast: frame.hc,
      textDirection: frame.rtl ? TextDirection.rtl : null,
      child: screen,
    ),
  );
  await _settle(tester);
  await _warmImages(tester);
}

double _pixelRatio(_Frame frame) => frame.width < 600 ? 2.0 : 1.0;

MessagesScreen _list(_FixtureMessageService service, {bool friends = true}) =>
    MessagesScreen(
      messageService: service,
      friendService: _FixtureFriendService(friends: friends),
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      // The shell always wires "Dodaj znajomego"; without a callback the tile
      // is disabled and cannot take focus.
      onFindFriends: () {},
    );

ChatScreen _chat(
  _FixtureMessageService service, {
  DirectMessageVoiceRecorderFactory? recorderFactory,
}) => ChatScreen(
  conversationId: '${_me}_ola',
  otherUserId: 'ola',
  otherDisplayName: 'Ola Nowak',
  otherEmail: '',
  otherPhotoUrl: '',
  messageService: service,
  auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
  voiceRecorderFactory: recorderFactory,
);

/// Lets images decode (the logo, the bundled GIF) so a frame shows the
/// picture, not a placeholder. Decoding needs real time, and a multi-frame
/// image only emits its first frame on a scheduled frame, so real time
/// alternates with pumps; awaiting `precacheImage` inside `runAsync` would
/// never finish for the GIF.
Future<void> _warmImages(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Runs a thread capture while ignoring one kind of environment noise: each
/// voice bubble builds a real `AudioPlayer` whose per-player event channel
/// (`xyz.luan/audioplayers/events/<id>`) has no host here, and its listen
/// fails once real time passes. That is not a rendering failure; every other
/// error still fails the capture.
Future<void> _ignoringAudioPluginNoise(Future<void> Function() body) async {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    final error = details.exception;
    if (error is MissingPluginException &&
        '$error'.contains('xyz.luan/audioplayers')) {
      return;
    }
    original?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
}

/// Tears the route down inside the test so its timers and subscriptions end
/// before the binding checks for pending work.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
}

/// Moves keyboard focus to the control that owns [inside] (its nearest
/// focus node) with the keyboard's highlight mode, as a Tab would.
Future<void> _focusOn(WidgetTester tester, Finder inside) async {
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  Focus.of(tester.element(inside.first)).requestFocus();
  await _settle(tester);
}

void main() {
  late PublicIdentityRepository originalIdentityRepository;

  // The voice bubbles build a real `AudioPlayer`; the plugin has no host
  // here, so its channels answer with nothing (the technique of
  // test/report_visual_qa.dart).
  const audioChannels = <MethodChannel>[
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
    MethodChannel('xyz.luan/audioplayers.global/events'),
  ];

  setUpAll(() async {
    await _loadFonts();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in audioChannels) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in audioChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

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
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  // ------------------------------------------------------------- the list

  for (final frame in [
    ..._full(),
    _Frame(390, _dark, 1, hc: true),
    _Frame(390, _pearl, 1, hc: true),
  ]) {
    final name = frame.name('chats', 'populated');
    testWidgets('list ${frame.width.toInt()} $name', (tester) async {
      await _pumpScreen(tester, frame, _list(_FixtureMessageService()));
      await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
      for (final id in const ['ola', 'marta']) {
        final row = find.byKey(ValueKey('conversation-row-${_me}_$id'));
        if (row.evaluate().isEmpty) continue; // lazily off screen
        // ignore: avoid_print
        print('$name row $id: ${tester.getSize(row)}');
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final frame in [
    ..._full(),
    _Frame(390, _dark, 1, hc: true),
    _Frame(390, _pearl, 1, hc: true),
  ]) {
    final name = frame.name('chats', 'empty');
    testWidgets('list ${frame.width.toInt()} $name', (tester) async {
      await _pumpScreen(
        tester,
        frame,
        _list(
          _FixtureMessageService(conversations: const <Conversation>[]),
          friends: false,
        ),
      );
      await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
      expect(tester.takeException(), isNull);
    });
  }

  for (final frame in [
    _Frame(390, _dark, 1),
    _Frame(390, _pearl, 1),
    _Frame(390, _dark, 2),
  ]) {
    final name = frame.name('chats', 'search-empty');
    testWidgets('list ${frame.width.toInt()} $name', (tester) async {
      await _pumpScreen(tester, frame, _list(_FixtureMessageService()));
      await tester.enterText(find.byType(TextField), 'zzz');
      await _settle(tester);
      await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
      expect(tester.takeException(), isNull);
    });
  }

  for (final frame in [_Frame(390, _dark, 1), _Frame(390, _pearl, 1)]) {
    final name = frame.name('chats', 'archived-empty');
    testWidgets('list ${frame.width.toInt()} $name', (tester) async {
      await _pumpScreen(tester, frame, _list(_FixtureMessageService()));
      await tester.tap(find.byTooltip('Pokaż zarchiwizowane rozmowy'));
      await _settle(tester);
      await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
      expect(tester.takeException(), isNull);
    });
  }

  // The New message sheet: populated (recent chats + friends), empty (no
  // friends, no chats) and a search.
  for (final (frame, state) in [
    for (final frame in _spots(hc: true)) (frame, 'new-message'),
    (_Frame(390, _dark, 1), 'new-message-empty'),
    (_Frame(390, _pearl, 1), 'new-message-empty'),
    (_Frame(390, _dark, 2), 'new-message-empty'),
    (_Frame(390, _pearl, 2), 'new-message-empty'),
    (_Frame(390, _dark, 1), 'new-message-search'),
    (_Frame(390, _pearl, 1), 'new-message-search'),
    (_Frame(390, _dark, 2), 'new-message-search'),
  ]) {
    final name = frame.name('chats', state);
    testWidgets('sheet ${frame.width.toInt()} $name', (tester) async {
      final empty = state == 'new-message-empty';
      await _pumpScreen(
        tester,
        frame,
        _list(
          _FixtureMessageService(
            conversations: empty ? const <Conversation>[] : null,
          ),
          friends: !empty,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('messages-compose')));
      await _settle(tester);
      if (state == 'new-message-search') {
        await tester.enterText(find.byType(TextField).last, 'ma');
        await _settle(tester);
      }
      await _warmImages(tester);
      await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
      expect(tester.takeException(), isNull);
    });
  }

  // A row's "…" sheet: mute, archive, delete.
  for (final frame in _spots(hc: true)) {
    final name = frame.name('chats', 'actions-sheet');
    testWidgets('sheet ${frame.width.toInt()} $name', (tester) async {
      await _pumpScreen(tester, frame, _list(_FixtureMessageService()));
      await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
      await _settle(tester);
      await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
      expect(tester.takeException(), isNull);
    });
  }

  // RTL spot frames of the list.
  for (final frame in [
    _Frame(390, _dark, 1, rtl: true),
    _Frame(390, _pearl, 1, rtl: true),
  ]) {
    final name = frame.name('chats', 'populated');
    testWidgets('list ${frame.width.toInt()} $name', (tester) async {
      await _pumpScreen(tester, frame, _list(_FixtureMessageService()));
      await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
      expect(tester.takeException(), isNull);
    });
  }

  // Keyboard focus on a row, the compose disc and a rail disc.
  for (final frame in [_Frame(390, _dark, 1), _Frame(390, _pearl, 1)]) {
    for (final (state, target) in <(String, Finder Function())>[
      (
        'focus-row',
        () => find.descendant(
          of: find.byKey(const ValueKey('conversation-row-${_me}_ola')),
          matching: find.byType(Text),
        ),
      ),
      (
        'focus-compose',
        () => find.descendant(
          of: find.byKey(const ValueKey('messages-compose')),
          matching: find.byType(Icon),
        ),
      ),
      (
        'focus-rail',
        () => find.descendant(
          of: find.byKey(const ValueKey('messages-add-friend')),
          matching: find.byType(Icon),
        ),
      ),
    ]) {
      final name = frame.name('chats', state);
      testWidgets('list ${frame.width.toInt()} $name', (tester) async {
        await _pumpScreen(tester, frame, _list(_FixtureMessageService()));
        await _focusOn(tester, target());
        await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
        expect(tester.takeException(), isNull);
      });
    }
  }

  // Pointer hover on a row at 1440.
  for (final frame in [_Frame(1440, _dark, 1), _Frame(1440, _pearl, 1)]) {
    final name = frame.name('chats', 'hover-row');
    testWidgets('list ${frame.width.toInt()} $name', (tester) async {
      await _pumpScreen(tester, frame, _list(_FixtureMessageService()));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('conversation-row-${_me}_ola')),
        ),
      );
      await _settle(tester);
      await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
      expect(tester.takeException(), isNull);
    });
  }

  // ----------------------------------------------------------- the thread

  for (final frame in [
    ..._full(),
    _Frame(390, _dark, 1, hc: true),
    _Frame(390, _pearl, 1, hc: true),
    // The composer's placeholder on the narrowest phone at 200 %.
    _Frame(320, _dark, 2),
    _Frame(320, _pearl, 2),
    _Frame(390, _dark, 1, rtl: true),
    _Frame(390, _pearl, 1, rtl: true),
  ]) {
    final name = frame.name('conversation', 'populated');
    testWidgets('thread ${frame.width.toInt()} $name', (tester) async {
      await _ignoringAudioPluginNoise(() async {
        await _pumpScreen(tester, frame, _chat(_FixtureMessageService()));
        await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
        for (final key in const ['chat-header', 'chat-composer', 'voice']) {
          // ignore: avoid_print
          print('$name $key: ${tester.getSize(find.byKey(ValueKey(key)))}');
        }
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }

  for (final frame in _spots(hc: true)) {
    final name = frame.name('conversation', 'queued');
    testWidgets('thread ${frame.width.toInt()} $name', (tester) async {
      await _ignoringAudioPluginNoise(() async {
        final outbox = MessageOutbox(storageKey: null, ownerId: _me);
        await tester.runAsync(() async {
          await outbox.enqueue(
            conversationId: '${_me}_ola',
            recipientId: 'ola',
            text: 'Wysyłam link do kanału za minutę.',
          );
          final failed = await outbox.enqueue(
            conversationId: '${_me}_ola',
            recipientId: 'ola',
            text: 'Ta wiadomość nie przeszła.',
          );
          await outbox.markFailed(failed.id, 'network unavailable');
        });
        await _pumpScreen(
          tester,
          frame,
          _chat(_FixtureMessageService(typing: true, outbox: outbox)),
        );
        await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }

  for (final frame in [
    for (final theme in [_dark, _pearl])
      for (final scale in _textScales()) _Frame(390, theme, scale),
    _Frame(320, _dark, 2),
    _Frame(320, _pearl, 2),
    _Frame(768, _dark, 2),
    _Frame(1440, _dark, 1),
    _Frame(390, _pearl, 1, hc: true),
  ]) {
    final name = frame.name('conversation', 'sheet');
    testWidgets('thread ${frame.width.toInt()} $name', (tester) async {
      await _ignoringAudioPluginNoise(() async {
        await _pumpScreen(tester, frame, _chat(_FixtureMessageService()));
        await tester.longPress(
          find.text('To co, widzimy się dziś na serwerze o 20?'),
        );
        await _settle(tester);
        await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }

  for (final frame in [
    _Frame(390, _dark, 1),
    _Frame(390, _pearl, 1),
    _Frame(390, _dark, 2),
    _Frame(1440, _pearl, 1),
  ]) {
    final name = frame.name('conversation', 'composer');
    testWidgets('thread ${frame.width.toInt()} $name', (tester) async {
      await _ignoringAudioPluginNoise(() async {
        await _pumpScreen(tester, frame, _chat(_FixtureMessageService()));
        await tester.enterText(find.byType(TextField), 'Będę o 19:50');
        await _settle(tester);
        await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }

  // The voice-message sheet: idle, recording, a take ready to send (review)
  // and that take sending (review-busy).
  for (final (frame, state) in [
    (_Frame(390, _dark, 1), 'recorder'),
    (_Frame(390, _pearl, 1), 'recorder'),
    (_Frame(390, _dark, 2), 'recorder'),
    (_Frame(390, _dark, 1), 'recorder-recording'),
    (_Frame(390, _pearl, 1), 'recorder-recording'),
    (_Frame(390, _dark, 2), 'recorder-recording'),
    (_Frame(390, _pearl, 2), 'recorder-recording'),
    for (final frame in _spots(hc: true)) (frame, 'recorder-review'),
    (_Frame(390, _dark, 1), 'recorder-review-busy'),
    (_Frame(390, _pearl, 1), 'recorder-review-busy'),
    (_Frame(390, _dark, 2), 'recorder-review-busy'),
    (_Frame(390, _dark, 1, hc: true), 'recorder-review-busy'),
  ]) {
    final name = frame.name('conversation', state);
    testWidgets('thread ${frame.width.toInt()} $name', (tester) async {
      await _ignoringAudioPluginNoise(() async {
        final clock = FakeStopwatch();
        await _pumpScreen(
          tester,
          frame,
          _chat(
            _FixtureMessageService(),
            recorderFactory: () => VoiceMomentRecorder(
              backend: FakeRecorderBackend(),
              capture: FakeAudioCapture()..result = FakeRecordedAudio(),
              clock: clock,
            ),
          ),
        );
        await tester.tap(find.byTooltip('Nagraj wiadomość głosową'));
        await _settle(tester);
        final bead = find.byKey(const ValueKey('voice-message-record-bead'));
        if (state != 'recorder') {
          await tester.tap(bead);
          // After the recorder has started (and reset its clock), so the
          // sheet shows a real 0:07 take rather than 0:00.
          await tester.pump();
          clock.value = const Duration(seconds: 7);
          await _settle(tester);
        }
        if (state.startsWith('recorder-review')) {
          await tester.tap(bead);
          await _settle(tester);
        }
        if (state == 'recorder-review-busy') {
          await tester.tap(find.text('Wyślij wiadomość głosową'));
          await _settle(tester);
        }
        await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }

  // Invitations carrying a room link: the card on the themed surface and on
  // the brand gradient.
  for (final frame in _spots(hc: true)) {
    final name = frame.name('conversation', 'room-link');
    testWidgets('thread ${frame.width.toInt()} $name', (tester) async {
      await _ignoringAudioPluginNoise(() async {
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: _me),
        );
        final firestore = FakeFirebaseFirestore();
        await tester.runAsync(
          () => firestore
              .collection('rooms')
              .doc('room-1')
              .set(_linkedRoom().toMap()),
        );
        resetRoomLinkCache(
          service: RoomService(firestore: firestore, auth: auth),
        );
        addTearDown(resetRoomLinkCache);
        await _pumpScreen(
          tester,
          frame,
          _chat(_FixtureMessageService(messages: _roomLinkThread())),
        );
        await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
        expect(find.byKey(const ValueKey('room-link-card')), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }

  // The header while an archive is in flight: the spinner in its glass disc.
  for (final frame in [
    _Frame(390, _dark, 1),
    _Frame(390, _pearl, 1),
    _Frame(390, _dark, 2),
    _Frame(1440, _dark, 1),
    _Frame(390, _dark, 1, hc: true),
    _Frame(390, _pearl, 1, hc: true),
  ]) {
    final name = frame.name('conversation', 'archive-busy');
    testWidgets('thread ${frame.width.toInt()} $name', (tester) async {
      await _ignoringAudioPluginNoise(() async {
        await _pumpScreen(tester, frame, _chat(_FixtureMessageService()));
        await tester.tap(find.byTooltip('Opcje rozmowy'));
        await _settle(tester);
        await tester.tap(find.text('Archiwizuj'));
        await _settle(tester);
        expect(find.byKey(const ValueKey('chat-archive-busy')), findsOne);
        await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }

  // Keyboard focus on a header disc, the composer's mic disc and a reaction
  // disc in the long-press sheet.
  for (final frame in [_Frame(390, _dark, 1), _Frame(390, _pearl, 1)]) {
    for (final state in const ['focus-header', 'focus-mic', 'focus-reaction']) {
      final name = frame.name('conversation', state);
      testWidgets('thread ${frame.width.toInt()} $name', (tester) async {
        await _ignoringAudioPluginNoise(() async {
          await _pumpScreen(tester, frame, _chat(_FixtureMessageService()));
          switch (state) {
            case 'focus-header':
              await _focusOn(tester, find.byIcon(Icons.call_rounded));
            case 'focus-mic':
              await _focusOn(tester, find.byIcon(Icons.mic_none_rounded));
            default:
              await tester.longPress(
                find.text('To co, widzimy się dziś na serwerze o 20?'),
              );
              await _settle(tester);
              await _focusOn(tester, find.text('😂'));
          }
          await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
          expect(tester.takeException(), isNull);
          await _teardown(tester);
        });
      });
    }
  }

  for (final frame in [_Frame(390, _dark, 1), _Frame(390, _pearl, 1)]) {
    final name = frame.name('conversation', 'empty');
    testWidgets('thread ${frame.width.toInt()} $name', (tester) async {
      await _ignoringAudioPluginNoise(() async {
        await _pumpScreen(
          tester,
          frame,
          _chat(_FixtureMessageService(messages: const <Message>[])),
        );
        await _capturePng(tester, name, pixelRatio: _pixelRatio(frame));
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }
}
