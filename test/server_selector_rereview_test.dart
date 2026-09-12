// RE-REVIEW PROBE — Principal Code and Release Reviewer, 2026-09-12.
//
// Proves or measures the points the re-review of fix round 1 could not settle
// by reading alone. R-1..R-3 assert the behaviour the fixes promise; a failure
// is a finding. R-4..R-6 are OBSERVATIONS: they assert the trap as it exists
// today so the report can cite a measured fact, not a reading.
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_creation.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/create_server_screen.dart';

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

class _HangingStoreRepository extends TestServerRepository {
  final completer = Completer<ServerCreationRequest?>();
  @override
  Future<ServerCreationRequest?> pendingCreation(ServerType type) =>
      completer.future;
}

void main() {
  rereview2();
  testWidgets(
    'R-1 a rejected-payload error does not follow the person to another template',
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
      expect(_nameEnabled(tester), isTrue);

      // The form is unlocked after `rejected`, so the template can change.
      await tester.ensureVisible(find.text('Zmień szablon'));
      await tester.tap(find.text('Zmień szablon'));
      await tester.pumpAndSettle();
      expect(_card(ServerType.podcast), findsOneWidget);
      await tester.ensureVisible(_card(ServerType.podcast));
      await tester.tap(_card(ServerType.podcast));
      await tester.pumpAndSettle();
      expect(find.text('Dla podcastu'), findsWidgets);
      expect(repository.requests.length, 1, reason: 'nothing submitted yet');

      // A template nobody has submitted must not open with a refusal.
      expect(
        _errorPanel,
        findsNothing,
        reason:
            'the invalid-argument message from the friends attempt is shown '
            'on the untouched podcast form',
      );
    },
  );

  testWidgets(
    'R-2 the wide configuration form starts at the top of a tall viewport',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Reference: the one-column arrangement at 768 is top-aligned.
      await pumpServers(
        tester,
        CreateServerScreen(
          key: UniqueKey(),
          repository: TestServerRepository(),
          initialType: ServerType.company,
          isRootTab: true,
        ),
        size: const Size(768, 1600),
      );
      final narrowHeader = tester.getRect(find.text('Dla firmy').first).top;
      final deltas = <String>[];
      for (final size in const [
        Size(1100, 1600),
        Size(1440, 1600),
        Size(1920, 1400),
        Size(1440, 900),
      ]) {
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
        final header = tester.getRect(find.text('Dla firmy').first);
        final name = tester.getRect(_name);
        final preview = tester.getRect(
          find.byKey(const ValueKey('server-seeded-channels')),
        );
        // ignore: avoid_print
        print(
          'R-2 ${size.width.toInt()}x${size.height.toInt()}: header.top='
          '${header.top.toStringAsFixed(1)} name.top='
          '${name.top.toStringAsFixed(1)} preview.top='
          '${preview.top.toStringAsFixed(1)} (narrow header.top='
          '${narrowHeader.toStringAsFixed(1)})',
        );
        if ((header.top - narrowHeader).abs() > 8) {
          deltas.add(
            '${size.width.toInt()}x${size.height.toInt()}: wide header sits '
            'at ${header.top.toStringAsFixed(0)} px, one-column header at '
            '${narrowHeader.toStringAsFixed(0)} px',
          );
        }
      }
      expect(deltas, isEmpty, reason: deltas.join('\n'));
    },
  );

  testWidgets(
    'R-3 when an older pending request wins, the dropdowns show what is sent',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()..failNext = true;
      await pumpServers(
        tester,
        CreateServerScreen(
          repository: repository,
          initialType: ServerType.community,
          onCreated: (_) {},
        ),
        size: const Size(768, 1800),
      );
      // The store answered "nothing pending" at entry. Then an earlier
      // unresolved request for the same owner + template appears (another
      // screen, another tab of the desktop shell, committed it).
      repository.pendingCreations['owner/community'] =
          const ServerCreationRequest(
            requestId: 'older',
            serverType: ServerType.community,
            name: 'Starsza nazwa',
            description: 'Stary opis',
            privacy: ServerPrivacy.private,
            defaultLanguage: 'Polish',
          );
      await tester.enterText(_name, 'Nowa nazwa');
      await tester.tap(find.byKey(const ValueKey('server-privacy-community')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publiczny').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(_submit);
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      final sent = repository.requests.single;
      expect(sent.requestId, 'older');
      expect(sent.privacy, ServerPrivacy.private);
      expect(sent.defaultLanguage, 'Polish');
      expect(_nameEnabled(tester), isFalse, reason: 'locked to the older id');
      // The text fields follow their controllers...
      expect(find.text('Starsza nazwa'), findsOneWidget);
      expect(find.text('Stary opis'), findsOneWidget);
      // ...and the dropdowns must too, or the locked form displays one payload
      // while "Wyślij ponownie" sends another.
      final privacy = tester.widget<DropdownButton<ServerPrivacy>>(
        find.descendant(
          of: find.byKey(const ValueKey('server-privacy-community')),
          matching: find.byType(DropdownButton<ServerPrivacy>),
        ),
      );
      final language = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(const ValueKey('server-language')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(
        privacy.value,
        ServerPrivacy.private,
        reason: 'displayed privacy differs from the privacy that is resent',
      );
      expect(
        language.value,
        'Polish',
        reason: 'displayed language differs from the language that is resent',
      );
    },
  );

  testWidgets(
    'R-4 OBSERVATION an unresolved unknown failure locks the template on '
    're-entry with no discard path',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..alwaysFailWith = FirebaseFunctionsException(
          code: 'internal',
          message: 'boom',
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
      expect(repository.pendingCreations, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      await pumpServers(
        tester,
        CreateServerScreen(
          repository: repository,
          initialType: ServerType.friends,
          onCreated: (_) {},
        ),
        size: const Size(768, 1800),
      );
      expect(find.byKey(const ValueKey('server-create-resumed')), findsOneWidget);
      expect(_nameEnabled(tester), isFalse);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Zmień szablon'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(_submit);
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(_errorPanel, findsOneWidget);
      expect(_nameEnabled(tester), isFalse);
      expect(repository.pendingCreations, isNotEmpty);
      expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
      // No affordance forgets the record: nothing on screen says "start over".
      expect(find.textContaining('od nowa'), findsNothing);
      expect(find.textContaining('Odrzuć'), findsNothing);
    },
  );

  testWidgets(
    'R-5 OBSERVATION a terminal refusal inside the shell leaves no exit on '
    'the widget itself',
    (tester) async {
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
          initialType: ServerType.family,
          isRootTab: true,
          onCreated: (_) {},
        ),
        size: const Size(1440, 900),
      );
      await _fillAndSubmit(tester, name: 'Nasz dom');
      expect(_errorPanel, findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Zmień szablon'))
            .onPressed,
        isNull,
      );
      expect(_nameEnabled(tester), isFalse);
      expect(repository.pendingCreations, isEmpty, reason: 'resolved');
    },
  );

  testWidgets(
    'R-6 OBSERVATION while the store is being read the step is a blank box',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _HangingStoreRepository();
      await pumpServers(
        tester,
        CreateServerScreen(
          repository: repository,
          initialType: ServerType.friends,
          isRootTab: true,
        ),
        size: const Size(1440, 900),
        settle: false,
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('server-create-restoring')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Text), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      repository.completer.complete(null);
      await tester.pumpAndSettle();
      expect(_name, findsOneWidget);
    },
  );
}

