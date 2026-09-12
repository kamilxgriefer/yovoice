// Fix round 1 for the independent selector review (S-1 .. S-15).
//
// QA4–QA10 in `server_selector_independent_qa_test.dart` are the reviewer's
// own reference assertions and are un-pended there. This file adds the cases
// the review asked for beyond those probes: one case per backend code (S-5),
// the per-template allowance line (S-6), the configuration step's three
// arrangements at the six acceptance widths (S-7), the durable idempotency
// record across the screen boundary (S-8), the wash stop (S-10), the readable
// link (S-11), mirroring (S-12), Polish plural forms (S-13) and the decoupled
// medium card (S-14). S-15 lives in `server_creation_gate_test.dart`.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/servers/data/models/server_creation.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_creation_request_store.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/screens/create_server_screen.dart';
import 'package:yovoice/features/servers/presentation/server_localized_copy.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_template_selector.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_type_symbol.dart';

import 'server_test_support.dart';

Finder get _submit => find.byKey(const ValueKey('server-create-submit'));
Finder get _name => find.byKey(const ValueKey('server-name'));
Finder get _errorPanel => find.byKey(const ValueKey('server-create-error'));
Finder _card(ServerType type) =>
    find.byKey(ValueKey('server-template-${type.name}'));

bool _nameEnabled(WidgetTester tester) =>
    tester
        .widget<TextField>(
          find.descendant(of: _name, matching: find.byType(TextField)),
        )
        .enabled ??
    true;

Future<void> _fillAndSubmit(
  WidgetTester tester, {
  String name = 'Nasza ekipa',
}) async {
  await tester.enterText(_name, name);
  await tester.ensureVisible(_submit);
  await tester.tap(_submit);
  await tester.pumpAndSettle();
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + .05) / (lb + .05) : (lb + .05) / (la + .05);
}

