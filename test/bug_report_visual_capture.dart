// Developer-only visual capture for the in-app bug reporter.
//
// Run explicitly:
//   flutter test test/bug_report_visual_capture.dart
//
// PNGs land in test/.screenshots/bug-report/ (git-ignored), or in
// $YOVOICE_CAPTURE_DIR when set. The filename deliberately does not end in
// `_test.dart`, so the regular suite never writes screenshot artifacts.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_admin_service.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_context.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_route_tracker.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_service.dart';
import 'package:yovoice/features/bug_reports/presentation/bug_report_floating_button.dart';
import 'package:yovoice/features/bug_reports/presentation/bug_report_sheet.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_bug_reports_section.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_section_shared.dart';

final _captureKey = GlobalKey();

class _MemoryStore implements AppPreferencesStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}

class _NoStaff extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
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

Future<void> _capturePng(WidgetTester tester, String filename) async {
  // Image.memory decodes off the fake clock; give it real time, then paint.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        _captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final warmup = await boundary.toImage(pixelRatio: 2);
    warmup.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final root =
          Platform.environment['YOVOICE_CAPTURE_DIR'] ??
          'test/.screenshots/bug-report';
      final file = File('$root/$filename.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

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

/// A stand-in "screen" frame: flat colour bands, no real content.
Uint8List _frame() {
  final image = img.Image(width: 390, height: 844);
  img.fill(image, color: img.ColorRgb8(24, 18, 40));
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: 390,
    y2: 110,
    color: img.ColorRgb8(60, 40, 110),
  );
  for (var row = 0; row < 6; row++) {
    img.fillRect(
      image,
      x1: 20,
      y1: 150 + row * 90,
      x2: row.isEven ? 300 : 370,
      y2: 210 + row * 90,
      color: img.ColorRgb8(row.isEven ? 70 : 110, 60, 140),
    );
  }
  return Uint8List.fromList(img.encodePng(image));
}

final _service = BugReportService(
  invoker: (name, payload) async => <Object?, Object?>{
    'reportId': 'br_${'c' * 40}',
  },
);

Widget _app({
  required ThemeData theme,
  required Widget home,
  TransitionBuilder? builder,
  GlobalKey<NavigatorState>? navigatorKey,
  List<NavigatorObserver> observers = const [],
}) {
  return AppPreferencesScope(
    controller: AppPreferencesController(store: _MemoryStore()),
    child: MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: observers,
      debugShowCheckedModeBanner: false,
      theme: theme,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => RepaintBoundary(
        key: _captureKey,
        child: builder == null ? child! : builder(context, child),
      ),
      home: home,
    ),
  );
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
}

Widget _dockPage() => Scaffold(
  body: const Center(child: Text('YO Voice')),
  bottomNavigationBar: YoFloatingNavigationDock(
    selectedTabIndex: 0,
    roomsTabIndex: 13,
    momentsTabIndex: 5,
    unreadConversationCount: 3,
    onDestinationSelected: (_) {},
    onVoicePressed: () {},
    onMorePressed: () {},
  ),
);

