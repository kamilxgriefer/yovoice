// Developer-only VISUAL harness: renders the populated Moderation
// Center — report detail plus audit timeline — to real PNG files.
//
// Why this exists. The project's rule is that a visual claim needs
// visual proof, and the usual route (run the web build, look at it) is
// unavailable here: the in-app browser cannot rasterise Flutter's
// CanvasKit output at all — the deployed production app renders blank in
// it too. This harness gets the same evidence from the widget layer
// instead: real widgets, real fonts, exact viewport, and a tap that
// actually lands, which a canvas click does not reliably do.
//
// It is NOT a test and deliberately does not end in `_test.dart`, so
// `flutter test` never picks it up. Run it explicitly:
//
//   flutter test test/moderation_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moderation/data/models/moderation_audit_event.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';

const String _mod = 'preview-mod';
const String _fontRoot =
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts';

final _capture = GlobalKey();

Future<void> _loadRealFonts() async {
  // Without this every glyph renders as a filled box and the "look at
  // it" step proves nothing.
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

Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  DateTime ago(Duration d) => DateTime.now().subtract(d);

  await db.collection('users').doc(_mod).set(<String, dynamic>{
    'uid': _mod,
    'displayName': 'CeoGriefer',
    'role': 'moderator',
  });
  await db.collection('users').doc('jonas').set(<String, dynamic>{
    'uid': 'jonas',
    'displayName': 'Jonas',
  });

  const reasons = [
    'harassment',
    'spam',
    'hate',
    'impersonation',
    'violence',
    'sexual',
  ];
  for (var i = 0; i < reasons.length; i++) {
    await db.collection('reports').doc('r$i').set(<String, dynamic>{
      'reporterId': 'reporter-$i',
      'targetType': 'globalMessage',
      'targetId': 'gm$i',
      'reportedUserId': 'jonas',
      'contextPath': 'globalChat/main/messages/gm$i',
      'reason': reasons[i],
      'note': i.isEven ? 'They kept going after being asked to stop.' : '',
      'createdAt': Timestamp.fromDate(ago(Duration(minutes: 4 + i * 37))),
      'status': 'open',
    });
  }

  await db
      .collection('globalChat')
      .doc('main')
      .collection('messages')
      .doc('gm0')
      .set(<String, dynamic>{
        'senderId': 'jonas',
        'senderName': 'Jonas',
        'senderPhotoUrl': null,
        'senderIsCreator': false,
        'senderIsStaff': false,
        'content': 'The reported message content sits here for review.',
        'sentAt': Timestamp.fromDate(ago(const Duration(minutes: 6))),
        'isDeleted': false,
        'deletedBy': null,
        'deletedAt': null,
      });

  return db;
}

/// Same stand-in the desktop preview harness uses: the trail is served by
/// a callable, and there is no Functions emulator behind a widget render.
class _ScreenshotService extends ModerationService {
  _ScreenshotService({super.firestore, super.auth});

  @override
  Future<ModerationAuditPage> reportAuditTrail(
    String reportId, {
    int limit = ModerationService.auditPageSize,
    String? cursor,
  }) async {
    Map<String, dynamic> event(
      String id,
      String kind,
      String action,
      String at, {
      String? previousStatus,
      String? newStatus,
      String? resolution,
      String? note,
      bool contentRemoved = false,
      String? removedContent,
    }) => <String, dynamic>{
      'id': id,
      'kind': kind,
      'action': action,
      'actorId': _mod,
      'actorName': 'CeoGriefer',
      'actorRole': 'moderator',
      'previousStatus': previousStatus,
      'newStatus': newStatus,
      'resolution': resolution,
      'note': note,
      'contentRemoved': contentRemoved,
      'removedContent': removedContent,
      'createdAt': at,
    };

    return ModerationAuditPage.fromResponse(<String, dynamic>{
      'events': [
        event(
          'c1',
          'contentModeration',
          'globalMessage_moderated',
          '2026-08-11T18:42:09.000Z',
          contentRemoved: true,
          removedContent: 'buy followers here, dm me',
        ),
        event(
          'w1',
          'reportWorkflow',
          'report_claim',
          '2026-08-11T18:39:02.000Z',
          previousStatus: 'open',
          newStatus: 'inReview',
          note: 'Taking this one.',
        ),
      ],
      'hasMore': true,
      'nextCursor': '2026-08-11T18:39:02.000Z',
    });
  }
}

/// Bounded alternative to pumpAndSettle: enough frames for futures and
/// transitions to land, but it cannot hang on a widget that animates
/// forever.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final boundary =
      _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('test/.screenshots/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote ${file.path}');
}

void main() {
  setUpAll(_loadRealFonts);

  for (final size in const [
    Size(1440, 820),
    Size(1440, 620),
    Size(1100, 820),
    Size(390, 844),
    Size(768, 1024),
  ]) {
    testWidgets('moderation center at ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final db = await _seed();
      final service = _ScreenshotService(
        firestore: db,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: _mod,
            displayName: 'CeoGriefer',
            customClaim: const {'role': 'moderator'},
          ),
        ),
      );

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
            home: ModerationCenterScreen(
              isRootTab: size.width >= 980,
              moderationService: service,
            ),
          ),
        ),
      );
      await _settle(tester);

      // Select the first report so the populated detail — and with it the
      // audit timeline — is what gets captured. A tester tap always
      // lands, which is the whole reason this route was taken.
      final row = find.text('Harassment or bullying').last;
      await tester.ensureVisible(row);
      await _settle(tester);
      await tester.tap(row, warnIfMissed: false);
      await _settle(tester);

      expect(find.text('Moderation history'), findsOneWidget);
      await _shoot(tester, 'moderation-${size.width.toInt()}x${size.height.toInt()}');
    });
  }
}
