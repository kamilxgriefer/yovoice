import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';

import 'moments_overview_test_support.dart';

/// The states the boards omit: loading silhouettes without fake authors or
/// panels, per-pool empty copy with real actions, the error card with a
/// retry, a refresh failure that keeps the cards and speaks once, Pearl.
void main() {
  late VoidCallback restoreIdentity;

  setUp(() => restoreIdentity = installIdentityStub());
  tearDown(() => restoreIdentity());

  Future<void> pumpFeed(
    WidgetTester tester, {
    required Size size,
    required MomentDiscoveryService discovery,
    MomentsFilter initialFilter = MomentsFilter.discover,
    List<VoiceMoment> social = const [],
    bool light = false,
    VoidCallback? onOpenFindCreators,
    VoidCallback? onRecord,
    bool withPool = true,
  }) async {
    useSurface(tester, size);
    final auth = authAs();
    final firestore = fakeFirestore();
    await tester.pumpWidget(
      overviewHost(
        Scaffold(
          body: MomentsFeedView(
            auth: auth,
            onRecord: onRecord ?? () {},
            onCreate: () {},
            onOpenFindCreators: onOpenFindCreators,
            initialFilter: initialFilter,
            discoveryService: discovery,
            feedService: QuietFeed(
              firestore: firestore,
              auth: auth,
              social: social,
            ),
            viewsService: StaticViews(const <String>{}),
            friendService: StaticFriends(
              firestore: firestore,
              auth: auth,
              friends: withPool ? [friend('ola', name: 'Ola')] : null,
            ),
            followService: FollowService(firestore: firestore, auth: auth),
            playerFactory: SilentPlayer.new,
          ),
        ),
        light: light,
        size: size,
      ),
    );
    await settleOverview(tester);
  }

  testWidgets('loading shows three card silhouettes and NO capsules, NO calm '
      'panel — then the real page replaces them', (tester) async {
    final gate = Completer<void>();
    await pumpFeed(
      tester,
      size: const Size(1300, 900),
      discovery: StaticDiscovery(populatedPool(), gate: gate),
    );
    final loading = find.byKey(const ValueKey('moments-discovery-loading'));
    expect(loading, findsOneWidget);
    expect(find.byKey(const ValueKey('moments-author-capsules')), findsNothing);
    expect(find.byKey(const ValueKey('moments-follow-panel')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('yo-moments-local-panel')),
      findsOneWidget,
      reason: 'the chrome stays live while the column loads',
    );
    final semantics = tester.ensureSemantics();
    try {
      expect(find.bySemanticsLabel('Loading Moments'), findsOneWidget);
    } finally {
      semantics.dispose();
    }

    gate.complete();
    await settleOverview(tester);
    expect(loading, findsNothing);
    expect(find.byKey(const ValueKey('moments-author-capsules')), findsOneWidget);
    expect(find.byKey(const ValueKey('moments-follow-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Discover empty: honest copy, the recorder offered, no capsules',
      (tester) async {
    var records = 0;
    await pumpFeed(
      tester,
      size: const Size(390, 844),
      discovery: StaticDiscovery(const <VoiceMoment>[]),
      onRecord: () => records += 1,
    );
    expect(find.byKey(const ValueKey('moments-discovery-empty')), findsOneWidget);
    expect(find.text('No Voice Moments yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('moments-author-capsules')), findsNothing);
    await tester.tap(find.text('Record a Moment'));
    await tester.pump();
    expect(records, 1);
  });

  testWidgets('Following empty: its own copy, the recorder, and "Find people" '
      'only when the host can open it', (tester) async {
    var finds = 0;
    await pumpFeed(
      tester,
      size: const Size(390, 844),
      discovery: StaticDiscovery(populatedPool()),
      initialFilter: MomentsFilter.following,
      onOpenFindCreators: () => finds += 1,
    );
    expect(find.byKey(const ValueKey('moments-following-empty')), findsOneWidget);
    expect(find.text('Nothing here yet'), findsOneWidget);
    final findPeople = find.byKey(const ValueKey('moments-following-find-people'));
    expect(findPeople, findsOneWidget);
    expect(find.text('Find people'), findsOneWidget);
    await tester.tap(findPeople);
    await tester.pump();
    expect(finds, 1);

    await pumpFeed(
      tester,
      size: const Size(390, 844),
      discovery: StaticDiscovery(populatedPool()),
      initialFilter: MomentsFilter.following,
    );
    expect(find.byKey(const ValueKey('moments-following-find-people')), findsNothing,
        reason: 'no dead button when nothing can open Find creators');
  });

  testWidgets('a failed first load is an inline card with one retry that '
      'really reloads', (tester) async {
    final discovery = ThrowingDiscovery();
    await pumpFeed(tester, size: const Size(390, 844), discovery: discovery);
    final error = find.byKey(const ValueKey('moments-discovery-error'));
    expect(error, findsOneWidget);
    expect(find.text('Moments could not load'), findsOneWidget);
    expect(find.byKey(const ValueKey('moments-author-capsules')), findsNothing);
    expect(discovery.loadCalls, 1);
    await tester.tap(find.text('Try again'));
    await settleOverview(tester);
    expect(discovery.loadCalls, 2);
    expect(error, findsOneWidget, reason: 'still failing, still honest');
  });

  testWidgets('a refresh failure keeps the cards on screen and speaks once as '
      'a SnackBar', (tester) async {
    final discovery = StaticDiscovery(populatedPool(), failAfterLoads: 1);
    await pumpFeed(tester, size: const Size(390, 844), discovery: discovery);
    expect(find.byKey(const ValueKey('moment-row-m4')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('moments-discovery-refresh')));
    await settleOverview(tester);
    expect(discovery.loadCalls, 2);
    expect(find.byKey(const ValueKey('moment-row-m4')), findsOneWidget);
    expect(find.byKey(const ValueKey('moments-discovery-error')), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Pearl paints the canvas, the panel and the card from the light '
      'palette — no dark literal leaks', (tester) async {
    await pumpFeed(
      tester,
      size: const Size(1300, 900),
      discovery: StaticDiscovery(populatedPool()),
      light: true,
    );
    final card = find.byKey(const ValueKey('moment-row-m4'));
    final palette = AppPalette.of(tester.element(card));
    expect(palette, AppPalette.light);
    final material = tester.widget<Material>(
      find.descendant(of: card, matching: find.byType(Material)).first,
    );
    expect(material.color, AppPalette.light.surface);
    final panel = tester.widget<Container>(
      find.byKey(const ValueKey<String>('yo-moments-local-panel')),
    );
    expect((panel.decoration as BoxDecoration).color, AppPalette.light.surfaceMuted);
    expect(
      find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Material &&
              (widget.color == AppPalette.dark.surface ||
                  widget.color == AppPalette.dark.surfaceRaised ||
                  widget.color == AppPalette.dark.background),
        ),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
