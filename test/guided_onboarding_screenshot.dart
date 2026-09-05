// Developer-only VISUAL harness for the guided onboarding product tour.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/guided_onboarding_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored). The tour itself and its
// spotlight anchors are production widgets; only the content behind them is
// a deterministic shell preview so visual evidence never depends on Firebase.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/onboarding/presentation/guided_onboarding_tour.dart';

final _capture = GlobalKey(debugLabel: 'guided onboarding capture');

String get _fontRoot {
  const candidates = [
    '/opt/homebrew/Caskroom/flutter/3.44.6/flutter/bin/cache/artifacts/material_fonts',
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
  return candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
  );
}

Future<void> _loadFonts() async {
  Future<ByteData> read(String name) async {
    final bytes = File('$_fontRoot/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  final roboto = FontLoader('Roboto');
  for (final face in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    roboto.addFont(read(face));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();

  final inter = FontLoader('Inter')
    ..addFont(
      Future.value(
        ByteData.view(
          Uint8List.fromList(
            File('assets/fonts/InterVariable.ttf').readAsBytesSync(),
          ).buffer,
        ),
      ),
    );
  await inter.load();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name must render cleanly');
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/.screenshots/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

Future<void> _tapNext(WidgetTester tester) async {
  final next = find.byKey(const ValueKey('guided-tour-next'));
  await tester.ensureVisible(next);
  await tester.pump();
  await tester.tap(next);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _renderSequence(
  WidgetTester tester, {
  required String prefix,
  required Size viewport,
  required ThemeData theme,
  required bool desktop,
  double textScale = 1,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          final original = MediaQuery.of(context);
          final safePadding = desktop
              ? EdgeInsets.zero
              : const EdgeInsets.only(top: 44, bottom: 34);
          return MediaQuery(
            data: original.copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
              padding: safePadding,
              viewPadding: safePadding,
            ),
            child: child!,
          );
        },
        home: _TourShellPreview(desktop: desktop),
      ),
    ),
  );

  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/images/yo-voice-favicon-512.png'),
      _capture.currentContext!,
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('guided-tour-card')), findsOneWidget);
  await _shoot(tester, '$prefix-welcome');

  await _tapNext(tester);
  expect(find.text('Use your voice'), findsOneWidget);
  await _shoot(tester, '$prefix-create');

  await _tapNext(tester);
  await _tapNext(tester);
  await _tapNext(tester);
  expect(find.text('More, one tap away'), findsOneWidget);
  await _shoot(tester, '$prefix-more');
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('mobile 390x844 dark: welcome, create, More', (tester) async {
    await _renderSequence(
      tester,
      prefix: 'guided-tour-mobile-dark-390x844',
      viewport: const Size(390, 844),
      theme: AppTheme.darkTheme,
      desktop: false,
    );
  });

  testWidgets('mobile 390x844 Pearl: welcome, create, More', (tester) async {
    await _renderSequence(
      tester,
      prefix: 'guided-tour-mobile-pearl-390x844',
      viewport: const Size(390, 844),
      theme: AppTheme.lightTheme,
      desktop: false,
    );
  });

  testWidgets('mobile 320x568 dark at 200%: welcome, create, More', (
    tester,
  ) async {
    await _renderSequence(
      tester,
      prefix: 'guided-tour-mobile-dark-320x568-scale2',
      viewport: const Size(320, 568),
      theme: AppTheme.darkTheme,
      desktop: false,
      textScale: 2,
    );
  });

  testWidgets('desktop 1440x900 dark: welcome, create, More', (tester) async {
    await _renderSequence(
      tester,
      prefix: 'guided-tour-desktop-dark-1440x900',
      viewport: const Size(1440, 900),
      theme: AppTheme.darkTheme,
      desktop: true,
    );
  });
}

class _TourShellPreview extends StatefulWidget {
  const _TourShellPreview({required this.desktop});

  final bool desktop;

  @override
  State<_TourShellPreview> createState() => _TourShellPreviewState();
}

