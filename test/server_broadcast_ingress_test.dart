import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/services/server_broadcast_ingress_service.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_obs_broadcast_sheet.dart';

const _receiptMap = <Object?, Object?>{
  'schemaVersion': 1,
  'serverId': 'server',
  'channelId': 'stage',
  'sessionId': 'session',
  'ingressId': 'ingress_123',
  'serverUrl': 'rtmps://ingress.example.test/live',
  'streamKey': 'private-stream-key',
};

class _Repository implements ServerBroadcastIngressRepository {
  final calls = <(String, String, String)>[];

  @override
  Future<ServerBroadcastIngressReceipt> provision({
    required String serverId,
    required String channelId,
    required String sessionId,
  }) async {
    calls.add((serverId, channelId, sessionId));
    return ServerBroadcastIngressReceipt.fromMap(
      _receiptMap,
      serverId: serverId,
      channelId: channelId,
      sessionId: sessionId,
    );
  }
}

/// Fails every call with [failure] until [failure] is cleared, then answers
/// with the real receipt shape.
class _FailingRepository extends _Repository {
  _FailingRepository(this.failure);

  Object? failure;

  @override
  Future<ServerBroadcastIngressReceipt> provision({
    required String serverId,
    required String channelId,
    required String sessionId,
  }) async {
    final error = failure;
    if (error != null) {
      calls.add((serverId, channelId, sessionId));
      throw error;
    }
    return super.provision(
      serverId: serverId,
      channelId: channelId,
      sessionId: sessionId,
    );
  }
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required ServerBroadcastIngressRepository repository,
  required Locale locale,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.darkTheme,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: ServerObsBroadcastSheet(
        repository: repository,
        serverId: 'server',
        channelId: 'stage',
        sessionId: 'session',
      ),
    ),
  ),
);

