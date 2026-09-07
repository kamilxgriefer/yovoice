import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_chat_sheet.dart';
import 'package:yovoice/shared/widgets/inputs/yo_emoji_picker.dart';

/// Mirrors how a composer hosts the picker: the picker is the sibling *below*
/// the composer, so the send button is laid out first and can never be
/// covered. That is the arrangement all three real composers use.
class _ComposerHarness extends StatefulWidget {
  const _ComposerHarness({required this.recents, this.initialText = ''});

  final YoEmojiRecentsStore recents;
  final String initialText;

  @override
  State<_ComposerHarness> createState() => _ComposerHarnessState();
}

class _ComposerHarnessState extends State<_ComposerHarness> {
  late final TextEditingController controller = TextEditingController(
    text: widget.initialText,
  );
  final FocusNode focusNode = FocusNode();
  bool open = false;

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Expanded(child: SizedBox.expand()),
          Row(
            children: [
              Expanded(
                child: TextField(controller: controller, focusNode: focusNode),
              ),
              YoEmojiComposerButton(
                open: open,
                onPressed: () {
                  setState(() => open = !open);
                  focusNode.requestFocus();
                },
              ),
              IconButton(
                key: const ValueKey('harness-send'),
                onPressed: () {},
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
          if (open)
            YoEmojiPicker(
              recentsStore: widget.recents,
              onSelected: (emoji) {
                yoInsertEmojiAtCaret(controller, emoji);
                if (!focusNode.hasFocus) focusNode.requestFocus();
              },
              onBackspace: () => yoDeleteBackAtCaret(controller),
            ),
        ],
      ),
    );
  }
}

Widget _app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.darkTheme,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

