import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_creation.dart';
import 'package:yovoice/features/servers/data/models/server_template.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/create_server_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/server_localized_copy.dart';

import 'server_test_support.dart';

Finder get _submit => find.byKey(const ValueKey('server-create-submit'));
Finder get _unavailable =>
    find.byKey(const ValueKey('server-create-unavailable'));
Finder get _errorPanel => find.byKey(const ValueKey('server-create-error'));

Future<void> _fillAndSubmit(
  WidgetTester tester, {
  String name = 'Nasza ekipa',
}) async {
  await tester.enterText(find.byKey(const ValueKey('server-name')), name);
  await tester.ensureVisible(_submit);
  await tester.tap(_submit);
  await tester.pumpAndSettle();
}

/// Whether a widget carries the liveness colour token in any of the places a
/// LIVE badge, pill or recording dot would carry it.
bool _paintsLiveness(Widget widget) {
  bool live(Color? color) => color == AppColors.live;
  return switch (widget) {
    Icon(:final color) => live(color),
    Container(:final color, :final decoration) =>
      live(color) ||
          (decoration is BoxDecoration &&
              (live(decoration.color) || live(decoration.border?.top.color))),
    DecoratedBox(:final decoration) =>
      decoration is BoxDecoration &&
          (live(decoration.color) || live(decoration.border?.top.color)),
    Chip(:final backgroundColor) => live(backgroundColor),
    _ => false,
  };
}

