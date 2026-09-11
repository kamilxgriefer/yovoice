import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/servers/data/models/server_creation.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/create_server_screen.dart';
import 'package:yovoice/features/servers/presentation/server_localized_copy.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_template_selector.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_type_symbol.dart';
import 'server_test_support.dart';

void main() {
  testWidgets('each selector card exposes a working semantic tap action', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final selected = <ServerType>[];
    await pumpServers(
      tester,
      Scaffold(body: ServerTemplateSelector(onSelected: selected.add)),
      size: const Size(1920, 1200),
    );
    for (final type in ServerType.values) {
      final card = find.byKey(ValueKey('server-template-${type.name}'));
      final node = tester.getSemantics(card);
      final data = node.getSemanticsData();
      expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
      expect(data.flagsCollection.isFocused, isNot(ui.Tristate.none));
      expect(
        data.hint,
        contains(
          AppLocalizations.of(tester.element(card)).serverTypeDescription(type),
        ),
      );
      tester.binding.performSemanticsAction(
        ui.SemanticsActionEvent(
          type: ui.SemanticsAction.tap,
          nodeId: node.id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pump();
      expect(selected.last, type);
    }
    expect(selected, ServerType.values);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('server-template-friends')))
          .getSemanticsData()
          .flagsCollection
          .isFocused,
      ui.Tristate.isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, [...ServerType.values, ServerType.friends]);
    semantics.dispose();
  });

  testWidgets('large desktop text reflows to readable columns in both themes', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final light in [false, true]) {
      for (final width in [768.0, 1100.0, 1440.0, 1920.0]) {
        await pumpServers(
          tester,
          Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
          size: Size(width, 1200),
          textScale: 2,
          light: light,
        );
        final rects = [
          for (final type in ServerType.values)
            tester.getRect(
              find.byKey(ValueKey('server-template-${type.name}')),
            ),
        ];
        if (width < 1100) {
          expect(rects[1].top, greaterThan(rects[0].bottom));
        } else {
          expect(rects[0].top, rects[2].top);
          expect(rects[3].top, greaterThan(rects[2].bottom));
          expect(rects[3].top, rects[4].top);
          expect(rects[0].width, greaterThanOrEqualTo(320));
        }
        expect(tester.takeException(), isNull, reason: '$width / light=$light');
      }
    }
  });

  testWidgets('large compact cards give text the full content width', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final light in [false, true]) {
      await pumpServers(
        tester,
        Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
        size: const Size(320, 844),
        textScale: 2,
        light: light,
      );
      for (final type in ServerType.values) {
        final card = find.byKey(ValueKey('server-template-${type.name}'));
        final title = find
            .descendant(of: card, matching: find.byType(Text))
            .first;
        final symbol = find.descendant(
          of: card,
          matching: find.byType(ServerTypeSymbol),
        );
        final cardRect = tester.getRect(card);
        final titleRect = tester.getRect(title);
        expect(titleRect.width, greaterThanOrEqualTo(cardRect.width - 40));
        expect(titleRect.top, greaterThan(tester.getRect(symbol).bottom));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('short keyboard layouts keep the actual editing caret visible', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    for (final light in [false, true]) {
      for (final width in [320.0, 768.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 500);
        tester.view.viewInsets = FakeViewPadding.zero;
        final repository = TestServerRepository();
        await pumpServers(
          tester,
          CreateServerScreen(
            key: UniqueKey(),
            repository: repository,
            initialType: ServerType.family,
            isRootTab: width >= 1100,
          ),
          size: Size(width, 500),
          textScale: 2,
          light: light,
        );
        final description = find.byKey(const ValueKey('server-description'));
        await tester.ensureVisible(description);
        await tester.pumpAndSettle();
        await tester.tap(description);
        await tester.showKeyboard(description);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.enterText(description, 'Opis podczas pisania');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        final scroll = find.ancestor(
          of: description,
          matching: find.byType(Scrollable),
        );
        final viewport = tester.getRect(scroll.first);
        final editable = tester.state<EditableTextState>(
          find.descendant(of: description, matching: find.byType(EditableText)),
        );
        final caret = editable.renderEditable
            .getLocalRectForCaret(editable.textEditingValue.selection.base)
            .shift(editable.renderEditable.localToGlobal(Offset.zero));
        expect(viewport.height, greaterThanOrEqualTo(96));
        final position =
            '$width / light=$light / viewport=$viewport / caret=$caret';
        expect(viewport.contains(caret.topLeft), isTrue, reason: position);
        expect(viewport.contains(caret.bottomRight), isTrue, reason: position);
        final done = find.byKey(const ValueKey('yo-keyboard-done'));
        expect(tester.getRect(done).bottom, lessThanOrEqualTo(220));
        expect(repository.requests, isEmpty);
        await tester.tap(done);
        tester.view.viewInsets = FakeViewPadding.zero;
        await tester.pumpAndSettle();
        expect(find.text('Opis podczas pisania'), findsOneWidget);
        final submit = find.byKey(const ValueKey('server-create-submit'));
        expect(submit, findsOneWidget);
        expect(tester.getRect(submit).bottom, lessThanOrEqualTo(500));
        expect(tester.takeException(), isNull, reason: '$width / light=$light');
      }
    }
  });

  testWidgets('selector uses exact compact, 3+2 and five-across breaks', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [
      320.0,
      390.0,
      640.0,
      641.0,
      768.0,
      1100.0,
      1150.0,
      1151.0,
      1440.0,
      1920.0,
    ]) {
      await pumpServers(
        tester,
        Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
        size: Size(width, 1200),
      );
      final rects = [
        for (final type in ServerType.values)
          tester.getRect(find.byKey(ValueKey('server-template-${type.name}'))),
      ];
      if (width <= 640) {
        expect(rects[1].top, greaterThan(rects[0].bottom));
      } else if (width <= 1150) {
        expect(rects[0].top, rects[2].top);
        expect(rects[3].top, greaterThan(rects[2].bottom));
        expect(rects[3].top, rects[4].top);
        expect(rects[3].left, greaterThan(rects[0].left));
      } else {
        expect(rects.map((rect) => rect.top).toSet().length, 1);
      }
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });

  testWidgets('all five cards remain reachable at 200 percent in both themes', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final light in [false, true]) {
      for (final width in [320.0, 768.0, 1440.0]) {
        ServerType? selected;
        await pumpServers(
          tester,
          Scaffold(
            body: ServerTemplateSelector(onSelected: (type) => selected = type),
          ),
          size: Size(width, 700),
          textScale: 2,
          light: light,
        );
        final company = find.byKey(const ValueKey('server-template-company'));
        final companyTitle = find.descendant(
          of: company,
          matching: find.text('Dla firmy'),
        );
        await tester.ensureVisible(companyTitle);
        await tester.tap(companyTitle);
        expect(selected, ServerType.company);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
    'template switches retain name and description without creating anything',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository();
      await pumpServers(
        tester,
        CreateServerScreen(
          repository: repository,
          initialType: ServerType.friends,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('server-name')),
        'Nasza ekipa',
      );
      await tester.enterText(
        find.byKey(const ValueKey('server-description')),
        'Zachowany opis',
      );
      await tester.ensureVisible(find.text('Zmień szablon'));
      await tester.tap(find.text('Zmień szablon'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('server-template-family')),
      );
      await tester.tap(find.byKey(const ValueKey('server-template-family')));
      await tester.pumpAndSettle();
      expect(find.text('Nasza ekipa'), findsOneWidget);
      expect(find.text('Zachowany opis'), findsOneWidget);
      expect(repository.requests, isEmpty);
    },
  );

  testWidgets('public-capable templates require a privacy choice', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository();
    await pumpServers(
      tester,
      CreateServerScreen(
        repository: repository,
        initialType: ServerType.community,
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('server-name')),
      'Community',
    );
    await tester.tap(find.byKey(const ValueKey('server-create-submit')));
    await tester.pumpAndSettle();
    expect(repository.requests, isEmpty);
    expect(
      find.text('Wybierz prywatność przed utworzeniem serwera.'),
      findsOneWidget,
    );
  });

  testWidgets('network retry retains exact payload and identity', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()..failNext = true;
    ServerCreationResult? created;
    await pumpServers(
      tester,
      CreateServerScreen(
        repository: repository,
        initialType: ServerType.friends,
        onCreated: (result) => created = result,
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('server-name')),
      '  Nasza ekipa  ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('server-description')),
      '  Opis  ',
    );
    await tester.tap(find.byKey(const ValueKey('server-create-submit')));
    await tester.pumpAndSettle();
    expect(repository.requests.single.name, 'Nasza ekipa');
    expect(repository.requests.single.description, 'Opis');
    expect(repository.requests.single.privacy, ServerPrivacy.inviteOnly);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('server-name')))
          .enabled,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('server-create-submit')));
    await tester.pumpAndSettle();
    expect(repository.requests.length, 2);
    expect(identical(repository.requests[0], repository.requests[1]), isTrue);
    expect(repository.allocated, 1);
    expect(created?.serverId, 'saved');
    expect(tester.takeException(), isNull);
  });
}
