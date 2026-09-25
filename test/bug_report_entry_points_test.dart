import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_admin_service.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_route_tracker.dart';
import 'package:yovoice/features/bug_reports/presentation/bug_report_launcher.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/settings/presentation/screens/settings_screen.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_bug_reports_section.dart';

/// Where a report can be started from: Settings > Help, the mobile More
/// sheet and the desktop More popover — and where the owner reads it.
class _MemoryStore implements AppPreferencesStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _NoStaff extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

Widget _app(Widget home, {AppPreferencesController? preferences}) {
  final app = MaterialApp(
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
  return preferences == null
      ? app
      : AppPreferencesScope(controller: preferences, child: app);
}

void _useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  final opened = <BuildContext>[];
  setUp(() {
    opened.clear();
    BugReportLauncher.debugOpenOverride = (context) async =>
        opened.add(context);
  });
  tearDown(() => BugReportLauncher.debugOpenOverride = null);

  testWidgets('Settings > Help: "Report a bug" and the Bug button switch', (
    tester,
  ) async {
    _useSize(tester, const Size(390, 844));
    final preferences = AppPreferencesController(store: _MemoryStore());
    var reported = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: settingsBugReportRows(
                context,
                onReportBug: () => reported++,
                buttonAvailable: true,
              ),
            ),
          ),
        ),
        preferences: preferences,
      ),
    );
    expect(find.text('Report a bug'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-report-bug')));
    expect(reported, 1);

    expect(find.text('Show the Bug button'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(preferences.value.bugReportButtonVisible, isFalse);
  });

  testWidgets('Settings in a build without the floating button keeps only '
      '"Report a bug"', (tester) async {
    _useSize(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: settingsBugReportRows(
                context,
                onReportBug: () {},
                buttonAvailable: false,
              ),
            ),
          ),
        ),
        preferences: AppPreferencesController(store: _MemoryStore()),
      ),
    );
    expect(find.text('Report a bug'), findsOneWidget);
    expect(find.text('Show the Bug button'), findsNothing);
  });

  testWidgets('mobile More sheet: "Report a bug" closes the sheet with no '
      'destination, then opens the reporter', (tester) async {
    _useSize(tester, const Size(390, 844));
    MoreDestination? picked = MoreDestination.settings;
    var returned = false;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await showMoreSheet(
                    context,
                    capabilityService: _NoStaff(),
                    currentUid: 'tester',
                  );
                  returned = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('more-report-bug'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(picked, isNull, reason: 'the shell navigates nowhere');
    expect(find.byType(MoreSheet), findsNothing, reason: 'the sheet is gone');
    expect(opened, hasLength(1));
  });

  testWidgets('a bare MoreSheet (no launcher) keeps its launcher grid '
      'unchanged', (tester) async {
    _useSize(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SizedBox.expand(
            child: MoreSheet(capabilityService: _NoStaff(), currentUid: 'u'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-report-bug')), findsNothing);
  });

  testWidgets('desktop More popover: "Report a bug" returns no destination '
      'and opens the reporter after the popover has left', (tester) async {
    _useSize(tester, const Size(1440, 900));
    MoreDestination? picked = MoreDestination.settings;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await showDesktopMoreMenu(
                  context,
                  anchor: const Offset(80, 200),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Report a bug'), findsOneWidget);
    await tester.tap(find.text('Report a bug'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
    expect(find.text('Report a bug'), findsNothing);
    expect(opened, hasLength(1));
  });

  testWidgets('the screen name is the visible screen class, never an id', (
    tester,
  ) async {
    _useSize(tester, const Size(390, 844));
    final tracker = BugReportRouteTracker();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [tracker],
        home: const IndexedStack(
          index: 1,
          children: [_HiddenTabScreen(), _VisibleTabScreen()],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tracker.currentScreenName(), '_VisibleTabScreen');
    expect(tracker.depth, 1);
    expect(isSafeScreenName('chat/abc123 with Anna'), isFalse);
  });

  group('Staff Center > Bug reports', () {
    testWidgets('lists reports, opens one, and changes its status', (
      tester,
    ) async {
      _useSize(tester, const Size(1440, 900));
      final calls = <String>[];
      final service = BugReportAdminService(
        invoker: (name, payload) async {
          calls.add(name);
          if (name == 'listBugReportsV1') {
            return <Object?, Object?>{
              'reports': [
                {
                  'reportId': 'br_${'b' * 40}',
                  'reporterId': 'reporter-uid',
                  'status': 'new',
                  'createdAtMillis': DateTime(
                    2026,
                    9,
                    25,
                  ).millisecondsSinceEpoch,
                  'descriptionPreview': 'The call drops after a minute.',
                  'platform': 'android',
                  'appVersion': '3.0.0',
                  'buildNumber': '36',
                  'route': 'DirectCallScreen',
                  'screenshotStatus': 'attached',
                },
              ],
              'nextCursor': null,
            };
          }
          if (name == 'getBugReportV1') {
            return <Object?, Object?>{
              'reportId': 'br_${'b' * 40}',
              'reporterId': 'reporter-uid',
              'status': 'new',
              'description': 'The call drops after a minute. Every time.',
              'context': {'platform': 'android', 'route': 'DirectCallScreen'},
              'screenshot': {'status': 'missing', 'url': null},
              'delivery': <Object?, Object?>{},
            };
          }
          return <Object?, Object?>{};
        },
      );
      await tester.pumpWidget(
        _app(Scaffold(body: StaffBugReportsSection(service: service))),
      );
      await tester.pumpAndSettle();
      expect(find.text('The call drops after a minute.'), findsOneWidget);
      await tester.tap(find.text('The call drops after a minute.'));
      await tester.pumpAndSettle();
      expect(
        find.text('The call drops after a minute. Every time.'),
        findsOneWidget,
      );
      expect(find.text('reporter-uid'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Resolved').last);
      await tester.pumpAndSettle();
      expect(calls, contains('updateBugReportStatusV1'));
    });

    testWidgets('a refused or failed load is an error with Retry, not an '
        'empty inbox', (tester) async {
      _useSize(tester, const Size(390, 844));
      final service = BugReportAdminService(
        invoker: (name, payload) async => throw StateError('permission-denied'),
      );
      await tester.pumpWidget(
        _app(Scaffold(body: StaffBugReportsSection(service: service))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bug reports could not be loaded.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}

class _HiddenTabScreen extends StatelessWidget {
  const _HiddenTabScreen();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _VisibleTabScreen extends StatelessWidget {
  const _VisibleTabScreen();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