void main() {
  test(
    'OBS receipt is exact, generation-bound and validates private settings',
    () {
      final receipt = ServerBroadcastIngressReceipt.fromMap(
        _receiptMap,
        serverId: 'server',
        channelId: 'stage',
        sessionId: 'session',
      );
      expect(receipt.ingressId, 'ingress_123');
      expect(receipt.serverUrl, 'rtmps://ingress.example.test/live');
      expect(receipt.streamKey, 'private-stream-key');

      for (final malformed in <Map<Object?, Object?>>[
        {..._receiptMap, 'sessionId': 'other'},
        {..._receiptMap, 'chosenHost': 'attacker'},
        {..._receiptMap, 'serverUrl': 'https://ingress.example.test/live'},
        {
          ..._receiptMap,
          'serverUrl': 'rtmps://user:pass@ingress.example.test/live',
        },
        {..._receiptMap, 'streamKey': 'short'},
        {..._receiptMap, 'streamKey': ' private-stream-key'},
      ]) {
        expect(
          () => ServerBroadcastIngressReceipt.fromMap(
            malformed,
            serverId: 'server',
            channelId: 'stage',
            sessionId: 'session',
          ),
          throwsFormatException,
          reason: '$malformed',
        );
      }
    },
  );

  test(
    'OBS service calls only the reviewed callable with exact authority-free input',
    () async {
      String? calledName;
      Map<String, Object?>? calledData;
      final service = ServerBroadcastIngressService(
        callOverride: (name, data) async {
          calledName = name;
          calledData = data;
          return _receiptMap;
        },
      );
      final receipt = await service.provision(
        serverId: 'server',
        channelId: 'stage',
        sessionId: 'session',
      );
      expect(calledName, 'createServerBroadcastIngressV1');
      expect(calledData?.keys.toSet(), {
        'serverId',
        'channelId',
        'sessionId',
        'requestId',
      });
      expect(calledData?['serverId'], 'server');
      expect(calledData?['channelId'], 'stage');
      expect(calledData?['sessionId'], 'session');
      expect(
        calledData?['requestId'],
        isA<String>().having((value) => value.length, 'length', 48),
      );
      expect(receipt.streamKey, 'private-stream-key');
    },
  );

  testWidgets(
    'OBS tutorial provisions real credentials and hides the key by default',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final repository = _Repository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ServerObsBroadcastSheet(
              repository: repository,
              serverId: 'server',
              channelId: 'stage',
              sessionId: 'session',
            ),
          ),
        ),
      );

      expect(find.text('OBS Broadcasting'), findsOneWidget);
      expect(find.textContaining('Settings → Stream'), findsOneWidget);
      expect(find.text('private-stream-key'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('server-obs-provision')));
      await tester.pumpAndSettle();

      expect(repository.calls, [('server', 'stage', 'session')]);
      expect(find.text('rtmps://ingress.example.test/live'), findsOneWidget);
      expect(find.text('private-stream-key'), findsNothing);
      expect(find.text('••••••••••••••••'), findsOneWidget);
      final copyKey = find.byKey(const ValueKey('server-obs-copy-stream-key'));
      await tester.ensureVisible(copyKey);
      await tester.tap(copyKey);
      await tester.pump(const Duration(milliseconds: 100));
      expect(copied, 'private-stream-key');
      expect(find.text('Stream Key copied'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('server-obs-copy-feedback')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('server-obs-reveal-key')));
      await tester.pump();
      expect(find.text('private-stream-key'), findsOneWidget);
    },
  );

  testWidgets('OBS credentials reflow at 320 px and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: ServerObsBroadcastSheet(
            repository: _Repository(),
            serverId: 'server',
            channelId: 'stage',
            sessionId: 'session',
          ),
        ),
      ),
    );
    final provision = find.byKey(const ValueKey('server-obs-provision'));
    await tester.ensureVisible(provision);
    await tester.tap(provision);
    await tester.pumpAndSettle();

    for (final key in [
      'server-obs-copy-server',
      'server-obs-reveal-key',
      'server-obs-copy-stream-key',
    ]) {
      final control = find.byKey(ValueKey(key));
      expect(control, findsOneWidget);
      final size = tester.getSize(control);
      expect(size.width, greaterThanOrEqualTo(48), reason: key);
      expect(size.height, greaterThanOrEqualTo(48), reason: key);
    }
    expect(tester.takeException(), isNull);
  });

  group('OBS setup refusals show a localized unavailable state', () {
    // An installed client can reach Functions that predate the callable
    // (`not-found` / `unimplemented`), and the backend refuses provisioning
    // with `failed-precondition` while the operator kill switch is off or the
    // capacity document is missing. None of these may crash the sheet, leak
    // the raw backend message, or present credentials.
    const cases =
        <({String code, String message, String english, String polish})>[
          (
            code: 'not-found',
            message: 'NOT_FOUND',
            english: 'This part of YO Voice is still being prepared.',
            polish: 'Ta część YO Voice jest jeszcze przygotowywana.',
          ),
          (
            code: 'unimplemented',
            message: 'UNIMPLEMENTED',
            english: 'This part of YO Voice is still being prepared.',
            polish: 'Ta część YO Voice jest jeszcze przygotowywana.',
          ),
          (
            code: 'failed-precondition',
            message: 'OBS broadcasting is temporarily disabled.',
            english: 'OBS setup is temporarily unavailable. Try again.',
            polish:
                'Konfiguracja OBS jest chwilowo niedostępna. Spróbuj ponownie.',
          ),
        ];

    for (final refusal in cases) {
      for (final locale in const [Locale('en'), Locale('pl')]) {
        testWidgets('${refusal.code} in ${locale.languageCode}', (
          tester,
        ) async {
          final repository = _FailingRepository(
            FirebaseFunctionsException(
              code: refusal.code,
              message: refusal.message,
            ),
          );
          await _pumpSheet(tester, repository: repository, locale: locale);

          final provision = find.byKey(const ValueKey('server-obs-provision'));
          await tester.ensureVisible(provision);
          await tester.tap(provision);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(repository.calls, [('server', 'stage', 'session')]);
          final error = find.byKey(const ValueKey('server-obs-error'));
          expect(error, findsOneWidget);
          expect(
            tester.widget<Text>(error).data,
            locale.languageCode == 'pl' ? refusal.polish : refusal.english,
          );
          expect(find.textContaining(refusal.message), findsNothing);
          expect(find.textContaining(refusal.code), findsNothing);
          expect(find.byKey(const ValueKey('server-obs-server')), findsNothing);
          expect(
            find.byKey(const ValueKey('server-obs-stream-key')),
            findsNothing,
          );
          // The host can retry once the backend is ready; the button is not
          // left stuck in its busy state.
          expect(tester.widget<FilledButton>(provision).onPressed, isNotNull);
        });
      }
    }

    testWidgets('a retry after the refusal clears it and shows credentials', (
      tester,
    ) async {
      final repository = _FailingRepository(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'OBS broadcasting is temporarily disabled.',
        ),
      );
      await _pumpSheet(tester, repository: repository, locale: Locale('en'));
      final provision = find.byKey(const ValueKey('server-obs-provision'));
      await tester.ensureVisible(provision);
      await tester.tap(provision);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-obs-error')), findsOneWidget);

      repository.failure = null;
      await tester.ensureVisible(provision);
      await tester.tap(provision);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(repository.calls, hasLength(2));
      expect(find.byKey(const ValueKey('server-obs-error')), findsNothing);
      expect(find.text('rtmps://ingress.example.test/live'), findsOneWidget);
      expect(find.text('private-stream-key'), findsNothing);
    });
  });
}
