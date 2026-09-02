import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';
import 'package:yovoice/features/permissions/presentation/permission_setup_sheet.dart';

void main() {
  testWidgets('one CTA requests all missing permissions in order', (
    tester,
  ) async {
    final platform = _SheetPermissionPlatform();
    final progress = _SheetProgressStore();
    final service = PermissionReadinessService(
      platform: platform,
      progressStore: progress,
    );
    await _pumpHarness(tester, service: service);

    await tester.tap(find.text('Open setup'));
    await tester.pumpAndSettle();
    expect(find.text('Set up calls and alerts'), findsOneWidget);
    expect(find.text('Not allowed yet'), findsNWidgets(3));

    await tester.tap(find.byKey(const ValueKey('permission-setup-primary')));
    await tester.pumpAndSettle();

    expect(platform.requests, AppPermissionKind.values);
    expect(find.text('Allowed'), findsNWidgets(3));
    expect(find.text('Done'), findsOneWidget);
    expect(progress.outcomes['user-1'], PermissionSetupOutcome.completed);

    await tester.tap(find.byKey(const ValueKey('permission-setup-primary')));
    await tester.pumpAndSettle();
    expect(find.text('Set up calls and alerts'), findsNothing);
  });

  testWidgets('Polish sheet can be skipped and remembers the choice', (
    tester,
  ) async {
    final progress = _SheetProgressStore();
    final service = PermissionReadinessService(
      platform: _SheetPermissionPlatform(),
      progressStore: progress,
    );
    await _pumpHarness(tester, service: service, locale: const Locale('pl'));

    await tester.tap(find.text('Otwórz konfigurację'));
    await tester.pumpAndSettle();
    expect(find.text('Skonfiguruj połączenia i powiadomienia'), findsOneWidget);
    expect(find.text('Skonfiguruj uprawnienia'), findsOneWidget);

    final skip = find.byKey(const ValueKey('permission-setup-skip'));
    await tester.ensureVisible(skip);
    await tester.tap(skip);
    await tester.pumpAndSettle();

    expect(progress.outcomes['user-1'], PermissionSetupOutcome.skipped);
    expect(find.text('Skonfiguruj połączenia i powiadomienia'), findsNothing);
  });

  testWidgets('sheet stays usable at 320px with 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = PermissionReadinessService(
      platform: _SheetPermissionPlatform(),
      progressStore: _SheetProgressStore(),
    );
    await _pumpHarness(
      tester,
      service: service,
      locale: const Locale('pl'),
      textScaler: const TextScaler.linear(2),
    );

    await tester.tap(find.text('Otwórz konfigurację'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final primary = find.byKey(const ValueKey('permission-setup-primary'));
    await tester.ensureVisible(primary);
    await tester.pumpAndSettle();
    expect(primary, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required PermissionReadinessService service,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showPermissionSetupSheet(
                context,
                userId: 'user-1',
                service: service,
              ),
              child: Text(
                locale.languageCode == 'pl'
                    ? 'Otwórz konfigurację'
                    : 'Open setup',
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _SheetPermissionPlatform implements AppPermissionPlatformGateway {
  final Map<AppPermissionKind, AppPermissionAccess> statuses = {
    for (final permission in AppPermissionKind.values)
      permission: AppPermissionAccess.denied,
  };
  final List<AppPermissionKind> requests = <AppPermissionKind>[];

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<AppPermissionAccess> requestFromUserGesture(
    AppPermissionKind permission,
  ) async {
    requests.add(permission);
    statuses[permission] = AppPermissionAccess.granted;
    return AppPermissionAccess.granted;
  }

  @override
  Future<AppPermissionAccess> status(AppPermissionKind permission) async =>
      statuses[permission]!;
}

final class _SheetProgressStore implements PermissionSetupProgressStore {
  final Map<String, PermissionSetupOutcome> outcomes = {};

  @override
  Future<PermissionSetupOutcome?> readOutcome({
    required String userId,
    required int version,
  }) async => outcomes[userId];

  @override
  Future<void> writeOutcome({
    required String userId,
    required int version,
    required PermissionSetupOutcome outcome,
  }) async {
    outcomes[userId] = outcome;
  }
}