// ---------------------------------------------------------------------------
// RE-REVIEW 2 additions — Principal Code and Release Reviewer, 2026-09-12.
// R-1..R-6 above are the round-1 probe, unchanged. R-7 measures the window
// between `setState(_busy = true)` and the `_submission` assignment that
// follows `await rememberPendingCreation(...)` in `_submit`: in production the
// store write is a platform-channel call, so a frame can render in between.
// Soft assertions: every measured deviation is collected and reported at once.

class _DeferredStoreRepository extends TestServerRepository {
  final remember = Completer<ServerCreationRequest>();
  ServerCreationRequest? received;
  @override
  Future<ServerCreationRequest> rememberPendingCreation(
    ServerCreationRequest request,
  ) {
    received = request;
    return remember.future;
  }
}

void rereview2() {
  testWidgets(
    'R-7 the form must stay locked from the first busy frame until the call '
    'answers, and a template change must never resend another template',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final call = Completer<ServerCreationResult>();
      final repository = _DeferredStoreRepository()..pending = call;
      final created = <ServerCreationResult>[];
      await pumpServers(
        tester,
        CreateServerScreen(
          repository: repository,
          initialType: ServerType.friends,
          isRootTab: true,
          onCreated: created.add,
        ),
        size: const Size(1440, 900),
      );
      final findings = <String>[];
      bool changeArmed() =>
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Zmień szablon'),
              )
              .onPressed !=
          null;

      await tester.enterText(_name, 'Nasza ekipa');
      await tester.tap(_submit);
      // The frame after setState(_busy = true); the store has not answered.
      await tester.pump();
      expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
      if (_nameEnabled(tester)) {
        findings.add('name field editable while the store is being written');
      }
      if (changeArmed()) {
        findings.add('"Zmień szablon" armed while the store is being written');
      }

      // The store answers; createServerV1 is now in flight and stays there.
      repository.remember.complete(repository.received!);
      await tester.pump();
      expect(repository.requests.length, 1, reason: 'the call went out');
      if (_nameEnabled(tester)) {
        findings.add('name field editable while createServerV1 is in flight');
      }
      if (changeArmed()) {
        findings.add('"Zmień szablon" armed while createServerV1 is in flight');
      }
      if (!changeArmed()) {
        expect(findings, isEmpty, reason: findings.join('\n'));
        return;
      }

      // Change template mid-flight; then the friends call fails offline.
      await tester.ensureVisible(find.text('Zmień szablon'));
      await tester.tap(find.text('Zmień szablon'));
      await tester.pumpAndSettle();
      if (_card(ServerType.podcast).evaluate().isNotEmpty) {
        findings.add('selector shown while the friends call is in flight');
      }
      call.completeError(
        FirebaseFunctionsException(code: 'unavailable', message: 'Offline'),
      );
      await tester.pumpAndSettle();
      if (_errorPanel.evaluate().isEmpty) {
        findings.add(
          'the offline failure of the friends attempt is never shown',
        );
      }
      await tester.ensureVisible(_card(ServerType.podcast));
      await tester.tap(_card(ServerType.podcast));
      await tester.pumpAndSettle();
      final nameLocked = !_nameEnabled(tester);
      final friendsName = find.text('Nasza ekipa').evaluate().isNotEmpty;
      final submitArmed = tester.widget<FilledButton>(_submit).onPressed != null;
      final label = find
          .descendant(of: _submit, matching: find.byType(Text))
          .evaluate()
          .map((element) => (element.widget as Text).data)
          .join();
      if (nameLocked || submitArmed) {
        findings.add(
          'podcast form: nameLocked=$nameLocked showsFriendsName=$friendsName '
          'submitArmed=$submitArmed label="$label" '
          'changeArmed=${changeArmed()} '
          'resumedBanner=${find.byKey(const ValueKey('server-create-resumed')).evaluate().isNotEmpty}',
        );
      }
      repository.pending = null;
      if (submitArmed) {
        await tester.ensureVisible(_submit);
        await tester.tap(_submit);
        await tester.pumpAndSettle();
        final sent = repository.requests.length == 2
            ? '${repository.requests[1].serverType.name} '
                  '(${repository.requests[1].requestId}, '
                  'identical=${identical(repository.requests[0], repository.requests[1])})'
            : 'nothing';
        findings.add(
          'tapping "$label" on the podcast form sent: $sent; created='
          '${created.map((result) => result.serverId).toList()}',
        );
      }
      expect(tester.takeException(), isNull);
      expect(findings, isEmpty, reason: findings.join('\n'));
    },
  );
}
