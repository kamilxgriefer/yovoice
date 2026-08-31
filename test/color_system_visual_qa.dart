// Developer-only visual QA harness for the YO Voice semantic colour system.
//
// Run explicitly:
//   flutter test test/color_system_visual_qa.dart
//
// PNGs land in test/.screenshots/color-system/ (git-ignored). The filename
// deliberately does not end in `_test.dart`, so the regular suite never writes
// screenshot artifacts.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/badges/yo_badge.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/inputs/yo_text_field.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

final _captureKey = GlobalKey();

String _resolveMaterialFontRoot() {
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null) {
    final configured = '$configuredRoot/bin/cache/artifacts/material_fonts';
    if (File('$configured/MaterialIcons-Regular.otf').existsSync()) {
      return configured;
    }
  }

  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final candidate = '${directory.path}/bin/cache/artifacts/material_fonts';
    if (File('$candidate/MaterialIcons-Regular.otf').existsSync()) {
      return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate Flutter material fonts.');
}

ByteData _asByteData(List<int> bytes) {
  final typed = Uint8List.fromList(bytes);
  return ByteData.view(typed.buffer, typed.offsetInBytes, typed.lengthInBytes);
}

Future<void> _loadRealFonts() async {
  Future<ByteData> read(String path) async =>
      _asByteData(File(path).readAsBytesSync());

  final inter = FontLoader('Inter')
    ..addFont(read('assets/fonts/InterVariable.ttf'))
    ..addFont(read('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();

  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(read('${_resolveMaterialFontRoot()}/MaterialIcons-Regular.otf'));
  await materialIcons.load();
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _capturePng(WidgetTester tester, String filename) async {
  await tester.runAsync(() async {
    final boundary =
        _captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;

    // Prime the font and icon atlases. Without this first raster pass a
    // headless engine can intermittently omit one glyph from the evidence.
    final warmup = await boundary.toImage(pixelRatio: 1);
    warmup.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 16));

    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/.screenshots/color-system/$filename.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

void _expectNoFrameworkError(WidgetTester tester) {
  expect(
    tester.takeException(),
    isNull,
    reason: 'The visual QA frame must not overflow or throw.',
  );
}

void _expectSharedTargetsAtLeast44(WidgetTester tester) {
  final sharedButtons = <Finder>[
    find.descendant(
      of: find.byType(YoButton),
      matching: find.byType(ElevatedButton),
    ),
    find.descendant(
      of: find.byType(YoIconButton),
      matching: find.byType(IconButton),
    ),
    find.descendant(
      of: find.byType(YoTextField),
      matching: find.byType(TextFormField),
    ),
  ];

  for (final collection in sharedButtons) {
    for (final element in collection.evaluate()) {
      final target = find.byElementPredicate(
        (candidate) => identical(candidate, element),
      );
      final size = tester.getSize(target);
      expect(
        size.height,
        greaterThanOrEqualTo(44),
        reason: '${element.widget.runtimeType} must keep a 44px target.',
      );
      expect(
        size.width,
        greaterThanOrEqualTo(44),
        reason: '${element.widget.runtimeType} must keep a 44px target.',
      );
    }
  }
}

enum _ShowcasePage { foundation, controls, states, overlays }

class _VisualConfig {
  const _VisualConfig({
    required this.name,
    required this.size,
    required this.brightness,
    this.textScale = 1,
  });

  final String name;
  final Size size;
  final Brightness brightness;
  final double textScale;
}

void main() {
  setUpAll(_loadRealFonts);

  const configurations = <_VisualConfig>[
    _VisualConfig(
      name: '390x844-dark',
      size: Size(390, 844),
      brightness: Brightness.dark,
    ),
    _VisualConfig(
      name: '390x844-pearl',
      size: Size(390, 844),
      brightness: Brightness.light,
    ),
    _VisualConfig(
      name: '1440x900-dark',
      size: Size(1440, 900),
      brightness: Brightness.dark,
    ),
    _VisualConfig(
      name: '1440x900-pearl',
      size: Size(1440, 900),
      brightness: Brightness.light,
    ),
    _VisualConfig(
      name: '320x640-pearl-text-200',
      size: Size(320, 640),
      brightness: Brightness.light,
      textScale: 2,
    ),
  ];

  for (final config in configurations) {
    testWidgets('semantic colour evidence — ${config.name}', (tester) async {
      tester.view.physicalSize = config.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final page in _ShowcasePage.values) {
        final fieldFocus = FocusNode(debugLabel: 'QA focused input');
        final iconFocus = FocusNode(debugLabel: 'QA focused icon action');
        addTearDown(fieldFocus.dispose);
        addTearDown(iconFocus.dispose);

        await tester.pumpWidget(
          _VisualHarnessApp(
            brightness: config.brightness,
            textScale: config.textScale,
            page: page,
            fieldFocus: fieldFocus,
            iconFocus: iconFocus,
          ),
        );
        await _settle(tester);

        if (page == _ShowcasePage.controls) {
          fieldFocus.requestFocus();
          await _settle(tester);
        }
        if (page == _ShowcasePage.foundation) {
          iconFocus.requestFocus();
          await _settle(tester);
        }

        if (page == _ShowcasePage.overlays) {
          final showDialog = find.byKey(const ValueKey('show-qa-dialog'));
          await tester.ensureVisible(showDialog);
          await _settle(tester);
          await tester.tap(showDialog);
          await _settle(tester);
          _expectNoFrameworkError(tester);
          _expectSharedTargetsAtLeast44(tester);
          await _capturePng(tester, '${config.name}-dialog-snackbar');

          await tester.tap(find.byKey(const ValueKey('qa-dialog-close')));
          await _settle(tester);
          _expectNoFrameworkError(tester);
          _expectSharedTargetsAtLeast44(tester);
          await _capturePng(tester, '${config.name}-snackbar');

          final showSheet = find.byKey(const ValueKey('show-qa-sheet'));
          ScaffoldMessenger.of(tester.element(showSheet)).hideCurrentSnackBar();
          await _settle(tester);
          await tester.ensureVisible(showSheet);
          await _settle(tester);
          await tester.tap(showSheet);
          await _settle(tester);
          expect(
            find.byKey(const ValueKey('modal-sheet-close')),
            findsOneWidget,
          );
          _expectNoFrameworkError(tester);
          _expectSharedTargetsAtLeast44(tester);
          await _capturePng(tester, '${config.name}-sheet');
          continue;
        }

        _expectNoFrameworkError(tester);
        _expectSharedTargetsAtLeast44(tester);
        await _capturePng(tester, '${config.name}-${page.name}');

        final scrollable = find.byKey(const ValueKey('qa-scroll'));
        if (scrollable.evaluate().isNotEmpty) {
          await tester.drag(scrollable, const Offset(0, -1200));
          await _settle(tester);
          _expectNoFrameworkError(tester);
          _expectSharedTargetsAtLeast44(tester);
          await _capturePng(tester, '${config.name}-${page.name}-lower');
        }
      }
    });
  }
}

class _VisualHarnessApp extends StatelessWidget {
  const _VisualHarnessApp({
    required this.brightness,
    required this.textScale,
    required this.page,
    required this.fieldFocus,
    required this.iconFocus,
  });

  final Brightness brightness;
  final double textScale;
  final _ShowcasePage page;
  final FocusNode fieldFocus;
  final FocusNode iconFocus;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          );
        },
        home: _ShowcaseScaffold(
          brightness: brightness,
          page: page,
          fieldFocus: fieldFocus,
          iconFocus: iconFocus,
        ),
      ),
    );
  }
}

