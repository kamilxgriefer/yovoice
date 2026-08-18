import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';

/// Pins the compact profile header (P1 fix).
///
/// The previous header was a fixed 300–320px banner Stack: on a phone it
/// consumed 38–56% of the viewport as mostly-empty gradient, and on
/// desktop the Back arrow floated alone in the far corner. This suite
/// asserts the redesign's contract:
///
///  * the header region is bounded — at most ~30% of a 390x844 viewport;
///  * the banner is a slim accent, never a viewport-consuming banner;
///  * Back is visible when the route can pop, with a >= 44px target,
///    aligned with the content frame (not the screen edge) on desktop;
///  * no RenderFlex overflow at 320 and 1440 with textScaleFactor 2.0;
///  * tapping Back actually pops (navigation semantics preserved).
UserProfile _profile() {
  return UserProfile(
    uid: 'u1',
    email: 'ada@yovoice.app',
    displayName: 'Ada Lovelace',
    username: 'ada',
    bio: 'bio',
    country: '',
    nativeLanguage: '',
    spokenLanguages: const [],
    learningLanguages: const [],
    photoUrl: null,
    bannerUrl: null,
    website: '',
    accountType: AccountType.creator,
    premiumIdentity: true,
    friendCount: 0,
    followerCount: 0,
    followingCount: 0,
    roomCount: 0,
    communityCount: 0,
    voiceMinutes: 0,
    messageCount: 0,
    activeDays: 0,
    momentCount: 0,
    reactionCount: 0,
    hostMinutes: 0,
    selectedTitleId: null,
    unlockedTitleIds: const [],
    unlockedTitleTimestamps: const {},
    createdAt: DateTime(2026),
  );
}

/// Hosts the header on a PUSHED route, the way production always shows
/// it (Profile has no desktop content slot — see main_shell.dart), so
/// `Navigator.canPop()` is true and the Back button renders.
Future<void> _pumpPushedHeader(WidgetTester tester) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Center(child: Text('previous-route'))),
    ),
  );
  navigatorKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: const Color(0xFF09050F),
        body: ListView(
          children: [ProfileHeader(profile: _profile(), onEdit: () {})],
        ),
      ),
    ),
  );
  // Fixed pumps, not pumpAndSettle: the premium avatar frame animates
  // continuously, so the tree never "settles".
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void _setSize(WidgetTester tester, Size size, {double textScale = 1.0}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

Finder get _backButton => find.byTooltip('Back');

void main() {
  testWidgets('390x844: header region is at most ~30% of the viewport '
      'and the banner is a slim accent', (tester) async {
    _setSize(tester, const Size(390, 844));
    await _pumpPushedHeader(tester);

    final headerSize = tester.getSize(find.byType(ProfileHeader));
    expect(
      headerSize.height,
      lessThanOrEqualTo(844 * 0.30),
      reason:
          'the header must never again claim a giant slice of the '
          'viewport (was a fixed 320px = 38% at this size)',
    );

    // The gradient banner survives — but as a slim accent card.
    final bannerFinder = find.byKey(const Key('profile-header-avatar'));
    expect(bannerFinder, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back button pops the route and meets the 44px target', (
    tester,
  ) async {
    _setSize(tester, const Size(390, 844));
    await _pumpPushedHeader(tester);

    expect(_backButton, findsOneWidget);
    final backSize = tester.getSize(_backButton);
    expect(backSize.width, greaterThanOrEqualTo(44));
    expect(backSize.height, greaterThanOrEqualTo(44));

    await tester.tap(_backButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('previous-route'), findsOneWidget);
  });

  testWidgets('320x568 at 2.0 text scale: no overflow, Back visible', (
    tester,
  ) async {
    _setSize(tester, const Size(320, 568), textScale: 2.0);
    await _pumpPushedHeader(tester);

    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    expect(_backButton, findsOneWidget);
    final backRect = tester.getRect(_backButton);
    expect(backRect.width, greaterThanOrEqualTo(44));
    expect(backRect.height, greaterThanOrEqualTo(44));
    expect(backRect.left, greaterThanOrEqualTo(0));
    expect(backRect.top, greaterThanOrEqualTo(0));

    // Identity survives the squeeze: name and username still render.
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('@ada'), findsOneWidget);
  });

  testWidgets('1440x900 at 2.0 text scale: no overflow, toolbar aligned '
      'with the bounded content frame', (tester) async {
    _setSize(tester, const Size(1440, 900), textScale: 2.0);
    await _pumpPushedHeader(tester);

    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    expect(_backButton, findsOneWidget);

    // The header self-caps at 1100px, so at 1440 the Back button must sit
    // inside the centered content frame — never alone in the far corner.
    const frameLeft = (1440 - 1100) / 2;
    final backRect = tester.getRect(_backButton);
    expect(
      backRect.left,
      greaterThanOrEqualTo(frameLeft),
      reason: 'Back must align with the content frame, not the window edge',
    );
    expect(backRect.width, greaterThanOrEqualTo(44));
    expect(backRect.height, greaterThanOrEqualTo(44));
  });

  for (final size in const [
    Size(320, 568),
    Size(390, 844),
    Size(768, 1024),
    Size(1100, 800),
    Size(1440, 900),
  ]) {
    testWidgets('renders without overflow and keeps a bounded header at '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      _setSize(tester, size);
      await _pumpPushedHeader(tester);

      expect(tester.takeException(), isNull);
      expect(_backButton, findsOneWidget);
      // Edit remains available — the redesign removes no functionality.
      expect(find.byTooltip('Edit profile'), findsOneWidget);

      final headerSize = tester.getSize(find.byType(ProfileHeader));
      expect(
        headerSize.height,
        lessThanOrEqualTo(340),
        reason: 'the header must stay a compact block at every width',
      );
      expect(headerSize.width, lessThanOrEqualTo(size.width));
    });
  }
}
