import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';

import 'moments_overview_test_support.dart';

/// Re-activating the selected format tab reloads that format, the same way
/// on both halves of YO Moments: "Yeels" re-reads its pool (covered in
/// `yeels_one_row_chrome_test.dart`), and "Głos" reloads its active filter
/// through `MomentsFeedView.refreshRequests` — the path re-tapping the active
/// filter tab already takes.
void main() {
  setUpAll(loadInterFont);
  late VoidCallback restoreIdentity;
  setUp(() => restoreIdentity = installIdentityStub());
  tearDown(() => restoreIdentity());

  const voiceTab = ValueKey<String>('yo-moments-format-voice');

  Future<StaticDiscovery> pumpVoice(WidgetTester tester) async {
    const size = Size(390, 844);
    useSurface(tester, size);
    final discovery = StaticDiscovery(populatedPool());
    final auth = authAs('viewer');
    await tester.pumpWidget(
      overviewHost(
        MomentsScreen(
          isRootTab: true,
          initialFormat: YoMomentsFormat.voice,
          auth: auth,
          discoveryService: discovery,
          feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
          viewsService: StaticViews(const <String>{}),
          playerFactory: SilentPlayer.new,
          reelService: ReelService(
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
            ),
            callableInvoker: (name, payload) async => <String, Object?>{
              'schemaVersion': 2,
              'items': const <Object?>[],
              'nextCursor': null,
            },
          ),
          onCreateReel: () async {},
        ),
        size: size,
        locale: const Locale('pl'),
      ),
    );
    await settleOverview(tester);
    return discovery;
  }

  testWidgets('tapping the selected Głos tab reloads the Voice feed once', (
    tester,
  ) async {
    final discovery = await pumpVoice(tester);
    final before = discovery.loadCalls;
    expect(before, greaterThan(0));

    await tester.tap(find.byKey(voiceTab));
    await tester.pump(const Duration(milliseconds: 400));
    await settleOverview(tester);

    expect(discovery.loadCalls, before + 1);
    // Still Głos: re-selecting is not a format change.
    expect(find.byKey(const ValueKey('moments-feed')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the selected Głos tab tells assistive technology it refreshes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpVoice(tester);

    final node = tester.getSemantics(find.byKey(voiceTab));
    expect(node.hint, 'Odśwież');
    handle.dispose();
  });
}