class _ShowcaseScaffold extends StatelessWidget {
  const _ShowcaseScaffold({
    required this.brightness,
    required this.page,
    required this.fieldFocus,
    required this.iconFocus,
  });

  final Brightness brightness;
  final _ShowcasePage page;
  final FocusNode fieldFocus;
  final FocusNode iconFocus;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final name = brightness == Brightness.dark ? 'Dark' : 'Pearl';
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: palette.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              _PageHeader(themeName: name, page: page),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('qa-scroll'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: _pageBody(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: page == _ShowcasePage.foundation
          ? _NavigationTokenSample(focusNode: iconFocus)
          : null,
    );
  }

  Widget _pageBody(BuildContext context) {
    return switch (page) {
      _ShowcasePage.foundation => const _FoundationShowcase(),
      _ShowcasePage.controls => _ControlsShowcase(focusNode: fieldFocus),
      _ShowcasePage.states => const _StatesShowcase(),
      _ShowcasePage.overlays => const _OverlayLauncher(),
    };
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.themeName, required this.page});

  final String themeName;
  final _ShowcasePage page;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scaledLabelHeight = MediaQuery.textScalerOf(
              context,
            ).scale(14);
            final useStackedHeader =
                constraints.maxWidth < 360 || scaledLabelHeight >= 24;
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'YO Voice colour system',
                  style: AppTypography.headlineMedium.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$themeName · ${page.name}',
                  style: AppTypography.bodyMedium.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            );
            const badge = YoBadge(
              label: 'Visual QA',
              variant: YoBadgeVariant.info,
              icon: Icons.visibility_rounded,
            );

            if (useStackedHeader) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  title,
                  const SizedBox(height: AppSpacing.sm),
                  badge,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: title),
                const SizedBox(width: AppSpacing.sm),
                badge,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FoundationShowcase extends StatelessWidget {
  const _FoundationShowcase();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionTitle(
          title: 'Surface hierarchy',
          subtitle: 'Canvas, nested surfaces, borders and readable copy.',
        ),
        const SizedBox(height: AppSpacing.sm),
        YoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SurfaceLayer(
                name: 'Surface',
                description: 'Primary content card',
                color: palette.surface,
                foreground: palette.textPrimary,
                border: palette.border,
              ),
              const SizedBox(height: AppSpacing.sm),
              _SurfaceLayer(
                name: 'Raised',
                description: 'Inputs, menus and active chrome',
                color: palette.surfaceRaised,
                foreground: palette.textPrimary,
                border: palette.borderStrong,
              ),
              const SizedBox(height: AppSpacing.sm),
              _SurfaceLayer(
                name: 'Muted / sunken',
                description: 'Secondary and disabled regions',
                color: palette.surfaceSunken,
                foreground: palette.textSecondary,
                border: palette.border,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _SectionTitle(
          title: 'Semantic badges',
          subtitle: 'Every status pairs colour with text and an icon.',
        ),
        const SizedBox(height: AppSpacing.sm),
        const Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            YoBadge(
              label: 'Premium',
              variant: YoBadgeVariant.primary,
              icon: Icons.workspace_premium_rounded,
            ),
            YoBadge(
              label: 'Connected',
              variant: YoBadgeVariant.success,
              icon: Icons.check_circle_outline_rounded,
            ),
            YoBadge(
              label: 'Needs review',
              variant: YoBadgeVariant.warning,
              icon: Icons.warning_amber_rounded,
            ),
            YoBadge(
              label: 'Offline',
              variant: YoBadgeVariant.error,
              icon: Icons.cloud_off_rounded,
            ),
            YoBadge(
              label: 'New update',
              variant: YoBadgeVariant.info,
              icon: Icons.info_outline_rounded,
            ),
          ],
        ),
      ],
    );
  }
}