void main() {
  setUpAll(_loadFonts);
  final frame = _frame();

  for (final (themeName, theme) in [
    ('dark', AppTheme.darkTheme),
    ('pearl', AppTheme.lightTheme),
  ]) {
    for (final size in const [
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
    ]) {
      final label = '${size.width.toInt()}-$themeName';

      testWidgets('reporter $label', (tester) async {
        _size(tester, size);
        await tester.pumpWidget(
          _app(
            theme: theme,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showBugReportSheet(
                      context,
                      contextBuilder: () async => _context,
                      screenshot: frame,
                      service: _service,
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
        await tester.enterText(
          find.byKey(const ValueKey('bug-report-description')),
          'The send button stays grey after I pick a photo from the library.',
        );
        await tester.pumpAndSettle();
        await _capturePng(tester, 'reporter-$label');

        await tester.tap(
          find.byKey(const ValueKey('bug-report-screenshot-review')),
        );
        await tester.pumpAndSettle();
        await _capturePng(tester, 'consent-$label');
        await tester.ensureVisible(
          find.byKey(const ValueKey('bug-report-screenshot-full-size')),
        );
        await tester.pumpAndSettle();
        await _capturePng(tester, 'consent-scrolled-$label');
        await tester.tap(
          find.byKey(const ValueKey('bug-report-screenshot-full-size')),
        );
        await tester.pumpAndSettle();
        await _capturePng(tester, 'consent-full-size-$label');
        await tester.tap(
          find.byKey(const ValueKey('bug-report-screenshot-full-size-close')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('bug-report-screenshot-confirm')),
        );
        await tester.pumpAndSettle();
        await _capturePng(tester, 'attached-$label');
        expect(tester.takeException(), isNull);
      });

      testWidgets('floating button $label', (tester) async {
        _size(tester, size);
        tester.view.systemGestureInsets = const FakeViewPadding(
          left: 24,
          right: 24,
          bottom: 20,
        );
        final navigatorKey = GlobalKey<NavigatorState>();
        final tracker = BugReportRouteTracker();
        await tester.pumpWidget(
          _app(
            theme: theme,
            navigatorKey: navigatorKey,
            observers: [tracker],
            builder: (context, child) => BugReportFloatingButtonHost(
              navigatorKey: navigatorKey,
              available: true,
              initiallySignedIn: true,
              signedInChanges: const Stream<bool>.empty(),
              routeTracker: tracker,
              onOpenReporter: (_) {},
              child: child!,
            ),
            home: _dockPage(),
          ),
        );
        await tester.pumpAndSettle();
        await _capturePng(tester, 'button-resting-$label');
        await tester.drag(
          find.byKey(const ValueKey('bug-report-floating-button')),
          const Offset(-4000, 4000),
        );
        await tester.pumpAndSettle();
        await _capturePng(tester, 'button-dragged-bottom-left-$label');
      });
    }

    testWidgets('more sheet 390-$themeName', (tester) async {
      _size(tester, const Size(390, 844));
      await tester.pumpWidget(
        _app(
          theme: theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showMoreSheet(
                    context,
                    capabilityService: _NoStaff(),
                    currentUid: 'tester',
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
      await _capturePng(tester, 'more-sheet-390-$themeName');
    });
  }

  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    testWidgets('staff inbox ${size.width.toInt()}', (tester) async {
      _size(tester, size);
      final admin = BugReportAdminService(
        invoker: (name, payload) async {
          if (name == 'listBugReportsV1') {
            return <Object?, Object?>{
              'reports': [
                for (final (index, status) in const [
                  (0, 'new'),
                  (1, 'triaged'),
                  (2, 'resolved'),
                ])
                  {
                    'reportId': 'br_${'$index' * 40}',
                    'reporterId': 'uid-$index',
                    'status': status,
                    'createdAtMillis': DateTime(
                      2026,
                      9,
                      25,
                      10 - index,
                    ).millisecondsSinceEpoch,
                    'descriptionPreview':
                        'Sample report $index: the call drops after a minute.',
                    'platform': index.isEven ? 'ios' : 'android',
                    'appVersion': '3.0.0',
                    'buildNumber': '36',
                    'route': 'DirectCallScreen',
                    'screenshotStatus': index == 0 ? 'attached' : 'none',
                  },
              ],
              'nextCursor': null,
            };
          }
          return <Object?, Object?>{
            'reportId': 'br_${'0' * 40}',
            'reporterId': 'uid-0',
            'status': 'new',
            'description':
                'Sample report 0: the call drops after a minute. Every time.',
            'context': _context.toJson(),
            'screenshot': {'status': 'attached', 'url': null},
            'delivery': <Object?, Object?>{},
          };
        },
      );
      await tester.pumpWidget(
        _app(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            backgroundColor: StaffCenterStyle.background,
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: StaffBugReportsSection(service: admin),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (size.width > 1000) {
        await tester.tap(find.textContaining('Sample report 0'));
        await tester.pumpAndSettle();
      }
      await _capturePng(tester, 'staff-inbox-${size.width.toInt()}');
      if (size.width > 1000) {
        // The rights-request actions at the foot of the detail.
        await tester.ensureVisible(
          find.byKey(const ValueKey('staff-bug-report-delete')),
        );
        await tester.pumpAndSettle();
        await _capturePng(tester, 'staff-detail-rights-1440');
        await tester.tap(find.byKey(const ValueKey('staff-bug-report-delete')));
        await tester.pumpAndSettle();
        await _capturePng(tester, 'staff-delete-confirm-1440');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.byKey(const ValueKey('staff-bug-report-find-account')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('staff-bug-report-find-account-field')),
        'uid-0',
      );
      await tester.pumpAndSettle();
      await _capturePng(tester, 'staff-find-account-${size.width.toInt()}');
      await tester.tap(
        find.byKey(const ValueKey('staff-bug-report-find-account-submit')),
      );
      await tester.pumpAndSettle();
      await _capturePng(tester, 'staff-account-filter-${size.width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }
}
