// TEMPORARY visual-QA harness (Trust and Safety Moderation Specialist).
// Not a test: deliberately does not end in `_test.dart`, so
// `flutter test` never picks it up.
//
//   flutter test test/report_visual_qa.dart
//
// PNGs land in test/.screenshots/report/. DELETE THIS FILE AFTERWARDS.
//
// Why it exists: this project's rule is that a visual claim needs visual
// proof, and widget tests prove behaviour, not rendering. Same technique
// as test/moderation_screenshot.dart — real widgets, real fonts, exact
// viewport.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

const _me = 'me-uid';
const _them = 'them-uid';
const _conversationId = 'me-uid_them-uid';

String _resolveFontRoot() {
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null) {
    final configured = '$configuredRoot/bin/cache/artifacts/material_fonts';
    if (File('$configured/Roboto-Regular.ttf').existsSync()) return configured;
  }
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final candidate = '${directory.path}/bin/cache/artifacts/material_fonts';
    if (File('$candidate/Roboto-Regular.ttf').existsSync()) return candidate;
    directory = directory.parent;
  }
  throw StateError('Could not locate Flutter material fonts.');
}

final String _fontRoot = _resolveFontRoot();
final _capture = GlobalKey();

Future<void> _loadRealFonts() async {
  Future<ByteData> read(String name) async {
    final bytes = File('$_fontRoot/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  final roboto = FontLoader('Roboto');
  for (final face in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    roboto.addFont(read(face));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/.screenshots/report/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(_loadRealFonts);

  setUp(() {
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  Message theirMessage() => Message(
    id: 'm1',
    conversationId: _conversationId,
    senderId: _them,
    type: MessageType.text,
    content: 'you are pathetic and everyone knows it',
    sentAt: DateTime.utc(2026, 8, 19, 12),
    readBy: const [_me],
    reactions: const <String, String>{},
  );

  for (final entry in const <String, Size>{
    'mobile': Size(390, 844),
    'tablet': Size(834, 1112),
    'desktop': Size(1440, 900),
  }.entries) {
    testWidgets('dm report sheet — ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final service = _StubMessageService();
      await tester.pumpWidget(
        RepaintBoundary(
          key: _capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
              fontFamily: 'Roboto',
            ),
            home: ChatScreen(
              conversationId: _conversationId,
              otherUserId: _them,
              otherDisplayName: 'Marek',
              otherEmail: '',
              otherPhotoUrl: '',
              messageService: service,
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: _me),
              ),
              contentReportService: ContentReportService(
                functions: _NoopFunctions(),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      service.emit([theirMessage()]);
      await _settle(tester);

      await tester.longPress(find.textContaining('pathetic'));
      await _settle(tester);
      await _shoot(tester, 'dm-actions-${entry.key}');

      await tester.tap(find.byKey(const ValueKey('report-message')));
      await _settle(tester);
      await _shoot(tester, 'dm-reason-picker-${entry.key}');

      await tester.tap(find.byKey(const ValueKey('report-reason-harassment')));
      await _settle(tester);
      await _shoot(tester, 'dm-report-sent-${entry.key}');
    });
  }

  testWidgets('dm report failure copy — mobile', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _StubMessageService();
    await tester.pumpWidget(
      RepaintBoundary(
        key: _capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            fontFamily: 'Roboto',
          ),
          home: ChatScreen(
            conversationId: _conversationId,
            otherUserId: _them,
            otherDisplayName: 'Marek',
            otherEmail: '',
            otherPhotoUrl: '',
            messageService: service,
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: _me),
            ),
            contentReportService: ContentReportService(
              functions: _NoopFunctions(
                failure: FirebaseFunctionsException(
                  code: 'already-exists',
                  message: 'requestId was already used for another operation.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    service.emit([theirMessage()]);
    await _settle(tester);

    await tester.longPress(find.textContaining('pathetic'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('report-message')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('report-reason-spam')));
    await _settle(tester);
    await _shoot(tester, 'dm-already-reported-mobile');
  });

  for (final entry in const <String, Size>{
    'mobile': Size(390, 844),
    'desktop': Size(1440, 900),
  }.entries) {
    testWidgets('moment comment report — ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final db = FakeFirebaseFirestore();
      final comments = db
          .collection('voiceMoments')
          .doc('v1')
          .collection('comments');
      await comments.doc('c1').set(<String, dynamic>{
        'authorId': _them,
        'authorName': 'Marek',
        'text': 'go away, nobody wants you here',
        'type': 'text',
        'createdAt': Timestamp.fromDate(DateTime(2026, 8, 19)),
      });
      await comments.doc('c2').set(<String, dynamic>{
        'authorId': _me,
        'authorName': 'Me',
        'text': 'my own comment, no report control',
        'type': 'text',
        'createdAt': Timestamp.fromDate(DateTime(2026, 8, 19, 1)),
      });

      await tester.pumpWidget(
        RepaintBoundary(
          key: _capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
              fontFamily: 'Roboto',
            ),
            home: MomentCommentsScreen(
              moment: VoiceMoment(
                id: 'v1',
                authorId: _them,
                authorName: 'Marek',
                authorPhotoUrl: null,
                caption: 'caption',
                audioUrl: 'https://cdn.example/a.m4a',
                durationSeconds: 12,
                likeCount: 0,
                commentCount: 2,
                isPublished: true,
                createdAt: DateTime(2026, 8, 19),
                schemaVersion: 2,
                status: 'published',
                isDeleted: false,
              ),
              firestore: db,
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: _me),
              ),
              contentReportService: ContentReportService(
                functions: _NoopFunctions(),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await _shoot(tester, 'comments-thread-${entry.key}');

      await tester.tap(find.byKey(const ValueKey('report-comment-c1')));
      await _settle(tester);
      await _shoot(tester, 'comments-reason-picker-${entry.key}');
    });
  }
}

class _NoopFunctions implements FirebaseFunctions {
  _NoopFunctions({this.failure});
  final Object? failure;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _NoopCallable(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopCallable implements HttpsCallable {
  _NoopCallable(this.owner);
  final _NoopFunctions owner;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    final failure = owner.failure;
    if (failure != null) throw failure;
    return _NoopResult<T>({'reportId': 'r1', 'created': true} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopResult<T> implements HttpsCallableResult<T> {
  _NoopResult(this.data);
  @override
  final T data;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubMessageService extends MessageService {
  _StubMessageService()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      );

  final StreamController<List<Message>> _messages =
      StreamController<List<Message>>.broadcast();

  void emit(List<Message> messages) => _messages.add(messages);

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      _messages.stream;

  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => Stream<bool>.value(false);

  @override
  Stream<ChatPresence> watchUserPresence(String userId) =>
      Stream<ChatPresence>.value(
        const ChatPresence(isOnline: false, lastSeen: null),
      );

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}
}