void main() {
  group('the held backend is reported honestly', () {
    for (final code in ['not-found', 'unimplemented', 'no-app']) {
      testWidgets('$code renders the unavailable state, never a success', (
        tester,
      ) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()
          ..alwaysFailWith = FirebaseFunctionsException(
            code: code,
            message: 'NOT FOUND',
          );
        var created = 0;
        await pumpServers(
          tester,
          CreateServerScreen(
            repository: repository,
            initialType: ServerType.friends,
            onCreated: (_) => created++,
          ),
        );
        await _fillAndSubmit(tester);

        expect(
          created,
          0,
          reason: 'nothing may report a server that is absent',
        );
        expect(_unavailable, findsOneWidget);
        expect(_errorPanel, findsNothing);
        expect(
          find.text('Tworzenie serwerów nie jest jeszcze dostępne'),
          findsOneWidget,
        );
        expect(find.text('Wkrótce'), findsOneWidget);
        // No raw failure text, and no "try again" that cannot succeed.
        expect(find.textContaining('NOT FOUND'), findsNothing);
        expect(
          find.text('Coś poszło nie tak. Spróbuj ponownie.'),
          findsNothing,
        );
        expect(
          find.descendant(of: _submit, matching: find.text('Sprawdź ponownie')),
          findsOneWidget,
        );
        // Looking again is still allowed: the gate opens server-side.
        expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('checking again reuses the identical request', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..alwaysFailWith = FirebaseFunctionsException(
          code: 'not-found',
          message: 'NOT FOUND',
        );
      await pumpServers(
        tester,
        CreateServerScreen(
          repository: repository,
          initialType: ServerType.friends,
          onCreated: (_) {},
        ),
      );
      await _fillAndSubmit(tester);
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(repository.requests.length, 2);
      expect(identical(repository.requests[0], repository.requests[1]), isTrue);
      expect(repository.allocated, 1, reason: 'one request identity, ever');
      expect(_unavailable, findsOneWidget);
    });

    test(
      'classification separates a missing endpoint from a failed attempt',
      () {
        expect(
          classifyServerCreationFailure(
            FirebaseFunctionsException(code: 'not-found', message: 'absent'),
          ),
          ServerCreationFailure.unavailable,
        );
        expect(
          classifyServerCreationFailure(
            FirebaseFunctionsException(code: 'unavailable', message: 'down'),
          ),
          ServerCreationFailure.offline,
        );
        expect(
          classifyServerCreationFailure(
            FirebaseFunctionsException(
              code: 'resource-exhausted',
              message: 'full',
              details: const {'reason': 'server-capacity-reached'},
            ),
          ),
          ServerCreationFailure.capacityReached,
        );
        expect(
          classifyServerCreationFailure(
            FirebaseFunctionsException(
              code: 'unauthenticated',
              message: 'signed out',
            ),
          ),
          ServerCreationFailure.signedOut,
        );
        expect(
          classifyServerCreationFailure(
            Exception('SocketException: Failed host lookup'),
          ),
          ServerCreationFailure.offline,
        );
        expect(ServerCreationFailure.unavailable.isBackendMissing, isTrue);
        expect(ServerCreationFailure.offline.isBackendMissing, isFalse);
        expect(ServerCreationFailure.capacityReached.isRetryable, isFalse);
        expect(ServerCreationFailure.signedOut.isRetryable, isFalse);
      },
    );
  });

  testWidgets('a spent allowance stops offering a retry that cannot work', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..alwaysFailWith = FirebaseFunctionsException(
        code: 'resource-exhausted',
        message: 'allowance spent',
        details: const {'reason': 'server-capacity-reached'},
      );
    await pumpServers(
      tester,
      CreateServerScreen(
        repository: repository,
        initialType: ServerType.friends,
        onCreated: (_) {},
      ),
    );
    await _fillAndSubmit(tester);

    expect(_errorPanel, findsOneWidget);
    expect(find.text('Masz już 20 aktywnych serwerów.'), findsOneWidget);
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
    expect(repository.requests.length, 1);
  });

  testWidgets('an interrupted attempt keeps one request and invites a retry', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()..failNext = true;
    await pumpServers(
      tester,
      CreateServerScreen(
        repository: repository,
        initialType: ServerType.friends,
        onCreated: (_) {},
      ),
    );
    await _fillAndSubmit(tester);

    expect(_errorPanel, findsOneWidget);
    expect(_unavailable, findsNothing);
    expect(
      find.textContaining('nie utworzy drugiego serwera'),
      findsOneWidget,
      reason: 'a resend must be described as safe',
    );
    expect(
      find.text('Wszystko, co wpisujesz, zostaje na miejscu.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
  });

  testWidgets('a second tap while the first is in flight creates nothing new', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completer = Completer<ServerCreationResult>();
    final repository = TestServerRepository()..pending = completer;
    final created = <ServerCreationResult>[];
    await pumpServers(
      tester,
      CreateServerScreen(
        repository: repository,
        initialType: ServerType.friends,
        onCreated: created.add,
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('server-name')),
      'Nasza ekipa',
    );
    await tester.ensureVisible(_submit);
    await tester.tap(_submit);
    await tester.pump();
    await tester.tap(_submit, warnIfMissed: false);
    await tester.pump();

    expect(repository.requests.length, 1);
    expect(repository.allocated, 1);
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);

    completer.complete(
      const ServerCreationResult(
        serverId: 'saved',
        defaultChannelId: 'general',
        channelIds: ['general'],
        alreadyExisted: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(created.single.serverId, 'saved');
    expect(repository.requests.length, 1);
  });

  testWidgets('the seeded preview shows exactly what the template creates', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final type in ServerType.values) {
      await pumpServers(
        tester,
        CreateServerScreen(
          key: UniqueKey(),
          repository: TestServerRepository(),
          initialType: type,
        ),
        size: const Size(768, 1600),
      );
      expect(
        find.byKey(const ValueKey('server-seeded-channels')),
        findsOneWidget,
      );
      // Default language is English, so the preview must promise the English
      // names the server will actually seed.
      for (final seed in serverTemplateChannelsFor(type)) {
        expect(
          find.text(seed.englishName),
          findsWidgets,
          reason: '${type.name} / ${seed.seedKey}',
        );
      }
      expect(tester.takeException(), isNull, reason: type.name);
    }
  });

  testWidgets('choosing Polish repoints the preview at the Polish seed names', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      CreateServerScreen(
        repository: TestServerRepository(),
        initialType: ServerType.family,
      ),
      size: const Size(768, 1600),
    );
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Kalendarz'), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('server-language')));
    await tester.tap(find.byKey(const ValueKey('server-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Polski').last);
    await tester.pumpAndSettle();

    expect(find.text('Kalendarz'), findsOneWidget);
    expect(find.text('Wspomnienia'), findsOneWidget);
    expect(find.text('Calendar'), findsNothing);
  });

  testWidgets('the two private company channels are shown as limited', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      CreateServerScreen(
        repository: TestServerRepository(),
        initialType: ServerType.company,
      ),
      size: const Size(768, 1600),
    );
    expect(find.text('HR'), findsOneWidget);
    expect(find.text('Management'), findsOneWidget);
    expect(find.text('Ograniczony dostęp'), findsNWidgets(2));
  });

  testWidgets('the icon previews the name and offers no unbuilt upload', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      CreateServerScreen(
        repository: TestServerRepository(),
        initialType: ServerType.friends,
      ),
    );
    final preview = find.byKey(const ValueKey('server-icon-preview'));
    expect(
      find.descendant(of: preview, matching: find.text('YO')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('server-name')),
      'ekipa z osiedla',
    );
    await tester.pump();
    expect(
      find.descendant(of: preview, matching: find.text('E')),
      findsOneWidget,
    );

    final upload = find.byKey(const ValueKey('server-icon-upload'));
    expect(tester.widget<OutlinedButton>(upload).onPressed, isNull);
    expect(find.text('Dodaj obrazek · Wkrótce'), findsOneWidget);
  });

  testWidgets('switching template keeps typed input for all five templates', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository();
    await pumpServers(
      tester,
      CreateServerScreen(
        repository: repository,
        initialType: ServerType.friends,
      ),
      size: const Size(768, 1600),
    );
    await tester.enterText(
      find.byKey(const ValueKey('server-name')),
      'Wspólna przestrzeń naszego zespołu',
    );
    await tester.enterText(
      find.byKey(const ValueKey('server-description')),
      'Opis, który ma przetrwać każdą zmianę szablonu.',
    );

    for (final type in ServerType.values) {
      await tester.ensureVisible(find.text('Zmień szablon'));
      await tester.tap(find.text('Zmień szablon'));
      await tester.pumpAndSettle();
      final card = find.byKey(ValueKey('server-template-${type.name}'));
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(
        find.text('Wspólna przestrzeń naszego zespołu'),
        findsOneWidget,
        reason: type.name,
      );
      expect(
        find.text('Opis, który ma przetrwać każdą zmianę szablonu.'),
        findsOneWidget,
        reason: type.name,
      );
    }
    expect(repository.requests, isEmpty, reason: 'browsing creates nothing');
  });

  testWidgets('long Polish names survive narrow screens at 200 percent', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Exactly the 40 characters `creationInput` accepts for a name, sliced
    // rather than hand-counted so the fixture cannot drift off the limit.
    final longest = ('Zgrana ekipa z osiedla i okolic — Gdańsk i Kraków' * 2)
        .substring(0, 40);
    expect(longest.length, 40);
    for (final light in [false, true]) {
      for (final width in [320.0, 390.0, 768.0, 1440.0]) {
        await pumpServers(
          tester,
          CreateServerScreen(
            key: UniqueKey(),
            repository: TestServerRepository(),
            initialType: ServerType.company,
          ),
          size: Size(width, 1600),
          textScale: 2,
          light: light,
        );
        await tester.enterText(
          find.byKey(const ValueKey('server-name')),
          longest,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$width light=$light');
        final preview = tester.getRect(
          find.byKey(const ValueKey('server-seeded-channels')),
        );
        expect(preview.left, greaterThanOrEqualTo(0));
        expect(preview.right, lessThanOrEqualTo(width));
      }
    }
  });

  testWidgets('configuration never claims to touch a microphone or camera', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final type in ServerType.values) {
      await pumpServers(
        tester,
        CreateServerScreen(
          key: UniqueKey(),
          repository: TestServerRepository(),
          initialType: type,
        ),
        size: const Size(768, 1600),
      );
      expect(
        find.text(
          'Serwer zaczyna się od Ciebie. Mikrofon i kamera pozostają wyłączone.',
        ),
        findsOneWidget,
        reason: type.name,
      );
      // Nothing on this screen may present live activity. The community and
      // podcast templates legitimately seed channels *named* "LIVE Stage" /
      // "Studio LIVE", and the community feature line ("…scena LIVE") is the
      // reference's own approved copy, so a word search proves nothing: the
      // guard is that every text carrying the word is exactly one of those
      // accepted strings, that "NA ŻYWO" appears nowhere, and that nothing
      // paints the liveness colour token a real LIVE badge or dot would carry.
      final copy = AppLocalizations.of(
        tester.element(find.byType(CreateServerScreen)),
      );
      final accepted = <String>{
        for (final seed in serverTemplateChannelsFor(type)) ...[
          seed.englishName,
          seed.polishName,
        ],
        copy.serverTypeFeatures(type),
      };
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final data = text.data ?? text.textSpan?.toPlainText() ?? '';
        if (data.contains('LIVE')) {
          expect(
            accepted,
            contains(data),
            reason:
                '${type.name}: "$data" presents liveness outside a seeded '
                'channel name or the approved feature line',
          );
        }
        expect(data.toUpperCase(), isNot(contains('NA ŻYWO')), reason: data);
        expect(text.style?.color, isNot(AppColors.live), reason: data);
      }
      expect(
        find.byWidgetPredicate(_paintsLiveness),
        findsNothing,
        reason: '${type.name}: a widget paints the LIVE colour token',
      );
    }
  });

  group('arriving in a brand-new server', () {
    Server fixture({required bool held}) => Server(
      id: 's',
      name: 'Nasza ekipa',
      description: '',
      ownerId: 'owner',
      type: ServerType.friends,
      privacy: ServerPrivacy.inviteOnly,
      memberCount: 1,
      schemaVersion: 1,
      activationState: held ? 'held' : 'active',
      status: held ? 'preparing' : 'active',
    );

    testWidgets('the owner is offered the people, narrow and wide', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [390.0, 768.0, 1440.0]) {
        var invited = 0;
        await pumpServers(
          tester,
          ServerWorkspaceScreen(
            key: UniqueKey(),
            serverId: 's',
            repository: TestServerRepository()
              ..servers = [fixture(held: false)],
            onInvite: (_) => invited++,
            justCreated: true,
          ),
          size: Size(width, 900),
        );
        final card = find.byKey(const ValueKey('server-invite-introduction'));
        final action = find.byKey(
          const ValueKey('server-invite-introduction-action'),
        );
        expect(card, findsOneWidget, reason: 'width $width');
        expect(find.text('Serwer czeka na ludzi'), findsOneWidget);
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pump();
        expect(invited, 1, reason: 'width $width');
        expect(tester.takeException(), isNull, reason: 'width $width');
      }
    });

    testWidgets('a held server says so instead of pretending to invite', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var invited = 0;
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()..servers = [fixture(held: true)],
          onInvite: (_) => invited++,
          justCreated: true,
        ),
      );
      final action = find.byKey(
        const ValueKey('server-invite-introduction-action'),
      );
      // No V1 invite writer exists yet, so the offer must be visibly inert.
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
      expect(find.text('Zaproś · Wkrótce'), findsOneWidget);
      expect(invited, 0);
    });

    testWidgets('returning to the server later does not repeat the offer', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()..servers = [fixture(held: false)],
          onInvite: (_) {},
        ),
      );
      expect(
        find.byKey(const ValueKey('server-invite-introduction')),
        findsNothing,
      );
    });
  });
}
