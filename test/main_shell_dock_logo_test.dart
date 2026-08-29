// The dock's branded centre and the detail page's navigation contract:
// the YO Voice logo anchors the centre action (same route/behaviour as
// ever — the voice sheet), and a Moment detail hosted by the shell keeps
// the bottom navigation visible with Moments the active tab.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';

VoiceMoment _moment() {
  final createdAt = DateTime.now().subtract(const Duration(hours: 2));
  return VoiceMoment(
    id: 'm1',
    authorId: 'nadia',
    authorName: 'Nadia Rutkowska',
    authorPhotoUrl: null,
    caption: 'The one thing nobody tells you.',
    audioUrl: 'https://cdn.example/m1.m4a',
    durationSeconds: 27,
    likeCount: 3,
    commentCount: 1,
    isPublished: true,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(hours: 24)),
    schemaVersion: 2,
    status: 'published',
  );
}

int get _momentsSlot => MainShell.desktopSlots.entries
    .firstWhere((entry) => entry.value == MoreDestination.moments)
    .key;

Future<SemanticsHandle> _pumpHost(
  WidgetTester tester, {
  required Widget body,
  required int selectedIndex,
  ValueChanged<int>? onDestinationSelected,
  VoidCallback? onVoicePressed,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  // Selected-state assertions read the semantics tree. The caller
  // disposes the handle before the test body returns — the framework
  // verifies that before teardowns run.
  final semantics = tester.ensureSemantics();

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: MoreDestinationHost(
            body: body,
            selectedIndex: selectedIndex,
            unreadConversationCount: 0,
            onDestinationSelected: onDestinationSelected ?? (_) {},
            onVoicePressed: onVoicePressed ?? () {},
            onMorePressed: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  return semantics;
}

/// Whether the dock item labelled [label] declares itself selected.
///
/// Read from the Semantics WIDGET the item builds (its accessibility
/// contract), which is stable regardless of how the compiled semantics
/// tree merges the label with the item's caption text.
bool _isSelected(WidgetTester tester, String label) {
  final items = tester.widgetList<Semantics>(
    find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    ),
  );
  expect(items, isNotEmpty, reason: 'no dock item labelled $label');
  return items.any((widget) => widget.properties.selected == true);
}

void main() {
  testWidgets('the dock centre is the YO Voice logo in its glowing anchor, '
      'and it still opens the voice action', (tester) async {
    var voiceOpened = 0;
    final semantics = await _pumpHost(
      tester,
      body: const Text('BODY'),
      selectedIndex: 0,
      onVoicePressed: () => voiceOpened++,
    );

    final logo = tester.widget<Image>(find.byKey(const ValueKey('dock-logo')));
    expect(
      (logo.image as AssetImage).assetName,
      'assets/images/logo.png',
      reason: 'the centre anchor renders the real brand asset',
    );

    await tester.tap(find.bySemanticsLabel('Open voice actions'));
    await tester.pump();
    expect(voiceOpened, 1, reason: 'same behaviour as ever, new face');
    semantics.dispose();
  });

  testWidgets('with the Moments slot selected, Moments is the active dock '
      'item — the state the shell passes for both the feed and the hosted '
      'detail page', (tester) async {
    final semantics = await _pumpHost(
      tester,
      body: const Text('BODY'),
      selectedIndex: _momentsSlot,
    );

    expect(_isSelected(tester, 'Moments'), isTrue);
    expect(_isSelected(tester, 'Home'), isFalse);
    semantics.dispose();
  });

  testWidgets('a Moment detail hosted by the shell keeps the whole dock '
      'visible with Moments active, and its sections render', (tester) async {
    // The detail screen constructs its services defensively: with no
    // Firebase app every seam degrades and the page still renders the
    // Moment it was handed — exactly what this hosting test needs.
    final semantics = await _pumpHost(
      tester,
      body: MomentDetailScreen(moment: _moment()),
      selectedIndex: _momentsSlot,
    );

    // The page's own chrome and content.
    expect(find.byKey(const ValueKey('moment-detail-back')), findsOneWidget);
    expect(find.text('The one thing nobody tells you.'), findsOneWidget);
    expect(find.byKey(const ValueKey('moment-detail-play')), findsOneWidget);

    // The persistent dock, with Moments lit.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Moments'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-logo')), findsOneWidget);
    expect(_isSelected(tester, 'Moments'), isTrue);
    semantics.dispose();
  });

  testWidgets('dock taps from the hosted detail still fire the shell '
      'routes', (tester) async {
    int? selected;
    final semantics = await _pumpHost(
      tester,
      body: MomentDetailScreen(moment: _moment()),
      selectedIndex: _momentsSlot,
      onDestinationSelected: (index) => selected = index,
    );

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(selected, 0);
    semantics.dispose();
  });

  testWidgets('the approved circular centre fully contains the real logo', (
    tester,
  ) async {
    final semantics = await _pumpHost(
      tester,
      body: const SizedBox.shrink(),
      selectedIndex: 0,
      onVoicePressed: () {},
    );
    final logo = find.byKey(const ValueKey('dock-logo'));
    expect(logo, findsOneWidget);

    final boundary = find.byKey(const ValueKey('yo-center-action-boundary'));
    expect(boundary, findsOneWidget);
    final buttonRect = tester.getRect(boundary);
    final logoRect = tester.getRect(logo);
    expect(buttonRect.width, inInclusiveRange(64, 68));
    expect(buttonRect.height, buttonRect.width);
    expect(logoRect.width, inInclusiveRange(59, 60));
    expect(logoRect.height, logoRect.width);
    expect(logoRect.width * .814, inInclusiveRange(48, 52));
    expect(logoRect.height * .844, inInclusiveRange(48, 52));
    expect(buttonRect.contains(logoRect.topLeft), isTrue);
    expect(buttonRect.contains(logoRect.bottomRight), isTrue);
    expect(
      find.ancestor(
        of: logo,
        matching: find.byWidgetPredicate(
          (widget) => widget is Material && widget.shape is CircleBorder,
        ),
      ),
      findsOneWidget,
      reason: 'the approved centre uses one clipped circular surface',
    );
    semantics.dispose();
  });

  testWidgets(
    'the button and contained logo follow the responsive size guide',
    (tester) async {
      final semantics = await _pumpHost(
        tester,
        body: const SizedBox.shrink(),
        selectedIndex: 0,
        onVoicePressed: () {},
      );
      tester.view.physicalSize = const Size(320, 700);
      await tester.pump();
      final small = tester.getSize(find.byKey(const ValueKey('dock-logo')));
      final smallButton = tester.getSize(
        find.byKey(const ValueKey('yo-center-action-boundary')),
      );
      expect(smallButton.width, 64);
      expect(small.width, 59);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(430, 900);
      await tester.pump();
      final large = tester.getSize(find.byKey(const ValueKey('dock-logo')));
      final largeButton = tester.getSize(
        find.byKey(const ValueKey('yo-center-action-boundary')),
      );
      expect(largeButton.width, 68);
      expect(large.width, 60);
      semantics.dispose();
    },
  );
}