class _TourShellPreviewState extends State<_TourShellPreview> {
  final Map<GuidedOnboardingTarget, GlobalKey> _anchors = {
    for (final target in GuidedOnboardingTarget.values)
      target: GlobalKey(debugLabel: 'preview-${target.name}'),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        showGuidedOnboardingTour(
          context,
          anchors: _anchors,
          desktop: widget.desktop,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.desktop
      ? _DesktopShell(anchors: _anchors)
      : _MobileShell(anchors: _anchors);
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({required this.anchors});

  final Map<GuidedOnboardingTarget, GlobalKey> anchors;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: palette.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Good evening,',
                          style: TextStyle(color: palette.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ada',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  _RoundAction(icon: Icons.notifications_none_rounded),
                  const SizedBox(width: 10),
                  const CircleAvatar(
                    radius: 23,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      'A',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 36),
              const _PreviewHeading('YO Moments from your circle'),
              const SizedBox(height: 14),
              Wrap(
                spacing: 18,
                runSpacing: 12,
                children: const [
                  _MomentAvatar(initial: '+', label: 'YO Moments'),
                  _MomentAvatar(initial: 'M', label: 'Maya'),
                  _MomentAvatar(initial: 'L', label: 'Leo'),
                ],
              ),
              const SizedBox(height: 34),
              const _PreviewHeading('Rooms for you'),
              const SizedBox(height: 14),
              const _RoomPreview(
                title: 'Late night stories',
                subtitle: 'Live · 18 voices',
                icon: Icons.nights_stay_rounded,
              ),
              const SizedBox(height: 12),
              const _RoomPreview(
                title: 'Creators coffee',
                subtitle: 'Starting soon',
                icon: Icons.coffee_rounded,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: YoFloatingNavigationDock(
        selectedTabIndex: 0,
        momentsTabIndex: 5,
        unreadConversationCount: 2,
        onDestinationSelected: (_) {},
        onVoicePressed: () {},
        onMorePressed: () {},
        tourDestinationKeys: {
          1: anchors[GuidedOnboardingTarget.chats]!,
          3: anchors[GuidedOnboardingTarget.moments]!,
          4: anchors[GuidedOnboardingTarget.more]!,
        },
        tourVoiceKey: anchors[GuidedOnboardingTarget.create],
      ),
    );
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({required this.anchors});

  final Map<GuidedOnboardingTarget, GlobalKey> anchors;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Scaffold(
      body: Row(
        children: [
          DesktopSidebar(
            active: DesktopNavItem.home,
            unreadConversationCount: 2,
            unreadNotificationCount: 1,
            onSelect: (_) {},
            onCreateRoom: () {},
            onCreateMoment: () {},
            onOpenProfile: () {},
            onOpenProfileSettings: () {},
            tourItemKeys: {
              DesktopNavItem.moments: anchors[GuidedOnboardingTarget.moments]!,
              DesktopNavItem.chats: anchors[GuidedOnboardingTarget.chats]!,
              DesktopNavItem.more: anchors[GuidedOnboardingTarget.more]!,
            },
            tourCreateKey: anchors[GuidedOnboardingTarget.create],
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: palette.backgroundGradient),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(48, 42, 48, 48),
                children: const [
                  Text(
                    'Good evening, Ada',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Your voice world, all in one place.',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 38),
                  _DesktopPreviewGrid(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopPreviewGrid extends StatelessWidget {
  const _DesktopPreviewGrid();

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Expanded(
        child: _RoomPreview(
          title: 'Rooms for you',
          subtitle: 'Discover live conversations',
          icon: Icons.graphic_eq_rounded,
          height: 240,
        ),
      ),
      const SizedBox(width: 18),
      Expanded(
        child: Column(
          children: const [
            _RoomPreview(
              title: 'Your recent chats',
              subtitle: '2 new messages',
              icon: Icons.chat_bubble_rounded,
              height: 108,
            ),
            SizedBox(height: 18),
            _RoomPreview(
              title: 'Voice Moments',
              subtitle: 'Fresh from your circle',
              icon: Icons.mic_rounded,
              height: 114,
            ),
          ],
        ),
      ),
    ],
  );
}

class _PreviewHeading extends StatelessWidget {
  const _PreviewHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
  );
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      color: context.appPalette.surfaceRaised,
      shape: BoxShape.circle,
      border: Border.all(color: context.appPalette.border),
    ),
    child: Icon(icon),
  );
}

class _MomentAvatar extends StatelessWidget {
  const _MomentAvatar({required this.initial, required this.label});

  final String initial;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.secondary],
          ),
          border: Border.all(color: context.appPalette.focus, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: 7),
      Text(label, style: const TextStyle(fontSize: 11)),
    ],
  );
}

class _RoomPreview extends StatelessWidget {
  const _RoomPreview({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.height = 116,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      height: height,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: palette.surface,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textSecondary, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