ServerCreationRequest _request(
  String id, {
  ServerType type = ServerType.friends,
  String name = 'Nasza ekipa',
}) => ServerCreationRequest(
  requestId: id,
  serverType: type,
  name: name,
  description: '',
  privacy: ServerPrivacy.inviteOnly,
  defaultLanguage: 'Polish',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('S-5 the refusals creation.js actually raises', () {
    test('each code has its own named state and none resends the payload', () {
      const named = <String, ServerCreationFailure>{
        'failed-precondition': ServerCreationFailure.precondition,
        'permission-denied': ServerCreationFailure.denied,
        'invalid-argument': ServerCreationFailure.rejected,
        'data-loss': ServerCreationFailure.lost,
      };
      for (final entry in named.entries) {
        final failure = classifyServerCreationFailure(
          FirebaseFunctionsException(code: entry.key, message: 'refused'),
        );
        expect(failure, entry.value, reason: entry.key);
        expect(failure.isRetryable, isFalse, reason: entry.key);
        expect(failure.resolvesRequest, isTrue, reason: entry.key);
      }
      // Terminal: submit disarmed. Correctable: the form unlocks instead.
      expect(ServerCreationFailure.precondition.isTerminal, isTrue);
      expect(ServerCreationFailure.denied.isTerminal, isTrue);
      expect(ServerCreationFailure.lost.isTerminal, isTrue);
      expect(ServerCreationFailure.rejected.isTerminal, isFalse);
      expect(ServerCreationFailure.rejected.isCorrectable, isTrue);
      // The uncertain outcomes keep their identity resumable.
      expect(ServerCreationFailure.offline.resolvesRequest, isFalse);
      expect(ServerCreationFailure.unknown.resolvesRequest, isFalse);
      expect(ServerCreationFailure.signedOut.resolvesRequest, isFalse);
      // The honest gate-off mapping is untouched.
      expect(
        classifyServerCreationFailure(
          FirebaseFunctionsException(code: 'not-found', message: 'absent'),
        ),
        ServerCreationFailure.unavailable,
      );
      expect(ServerCreationFailure.unavailable.isRetryable, isTrue);
    });

    testWidgets('failed-precondition on family names the existing server', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..alwaysFailWith = FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Your existing family server must be recovered first.',
        );
      var created = 0;
      await pumpServers(
        tester,
        CreateServerScreen(
          repository: repository,
          initialType: ServerType.family,
          onCreated: (_) => created++,
        ),
        size: const Size(768, 1800),
      );
      await _fillAndSubmit(tester, name: 'Nasz dom');

      expect(created, 0);
      expect(_errorPanel, findsOneWidget);
      expect(
        find.text(
          'Masz już serwer rodzinny — może być tylko jeden. Otwórz go z listy '
          'serwerów zamiast tworzyć nowy. Nic nie zostało utworzone.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('must be recovered'), findsNothing);
      expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
      expect(_nameEnabled(tester), isFalse);
      // Refused before any write: nothing is left pending for re-entry.
      expect(repository.pendingCreations, isEmpty);
      expect(repository.requests.length, 1);
    });

    testWidgets('failed-precondition elsewhere does not mention family', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..alwaysFailWith = FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'refused',
        );
      await pumpServers(
        tester,
        CreateServerScreen(
          repository: repository,
          initialType: ServerType.company,
          onCreated: (_) {},
        ),
        size: const Size(768, 1800),
      );
      await _fillAndSubmit(tester);
      expect(find.textContaining('serwer rodzinny'), findsNothing);
      expect(
        find.text(
          'Ten serwer nie może teraz powstać. Nic nie zostało utworzone — '
          'wróć do serwerów i sprawdź te, które już masz.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
    });

    for (final entry in const {
      'permission-denied':
          'To konto nie może teraz tworzyć serwerów. Nic nie zostało '
          'utworzone — sprawdź, czy jesteś na właściwym koncie.',
      'data-loss':
          'Nic nowego nie powstało. Wróć do serwerów — to wymaga naprawy po '
          'naszej stronie, nie kolejnej próby stąd.',
    }.entries) {
      testWidgets('${entry.key} disarms the action and names the next step', (
        tester,
      ) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()
          ..alwaysFailWith = FirebaseFunctionsException(
            code: entry.key,
            message: 'RAW BACKEND TEXT',
          );
        var created = 0;
        await pumpServers(
          tester,
          CreateServerScreen(
            repository: repository,
            initialType: ServerType.friends,
            onCreated: (_) => created++,
          ),
          size: const Size(768, 1800),
        );
        await _fillAndSubmit(tester);
        expect(created, 0);
        expect(_errorPanel, findsOneWidget);
        expect(find.text(entry.value), findsOneWidget);
        expect(find.textContaining('RAW BACKEND TEXT'), findsNothing);
        expect(
          find.text('Wszystko, co wpisujesz, zostaje na miejscu.'),
          findsNothing,
        );
        expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
        expect(_nameEnabled(tester), isFalse);
        expect(repository.pendingCreations, isEmpty);
        // The identical payload is never resent behind the person's back.
        await tester.tap(_submit, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(repository.requests.length, 1);
      });
    }

    testWidgets(
      'invalid-argument unlocks the form; a corrected payload is a new request',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()
          ..alwaysFailWith = FirebaseFunctionsException(
            code: 'invalid-argument',
            message: 'name rejected',
          );
        final created = <ServerCreationResult>[];
        await pumpServers(
          tester,
          CreateServerScreen(
            repository: repository,
            initialType: ServerType.friends,
            onCreated: created.add,
          ),
          size: const Size(768, 1800),
        );
        await _fillAndSubmit(tester, name: 'Zła nazwa');

        expect(created, isEmpty);
        expect(_errorPanel, findsOneWidget);
        expect(
          find.text(
            'Serwer nie powstał — coś w nazwie lub opisie nie zostało przyjęte. '
            'Popraw i wyślij ponownie.',
          ),
          findsOneWidget,
        );
        // The one code where editing helps: every field is open again and the
        // action is a fresh "create", not a resend of the refused payload.
        expect(_nameEnabled(tester), isTrue);
        expect(
          find.descendant(of: _submit, matching: find.text('Stwórz serwer')),
          findsOneWidget,
        );
        expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
        expect(
          find.text('Wszystko, co wpisujesz, zostaje na miejscu.'),
          findsOneWidget,
        );
        // A rejected payload was never committed, so nothing stays pending.
        expect(repository.pendingCreations, isEmpty);

        repository.alwaysFailWith = null;
        await _fillAndSubmit(tester, name: 'Poprawiona nazwa');
        expect(repository.requests.length, 2);
        expect(repository.requests[1].name, 'Poprawiona nazwa');
        expect(
          repository.requests[1].requestId,
          isNot(repository.requests[0].requestId),
          reason: 'a corrected payload must not travel under the refused id',
        );
        expect(repository.allocated, 2);
        expect(created.single.serverId, 'saved');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'R-1 a rejected payload does not follow the person to another template',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()
          ..alwaysFailWith = FirebaseFunctionsException(
            code: 'invalid-argument',
            message: 'name rejected',
          );
        await pumpServers(
          tester,
          CreateServerScreen(
            repository: repository,
            initialType: ServerType.friends,
            onCreated: (_) {},
          ),
          size: const Size(768, 1800),
        );
        await _fillAndSubmit(tester, name: 'Zła nazwa');
        expect(_errorPanel, findsOneWidget);
        expect(_nameEnabled(tester), isTrue, reason: 'unlocked for correction');

        // Unlocked, so the template can change. The refusal answered the
        // friends attempt only; the untouched podcast form starts clean.
        await tester.ensureVisible(find.text('Zmień szablon'));
        await tester.tap(find.text('Zmień szablon'));
        await tester.pumpAndSettle();
        expect(_errorPanel, findsNothing, reason: 'selector shows no refusal');
        await tester.ensureVisible(_card(ServerType.podcast));
        await tester.tap(_card(ServerType.podcast));
        await tester.pumpAndSettle();
        expect(find.text('Dla podcastu'), findsWidgets);
        expect(repository.requests.length, 1, reason: 'nothing submitted yet');
        expect(_errorPanel, findsNothing);
        expect(
          find.textContaining('nie zostało przyjęte'),
          findsNothing,
          reason: 'the friends refusal must not open the podcast form',
        );
        expect(find.byKey(const ValueKey('server-create-resumed')), findsNothing);
        expect(_nameEnabled(tester), isTrue);
        expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
        expect(
          find.descendant(of: _submit, matching: find.text('Stwórz serwer')),
          findsOneWidget,
        );

        // Back to the refused template: still a fresh form, not a replay of
        // the panel — only a new attempt from here can raise one again.
        await tester.ensureVisible(find.text('Zmień szablon'));
        await tester.tap(find.text('Zmień szablon'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(_card(ServerType.friends));
        await tester.tap(_card(ServerType.friends));
        await tester.pumpAndSettle();
        expect(_errorPanel, findsNothing);
        expect(repository.requests.length, 1);
        expect(repository.pendingCreations, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('S-6 the allowance line tells each template the truth', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const twenty = 'Możesz bezpłatnie utworzyć do 20 serwerów.';
    const family =
        'Serwer rodzinny może być tylko jeden. Nie wlicza się do 20 '
        'bezpłatnych serwerów.';
    for (final type in ServerType.values) {
      await pumpServers(
        tester,
        CreateServerScreen(
          key: UniqueKey(),
          repository: TestServerRepository(),
          initialType: type,
        ),
        size: const Size(768, 1800),
      );
      final line = find.byKey(const ValueKey('server-create-allowance'));
      expect(line, findsOneWidget, reason: type.name);
      if (type == ServerType.family) {
        // FAMILY_SERVER_LIMIT is 1 (functions/servers/capacity.js:21).
        expect(find.text(family), findsOneWidget);
        expect(find.text(twenty), findsNothing);
      } else {
        expect(find.text(twenty), findsOneWidget, reason: type.name);
        expect(find.text(family), findsNothing, reason: type.name);
      }
    }
  });

  group('S-7 the configuration step has three arrangements', () {
    testWidgets('one column below 1100, form beside the preview from 1100', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Where the one-column form starts below the body's top edge, measured
      // at 768 (medium, pushed as a route with its app bar); the wide frame
      // must start at the same offset instead of floating to the middle.
      double? oneColumnHeaderTop;
      for (final width in [320.0, 390.0, 768.0, 1100.0, 1440.0, 1920.0]) {
        await pumpServers(
          tester,
          CreateServerScreen(
            key: UniqueKey(),
            repository: TestServerRepository(),
            initialType: ServerType.company,
            isRootTab: width >= 1100,
          ),
          size: Size(width, 1600),
        );
        final appBar = find.byType(AppBar);
        final bodyTop = appBar.evaluate().isEmpty
            ? 0.0
            : tester.getRect(appBar).bottom;
        final header = tester.getRect(find.text('Dla firmy').first);
        final headerOffset = header.top - bodyTop;
        if (width == 768) oneColumnHeaderTop = headerOffset;
        final name = tester.getRect(_name);
        final language = tester.getRect(
          find.byKey(const ValueKey('server-language')),
        );
        final preview = tester.getRect(
          find.byKey(const ValueKey('server-seeded-channels')),
        );
        final starting = tester.getRect(
          find.byKey(const ValueKey('server-create-starting-point')),
        );
        final submit = tester.getRect(_submit);
        final reason = 'width $width';
        expect(preview.left, greaterThanOrEqualTo(0), reason: reason);
        expect(preview.right, lessThanOrEqualTo(width), reason: reason);
        if (width < ServerConfigurationMetrics.wideBreakpoint) {
          // Narrow and medium: the preview follows the fields in one column.
          expect(preview.top, greaterThan(language.bottom), reason: reason);
          expect(starting.top, greaterThan(preview.bottom), reason: reason);
          expect(
            preview.left,
            moreOrLessEquals(name.left, epsilon: 1),
            reason: reason,
          );
          expect(
            find.byKey(const ValueKey('server-create-aside-scroll')),
            findsNothing,
          );
        } else {
          // Wide: the form on the left, the preview beside it and visible
          // from the first line, the action bar spanning the whole frame.
          expect(preview.left, greaterThan(name.right), reason: reason);
          expect(preview.top, lessThan(name.bottom), reason: reason);
          expect(
            preview.left - name.right,
            moreOrLessEquals(ServerConfigurationMetrics.gutter, epsilon: 1),
            reason: reason,
          );
          expect(
            name.width,
            moreOrLessEquals(
              ServerConfigurationMetrics.formColumnWidth,
              epsilon: 1,
            ),
            reason: reason,
          );
          expect(
            preview.width,
            moreOrLessEquals(ServerConfigurationMetrics.asideWidth, epsilon: 1),
            reason: reason,
          );
          expect(starting.top, greaterThan(preview.bottom), reason: reason);
          expect(starting.left, moreOrLessEquals(preview.left, epsilon: 1));
          // Centred frame, not a left-hugging phone column.
          expect(
            name.left,
            moreOrLessEquals(width - preview.right, epsilon: 2),
            reason: reason,
          );
          expect(submit.left, lessThanOrEqualTo(name.left + 1), reason: reason);
          expect(
            submit.right,
            greaterThanOrEqualTo(preview.right - 1),
            reason: reason,
          );
          expect(
            find.byKey(const ValueKey('server-create-aside-scroll')),
            findsOneWidget,
          );
          // Top-aligned on a tall viewport: both columns are shorter than
          // 1600 px, so a vertically centred frame would sit hundreds of
          // pixels lower than the one-column form does.
          expect(
            headerOffset,
            moreOrLessEquals(oneColumnHeaderTop!, epsilon: 4),
            reason:
                '$reason: wide header ${headerOffset.toStringAsFixed(0)} px '
                'below the body top, one-column header '
                '${oneColumnHeaderTop.toStringAsFixed(0)} px',
          );
        }
        expect(submit.bottom, lessThanOrEqualTo(1600), reason: reason);
        expect(tester.takeException(), isNull, reason: reason);
      }
    });

    testWidgets('the wide frame starts at the top whatever the height', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<double> headerTop(Size size) async {
        await pumpServers(
          tester,
          CreateServerScreen(
            key: UniqueKey(),
            repository: TestServerRepository(),
            initialType: ServerType.company,
            isRootTab: true,
          ),
          size: size,
        );
        return tester.getRect(find.text('Dla firmy').first).top;
      }

      final oneColumn = await headerTop(const Size(768, 1600));
      // Short and tall, with the columns shorter and longer than the body.
      for (final size in const [
        Size(1100, 1600),
        Size(1440, 1600),
        Size(1920, 1400),
        Size(1440, 900),
        Size(1920, 700),
      ]) {
        final top = await headerTop(size);
        expect(
          top,
          moreOrLessEquals(oneColumn, epsilon: 4),
          reason:
              '${size.width.toInt()}x${size.height.toInt()}: wide header at '
              '${top.toStringAsFixed(0)} px, one-column header at '
              '${oneColumn.toStringAsFixed(0)} px',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
      'the wide arrangement survives 200 percent text and both themes',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final light in [false, true]) {
          for (final width in [1100.0, 1440.0, 1920.0]) {
            await pumpServers(
              tester,
              CreateServerScreen(
                key: UniqueKey(),
                repository: TestServerRepository(),
                initialType: ServerType.podcast,
                isRootTab: true,
              ),
              size: Size(width, 700),
              textScale: 2,
              light: light,
            );
            final preview = tester.getRect(
              find.byKey(const ValueKey('server-seeded-channels')),
            );
            final name = tester.getRect(_name);
            expect(preview.left, greaterThan(name.right), reason: '$width');
            expect(preview.right, lessThanOrEqualTo(width), reason: '$width');
            // The aside scrolls on its own, so the long preview never pushes
            // the action bar off the short viewport.
            expect(tester.getRect(_submit).bottom, lessThanOrEqualTo(700));
            await tester.ensureVisible(
              find.byKey(const ValueKey('server-create-starting-point')),
            );
            expect(tester.takeException(), isNull, reason: '$width / $light');
          }
        }
      },
    );

    testWidgets('the wide form still submits and locks like the narrow one', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()..failNext = true;
      await pumpServers(
        tester,
        CreateServerScreen(
          repository: repository,
          initialType: ServerType.friends,
          isRootTab: true,
          onCreated: (_) {},
        ),
        size: const Size(1440, 900),
      );
      await _fillAndSubmit(tester);
      expect(_errorPanel, findsOneWidget);
      expect(_nameEnabled(tester), isFalse);
      expect(repository.requests.single.name, 'Nasza ekipa');
      expect(
        find.descendant(of: _submit, matching: find.text('Wyślij ponownie')),
        findsOneWidget,
      );
    });
  });

  group('S-8 the idempotency promise holds across the screen boundary', () {
    testWidgets(
      'an unresolved submission is resumed on re-entry with the same id',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()..failNext = true;
        final created = <ServerCreationResult>[];
        await pumpServers(
          tester,
          CreateServerScreen(
            repository: repository,
            initialType: ServerType.friends,
            onCreated: created.add,
          ),
          size: const Size(768, 1800),
        );
        await _fillAndSubmit(tester);
        expect(_errorPanel, findsOneWidget);
        // Committed before the network write, so it already outlives the widget.
        expect(
          repository.pendingCreations.values.single.requestId,
          'request-1',
        );

        // Leave the screen entirely and come back to the same template.
        await tester.pumpWidget(const SizedBox());
        await pumpServers(
          tester,
          CreateServerScreen(
            repository: repository,
            initialType: ServerType.friends,
            onCreated: created.add,
          ),
          size: const Size(768, 1800),
        );
        expect(
          find.byKey(const ValueKey('server-create-resumed')),
          findsOneWidget,
        );
        expect(
          find.text(
            'Ostatnia próba utworzenia tego serwera nie została potwierdzona. '
            'Wyślij ponownie — to bezpieczne i nie utworzy drugiego serwera.',
          ),
          findsOneWidget,
        );
        expect(_errorPanel, findsNothing);
        expect(_nameEnabled(tester), isFalse);
        expect(find.text('Nasza ekipa'), findsOneWidget);
        expect(
          find.descendant(of: _submit, matching: find.text('Wyślij ponownie')),
          findsOneWidget,
        );

        await tester.ensureVisible(_submit);
        await tester.tap(_submit);
        await tester.pumpAndSettle();
        expect(repository.requests.length, 2);
        expect(repository.requests[1].requestId, 'request-1');
        expect(repository.requests[1].name, 'Nasza ekipa');
        expect(
          repository.allocated,
          1,
          reason: 'one identity across two screens',
        );
        expect(created.single.serverId, 'saved');
        expect(repository.pendingCreations, isEmpty, reason: 'resolved');
      },
    );

    testWidgets('a pending record is scoped to its template', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..pendingCreations['owner/friends'] = _request('older');
      await pumpServers(
        tester,
        CreateServerScreen(
          repository: repository,
          initialType: ServerType.podcast,
        ),
        size: const Size(768, 1800),
      );
      expect(find.byKey(const ValueKey('server-create-resumed')), findsNothing);
      expect(_nameEnabled(tester), isTrue);
    });

    for (final entry in const {
      'not-found': false,
      'failed-precondition': false,
      'permission-denied': false,
      'invalid-argument': false,
      'data-loss': false,
      'unavailable': true,
      'internal': true,
      'unauthenticated': true,
    }.entries) {
      testWidgets(
        '${entry.key} ${entry.value ? 'keeps' : 'clears'} the pending record',
        (tester) async {
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final repository = TestServerRepository()
            ..alwaysFailWith = FirebaseFunctionsException(
              code: entry.key,
              message: 'x',
            );
          await pumpServers(
            tester,
            CreateServerScreen(
              repository: repository,
              initialType: ServerType.friends,
              onCreated: (_) {},
            ),
            size: const Size(768, 1800),
          );
          await _fillAndSubmit(tester);
          expect(
            repository.pendingCreations.isNotEmpty,
            entry.value,
            reason: entry.key,
          );
        },
      );
    }

    testWidgets(
      'a store that cannot be read or written never blocks creation',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = TestServerRepository()..failPendingStore = true;
        final created = <ServerCreationResult>[];
        await pumpServers(
          tester,
          CreateServerScreen(
            repository: repository,
            initialType: ServerType.friends,
            onCreated: created.add,
          ),
          size: const Size(768, 1800),
        );
        await _fillAndSubmit(tester);
        expect(created.single.serverId, 'saved');
        expect(repository.requests.length, 1);
        expect(tester.takeException(), isNull);
      },
    );

    // Plain `test`, not `testWidgets`: the store and the auth mock resolve
    // through real microtasks and timers, which a FakeAsync zone never runs.
    test(
      'the durable store scopes by owner and template, prunes by TTL, forgets by id',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = SharedPreferencesServerCreationRequestStore();
        final t0 = DateTime(2026, 9, 12, 3);
        const ttl = Duration(hours: 24);

        expect(
          await store.load(
            ownerId: 'a',
            type: ServerType.friends,
            now: t0,
            ttl: ttl,
          ),
          isNull,
        );
        final kept = await store.remember(
          ownerId: 'a',
          request: _request('first'),
          now: t0,
        );
        expect(kept.requestId, 'first');
        // An earlier unresolved request for the same scope wins over a new one.
        final again = await store.remember(
          ownerId: 'a',
          request: _request('second', name: 'Inna nazwa'),
          now: t0,
        );
        expect(again.requestId, 'first');
        expect(again.name, 'Nasza ekipa');
        // Other owners and other templates see nothing.
        expect(
          await store.load(
            ownerId: 'b',
            type: ServerType.friends,
            now: t0,
            ttl: ttl,
          ),
          isNull,
        );
        expect(
          await store.load(
            ownerId: 'a',
            type: ServerType.podcast,
            now: t0,
            ttl: ttl,
          ),
          isNull,
        );
        final loaded = await store.load(
          ownerId: 'a',
          type: ServerType.friends,
          now: t0.add(const Duration(hours: 23)),
          ttl: ttl,
        );
        expect(loaded?.requestId, 'first');
        expect(loaded?.toCallableData(), _request('first').toCallableData());
        // Forgetting checks the id, so a late older screen cannot clear a newer one.
        await store.forget(
          ownerId: 'a',
          type: ServerType.friends,
          expectedRequestId: 'other',
        );
        expect(
          (await store.load(
            ownerId: 'a',
            type: ServerType.friends,
            now: t0,
            ttl: ttl,
          ))?.requestId,
          'first',
        );
        await store.forget(
          ownerId: 'a',
          type: ServerType.friends,
          expectedRequestId: 'first',
        );
        expect(
          await store.load(
            ownerId: 'a',
            type: ServerType.friends,
            now: t0,
            ttl: ttl,
          ),
          isNull,
        );
        // Stale records are pruned by the TTL.
        await store.remember(ownerId: 'a', request: _request('old'), now: t0);
        expect(
          await store.load(
            ownerId: 'a',
            type: ServerType.friends,
            now: t0.add(ttl),
            ttl: ttl,
          ),
          isNull,
        );
        // A corrupt record reads as nothing pending rather than crashing.
        SharedPreferences.setMockInitialValues({
          SharedPreferencesServerCreationRequestStore.storageKey: '{not json',
        });
        expect(
          await SharedPreferencesServerCreationRequestStore().load(
            ownerId: 'a',
            type: ServerType.friends,
            now: t0,
            ttl: ttl,
          ),
          isNull,
        );
      },
    );

    test('ServerService keys the record by the signed-in owner', () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime(2026, 9, 12, 3);
      ServerService serviceFor(String uid) => ServerService(
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid)),
        pendingStore: SharedPreferencesServerCreationRequestStore(),
        now: () => now,
      );
      final mine = serviceFor('u');
      final theirs = serviceFor('v');
      expect(await mine.pendingCreation(ServerType.family), isNull);
      await mine.rememberPendingCreation(
        _request('r', type: ServerType.family),
      );
      expect((await mine.pendingCreation(ServerType.family))?.requestId, 'r');
      expect(await theirs.pendingCreation(ServerType.family), isNull);
      await mine.forgetPendingCreation(_request('r', type: ServerType.family));
      expect(await mine.pendingCreation(ServerType.family), isNull);
    });
  });

  testWidgets('S-10 the card wash fades out by 75 percent, 90 on hover', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(1440, 1200),
    );
    LinearGradient wash() =>
        (tester.widget<AnimatedContainer>(_card(ServerType.friends)).decoration!
                    as BoxDecoration)
                .gradient!
            as LinearGradient;
    expect(wash().stops, [0, .75]);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(_card(ServerType.friends)));
    await tester.pumpAndSettle();
    expect(wash().stops, [0, .9]);
  });

  testWidgets('S-11 every card link reaches 4.5:1 on the tinted card', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
      size: const Size(1440, 1200),
    );
    for (final type in ServerType.values) {
      final visuals = ServerIdentity.of(type).resolve(Brightness.dark);
      final link = tester.widget<Text>(
        find.descendant(of: _card(type), matching: find.text('Wybierz')),
      );
      final ink = link.style!.color!;
      // Worst case on the card: the strongest (hover) wash over the fill.
      final tinted = Color.alphaBlend(
        visuals.selectedWash,
        AppPalette.dark.surfaceMuted,
      );
      expect(
        _contrast(ink, tinted),
        greaterThanOrEqualTo(4.5),
        reason: '$type',
      );
      expect(
        _contrast(ink, AppPalette.dark.surfaceMuted),
        greaterThanOrEqualTo(4.5),
        reason: '$type',
      );
      if (type != ServerType.community) {
        expect(ink, visuals.foreground, reason: '$type keeps its accent');
      }
    }
  });

  testWidgets('S-12 the selector mirrors in a right-to-left layout', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Finder orbit(ServerType type) => find.descendant(
      of: _card(type),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints ==
                const BoxConstraints.tightFor(width: 190, height: 190),
      ),
    );
    for (final rtl in [false, true]) {
      for (final width in [390.0, 1440.0]) {
        await pumpServers(
          tester,
          Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
          ),
          size: Size(width, 1400),
        );
        final card = tester.getRect(_card(ServerType.friends));
        final ring = tester.getRect(orbit(ServerType.friends));
        final reason = 'rtl=$rtl width=$width';
        if (rtl) {
          // `right:-64px` becomes the start edge: the ring hangs off the left.
          expect(ring.left, lessThan(card.left), reason: reason);
          expect(ring.right, lessThan(card.right - 100), reason: reason);
          expect(
            find.byIcon(Icons.north_west_rounded),
            findsNWidgets(5),
            reason: reason,
          );
          expect(
            find.byIcon(Icons.north_east_rounded),
            findsNothing,
            reason: reason,
          );
          // The compact row mirrors too: the symbol sits at the start.
          if (width <= 640) {
            final symbol = tester.getRect(
              find.descendant(
                of: _card(ServerType.friends),
                matching: find.byType(ServerTypeSymbol),
              ),
            );
            expect(
              symbol.center.dx,
              greaterThan(card.center.dx),
              reason: reason,
            );
          }
        } else {
          expect(ring.right, greaterThan(card.right), reason: reason);
          expect(
            find.byIcon(Icons.north_east_rounded),
            findsNWidgets(5),
            reason: reason,
          );
          expect(
            find.byIcon(Icons.north_west_rounded),
            findsNothing,
            reason: reason,
          );
        }
        expect(tester.takeException(), isNull, reason: reason);
      }
    }
  });

  testWidgets('S-13 member counts use the three Polish forms', (tester) async {
    late AppLocalizations copy;
    await pumpServers(
      tester,
      Builder(
        builder: (context) {
          copy = AppLocalizations.of(context);
          return const SizedBox();
        },
      ),
    );
    expect(copy.isPolish, isTrue);
    expect(copy.serverMembers(1), '1 osoba');
    expect(copy.serverMembers(2), '2 osoby');
    expect(copy.serverMembers(4), '4 osoby');
    expect(copy.serverMembers(5), '5 osób');
    expect(copy.serverMembers(11), '11 osób');
    expect(copy.serverMembers(12), '12 osób');
    expect(copy.serverMembers(14), '14 osób');
    expect(copy.serverMembers(22), '22 osoby');
    expect(copy.serverMembers(25), '25 osób');
    expect(copy.serverMembers(112), '112 osób');
    expect(copy.serverMembers(0), '0 osób');
    const english = AppLocalizations(Locale('en'));
    expect(english.serverMembers(1), '1 person');
    expect(english.serverMembers(12), '12 people');
    // The rewritten strings read as written Polish, not translated.
    expect(
      copy.serverIconBody,
      'Na początek serwer nosi pierwszą literę swojej nazwy — w kolorze szablonu.',
    );
    expect(
      copy.serverCreationRetrySafe,
      'Wszystko, co wpisujesz, zostaje na miejscu.',
    );
    expect(copy.serverInviteIntroTitle, 'Serwer czeka na ludzi');
    expect(
      copy.serverCreationAllowanceBody,
      'Możesz bezpłatnie utworzyć do 20 serwerów.',
    );
  });

  testWidgets('S-14 the medium symbol gap is a layout mode, not a height', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final medium in [false, true]) {
      await pumpServers(
        tester,
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: ServerTemplateCard(
                type: ServerType.friends,
                onPressed: () {},
                medium: medium,
                // Deliberately neither 320 nor 390: the gap must not care.
                minimumHeight: 500,
              ),
            ),
          ),
        ),
        size: const Size(800, 1200),
      );
      final tile = tester.getRect(
        find
            .ancestor(
              of: find.byType(ServerTypeSymbol),
              matching: find.byType(Container),
            )
            .first,
      );
      final title = tester.getRect(find.text('Dla znajomych'));
      expect(
        title.top - tile.bottom,
        moreOrLessEquals(medium ? 22 : 35, epsilon: 4),
        reason: 'medium=$medium',
      );
    }
    expect(ServerSelectorMetrics.sidePadding, 48);
    expect(ServerSelectorMetrics.compactSidePadding, 20);
  });
}
