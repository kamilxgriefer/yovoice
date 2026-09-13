import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/yo_moments_chrome.dart';

import 'moments_overview_test_support.dart';

/// The shared YO Moments chrome of board 06: one title, the two-level
/// switch + filters, Utwórz, no search, 48-px targets, focus order, RTL,
/// 200 % text.
void main() {
  late VoidCallback restoreIdentity;

  setUpAll(loadInterFont);
  setUp(() => restoreIdentity = installIdentityStub());
  tearDown(() => restoreIdentity());

  ReelService emptyReels() => ReelService(
    auth: authAs(),
    callableInvoker: (name, payload) async {
      if (name == 'listReelsV2') {
        return <Object?, Object?>{
          'schemaVersion': 2,
          'items': const <Object?>[],
          'nextCursor': null,
        };
      }
      throw StateError('Unexpected callable $name with $payload');
    },
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required Size size,
    YoMomentsFormat format = YoMomentsFormat.voice,
    Locale locale = const Locale('pl'),
    bool rtl = false,
    double textScale = 1,
    ReelService? reelService,
  }) async {
    useSurface(tester, size);
    final auth = authAs();
    await tester.pumpWidget(
      overviewHost(
        MomentsScreen(
          isRootTab: true,
          auth: auth,
          initialFormat: format,
          discoveryService: StaticDiscovery(populatedPool()),
          feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
          viewsService: StaticViews(const <String>{}),
          playerFactory: SilentPlayer.new,
          reelService: reelService,
          onCreateReel: () async {},
        ),
        locale: locale,
        rtl: rtl,
        textScale: textScale,
        size: size,
      ),
    );
    await settleOverview(tester);
  }

  const voiceFilters = <String>[
    'moments-filter-discover',
    'moments-filter-following',
    'moments-filter-mostEngaged',
    'moments-filter-recent',
  ];

  testWidgets('Voice uses the same compact two-level chrome as Yeels below '
      '1100', (tester) async {
    await pumpScreen(tester, size: const Size(390, 844));

    expect(find.text('YO Moments'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('voice-immersive-chrome')),
      findsOneWidget,
    );
    expect(find.text('Głos'), findsOneWidget);
    expect(find.text('Yeels'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Szukaj'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('yo-moments-local-panel')),
      findsNothing,
      reason: 'below 1100 the filters are chips, not a panel',
    );
    for (final key in voiceFilters) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget);
    }

    final semantics = tester.ensureSemantics();
    try {
      final voice = tester
          .getSemantics(
            find.byKey(const ValueKey<String>('yo-moments-format-voice')),
          )
          .getSemanticsData();
      final reels = tester
          .getSemantics(
            find.byKey(const ValueKey<String>('yo-moments-format-reels')),
          )
          .getSemanticsData();
      expect(voice.flagsCollection.isSelected, Tristate.isTrue);
      expect(reels.flagsCollection.isSelected, isNot(Tristate.isTrue));
      expect(voice.flagsCollection.isButton, isTrue);
    } finally {
      semantics.dispose();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '768 px keeps the compact chrome while switching Voice and Yeels',
    (tester) async {
      await pumpScreen(
        tester,
        size: const Size(768, 900),
        reelService: emptyReels(),
      );

      expect(
        find.byKey(const ValueKey('voice-immersive-chrome')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('yo-moments-title')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('yo-moments-format-reels')));
      await settleOverview(tester);

      expect(find.byKey(const ValueKey('reels-chrome')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reels-discover-filter')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('yo-moments-title')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('yo-moments-format-voice')));
      await settleOverview(tester);

      expect(
        find.byKey(const ValueKey('voice-immersive-chrome')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('yo-moments-title')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the English label is Voice and the four filters keep their '
      'English copy', (tester) async {
    await pumpScreen(
      tester,
      size: const Size(390, 844),
      locale: const Locale('en'),
    );
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Most engaged'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
  });

  testWidgets('at 1280 the four Voice filters are local-panel rows, the '
      'panel has no title and Utwórz opens the create chooser', (tester) async {
    await pumpScreen(tester, size: const Size(1280, 900));

    expect(find.text('YO Moments'), findsOneWidget, reason: 'one title only');
    final panel = find.byKey(const ValueKey<String>('yo-moments-local-panel'));
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, YoMomentsLayout.localPanelBaseWidth);
    for (final key in voiceFilters) {
      final row = find.byKey(ValueKey<String>(key));
      expect(find.descendant(of: panel, matching: row), findsOneWidget);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    }
    expect(find.text('Najbardziej angażujące'), findsOneWidget);

    final create = find.byKey(const ValueKey<String>('moments-create-cta'));
    expect(find.descendant(of: panel, matching: create), findsOneWidget);
    expect(find.text('Utwórz'), findsOneWidget);
    expect(tester.getSize(create).height, 48);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('yo-moments-create-sheet')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Yeels format keeps both Yeels filters reachable at 1280', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      size: const Size(1280, 900),
      format: YoMomentsFormat.reels,
      reelService: emptyReels(),
    );
    expect(find.text('YO Moments'), findsOneWidget);
    expect(find.text('Odkrywaj'), findsWidgets);
    expect(find.text('Twoje Yeels'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('every chrome control is at least 48 px on a phone', (
    tester,
  ) async {
    await pumpScreen(tester, size: const Size(390, 844));
    for (final key in <String>[
      'moments-create-cta',
      'yo-moments-format-voice',
      'yo-moments-format-reels',
      'moments-filter-discover',
      'moments-filter-following',
      'moments-discovery-refresh',
    ]) {
      final size = tester.getSize(find.byKey(ValueKey<String>(key)));
      expect(size.height, greaterThanOrEqualTo(48), reason: key);
      expect(size.width, greaterThanOrEqualTo(48), reason: key);
    }
  });

  testWidgets('keyboard focus walks the switch before the filters', (
    tester,
  ) async {
    await pumpScreen(tester, size: const Size(390, 844));
    final order = <String>[];
    for (var i = 0; i < 8 && order.length < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final context = FocusManager.instance.primaryFocus?.context;
      if (context == null) continue;
      String? found;
      context.visitAncestorElements((element) {
        final key = element.widget.key;
        if (key is ValueKey<String> &&
            (key.value.startsWith('yo-moments-format-') ||
                key.value.startsWith('moments-filter-') ||
                key.value == 'moments-create-cta')) {
          found = key.value;
          return false;
        }
        return true;
      });
      if (found != null && (order.isEmpty || order.last != found)) {
        order.add(found!);
      }
    }
    expect(order, isNotEmpty);
    final firstFilter = order.indexWhere(
      (k) => k.startsWith('moments-filter-'),
    );
    final firstSwitch = order.indexWhere(
      (k) => k.startsWith('yo-moments-format-'),
    );
    expect(firstSwitch, greaterThanOrEqualTo(0));
    if (firstFilter >= 0) expect(firstSwitch, lessThan(firstFilter));
  });

  testWidgets('RTL mirrors the header, the switch and the chip row', (
    tester,
  ) async {
    await pumpScreen(tester, size: const Size(390, 844), rtl: true);
    final create = tester.getRect(
      find.byKey(const ValueKey<String>('moments-create-cta')),
    );
    final switcher = tester.getRect(
      find.byKey(const ValueKey<String>('yo-moments-format-tabs')),
    );
    expect(create.center.dx, lessThan(195));
    expect(switcher.center.dx, greaterThan(create.center.dx));
    final discover = tester.getRect(
      find.byKey(const ValueKey<String>('moments-filter-discover')),
    );
    final following = tester.getRect(
      find.byKey(const ValueKey<String>('moments-filter-following')),
    );
    expect(discover.left, greaterThan(following.left));
    final voice = tester.getRect(
      find.byKey(const ValueKey<String>('yo-moments-format-voice')),
    );
    final reels = tester.getRect(
      find.byKey(const ValueKey<String>('yo-moments-format-reels')),
    );
    expect(voice.left, greaterThan(reels.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '200 % text at 320 keeps compact Voice and Yeels segments laid out',
    (tester) async {
      await pumpScreen(tester, size: const Size(320, 1400), textScale: 2);
      expect(
        find.byKey(const ValueKey<String>('yo-moments-title')),
        findsNothing,
      );
      for (final finder in <Finder>[find.text('Głos'), find.text('Yeels')]) {
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$finder');
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(-0.5), reason: '$finder');
        expect(rect.right, lessThanOrEqualTo(320.5), reason: '$finder');
      }
      expect(tester.takeException(), isNull);
    },
  );
}
