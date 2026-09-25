import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_context.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_service.dart';
import 'package:yovoice/features/bug_reports/presentation/bug_report_capture.dart';
import 'package:yovoice/features/bug_reports/presentation/bug_report_sheet.dart';

/// The reporter: description required, the screenshot consent step, what is
/// sent, refusals, and the sheet/dialog split by width.
const _context = BugReportContext(
  appVersion: '3.0.0',
  buildNumber: '36',
  platform: 'ios',
  osVersion: 'Version 18.6',
  locale: 'en',
  theme: 'dark',
  brightness: 'dark',
  route: 'ChatScreen',
  routeDepth: 2,
  viewportWidth: 390,
  viewportHeight: 844,
  textScale: 1,
);

final Uint8List _screenshot = Uint8List.fromList(
  img.encodePng(img.Image(width: 8, height: 12)),
);

class _Calls {
  final List<(String, Map<String, Object?>)> calls = [];
  final List<Uint8List> uploads = [];
  String? refuseWith;
}

BugReportService _service(_Calls record) => BugReportService(
  invoker: (name, payload) async {
    record.calls.add((name, payload));
    if (record.refuseWith != null) {
      throw BugReportException(record.refuseWith!);
    }
    if (name == 'submitBugReportV1') {
      final reportId = 'br_${'a' * 40}';
      return <Object?, Object?>{
        'reportId': reportId,
        'screenshotUpload': payload['screenshot'] == null
            ? null
            : <Object?, Object?>{
                'storagePath': 'bug_reports/uid/$reportId.jpg',
                'uploadMetadata': <Object?, Object?>{
                  'yovoiceOwnerUid': 'uid',
                  'yovoiceReportId': reportId,
                },
              },
      };
    }
    return <Object?, Object?>{'attached': true};
  },
  uploader:
      ({
        required String storagePath,
        required Uint8List bytes,
        required Map<String, String> customMetadata,
      }) async {
        record.uploads.add(bytes);
        return '1700000000000001';
      },
);

Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.darkTheme,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