class _SurfaceLayer extends StatelessWidget {
  const _SurfaceLayer({
    required this.name,
    required this.description,
    required this.color,
    required this.foreground,
    required this.border,
  });

  final String name;
  final String description;
  final Color color;
  final Color foreground;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.md,
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            name,
            style: AppTypography.titleMedium.copyWith(color: foreground),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            description,
            style: AppTypography.bodySmall.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

class _ControlsShowcase extends StatelessWidget {
  const _ControlsShowcase({required this.focusNode});

  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionTitle(
          title: 'Action states',
          subtitle: 'Enabled and disabled variants keep text legible.',
        ),
        const SizedBox(height: AppSpacing.sm),
        YoCard(
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              YoButton(
                label: 'Primary',
                icon: const Icon(Icons.mic_rounded),
                onPressed: () {},
                fullWidth: false,
                height: 48,
              ),
              const YoButton(
                label: 'Primary disabled',
                onPressed: null,
                fullWidth: false,
                height: 48,
              ),
              YoButton(
                label: 'Secondary',
                icon: const Icon(Icons.tune_rounded),
                variant: YoButtonVariant.secondary,
                onPressed: () {},
                fullWidth: false,
                height: 48,
              ),
              const YoButton(
                label: 'Secondary disabled',
                variant: YoButtonVariant.secondary,
                onPressed: null,
                fullWidth: false,
                height: 48,
              ),
              YoButton(
                label: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded),
                variant: YoButtonVariant.danger,
                onPressed: () {},
                fullWidth: false,
                height: 48,
              ),
              const YoButton(
                label: 'Delete disabled',
                variant: YoButtonVariant.danger,
                onPressed: null,
                fullWidth: false,
                height: 48,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _SectionTitle(
          title: 'Input states',
          subtitle: 'Focused, error and disabled states use semantic roles.',
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final useColumns = constraints.maxWidth >= 780;
            final itemWidth = useColumns
                ? (constraints.maxWidth - AppSpacing.md) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: <Widget>[
                SizedBox(
                  width: itemWidth,
                  child: YoTextField(
                    focusNode: focusNode,
                    label: 'Focused field',
                    hint: 'What is your current vibe?',
                    helperText: 'Visible focus uses the semantic focus token.',
                    prefixIcon: const Icon(Icons.auto_awesome_rounded),
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: const YoTextField.email(
                    label: 'Email with error',
                    hint: 'name@example.com',
                    errorText: 'Enter a valid email address.',
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: const YoTextField(
                    label: 'Disabled field',
                    hint: 'Unavailable while saving',
                    enabled: false,
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StatesShowcase extends StatelessWidget {
  const _StatesShowcase();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionTitle(
          title: 'Status communication',
          subtitle: 'Colour never carries the message by itself.',
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final useColumns = constraints.maxWidth >= 700;
            final width = useColumns
                ? (constraints.maxWidth - AppSpacing.md) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: <Widget>[
                SizedBox(
                  width: width,
                  child: const _StatusCard(
                    kind: _StatusKind.success,
                    title: 'Room is live',
                    message: 'Audio is connected and ready.',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: const _StatusCard(
                    kind: _StatusKind.warning,
                    title: 'Connection unstable',
                    message: 'Voice quality may briefly drop.',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: const _StatusCard(
                    kind: _StatusKind.info,
                    title: 'Update available',
                    message: 'A new tester build is ready.',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: const _StatusCard(
                    kind: _StatusKind.danger,
                    title: 'Message not sent',
                    message: 'Check your connection and retry.',
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        const _SectionTitle(
          title: 'System states',
          subtitle: 'Loading, empty and recoverable error treatments.',
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final useColumns = constraints.maxWidth >= 900;
            final width = useColumns
                ? (constraints.maxWidth - AppSpacing.md * 2) / 3
                : constraints.maxWidth;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: width,
                  child: const YoCard(
                    child: SizedBox(
                      height: 186,
                      child: Center(
                        child: YoLoadingIndicator(
                          message: 'Loading your rooms…',
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: YoCard(
                    child: YoEmptyState(
                      icon: Icons.forum_outlined,
                      title: 'No chats yet',
                      subtitle: 'Start a conversation with someone you trust.',
                      actionLabel: 'Find people',
                      onAction: () {},
                      compact: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: YoCard(
                    child: YoErrorState(
                      message: 'We could not refresh this list.',
                      onRetry: () {},
                      compact: true,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

enum _StatusKind { success, warning, info, danger }

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.kind,
    required this.title,
    required this.message,
  });

  final _StatusKind kind;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final (surface, foreground, icon) = switch (kind) {
      _StatusKind.success => (
        palette.successSurface,
        palette.successForeground,
        Icons.check_circle_outline_rounded,
      ),
      _StatusKind.warning => (
        palette.warningSurface,
        palette.warningForeground,
        Icons.warning_amber_rounded,
      ),
      _StatusKind.info => (
        palette.infoSurface,
        palette.infoForeground,
        Icons.info_outline_rounded,
      ),
      _StatusKind.danger => (
        palette.dangerSurface,
        palette.dangerForeground,
        Icons.error_outline_rounded,
      ),
    };

    return YoCard(
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: surface, borderRadius: AppRadius.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: foreground, size: 24),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: AppTypography.titleMedium.copyWith(
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message,
                    style: AppTypography.bodySmall.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationTokenSample extends StatelessWidget {
  const _NavigationTokenSample({required this.focusNode});

  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.navigationSurface,
          borderRadius: AppRadius.xl,
          border: Border.all(color: palette.navigationOutline),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: palette.shadow.withValues(alpha: .18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: NavigationBar(
                selectedIndex: 0,
                destinations: const <NavigationDestination>[
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.chat_bubble_outline_rounded),
                    selectedIcon: Icon(Icons.chat_bubble_rounded),
                    label: 'Chats',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.grid_view_rounded),
                    label: 'More',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: YoIconButton(
                icon: Icons.add_rounded,
                tooltip: 'Create room',
                semanticLabel: 'Create room',
                focusNode: focusNode,
                onPressed: () {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayLauncher extends StatelessWidget {
  const _OverlayLauncher();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionTitle(
          title: 'Overlay surfaces',
          subtitle: 'Dialog, sheet and snackbar use semantic elevated roles.',
        ),
        const SizedBox(height: AppSpacing.sm),
        YoCard(
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              YoButton(
                key: const ValueKey('show-qa-dialog'),
                label: 'Show dialog',
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: () => _showDialogAndSnackBar(context),
                fullWidth: false,
                height: 48,
              ),
              YoButton(
                key: const ValueKey('show-qa-sheet'),
                label: 'Show sheet',
                icon: const Icon(Icons.vertical_align_top_rounded),
                variant: YoButtonVariant.secondary,
                onPressed: () => _showSheet(context),
                fullWidth: false,
                height: 48,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDialogAndSnackBar(BuildContext context) {
    final palette = context.appPalette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: <Widget>[
            Icon(Icons.check_circle_outline_rounded, size: 20),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('Changes saved to your profile.')),
          ],
        ),
        action: SnackBarAction(label: 'View', onPressed: () {}),
      ),
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.notifications_active_outlined,
          color: palette.interactiveForeground,
        ),
        title: const Text('Turn on notifications?'),
        content: const Text(
          'Choose when YO Voice should let you know about conversations.',
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey('qa-dialog-close'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Not now'),
          ),
          FilledButton(onPressed: () {}, child: const Text('Continue')),
        ],
      ),
    );
  }

  void _showSheet(BuildContext context) {
    final palette = context.appPalette;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .72,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  YoModalSheetChrome(
                    sheetLabel: 'Room controls',
                    surfaceColor: palette.surfaceRaised,
                    onClose: () => Navigator.of(sheetContext).pop(),
                    handleColor: palette.borderStrong,
                    closeColor: palette.textPrimary,
                  ),
                  Text(
                    'Room controls',
                    style: AppTypography.headlineSmall.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Everyone can hear you. Muting will keep the room open.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _StatusCard(
                    kind: _StatusKind.success,
                    title: 'Microphone connected',
                    message: 'Your voice is live in the room.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  YoButton(
                    label: 'Mute microphone',
                    icon: const Icon(Icons.mic_off_rounded),
                    onPressed: () {},
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  YoButton(
                    label: 'Leave room',
                    icon: const Icon(Icons.logout_rounded),
                    variant: YoButtonVariant.danger,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: AppTypography.titleLarge.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: AppTypography.bodyMedium.copyWith(
            color: palette.textSecondary,
          ),
        ),
      ],
    );
  }
}