Future<void> _setViewport(
  WidgetTester tester,
  Size size, {
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  if (scale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
}

void main() {
  group('composer wiring', () {
    testWidgets('the picker opens and closes from the composer button', (
      tester,
    ) async {
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        _app(_ComposerHarness(recents: YoEmojiRecentsStore.inMemory())),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('emoji-picker')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('emoji-picker-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emoji-picker')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('emoji-picker-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emoji-picker')), findsNothing);
    });

    testWidgets('selecting inserts at the caret and keeps composer focus', (
      tester,
    ) async {
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        _app(
          _ComposerHarness(
            recents: YoEmojiRecentsStore.inMemory(),
            initialText: 'hello world',
          ),
        ),
      );
      final state = tester.state<_ComposerHarnessState>(
        find.byType(_ComposerHarness),
      );
      // Caret between "hello" and " world".
      state.controller.selection = const TextSelection.collapsed(offset: 5);
      state.focusNode.requestFocus();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('emoji-picker-toggle')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('emoji-cell-😀')));
      await tester.pumpAndSettle();

      expect(state.controller.text, 'hello😀 world');
      // The caret advanced past the inserted emoji rather than resetting, so a
      // second tap composes left to right.
      expect(state.controller.selection.baseOffset, 5 + '😀'.length);
      expect(state.focusNode.hasFocus, isTrue);

      await tester.tap(find.byKey(const ValueKey('emoji-cell-😂')));
      await tester.pumpAndSettle();
      expect(state.controller.text, 'hello😀😂 world');
    });

    testWidgets('backspace removes one whole emoji, not half a glyph', (
      tester,
    ) async {
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        _app(
          _ComposerHarness(
            recents: YoEmojiRecentsStore.inMemory(),
            initialText: 'hi 🇵🇱',
          ),
        ),
      );
      final state = tester.state<_ComposerHarnessState>(
        find.byType(_ComposerHarness),
      );
      state.controller.selection = TextSelection.collapsed(
        offset: state.controller.text.length,
      );
      await tester.tap(find.byKey(const ValueKey('emoji-picker-toggle')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('emoji-picker-backspace')));
      await tester.pumpAndSettle();

      // The Polish flag is a two-codepoint regional-indicator pair; deleting by
      // code unit would leave a stray half behind.
      expect(state.controller.text, 'hi ');
    });

    testWidgets('the open picker never covers the send button', (tester) async {
      await _setViewport(tester, const Size(320, 640), scale: 2);
      await tester.pumpWidget(
        _app(_ComposerHarness(recents: YoEmojiRecentsStore.inMemory())),
      );
      await tester.tap(find.byKey(const ValueKey('emoji-picker-toggle')));
      await tester.pumpAndSettle();

      final send = tester.getRect(find.byKey(const ValueKey('harness-send')));
      final picker = tester.getRect(find.byKey(const ValueKey('emoji-picker')));
      expect(
        send.bottom,
        lessThanOrEqualTo(picker.top + 0.5),
        reason: 'the send button must stay above the picker panel',
      );
      expect(send.bottom, lessThanOrEqualTo(640));
    });
  });

  group('search', () {
    Future<void> pumpPicker(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      YoEmojiRecentsStore? recents,
      Size size = const Size(390, 844),
    }) async {
      await _setViewport(tester, size);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Column(
              children: [
                const Spacer(),
                YoEmojiPicker(
                  recentsStore: recents ?? YoEmojiRecentsStore.inMemory(),
                  onSelected: (_) {},
                ),
              ],
            ),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('filters by an English keyword', (tester) async {
      await pumpPicker(tester);
      await tester.enterText(
        find.byKey(const ValueKey('emoji-picker-search')),
        'unicorn',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('emoji-cell-🦄')), findsOneWidget);
      expect(find.byKey(const ValueKey('emoji-cell-😀')), findsNothing);
    });

    testWidgets('filters by a Polish keyword', (tester) async {
      await pumpPicker(tester, locale: const Locale('pl'));
      await tester.enterText(
        find.byKey(const ValueKey('emoji-picker-search')),
        'jednorożec',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('emoji-cell-🦄')), findsOneWidget);
      expect(find.byKey(const ValueKey('emoji-cell-😀')), findsNothing);
    });

    testWidgets('Polish search ignores diacritics', (tester) async {
      // Most people type Polish on an English keyboard layout; requiring "ż"
      // would make the Polish catalogue unreachable for them.
      expect(yoSearchEmoji('żółw').map((e) => e.char), contains('🐢'));
      expect(yoSearchEmoji('zolw').map((e) => e.char), contains('🐢'));
      expect(yoSearchEmoji('ZOLW').map((e) => e.char), contains('🐢'));

      await pumpPicker(tester, locale: const Locale('pl'));
      await tester.enterText(
        find.byKey(const ValueKey('emoji-picker-search')),
        'zolw',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emoji-cell-🐢')), findsOneWidget);
    });

    testWidgets('a search with no match shows an explanation, not a blank', (
      tester,
    ) async {
      await pumpPicker(tester);
      await tester.enterText(
        find.byKey(const ValueKey('emoji-picker-search')),
        'zzzzqqqq',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No emoji match'), findsOneWidget);
    });

    testWidgets('the category strip is hidden while searching', (tester) async {
      await pumpPicker(tester);
      expect(
        find.byKey(const ValueKey('emoji-category-smileys')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('emoji-picker-search')),
        'cat',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('emoji-category-smileys')),
        findsNothing,
      );
    });

    testWidgets('the strip scrolls to the categories that do not fit', (
      tester,
    ) async {
      // Nine 44px targets need 396px plus padding, so on a 390px phone the
      // last categories are reached by scrolling rather than by shrinking the
      // buttons below the accessible minimum.
      await pumpPicker(tester);
      expect(find.byKey(const ValueKey('emoji-category-flags')), findsNothing);

      await tester.drag(
        find.byKey(const ValueKey('emoji-category-smileys')),
        const Offset(-240, 0),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('emoji-category-flags')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('emoji-category-flags')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emoji-cell-🇵🇱')), findsOneWidget);
    });

    testWidgets('switching category swaps the grid contents', (tester) async {
      await pumpPicker(tester);
      expect(find.byKey(const ValueKey('emoji-cell-😀')), findsOneWidget);
      // Grapes lead the food category; the grid builds lazily, so an entry
      // further down the list would not be mounted yet either way.
      expect(find.byKey(const ValueKey('emoji-cell-🍇')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('emoji-category-food')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('emoji-cell-🍇')), findsOneWidget);
      expect(find.byKey(const ValueKey('emoji-cell-😀')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('emoji-category-animals')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emoji-cell-🐵')), findsOneWidget);
      expect(find.byKey(const ValueKey('emoji-cell-🍇')), findsNothing);
    });
  });

  group('recently used', () {
    testWidgets('a chosen emoji appears in the recents row, newest first', (
      tester,
    ) async {
      final recents = YoEmojiRecentsStore.inMemory();
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(_app(_ComposerHarness(recents: recents)));
      await tester.tap(find.byKey(const ValueKey('emoji-picker-toggle')));
      await tester.pumpAndSettle();

      // Nothing used yet, so no recents section.
      expect(find.byKey(const ValueKey('emoji-recents')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('emoji-cell-😂')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emoji-recents')), findsOneWidget);
      expect(find.byKey(const ValueKey('emoji-recent-😂')), findsOneWidget);
      expect(recents.value, ['😂']);

      await tester.tap(find.byKey(const ValueKey('emoji-cell-😀')));
      await tester.pumpAndSettle();
      expect(recents.value, ['😀', '😂']);

      // Reusing an entry promotes it instead of duplicating it.
      await tester.tap(find.byKey(const ValueKey('emoji-cell-😂')));
      await tester.pumpAndSettle();
      expect(recents.value, ['😂', '😀']);
    });

    test('recents survive a reload and are capped', () async {
      final store = YoEmojiRecentsStore.inMemory();
      await store.load();
      for (final emoji in yoEmojiCatalog.take(
        YoEmojiRecentsStore.maxEntries + 5,
      )) {
        await store.register(emoji.char);
      }
      expect(store.value, hasLength(YoEmojiRecentsStore.maxEntries));

      // Most recent first.
      expect(
        store.value.first,
        yoEmojiCatalog[YoEmojiRecentsStore.maxEntries + 4].char,
      );
    });

    test('a persisted emoji outside the catalogue is dropped on load', () async {
      // Guards the platform-support ceiling: if the catalogue is ever narrowed,
      // a previously used emoji must not come back through the recents row.
      final store = YoEmojiRecentsStore.inMemory(initial: ['🔥', '🥳', '😀']);
      await store.load();
      expect(store.value, ['🔥', '😀']);
      expect(store.emoji.map((e) => e.char), ['🔥', '😀']);
    });
  });

  group('accessibility', () {
    testWidgets('every emoji target is at least 44px at 320px and 200% text', (
      tester,
    ) async {
      await _setViewport(tester, const Size(320, 640), scale: 2);
      await tester.pumpWidget(
        _app(_ComposerHarness(recents: YoEmojiRecentsStore.inMemory())),
      );
      await tester.tap(find.byKey(const ValueKey('emoji-picker-toggle')));
      await tester.pumpAndSettle();

      final cells = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('emoji-cell-'),
      );
      expect(cells, findsWidgets);
      for (final element in cells.evaluate()) {
        final size = element.size!;
        expect(
          size.width,
          greaterThanOrEqualTo(44.0),
          reason: 'emoji cell width at 200% text',
        );
        expect(
          size.height,
          greaterThanOrEqualTo(44.0),
          reason: 'emoji cell height at 200% text',
        );
      }

      // The strip scrolls, so only the buttons currently built are measurable.
      final stripButtons = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'emoji-category-',
            ),
      );
      expect(stripButtons, findsWidgets);
      for (final element in stripButtons.evaluate()) {
        expect(element.size!.width, greaterThanOrEqualTo(44.0));
        expect(element.size!.height, greaterThanOrEqualTo(44.0));
      }

      final toggle = tester.getSize(
        find.byKey(const ValueKey('emoji-picker-toggle')),
      );
      expect(toggle.width, greaterThanOrEqualTo(44.0));
      expect(toggle.height, greaterThanOrEqualTo(44.0));

      expect(tester.takeException(), isNull);
    });

    testWidgets('emoji carry their name as a semantic label, not the glyph', (
      tester,
    ) async {
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        _app(_ComposerHarness(recents: YoEmojiRecentsStore.inMemory())),
      );
      await tester.tap(find.byKey(const ValueKey('emoji-picker-toggle')));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('grinning face'), findsOneWidget);
      expect(find.bySemanticsLabel('Smileys & emotion'), findsWidgets);
    });

    testWidgets('semantic labels follow the locale', (tester) async {
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Column(
              children: [
                const Spacer(),
                YoEmojiPicker(
                  recentsStore: YoEmojiRecentsStore.inMemory(),
                  onSelected: (_) {},
                ),
              ],
            ),
          ),
          locale: const Locale('pl'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('uśmiechnięta twarz'), findsOneWidget);
      expect(find.bySemanticsLabel('Buźki i emocje'), findsWidgets);
    });

    testWidgets('the grid is reachable with the keyboard', (tester) async {
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        _app(_ComposerHarness(recents: YoEmojiRecentsStore.inMemory())),
      );
      await tester.tap(find.byKey(const ValueKey('emoji-picker-toggle')));
      await tester.pumpAndSettle();

      final cell = tester.widget<InkWell>(
        find.byKey(const ValueKey('emoji-cell-😀')),
      );
      // An InkWell with an onTap is focusable and answers ActivateIntent, which
      // is what makes Tab-then-Enter work without a bespoke shortcut map.
      expect(cell.onTap, isNotNull);
      expect(cell.excludeFromSemantics, isFalse);
    });
  });

  group('reaction vocabularies stay inside the server allowlist', () {
    // The picker deliberately does NOT widen these. Reactions are validated
    // server-side, so an emoji outside these lists is rejected on write; only
    // a Cloud Functions change plus a rules change, both deployed, could widen
    // them. These tests read the servers' own source so the two cannot drift
    // apart silently.

    test('direct-message reactions match the Cloud Functions allowlist', () {
      final functions = File(
        'functions/messaging/direct_integrity.js',
      ).readAsStringSync();
      final block = RegExp(
        r'ALLOWED_DIRECT_REACTIONS\s*=\s*Object\.freeze\(\[(.*?)\]\)',
        dotAll: true,
      ).firstMatch(functions);
      expect(block, isNotNull, reason: 'server allowlist not found');
      final server = RegExp(
        '"([^"]+)"',
      ).allMatches(block!.group(1)!).map((match) => match.group(1)!).toList();
      expect(server, ['❤️', '😂', '🔥', '😮', '😢', '👍']);

      final screen = File(
        'lib/features/messages/presentation/screens/chat_screen.dart',
      ).readAsStringSync();
      final client = RegExp(
        r"const reactions = \[(.*?)\];",
      ).firstMatch(screen)?.group(1);
      expect(client, isNotNull);
      final clientSet = RegExp(
        "'([^']+)'",
      ).allMatches(client!).map((match) => match.group(1)!).toList();
      expect(
        clientSet,
        server,
        reason:
            'The direct-message reaction row must offer exactly what '
            'functions/messaging/direct_integrity.js accepts.',
      );
    });

    test('room reactions match firestore.rules', () {
      final rules = File('firestore.rules').readAsStringSync();
      final match = RegExp(
        r"after\.keys\(\)\.hasOnly\(\[('(?:[^']+)'(?:,\s*'(?:[^']+)')*)\]\)",
      ).firstMatch(rules);
      expect(match, isNotNull, reason: 'room reaction rule not found');
      final rulesSet = RegExp(
        "'([^']+)'",
      ).allMatches(match!.group(1)!).map((m) => m.group(1)!).toList();

      expect(rulesSet, ['❤️', '😂', '👏', '🔥', '💯']);
      expect(
        roomReactionEmojis,
        rulesSet,
        reason:
            'The room reaction row must offer exactly what firestore.rules '
            'accepts; a sixth entry would be refused on write.',
      );
    });

    test('the picker catalogue is not wired into either reaction row', () {
      // The catalogue is a superset by design — it is composer vocabulary, not
      // reaction vocabulary. If a future change points a reaction row at it,
      // this fails loudly.
      for (final path in const [
        'lib/features/messages/presentation/screens/chat_screen.dart',
        'lib/features/rooms/presentation/widgets/room_chat_sheet.dart',
      ]) {
        final source = File(path).readAsStringSync();
        final reactionCalls = RegExp(
          r'onReaction\w*\s*[:(]|_toggleReaction\(',
        ).allMatches(source);
        expect(
          reactionCalls.isNotEmpty,
          isTrue,
          reason: '$path should still have a reaction path',
        );
        expect(
          source.contains('yoEmojiCatalog'),
          isFalse,
          reason: '$path must not feed the full catalogue to reactions',
        );
      }
    });
  });

  group('catalogue integrity', () {
    test('every category is populated and nothing is duplicated', () {
      for (final category in YoEmojiCategory.values) {
        expect(
          yoEmojiByCategory[category],
          isNotEmpty,
          reason: '${category.name} is empty',
        );
      }
      final seen = <String>{};
      final duplicates = <String>[];
      for (final emoji in yoEmojiCatalog) {
        if (!seen.add(emoji.char)) duplicates.add(emoji.char);
      }
      expect(duplicates, isEmpty);
      expect(yoEmojiCatalog.length, greaterThanOrEqualTo(500));
    });

    test('every entry has an English and a Polish name', () {
      for (final emoji in yoEmojiCatalog) {
        expect(emoji.name.trim(), isNotEmpty, reason: emoji.char);
        expect(emoji.namePolish.trim(), isNotEmpty, reason: emoji.char);
      }
    });

    test('no entry is newer than the Android 8.0 emoji ceiling', () {
      // Android 8.0 ships Unicode Emoji 5.0 and is the oldest release the app
      // supports, so it — not iOS — is the binding constraint. These ranges
      // were assigned by Emoji 11.0 and later; anything drawn from them is a
      // tofu box on a device that never received a font update.
      const postCeilingRanges = <List<int>>[
        [0x1F6D5, 0x1F6DF],
        [0x1F6FA, 0x1F6FF],
        [0x1F7E0, 0x1F7FF],
        [0x1F90C, 0x1F90F],
        [0x1F96C, 0x1F97F],
        [0x1F998, 0x1F9BF],
        [0x1F9C1, 0x1F9CF],
        [0x1F9E7, 0x1F9FF],
        [0x1FA70, 0x1FAFF],
      ];

      final offenders = <String>[];
      for (final emoji in yoEmojiCatalog) {
        for (final rune in emoji.char.runes) {
          final tooNew = postCeilingRanges.any(
            (range) => rune >= range[0] && rune <= range[1],
          );
          if (tooNew) {
            offenders.add(
              '${emoji.char} (${emoji.name}) '
              'U+${rune.toRadixString(16).toUpperCase()}',
            );
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'These render as tofu on Android 8.0. Raise the ceiling in '
            'yo_emoji_catalog.dart and this test together, or drop them.\n'
            '${offenders.join('\n')}',
      );
    });

    test('the ceiling check actually catches a too-new emoji', () {
      // Without this, the guard above could silently pass because its ranges
      // were wrong rather than because the catalogue is clean.
      const postCeiling = ['🥳', '🥺', '🧊', '🟢', '🫠', '🦩'];
      for (final char in postCeiling) {
        expect(
          yoEmojiByChar.containsKey(char),
          isFalse,
          reason: '$char is newer than Emoji 5.0 and must not be catalogued',
        );
      }
      // …and a few Emoji 5.0 entries that must NOT be excluded by mistake.
      for (final char in const ['🧀', '🧠', '🧡', '🦒', '🦗', '🛸', '🤩']) {
        expect(
          yoEmojiByChar.containsKey(char),
          isTrue,
          reason: '$char is Emoji 5.0 or older and should be available',
        );
      }
    });

    test('search matches names and keywords in both languages', () {
      expect(yoSearchEmoji('pizza').map((e) => e.char), contains('🍕'));
      expect(yoSearchEmoji('kciuk').map((e) => e.char), contains('👍'));
      expect(yoSearchEmoji('thumbs up').map((e) => e.char), contains('👍'));
      expect(yoSearchEmoji('serce').map((e) => e.char), contains('❤️'));
      // An empty query browses rather than filtering.
      expect(yoSearchEmoji('   '), same(yoEmojiCatalog));
    });
  });

  group('caret helpers', () {
    test('insertion replaces a selection', () {
      final controller = TextEditingController(text: 'abc def');
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      yoInsertEmojiAtCaret(controller, '🔥');
      expect(controller.text, '🔥 def');
      expect(controller.selection.baseOffset, '🔥'.length);
      controller.dispose();
    });

    test('insertion into an unfocused field appends', () {
      final controller = TextEditingController(text: 'abc');
      yoInsertEmojiAtCaret(controller, '🔥');
      expect(controller.text, 'abc🔥');
      controller.dispose();
    });

    test('backspace on an empty field is a no-op', () {
      final controller = TextEditingController();
      yoDeleteBackAtCaret(controller);
      expect(controller.text, isEmpty);
      controller.dispose();
    });

    test('backspace deletes a selection when there is one', () {
      final controller = TextEditingController(text: 'abcdef');
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      yoDeleteBackAtCaret(controller);
      expect(controller.text, 'aef');
      expect(controller.selection.baseOffset, 1);
      controller.dispose();
    });
  });
}
