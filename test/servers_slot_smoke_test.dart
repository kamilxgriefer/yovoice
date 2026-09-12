// Home "Tu i teraz" — Foundation, brief §4 M18. Content slot 13 mounts
// `ServersScreen(isRootTab: true)` as-is. This Home-side smoke proves the
// destination renders an honest state for an account holding only legacy
// clubs — loading, error with retry, empty, list — and that its create entry
// leads into the feature's own flow, where the server-side gate is reported
// (`test/server_creation_gate_test.dart`, owned by the Servers program).
// Nothing here edits `lib/features/servers/**`; the fake repository
// implements only what the directory reads.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/screens/create_server_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

/// Only `watchMyServers` is real; anything else the directory might reach
/// for is a test failure, which is the point: opening Serwery reads, it
/// never creates, migrates or joins anything.
class _LegacyClubsRepository implements ServerRepository {
  _LegacyClubsRepository(this.stream);
  Stream<List<Server>> stream;
  int subscriptions = 0;

  @override
  Stream<List<Server>> watchMyServers() {
    subscriptions++;
    return stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not needed to render the Serwery destination',
  );
}

/// A club document exactly as `users/{uid}/clubs` mirrors it today: no
/// `serverSchemaVersion`, a `type` of community or family.
Server _legacyClub(
  String id,
  String name, {
  String type = 'community',
  int members = 12,
}) => Server.fromMap(id, {
  'name': name,
  'ownerId': 'owner',
  'type': type,
  'memberCount': members,
});

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('pl'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pump();
}

Finder get _create => find.byKey(const ValueKey('servers-create'));
Finder _tile(String id) => find.byKey(ValueKey('server-directory-$id'));

void main() {
  testWidgets('loading: a spinner with a spoken label, no app bar, nothing '
      'pretending to be empty', (tester) async {
    final pending = StreamController<List<Server>>();
    addTearDown(pending.close);
    final repository = _LegacyClubsRepository(pending.stream);
    await _pump(
      tester,
      ServersScreen(repository: repository, isRootTab: true),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Wczytywanie serwerów',
      ),
      findsOneWidget,
    );
    expect(find.byType(AppBar), findsNothing, reason: 'the shell owns chrome');
    expect(find.byType(YoEmptyState), findsNothing);
    expect(find.byType(YoErrorState), findsNothing);
    expect(_create, findsNothing, reason: 'nothing to act on yet');
    expect(repository.subscriptions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error: an error with retry, never an empty page; retry '
      'resubscribes and then shows the clubs', (tester) async {
    final repository = _LegacyClubsRepository(
      Stream<List<Server>>.error(StateError('offline')),
    );
    await _pump(
      tester,
      ServersScreen(repository: repository, isRootTab: true),
    );
    await tester.pump();

    expect(find.byType(YoErrorState), findsOneWidget);
    expect(find.text('Spróbuj ponownie'), findsOneWidget);
    expect(find.byType(YoEmptyState), findsNothing);
    expect(_create, findsNothing);
    expect(repository.subscriptions, 1);

    repository.stream = Stream.value([_legacyClub('club-1', 'Nasz dom')]);
    await tester.tap(find.text('Spróbuj ponownie'));
    await tester.pumpAndSettle();
    expect(repository.subscriptions, 2, reason: 'retry opens a new stream');
    expect(find.byType(YoErrorState), findsNothing);
    expect(_tile('club-1'), findsOneWidget);
    expect(find.text('Nasz dom'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty: the honest empty state and an enabled create entry', (
    tester,
  ) async {
    final repository = _LegacyClubsRepository(Stream.value(const []));
    await _pump(
      tester,
      ServersScreen(repository: repository, isRootTab: true),
    );
    await tester.pump();

    expect(find.text('Serwery'), findsOneWidget);
    expect(find.byType(YoEmptyState), findsOneWidget);
    expect(find.text('Twoje miejsce na wspólne rozmowy'), findsOneWidget);
    expect(find.byType(YoErrorState), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(_create, findsOneWidget);
    expect(tester.widget<FilledButton>(_create).enabled, isTrue);
    expect(tester.getSize(_create).height, greaterThanOrEqualTo(48));
    expect(find.text('Stwórz serwer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    testWidgets('list at ${size.width.toInt()}: only the account\'s legacy '
        'clubs, as real tiles, nothing invented', (tester) async {
      final clubs = [
        _legacyClub('club-1', 'Nasz dom', type: 'family', members: 12),
        _legacyClub('club-2', 'Po godzinach', members: 128),
      ];
      expect(clubs.every((club) => club.isLegacy), isTrue);
      final repository = _LegacyClubsRepository(Stream.value(clubs));
      await _pump(
        tester,
        ServersScreen(repository: repository, isRootTab: true),
        size: size,
      );
      await tester.pump();

      expect(_tile('club-1'), findsOneWidget);
      expect(_tile('club-2'), findsOneWidget);
      expect(find.text('Nasz dom'), findsOneWidget);
      expect(find.text('Po godzinach'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('server-directory-club-3')),
        findsNothing,
      );
      expect(find.byType(YoEmptyState), findsNothing);
      expect(find.byType(YoErrorState), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(_create, findsOneWidget);
      expect(repository.subscriptions, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('create opens the feature\'s own flow; opening it creates '
      'nothing', (tester) async {
    final repository = _LegacyClubsRepository(
      Stream.value([_legacyClub('club-1', 'Nasz dom')]),
    );
    await _pump(
      tester,
      ServersScreen(repository: repository, isRootTab: true),
    );
    await tester.pump();

    await tester.tap(_create);
    await tester.pumpAndSettle();
    // The selector is the gate's front door: the refusal itself is the
    // feature's (server-side, rendered by CreateServerScreen), never Home's.
    expect(find.byType(CreateServerScreen), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'the repository was not asked to create, allocate or store',
    );
  });

  testWidgets('pushed as a mobile route the same screen carries an app bar', (
    tester,
  ) async {
    final repository = _LegacyClubsRepository(Stream.value(const []));
    await _pump(tester, ServersScreen(repository: repository));
    await tester.pump();

    expect(find.byType(AppBar), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Serwery')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