Future<void> _pumpForm(
  WidgetTester tester,
  _Calls record, {
  Uint8List? screenshot,
  bool captureBlocked = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _app(
      Scaffold(
        body: BugReportForm(
          contextBuilder: () async => _context,
          screenshot: screenshot,
          captureBlocked: captureBlocked,
          service: _service(record),
          openPrivacyPolicy: () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _describe(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('bug-report-description')),
    text,
  );
  await tester.pump();
}

Future<void> _send(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('bug-report-send')));
  await tester.tap(find.byKey(const ValueKey('bug-report-send')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a description of at least ten characters is required', (
    tester,
  ) async {
    final record = _Calls();
    await _pumpForm(tester, record);
    await _describe(tester, 'broken');
    await _send(tester);
    expect(
      find.text('Describe the problem in at least 10 characters.'),
      findsOneWidget,
    );
    expect(record.calls, isEmpty);
  });

  testWidgets('without the consent step no screenshot is sent, even though '
      'one was captured', (tester) async {
    final record = _Calls();
    await _pumpForm(tester, record, screenshot: _screenshot);
    expect(
      find.byKey(const ValueKey('bug-report-screenshot-attached')),
      findsNothing,
      reason: 'the capture is a candidate, never attached by default',
    );
    await _describe(tester, 'The send button stays grey after a photo.');
    await _send(tester);
    expect(record.calls, hasLength(1));
    final (name, payload) = record.calls.single;
    expect(name, 'submitBugReportV1');
    expect(payload['screenshot'], isNull);
    expect(payload['description'], 'The send button stays grey after a photo.');
    expect(payload['context'], _context.toJson());
    expect(payload.keys.toSet(), {
      'requestId',
      'description',
      'context',
      'screenshot',
    });
    expect(record.uploads, isEmpty);
    expect(find.byKey(const ValueKey('bug-report-sent')), findsOneWidget);
  });

  testWidgets('the preview shows the warning; declining attaches nothing, '
      'confirming attaches exactly the captured frame', (tester) async {
    final record = _Calls();
    await _pumpForm(tester, record, screenshot: _screenshot);

    await tester.tap(
      find.byKey(const ValueKey('bug-report-screenshot-review')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bug-report-screenshot-preview')),
      findsOneWidget,
    );
    expect(
      find.textContaining('may show other people\'s names, photos or messages'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('bug-report-screenshot-decline')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bug-report-screenshot-attached')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('bug-report-screenshot-review')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bug-report-screenshot-confirm')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bug-report-screenshot-attached')),
      findsOneWidget,
    );

    await _describe(tester, 'Video tile is black on the server stage.');
    await _send(tester);
    final submit = record.calls.first.$2;
    expect(submit['screenshot'], {
      'contentType': 'image/jpeg',
      'size': _screenshot.length,
    });
    expect(record.uploads.single, _screenshot);
    expect(record.calls.last.$1, 'attachBugReportScreenshotV1');
    expect(record.calls.last.$2, {
      'reportId': 'br_${'a' * 40}',
      'objectGeneration': '1700000000000001',
    });
  });

  testWidgets('an attached screenshot can be removed again before sending', (
    tester,
  ) async {
    final record = _Calls();
    await _pumpForm(tester, record, screenshot: _screenshot);
    await tester.tap(
      find.byKey(const ValueKey('bug-report-screenshot-review')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bug-report-screenshot-confirm')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bug-report-screenshot-remove')),
    );
    await tester.pumpAndSettle();
    await _describe(tester, 'Changed my mind about the screenshot.');
    await _send(tester);
    expect(record.calls.single.$2['screenshot'], isNull);
  });

  testWidgets('on a protected screen there is no screenshot to review', (
    tester,
  ) async {
    await _pumpForm(tester, _Calls(), captureBlocked: true);
    expect(
      find.byKey(const ValueKey('bug-report-screenshot-blocked')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bug-report-screenshot-review')),
      findsNothing,
    );
  });

  testWidgets('a rate-limit refusal is explained and the report can be '
      'retried with the same request id', (tester) async {
    final record = _Calls()..refuseWith = 'resource-exhausted';
    await _pumpForm(tester, record);
    await _describe(tester, 'Something is wrong with the chat list.');
    await _send(tester);
    expect(find.byKey(const ValueKey('bug-report-error')), findsOneWidget);
    expect(
      find.textContaining('several reports in a short time'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);

    record.refuseWith = null;
    await _send(tester);
    expect(find.byKey(const ValueKey('bug-report-sent')), findsOneWidget);
    expect(
      record.calls[0].$2['requestId'],
      record.calls[1].$2['requestId'],
      reason: 'a retry replays the same report on the server',
    );
  });

  for (final (size, dialog) in const [
    (Size(390, 844), false),
    (Size(768, 1024), true),
    (Size(1440, 900), true),
  ]) {
    testWidgets('${size.width.toInt()}px opens the reporter as a '
        '${dialog ? 'dialog' : 'bottom sheet'}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showBugReportSheet(
                    context,
                    contextBuilder: () async => _context,
                    service: _service(_Calls()),
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
      expect(find.byType(BugReportForm), findsOneWidget);
      expect(find.byType(Dialog), dialog ? findsOneWidget : findsNothing);
      expect(find.byType(BottomSheet), dialog ? findsNothing : findsOneWidget);
      if (dialog) {
        expect(
          tester.getSize(find.byType(BugReportForm)).width,
          lessThanOrEqualTo(bugReportDialogMaxWidth),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('capture produces a JPEG, and a guarded screen produces none', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      _app(
        RepaintBoundary(
          key: key,
          child: const ColoredBox(
            color: Colors.indigo,
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
    final bytes = await tester.runAsync(
      () => captureBugReportScreenshot(key: key),
    );
    expect(bytes, isNotNull);
    expect(bytes!.sublist(0, 3), [0xff, 0xd8, 0xff]);
    expect(bytes.length, lessThanOrEqualTo(bugReportScreenshotMaxBytes));

    await tester.pumpWidget(
      _app(
        RepaintBoundary(
          key: key,
          child: const BugReportCaptureGuard(child: SizedBox.expand()),
        ),
      ),
    );
    expect(BugReportCaptureGuard.isActive, isTrue);
    final blocked = await tester.runAsync(
      () => captureBugReportScreenshot(key: key),
    );
    expect(blocked, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(BugReportCaptureGuard.isActive, isFalse);
  });
}
