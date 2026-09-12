// Hosted detail routes retain the same five-destination flat dock
// (Start · Serwery · Czaty · Momenty · Więcej).
// The former central logo/voice action is intentionally not a sixth action.
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

/// Content slot 13: the Servers destination behind dock cell 1.
int get _serversSlot => MainShell.desktopSlots.entries
    .firstWhere((entry) => entry.value == MoreDestination.servers)
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

bool _isSelected(WidgetTester tester, String label) {
  final items = tester.widgetList<Semantics>(
    find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    ),
  );
  expect(items, isNotEmpty, reason: 'no dock item labelled $label');
  return items.any((widget) => widget.properties.selected == true);
}

class _HostedNavigationObserver extends NavigatorObserver {
  var pushes = 0;
  var pops = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
    super.didPop(route, previousRoute);
  }
}

void main() {
  for (final destination in [
    (0, 0, 'Home'),
    (_serversSlot, 1, 'Servers'),
    (5, 3, 'Moments'),
  ]) {
    testWidgets(
      'retapping selected ${destination.$3} exits hosted route exactly once',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final navigatorKey = GlobalKey<NavigatorState>();
        final observer = _HostedNavigationObserver();
        final requests = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [observer],
            theme: ThemeData.dark(useMaterial3: true),
            home: const Scaffold(body: Text('RETAINED ROOT CONTENT')),
          ),
        );
        final rootElement = tester.element(find.text('RETAINED ROOT CONTENT'));
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => MoreDestinationHost(
              body: const Text('HOSTED PROFILE OR SETTINGS'),
              selectedIndex: destination.$1,
              unreadConversationCount: 0,
              onDestinationSelected: requests.add,
              onVoicePressed: () =>
                  fail('Retapping a destination must not open voice actions'),
              onMorePressed: () =>
                  fail('Retapping a destination must not open More'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(_isSelected(tester, destination.$3), isTrue);
        final tap = tester
            .widget<InkWell>(
              find.byKey(ValueKey('yo-destination-${destination.$2}')),
            )
            .onTap!;
        tap();
        tap();
        await tester.pump();
        expect(
          observer.pops,
          1,
          reason: 'The hosted route owns one navigation commit.',
        );
        expect(
          requests,
          isEmpty,
          reason: 'Forward only after reverse transition completes.',
        );
        await tester.pumpAndSettle();
        expect(requests, [destination.$1]);
        expect(observer.pops, 1);
        expect(
          observer.pushes,
          2,
          reason: 'No duplicate root or content route may be pushed.',
        );
        expect(navigatorKey.currentState!.canPop(), isFalse);
        expect(find.text('HOSTED PROFILE OR SETTINGS'), findsNothing);
        expect(find.text('RETAINED ROOT CONTENT'), findsOneWidget);
        expect(
          identical(
            tester.element(find.text('RETAINED ROOT CONTENT')),
            rootElement,
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'hosted dock has five real destinations and no central voice action',
    (tester) async {
      var voiceOpened = 0;
      final semantics = await _pumpHost(
        tester,
        body: const Text('BODY'),
        selectedIndex: 0,
        onVoicePressed: () => voiceOpened++,
      );
      expect(find.byKey(const ValueKey('dock-logo')), findsNothing);
      expect(
        find.byKey(const ValueKey('yo-center-action-hit-target')),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Open voice actions'), findsNothing);
      for (final label in ['Home', 'Servers', 'Chats', 'Moments', 'More']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      expect(voiceOpened, 0);
      expect(_isSelected(tester, 'Home'), isTrue);
      semantics.dispose();
    },
  );
  testWidgets('Moments domain slot selects Moments in hosted dock', (
    tester,
  ) async {
    final semantics = await _pumpHost(
      tester,
      body: const Text('BODY'),
      selectedIndex: _momentsSlot,
    );
    expect(_isSelected(tester, 'Moments'), isTrue);
    expect(_isSelected(tester, 'Home'), isFalse);
    semantics.dispose();
  });
  testWidgets(
    'hosted Moment detail preserves content and the active navigation',
    (tester) async {
      final semantics = await _pumpHost(
        tester,
        body: MomentDetailScreen(moment: _moment()),
        selectedIndex: _momentsSlot,
      );
      expect(find.byKey(const ValueKey('moment-detail-back')), findsOneWidget);
      expect(find.text('The one thing nobody tells you.'), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-detail-play')), findsOneWidget);
      expect(find.text('Moments'), findsOneWidget);
      expect(find.byKey(const ValueKey('dock-logo')), findsNothing);
      expect(_isSelected(tester, 'Moments'), isTrue);
      semantics.dispose();
    },
  );
  testWidgets('hosted detail Home tap still uses shell callback', (
    tester,
  ) async {
    int? selected;
    final semantics = await _pumpHost(
      tester,
      body: MomentDetailScreen(moment: _moment()),
      selectedIndex: _momentsSlot,
      onDestinationSelected: (index) => selected = index,
    );
    await tester.tap(find.byKey(const ValueKey('yo-destination-0')));
    await tester.pumpAndSettle();
    expect(selected, 0);
    semantics.dispose();
  });
  testWidgets('hosted Servers cell routes to the stable Servers slot 13, '
      'not Chats', (tester) async {
    int? selected;
    final semantics = await _pumpHost(
      tester,
      body: const Text('BODY'),
      selectedIndex: _momentsSlot,
      onDestinationSelected: (index) => selected = index,
    );
    await tester.tap(find.byKey(const ValueKey('yo-destination-1')));
    await tester.pumpAndSettle();
    expect(selected, _serversSlot);
    expect(selected, 13);
    semantics.dispose();
  });
}
