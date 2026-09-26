// Local-only PRIMITIVES SAMPLE SHEET for the refine-look batch 1
// ("simple, but super wow"): every new finish recipe and primitive, drawn
// by the real widgets from lib/ — no mock drawings, no screenshots pasted in.
//
// Names and copy come from the redesign preview's fixtures
// (lib/dev/redesign_preview.dart) and the app's own Polish strings; there is
// no real user data and no network.
//
//   flutter run -t lib/dev/refine_sheet_preview.dart -d <device>
//     --dart-define=YO_PREVIEW_THEME=dark|pearl   (default dark)
//     --dart-define=YO_PREVIEW_TEXT=100|200       (default 100)
//     --dart-define=YO_PREVIEW_HC=true             (high contrast)
//
// The PNG pages Kamil reviews are rendered by test/refine_sheet_capture.dart.
// Not referenced by lib/main.dart; never part of a shipped build.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_icons.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_greeting_header.dart'
    show HomeHeaderDisc;
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/server_localized_copy.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_panel.dart'
    show serverChannelIcon;
import 'package:yovoice/shared/widgets/badges/yo_badge.dart';
import 'package:yovoice/shared/widgets/badges/yo_metric_pill.dart';
import 'package:yovoice/shared/widgets/badges/yo_progress_ring.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/inputs/yo_search_field.dart';
import 'package:yovoice/shared/widgets/inputs/yo_text_field.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart'
    show YoServerTile;
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart';

void main() {
  const theme = String.fromEnvironment(
    'YO_PREVIEW_THEME',
    defaultValue: 'dark',
  );
  const text = int.fromEnvironment('YO_PREVIEW_TEXT', defaultValue: 100);
  const highContrast = bool.fromEnvironment('YO_PREVIEW_HC');
  runApp(
    RefineSheetApp(
      brightness: theme == 'pearl' ? Brightness.light : Brightness.dark,
      textScale: text / 100,
      highContrast: highContrast,
    ),
  );
}

/// The sheet inside a Polish `MaterialApp` in one theme and text scale.
/// Animations are disabled so every sample is captured at rest.
class RefineSheetApp extends StatelessWidget {
  const RefineSheetApp({
    this.brightness = Brightness.dark,
    this.textScale = 1,
    this.highContrast = false,
    this.sections,
    this.page = 1,
    this.pageCount = 1,
    this.scrollable = true,
    super.key,
  });

  final Brightness brightness;
  final double textScale;

  /// The platform's high-contrast setting, as the samples would read it.
  final bool highContrast;

  /// Which sections to draw (indices into [RefineSheet.sectionCount]); all
  /// when null.
  final List<int>? sections;
  final int page;
  final int pageCount;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // The app hands MaterialApp these twins as its high-contrast themes.
      theme: switch ((brightness, highContrast)) {
        (Brightness.dark, false) => AppTheme.darkTheme,
        (Brightness.dark, true) => AppTheme.darkHighContrastTheme,
        (Brightness.light, false) => AppTheme.lightTheme,
        (Brightness.light, true) => AppTheme.lightHighContrastTheme,
      },
      locale: const Locale('pl'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
          highContrast: highContrast,
        ),
        child: child!,
      ),
      home: RefineSheet(
        sections: sections,
        page: page,
        pageCount: pageCount,
        scrollable: scrollable,
      ),
    );
  }
}

typedef _SectionBuilder = Widget Function(BuildContext context);

class _Section {
  const _Section(this.title, this.code, this.build, {this.controls = false});

  final String title;
  final String code;
  final _SectionBuilder build;

  /// A batch-3 shared-controls section (also captured in high contrast).
  final bool controls;
}

/// The sample sheet itself: a page on the R1 canvas with one section per
/// recipe. Each section is wrapped in a `refine-section-<i>` key so the
/// capture harness can measure and paginate on section boundaries.
class RefineSheet extends StatelessWidget {
  const RefineSheet({
    this.sections,
    this.page = 1,
    this.pageCount = 1,
    this.scrollable = true,
    super.key,
  });

  final List<int>? sections;
  final int page;
  final int pageCount;
  final bool scrollable;

  static const Key contentKey = ValueKey('refine-sheet-content');
  static int get sectionCount => _sections.length;
  static Key sectionKey(int index) => ValueKey('refine-section-$index');

  /// The batch-3 shared-controls sections, by index.
  static List<int> get controlSections => [
    for (var i = 0; i < _sections.length; i++)
      if (_sections[i].controls) i,
  ];

  /// Samples the capture harness puts into a live state before it shoots:
  /// a mouse pointer rests on [hoverProbeKey] and [focusProbeKey] takes
  /// keyboard focus. In `flutter run` they are ordinary samples.
  static const Key hoverProbeKey = ValueKey('refine-probe-hover');
  static const Key focusProbeKey = ValueKey('refine-probe-focus');

  /// The live-state section's samples (see [liveStateShots]).
  static const Key livePrimaryKey = ValueKey('refine-live-primary');
  static const Key liveSecondaryKey = ValueKey('refine-live-secondary');
  static const Key liveIconKey = ValueKey('refine-live-icon');

  /// The two shots the harness takes of a page that holds the live-state
  /// section, as (file suffix, pointer target, keyboard-focus target). The
  /// page's ordinary shot keeps [hoverProbeKey] / [focusProbeKey].
  static const List<(String, Key, Key)> liveStateShots = [
    ('live-a', livePrimaryKey, liveIconKey),
    ('live-b', liveSecondaryKey, livePrimaryKey),
  ];

  static const double gutter = 20;

  static final List<_Section> _sections = <_Section>[
    _Section('Logo', '§4 · W1', (c) => const _LogoSamples()),
    _Section('Karta z poświatą', 'R2 + R3', (c) => const _ContinueCardSample()),
    _Section(
      'Karta bez poświaty',
      'R2 + R14',
      (c) => const _RecordCardSample(),
    ),
    _Section('Karta NA ŻYWO', 'R4 · W2', (c) => const _LiveTileSample()),
    _Section('Przycisk główny', 'R5', (c) => const _PrimaryActionSamples()),
    _Section('Dysk ikony', 'R6', (c) => const _IconDiscSamples()),
    _Section('Akcje tonalne', 'R7', (c) => const _TonalSamples()),
    _Section('Chipy filtrów', 'R8', (c) => const _ChipSamples()),
    _Section(
      'Przyciski wspólne',
      'R5 · R9 · etap 3',
      (c) => const _SharedButtonSamples(),
      controls: true,
    ),
    _Section(
      'Kursor i fokus',
      'R5 · R9 · etap 3',
      (c) => const _LiveStateSamples(),
      controls: true,
    ),
    _Section(
      'Wyszukiwanie i pola',
      'R9 · etap 3',
      (c) => const _SearchFieldSamples(),
      controls: true,
    ),
    _Section(
      'Plakietki i chipy Material',
      'R11 · R8 · etap 3',
      (c) => const _BadgeAndChipSamples(),
      controls: true,
    ),
    _Section('Awatary', 'R10', (c) => const _AvatarSamples()),
    _Section('Licznik', 'R11', (c) => const _CountBadgeSamples()),
    _Section('Pierścień wygasania', 'R12', (c) => const _ExpirySamples()),
    _Section('Fala głosu', 'R13 · A / B', (c) => const _WaveSamples()),
    _Section('Kulka głosu', 'R14 · W3', (c) => const _BeadSamples()),
    _Section('Dymki czatu', 'R15', (c) => const _BubbleSamples()),
    _Section('Kafelki Więcej', 'R16', (c) => const _TileSamples()),
    _Section('Pusty stan z logo', 'R17 · §4', (c) => const _EmptyStateSample()),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final indices =
        sections ?? List<int>.generate(_sections.length, (index) => index);
    final content = Padding(
      key: contentKey,
      padding: const EdgeInsets.fromLTRB(gutter, 28, gutter, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHeader(page: page, pageCount: pageCount),
          for (final index in indices)
            KeyedSubtree(
              key: sectionKey(index),
              child: Padding(
                padding: const EdgeInsets.only(top: 34),
                child: _SectionFrame(section: _sections[index]),
              ),
            ),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: palette.background,
      body: DecoratedBox(
        // R1: the Chats / Friends canvas radial, promoted to a getter.
        decoration: BoxDecoration(gradient: palette.canvasGlow(scheme.primary)),
        child: scrollable
            ? SafeArea(child: SingleChildScrollView(child: content))
            : Align(alignment: Alignment.topCenter, child: content),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.page, required this.pageCount});

  final int page;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final theme = palette.isDark ? 'Ciemny' : 'Jasny (Pearl)';
    final scale = MediaQuery.textScalerOf(context).scale(100).round();
    final contrast = MediaQuery.highContrastOf(context)
        ? ' · wysoki kontrast'
        : '';
    final meta = '$theme$contrast · tekst $scale% · strona $page z $pageCount';
    if (page > 1) {
      return Text(
        'PRÓBKI · ${meta.toUpperCase()}',
        style: AppTypography.overline.copyWith(color: palette.textTertiary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YO VOICE 3.X · PRÓBKI · ETAPY 1–3',
          style: AppTypography.overline.copyWith(
            color: palette.interactiveForeground,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Wykończenie klocków',
          style: AppTypography.screenTitle.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'Prawdziwe widżety z aplikacji, bez makiet. Światło tylko z logo, '
          'z NA ŻYWO i z grającego głosu.',
          style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: 6),
        Text(
          meta,
          style: AppTypography.labelMedium.copyWith(
            color: palette.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _SectionFrame extends StatelessWidget {
  const _SectionFrame({required this.section});

  final _Section section;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                section.title,
                style: AppTypography.sectionTitle.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.glass,
                borderRadius: AppRadius.pill,
                border: Border.all(color: palette.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                child: Text(
                  section.code,
                  style: AppTypography.overline.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        section.build(context),
      ],
    );
  }
}

/// A small caption under a sample.
class _Caption extends StatelessWidget {
  const _Caption(this.text, {this.align = TextAlign.start});

  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        textAlign: align,
        style: AppTypography.labelMedium.copyWith(
          color: context.appPalette.textTertiary,
          height: 1.35,
        ),
      ),
    );
  }
}

bool _bigText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) >= 1.6;

// ---------------------------------------------------------------------------
// §4 — the real logo
// ---------------------------------------------------------------------------

class _LogoSamples extends StatelessWidget {
  const _LogoSamples();

  @override
  Widget build(BuildContext context) {
    final dark = context.appPalette.isDark;
    final light = dark ? 'poświata' : 'cień kontaktowy';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: YoBrandLockup(),
        ),
        _Caption('Start: znak 32 px bez kafelka + niezmieniony napis · $light'),
        const SizedBox(height: 24),
        Wrap(
          spacing: 36,
          runSpacing: 20,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _LabelledMark(size: 56, caption: '56 px · $light'),
            _LabelledMark(size: 96, caption: '96 px · $light'),
          ],
        ),
        const SizedBox(height: 28),
        // The startup screen is immersive (dark in both themes), so its
        // sample is drawn on the immersive canvas in both sheet themes too.
        const DecoratedBox(
          key: ValueKey('refine-logo-immersive'),
          decoration: BoxDecoration(
            color: AppImmersiveColors.background,
            borderRadius: AppRadius.block,
          ),
          child: SizedBox(
            height: 208 + 72,
            child: Center(
              child: YoBrandMark(size: 208, light: YoBrandLight.bloom),
            ),
          ),
        ),
        const _Caption(
          '208 px z poświatą na ciemnym tle ekranu startowego (w aplikacji '
          'zawsze ciemny, w obu motywach)',
          align: TextAlign.center,
        ),
      ],
    );
  }
}

class _LabelledMark extends StatelessWidget {
  const _LabelledMark({required this.size, required this.caption});

  final double size;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: YoBrandMark(size: size),
        ),
        _Caption(caption),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// R2 + R3 — "Tu i teraz" continue card
// ---------------------------------------------------------------------------

class _ContinueCardSample extends StatelessWidget {
  const _ContinueCardSample();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    const type = ServerType.friends;
    final identity = ServerIdentity.of(type);
    final visuals = identity.resolve(Theme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          copy.homeHereNow,
          style: AppTypography.sectionTitle.copyWith(
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        YoCard(
          tint: identity.primary,
          onTap: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  YoServerTile(
                    initial: 'W',
                    type: type,
                    size: 48,
                    textStyle: AppTypography.titleLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          copy.serverTypeTitle(type),
                          style: AppTypography.labelMedium.copyWith(
                            color: visuals.foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Weekendowa ekipa',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.headlineSmall.copyWith(
                            color: palette.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.3,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Głos, tekst i plany w jednym miejscu.',
                style: AppTypography.bodyMedium.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.forum_outlined,
                    size: 18,
                    color: visuals.foreground,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      copy.text('Choose a channel', 'Wybierz kanał'),
                      style: AppTypography.labelLarge.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  ExcludeSemantics(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: visuals.iconSurface,
                        border: Border.all(color: visuals.iconBorder),
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: visuals.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const _Caption(
          'Wypełnienie oświetlone od góry, włoskowa krawędź, promień 20. '
          'Poświata w kolorze serwera w rogu — jedna na ekran.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// R2 + R14 — "Masz chwilę?"
// ---------------------------------------------------------------------------

class _RecordCardSample extends StatelessWidget {
  const _RecordCardSample();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YoCard(
          padding: const EdgeInsets.all(12),
          onTap: () {},
          child: Row(
            children: [
              const YoGradientDisc(
                size: 48,
                icon: Icons.mic_rounded,
                gloss: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.homeGotAMinute,
                      style: AppTypography.titleMedium.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      copy.homeRecordVoiceMoment,
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.textTertiary),
            ],
          ),
        ),
        const _Caption(
          'Zwykły blok — bez poświaty. Mikrofon to kulka głosu w spoczynku '
          '(tylko cień kontaktowy).',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// R4 — the LIVE block at rest (after its one-time ignite)
// ---------------------------------------------------------------------------

class _LiveTileSample extends StatelessWidget {
  const _LiveTileSample();

  static const double width = 280;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    const type = ServerType.podcast;
    final identity = ServerIdentity.of(type);
    final visuals = identity.resolve(Theme.of(context).brightness);
    const kind = ServerChannelKind.stage;
    const height = width * 9 / 16;
    final specular = AppFinish.liveSpecular(
      palette,
      highContrast: highContrast,
    );
    final clock = copy.serverLiveSinceShort('19:48');

    final thumbnail = DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(visuals.cardWash, palette.surfaceRaised),
        borderRadius: AppRadius.block,
        boxShadow: AppFinish.liveGlow(palette, highContrast: highContrast),
      ),
      position: DecorationPosition.background,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: AppRadius.block,
          border: AppFinish.liveRim(palette, highContrast: highContrast),
        ),
        child: ClipRRect(
          borderRadius: AppRadius.block,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                if (!highContrast)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppFinish.liveCorner(
                          identity.accent,
                          palette,
                          shortestSide: height,
                        ),
                      ),
                    ),
                  ),
                if (specular != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: specular),
                    ),
                  ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          serverChannelIcon(kind),
                          size: 24,
                          color: visuals.foreground,
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: YoWaveform(
                            color: visuals.foreground.withValues(alpha: .72),
                            height: 36,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: YoBadge(
                    label: copy.serverLivePill,
                    variant: YoBadgeVariant.live,
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: YoMetricPill(
                    value: clock,
                    icon: Icons.schedule_rounded,
                    tone: YoMetricPillTone.overlay,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              thumbnail,
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  YoServerTile(
                    initial: 'S',
                    type: type,
                    size: 36,
                    textStyle: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Studio na żywo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleSmall.copyWith(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Studio głosu · ${copy.serverChannelKindTitle(kind)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const _Caption(
          'Stan po jednorazowym zapłonie: światło z rogu w kolorze serwera, '
          'czerwona obwódka, poświata pod spodem. Fala stoi — nie udaje '
          'dźwięku.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// R5 — the labelled primary action
// ---------------------------------------------------------------------------

class _PrimaryActionSamples extends StatefulWidget {
  const _PrimaryActionSamples();

  @override
  State<_PrimaryActionSamples> createState() => _PrimaryActionSamplesState();
}

class _PrimaryActionSamplesState extends State<_PrimaryActionSamples> {
  // Holds the second sample in its pressed state so the sheet can show it.
  final WidgetStatesController _pressed = WidgetStatesController({
    WidgetState.pressed,
  });

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(
      context,
    ).text('Create server', 'Stwórz serwer');
    Widget cell(String caption, Widget button) => _Cell(
      caption: caption,
      child: Align(alignment: AlignmentDirectional.centerStart, child: button),
    );
    return _Grid(
      children: [
        cell(
          'spoczynek',
          YoGradientFilledButton(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded),
            child: Text(label),
          ),
        ),
        cell(
          'wciśnięty',
          YoGradientFilledButton(
            onPressed: () {},
            statesController: _pressed,
            icon: const Icon(Icons.add_rounded),
            child: Text(label),
          ),
        ),
        cell(
          'nieaktywny',
          YoGradientFilledButton(
            onPressed: null,
            icon: const Icon(Icons.add_rounded),
            child: Text(label),
          ),
        ),
        cell(
          'w toku',
          YoGradientFilledButton(
            onPressed: () {},
            busy: true,
            child: Text(label),
          ),
        ),
      ],
    );
  }
}

/// Two columns at normal text, one column at large text.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = _bigText(context) ? 1 : 2;
        const gap = 16.0;
        final width = (constraints.maxWidth - gap * (count - 1)) / count;
        return Wrap(
          spacing: gap,
          runSpacing: 18,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.caption, required this.child});

  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [child, _Caption(caption)],
    );
  }
}

// ---------------------------------------------------------------------------
// R6 — icon-only CTA discs
// ---------------------------------------------------------------------------

class _IconDiscSamples extends StatelessWidget {
  const _IconDiscSamples();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 40,
      runSpacing: 18,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        _DiscCell(
          caption: 'Czaty · nowa rozmowa (40)',
          disc: YoGradientDisc(
            size: 40,
            icon: Icons.edit_square,
            glyphSize: 20,
            emphasis: YoDiscEmphasis.lift,
          ),
        ),
        _DiscCell(
          caption: 'Głos · dodaj (48)',
          disc: YoGradientDisc(
            size: 48,
            icon: Icons.add_rounded,
            emphasis: YoDiscEmphasis.lift,
          ),
        ),
      ],
    );
  }
}

class _DiscCell extends StatelessWidget {
  const _DiscCell({required this.caption, required this.disc});

  final String caption;
  final Widget disc;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(padding: const EdgeInsets.all(6), child: disc),
        _Caption(caption, align: TextAlign.center),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// R7 — tonal actions
// ---------------------------------------------------------------------------

class _TonalSamples extends StatelessWidget {
  const _TonalSamples();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Wrap(
      spacing: 16,
      runSpacing: 18,
      children: [
        _Cell(
          caption: 'neutralna',
          child: OutlinedButton.icon(
            style: AppFinish.tonalNeutral(
              palette,
            ).copyWith(minimumSize: const WidgetStatePropertyAll(Size(44, 44))),
            onPressed: () {},
            icon: const Icon(Icons.person_add_alt_outlined, size: 20),
            label: Text(copy.friends),
          ),
        ),
        _Cell(
          caption: 'akcent (jedna na blok)',
          child: OutlinedButton.icon(
            style: AppFinish.tonalAccent(
              palette,
            ).copyWith(minimumSize: const WidgetStatePropertyAll(Size(44, 44))),
            onPressed: () {},
            icon: const Icon(Icons.mic_none_rounded, size: 20),
            label: Text(copy.text('Reply with voice', 'Odpowiedz głosem')),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// R8 — single-select filter chips (Friends)
// ---------------------------------------------------------------------------

class _ChipSamples extends StatelessWidget {
  const _ChipSamples();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final labels = <(String, bool)>[
      (copy.text('All', 'Wszyscy'), true),
      (copy.text('Online', 'Online'), false),
      (copy.text('Requests', 'Zaproszenia'), false),
      (copy.text('Blocked', 'Zablokowani'), false),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 0,
          children: [
            for (final (label, selected) in labels)
              _FilterChipSample(label: label, selected: selected),
          ],
        ),
        const _Caption(
          'Wybrany = odwrócony atrament (18,5:1). Reszta: tylko włoskowa '
          'krawędź, bez drugiego fioletu.',
        ),
      ],
    );
  }
}

class _FilterChipSample extends StatelessWidget {
  const _FilterChipSample({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return AccessibleTapRegion(
      onTap: () {},
      semanticLabel: label,
      selected: selected,
      selectedBorderColor: Colors.transparent,
      borderRadius: 999,
      minimumSize: const Size(48, 48),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppFinish.chipHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: AppFinish.chipPaddingH,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: AppFinish.chipFill(palette, selected: selected),
          borderRadius: AppRadius.pill,
          border: AppFinish.chipBorder(palette, selected: selected),
        ),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            label,
            style: AppTypography.labelLarge.copyWith(
              fontSize: AppFinish.chipFontSize,
              letterSpacing: 0,
              fontWeight: AppFinish.chipWeight(selected: selected),
              color: AppFinish.chipLabel(palette, selected: selected),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Batch 3 — shared controls: YoButton (R5), YoIconButton (R9)
// ---------------------------------------------------------------------------

class _SharedButtonSamples extends StatefulWidget {
  const _SharedButtonSamples();

  @override
  State<_SharedButtonSamples> createState() => _SharedButtonSamplesState();
}

class _SharedButtonSamplesState extends State<_SharedButtonSamples> {
  // Holds one primary sample in its pressed state so the sheet can show it.
  final WidgetStatesController _pressed = WidgetStatesController({
    WidgetState.pressed,
  });

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final save = copy.text('Save', 'Zapisz');
    Widget button(String caption, Widget child) =>
        _Cell(caption: caption, child: child);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Grid(
          children: [
            button(
              'YoButton · spoczynek',
              YoButton(label: save, height: 48, onPressed: () {}),
            ),
            button(
              'wciśnięty (cień opada)',
              YoButton(
                label: save,
                height: 48,
                statesController: _pressed,
                onPressed: () {},
              ),
            ),
            button(
              'nieaktywny',
              YoButton(label: save, height: 48, onPressed: null),
            ),
            button(
              'w toku (pół cienia)',
              YoButton(
                label: copy.text('Saving', 'Zapisywanie'),
                height: 48,
                isLoading: true,
                onPressed: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        // As in YoErrorState: a secondary retry at its own width.
        _Cell(
          caption: 'drugorzędny (np. „Spróbuj ponownie”) — bez zmian',
          child: YoButton(
            label: copy.text('Try again', 'Spróbuj ponownie'),
            variant: YoButtonVariant.secondary,
            height: 48,
            fullWidth: false,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {},
          ),
        ),
        const SizedBox(height: 22),
        _IconSampleRow(
          samples: [
            (
              'szkło',
              YoIconButton(
                icon: Icons.settings_rounded,
                tooltip: copy.text('Settings', 'Ustawienia'),
                onPressed: () {},
              ),
            ),
            (
              'najechany',
              // The real hover also opens the tooltip; it is held back here
              // only so it does not cover the neighbouring captions.
              TooltipVisibility(
                visible: false,
                child: YoIconButton(
                  key: RefineSheet.hoverProbeKey,
                  icon: Icons.search_rounded,
                  tooltip: copy.text('Search', 'Szukaj'),
                  onPressed: () {},
                ),
              ),
            ),
            (
              'nieaktywny',
              YoIconButton(
                icon: Icons.add_rounded,
                tooltip: copy.text('Add', 'Dodaj'),
                onPressed: null,
              ),
            ),
            (
              'kolory wywołującego',
              // Settings / Friends still pass these today (batch 9 drops
              // them): a caller's fill and edge win over the default; high
              // contrast turns the visible caller edge `borderStrong`.
              YoIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                backgroundColor: palette.surface,
                borderColor: palette.border,
                onPressed: () {},
              ),
            ),
          ],
        ),
        const _Caption(
          'Główny: gradient akcji i cień szyny (32 %, rozmycie 18, y 5). '
          'Ikona: szkło + włoskowa krawędź kontrolki; kursor ją wzmacnia. '
          'Wysoki kontrast przywraca mocną krawędź i zdejmuje cień.',
        ),
      ],
    );
  }
}

/// A row of icon-button samples: equal fixed-width cells, every button
/// centred in the same 48 px box, so the captions share one top line and
/// the gaps between the buttons are even. Two per row at large text.
class _IconSampleRow extends StatelessWidget {
  const _IconSampleRow({required this.samples});

  final List<(String, Widget)> samples;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _bigText(context) ? 2 : samples.length;
        const gap = 12.0;
        final cell = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 16,
          children: [
            for (final (caption, button) in samples)
              SizedBox(
                width: cell,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 48, child: Center(child: button)),
                    _Caption(caption, align: TextAlign.center),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Batch 3 — live pointer and keyboard-focus states
// ---------------------------------------------------------------------------

/// The shared controls under a REAL mouse pointer and REAL keyboard focus.
/// There is one pointer and one focus at a time, so the capture harness
/// shoots this section twice ([RefineSheet.liveStateShots]): once with the
/// pointer on the primary button and focus in the icon button, once with
/// focus on the primary button and the pointer on the secondary. In
/// `flutter run` these are ordinary samples.
class _LiveStateSamples extends StatelessWidget {
  const _LiveStateSamples();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Grid(
          children: [
            _Cell(
              caption: 'główny · A: kursor · B: fokus',
              child: YoButton(
                key: RefineSheet.livePrimaryKey,
                label: copy.text('Save', 'Zapisz'),
                height: 48,
                onPressed: () {},
              ),
            ),
            _Cell(
              caption: 'drugorzędny · B: kursor',
              child: YoButton(
                key: RefineSheet.liveSecondaryKey,
                label: copy.text('Cancel', 'Anuluj'),
                variant: YoButtonVariant.secondary,
                height: 48,
                onPressed: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _IconSampleRow(
          samples: [
            (
              'ikona · A: fokus',
              TooltipVisibility(
                visible: false,
                child: YoIconButton(
                  key: RefineSheet.liveIconKey,
                  icon: Icons.tune_rounded,
                  tooltip: copy.text('Filters', 'Filtry'),
                  onPressed: () {},
                ),
              ),
            ),
          ],
        ),
        const _Caption(
          'Ujęcie A: kursor na głównym (biała poświata .06 i mocniejszy '
          'cień, bez obrysu), fokus klawiatury w ikonie (pierścień 2 px). '
          'Ujęcie B: fokus na głównym (biały pierścień 2 px rysowany na '
          'wierzchu, etykieta się nie przesuwa), kursor na drugorzędnym '
          '(krawędź 1,5 px na wierzchu). Bez stanu: spoczynek.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Batch 3 — the R9 search pill beside the unchanged form field
// ---------------------------------------------------------------------------

class _SearchFieldSamples extends StatefulWidget {
  const _SearchFieldSamples();

  @override
  State<_SearchFieldSamples> createState() => _SearchFieldSamplesState();
}

class _SearchFieldSamplesState extends State<_SearchFieldSamples> {
  final TextEditingController _filled = TextEditingController(text: 'Ola');
  final TextEditingController _focused = TextEditingController();

  @override
  void dispose() {
    _filled.dispose();
    _focused.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final hint = copy.text('Search friends', 'Szukaj znajomych');
    Widget sample(String caption, Widget field) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _Cell(caption: caption, child: field),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sample('spoczynek', YoSearchField(hint: hint)),
        sample(
          'z tekstem — przycisk czyszczenia 44 px',
          YoSearchField(hint: hint, controller: _filled),
        ),
        sample(
          'fokus — pierścień 2 px na pigułce, bez przesunięcia tekstu',
          KeyedSubtree(
            key: RefineSheet.focusProbeKey,
            child: YoSearchField(hint: hint, controller: _focused),
          ),
        ),
        sample('nieaktywne', YoSearchField(hint: hint, enabled: false)),
        sample(
          'pole formularza — bez zmian (mocna krawędź)',
          YoTextField(
            label: copy.text('Display name', 'Nazwa wyświetlana'),
            hint: copy.text('Your name', 'Twoje imię'),
          ),
        ),
        const _Caption(
          'Szukanie: 44 px, tło powierzchni (Ciemny) lub białe (Pearl), '
          'krawędź 1 px, szara lupa 20 px, bez cienia.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Batch 3 — tonal badges (R11) and the theme's Material chips (R8)
// ---------------------------------------------------------------------------

class _BadgeAndChipSamples extends StatelessWidget {
  const _BadgeAndChipSamples();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final badges = <(String, YoBadgeVariant)>[
      (copy.text('New', 'Nowy'), YoBadgeVariant.primary),
      (copy.text('Saved', 'Zapisano'), YoBadgeVariant.success),
      (copy.text('Heads up', 'Uwaga'), YoBadgeVariant.warning),
      (copy.text('Error', 'Błąd'), YoBadgeVariant.error),
      (copy.text('Info', 'Info'), YoBadgeVariant.info),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (final (label, variant) in badges)
              YoBadge(label: label, variant: variant),
          ],
        ),
        const _Caption(
          'Plakietki tonalne: krawędź to atrament przy 32 % (wcześniej '
          'pełny). NA ŻYWO bez zmian.',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              label: Text(copy.text('Podcast', 'Podcast')),
              selected: true,
              onSelected: (_) {},
            ),
            FilterChip(
              label: Text(copy.text('Family', 'Rodzina')),
              selected: false,
              onSelected: (_) {},
            ),
            FilterChip(
              label: Text(copy.text('Company', 'Firma')),
              selected: false,
              onSelected: null,
            ),
          ],
        ),
        const _Caption(
          'Chipy Material (motyw): zaznaczony zachowuje kontener i ptaszka; '
          'krawędź wszystkich to włoskowa krawędź kontrolki.',
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              copy.text(
                'A Material card takes the block hairline.',
                'Karta Material dostaje włoskową krawędź bloku.',
              ),
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// R10 — avatars
// ---------------------------------------------------------------------------

class _AvatarSamples extends StatelessWidget {
  const _AvatarSamples();

  static const _names = ['Ada', 'Marek', 'Kasia', 'Ola', 'Tomek'];

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    Widget row(String label, UserAvatarFinish finish) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 12,
          children: [
            for (final name in _names)
              UserAvatar(radius: 28, displayName: name, finish: finish),
          ],
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('Dziś — płaska moneta', UserAvatarFinish.flat),
        const SizedBox(height: 18),
        row(
          'Nowe — jeden gradient marki, spokojna litera',
          UserAvatarFinish.brand,
        ),
        const _Caption(
          'Dane podglądu nie mają zdjęć profilowych, więc awatar ze zdjęciem '
          '(z włoskową obwódką) nie jest tu pokazany.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// R11 — count badge on the Start bell
// ---------------------------------------------------------------------------

class _CountBadgeSamples extends StatelessWidget {
  const _CountBadgeSamples();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 36,
          runSpacing: 18,
          children: [
            _BellCell(count: 2),
            _BellCell(count: 12),
            _BellCell(count: 123),
          ],
        ),
        _Caption(
          'Dzwonek na Starcie: szklany krąg 46 px, licznik z gradientem '
          'akcji i pierścieniem w kolorze tła (bez cienia). Przy większym '
          'tekście licznik rośnie do 1,5 × w górę i na zewnątrz.',
        ),
      ],
    );
  }
}

class _BellCell extends StatelessWidget {
  const _BellCell({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // The real Start bell: at larger text its count grows up and out from
    // the disc's corner, so the cell leaves room above it.
    return Padding(
      padding: const EdgeInsets.only(top: 16, right: 8),
      child: HomeHeaderDisc(
        icon: AppIcons.notifications,
        onTap: () {},
        tooltip: 'Powiadomienia',
        badgeCount: count,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// R12 — the Moment expiry pill
// ---------------------------------------------------------------------------

class _ExpirySamples extends StatelessWidget {
  const _ExpirySamples();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Wrap(
      spacing: 28,
      runSpacing: 16,
      children: [
        _Cell(
          caption: 'zostało 23 godz.',
          child: _ExpiryPill(
            label: '23 godz.',
            value: 23 / 24,
            arc: palette.interactiveForeground,
          ),
        ),
        _Cell(
          caption: 'poniżej godziny — bursztyn',
          child: _ExpiryPill(
            label: '42 min',
            value: 42 / (24 * 60),
            arc: palette.warningForeground,
          ),
        ),
      ],
    );
  }
}

class _ExpiryPill extends StatelessWidget {
  const _ExpiryPill({
    required this.label,
    required this.value,
    required this.arc,
  });

  final String label;
  final double value;
  final Color arc;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.glass,
        borderRadius: AppRadius.pill,
        border: Border.all(color: palette.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 11, 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            YoProgressRing(
              value: value,
              trackColor: palette.border,
              arcColor: arc,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: palette.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// R13 — waveform, variants A and B, in a real Moment block
// ---------------------------------------------------------------------------

class _WaveSamples extends StatelessWidget {
  const _WaveSamples();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final variantB = AppGradients.voicePlayed(
      Theme.of(context).colorScheme,
      palette,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const UserAvatar(
                    radius: 16,
                    displayName: 'Ola',
                    finish: UserAvatarFinish.brand,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ola',
                      style: AppTypography.titleSmall.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _ExpiryPill(
                    label: '23 godz.',
                    value: 23 / 24,
                    arc: palette.interactiveForeground,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Małe rzeczy cieszą',
                style: AppTypography.titleMedium.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.2,
                ),
              ),
              const SizedBox(height: 14),
              _TransportRow(tag: 'B', gradient: variantB),
              const SizedBox(height: 14),
              _TransportRow(tag: 'A', gradient: palette.audioProgressGradient),
            ],
          ),
        ),
        const _Caption(
          'Odtworzone 40%, pauza. B — fiolet → magenta z logo (wybrane '
          '25.09); w ciemnym motywie rozjaśnione, żeby odtworzona część '
          'miała co najmniej 3:1 wobec nieodtworzonej na obu końcach. '
          'A — cyjan → lawenda, tylko dla porównania. Gradient rozpięty na '
          'całej fali i odsłaniany do głowicy; nieodtworzone słupki nie '
          'ciemnieją.',
        ),
      ],
    );
  }
}

class _TransportRow extends StatelessWidget {
  const _TransportRow({required this.tag, required this.gradient});

  final String tag;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(
            tag,
            style: AppTypography.overline.copyWith(
              color: palette.textTertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const YoGradientDisc(
          size: 48,
          icon: Icons.play_arrow_rounded,
          nudgePlay: true,
          gloss: true,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YoWaveform(
                color: palette.waveUnplayed,
                progress: .4,
                playedGradient: gradient,
                continuousProgress: true,
                gradientSpan: YoWaveformGradientSpan.full,
                height: 36,
                barWidth: 3,
                barGap: 2,
                barRadius: 1.5,
              ),
              const SizedBox(height: 4),
              Text(
                '0:05 / 0:12',
                textAlign: TextAlign.end,
                style: AppTypography.labelSmall.copyWith(
                  color: palette.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// R14 — the voice bead
// ---------------------------------------------------------------------------

class _BeadSamples extends StatelessWidget {
  const _BeadSamples();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 26,
          runSpacing: 18,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _DiscCell(
              caption: '34',
              disc: YoGradientDisc(
                size: 34,
                icon: Icons.play_arrow_rounded,
                nudgePlay: true,
                gloss: true,
              ),
            ),
            _DiscCell(
              caption: '48',
              disc: YoGradientDisc(
                size: 48,
                icon: Icons.play_arrow_rounded,
                nudgePlay: true,
                gloss: true,
              ),
            ),
            _DiscCell(
              caption: '72',
              disc: YoGradientDisc(
                size: 72,
                icon: Icons.play_arrow_rounded,
                nudgePlay: true,
                gloss: true,
              ),
            ),
            _DiscCell(
              caption: '48 · gra (świeci)',
              disc: YoGradientDisc(
                size: 48,
                icon: Icons.pause_rounded,
                emphasis: YoDiscEmphasis.lit,
                gloss: true,
              ),
            ),
          ],
        ),
        SizedBox(height: 18),
        Wrap(
          spacing: 26,
          runSpacing: 18,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _DiscCell(
              caption: 'ładowanie',
              disc: YoGradientDisc(
                size: 48,
                status: YoDiscStatus.busy,
                gloss: true,
              ),
            ),
            _DiscCell(
              caption: 'błąd',
              disc: YoGradientDisc(
                size: 48,
                status: YoDiscStatus.failed,
                gloss: true,
              ),
            ),
            _DiscCell(
              caption: 'nieaktywna',
              disc: YoGradientDisc(
                size: 48,
                icon: Icons.play_arrow_rounded,
                nudgePlay: true,
                status: YoDiscStatus.disabled,
                gloss: true,
              ),
            ),
          ],
        ),
        _Caption(
          'Szkło logo: połysk z lewej-góry i cienka krawędź. W spoczynku tylko '
          'cień kontaktowy; świeci wyłącznie klip, który właśnie gra.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// R15 — chat bubbles
// ---------------------------------------------------------------------------

class _BubbleSamples extends StatelessWidget {
  const _BubbleSamples();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Semantics(
            label: 'Dziś',
            excludeSemantics: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.glass,
                borderRadius: AppRadius.pill,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                child: Text(
                  'DZIŚ',
                  style: AppTypography.overline.copyWith(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Bubble(
          outgoing: false,
          time: '19:42',
          child: Text(
            'Masz chwilę na rozmowę?',
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: _ReactionPill(emoji: '❤️', count: 2),
        ),
        const SizedBox(height: 10),
        _Bubble(
          outgoing: true,
          time: '19:43',
          child: Text(
            'Jasne! Wskakuję na serwer za pięć minut.',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
        const SizedBox(height: 10),
        _Bubble(
          outgoing: false,
          time: '19:45',
          child: _VoiceBubbleBody(outgoing: false),
        ),
        const SizedBox(height: 10),
        _Bubble(
          outgoing: true,
          time: '19:46',
          child: _VoiceBubbleBody(outgoing: true),
        ),
        const _Caption(
          'Przychodzące: blok z włoskową krawędzią. Wychodzące: gradient akcji '
          '(biały tekst 5,8:1; godzina i czas trwania białe @ .92, co '
          'najmniej 5:1; nieodtworzone słupki białe @ .35, co najmniej 3:1 '
          'wobec odtworzonych). Ogonek 6 px, reakcja w osobnym miejscu.',
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.outgoing,
    required this.time,
    required this.child,
  });

  final bool outgoing;
  final String time;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadiusDirectional.only(
      topStart: const Radius.circular(18),
      topEnd: const Radius.circular(18),
      bottomStart: Radius.circular(outgoing ? 18 : 6),
      bottomEnd: Radius.circular(outgoing ? 6 : 18),
    );
    final decoration = outgoing
        ? BoxDecoration(
            gradient: AppGradients.primaryAction(scheme),
            borderRadius: radius,
          )
        : BoxDecoration(
            gradient: palette.blockGradient,
            borderRadius: radius,
            border: Border.all(color: palette.hairline),
            boxShadow: palette.blockShadows,
          );
    return Align(
      alignment: outgoing
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .78,
        ),
        child: DecoratedBox(
          decoration: decoration,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 12, 7),
            // Hug the content: a short message is a short bubble.
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  child,
                  const SizedBox(height: 2),
                  Text(
                    time,
                    textAlign: TextAlign.end,
                    style: AppTypography.labelSmall.copyWith(
                      color: outgoing
                          ? AppFinish.outgoingMeta
                          : palette.textTertiary,
                      letterSpacing: 0,
                    ),
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

class _VoiceBubbleBody extends StatelessWidget {
  const _VoiceBubbleBody({required this.outgoing});

  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        YoGradientDisc(
          size: 34,
          icon: Icons.play_arrow_rounded,
          nudgePlay: true,
          gloss: !outgoing,
          tone: outgoing ? YoDiscTone.onBrand : YoDiscTone.brand,
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 132,
          child: outgoing
              ? YoWaveform(
                  color: AppFinish.outgoingWaveUnplayed,
                  playedColor: AppFinish.outgoingWavePlayed,
                  progress: .6,
                  continuousProgress: true,
                  height: 26,
                  barWidth: 3,
                  barGap: 2,
                  barRadius: 1.5,
                )
              : YoWaveform(
                  color: palette.waveUnplayed,
                  progress: .35,
                  playedGradient: AppGradients.voicePlayed(
                    Theme.of(context).colorScheme,
                    palette,
                  ),
                  continuousProgress: true,
                  gradientSpan: YoWaveformGradientSpan.full,
                  height: 26,
                  barWidth: 3,
                  barGap: 2,
                  barRadius: 1.5,
                ),
        ),
        const SizedBox(width: 10),
        Text(
          outgoing ? '0:12' : '0:24',
          style: AppTypography.labelSmall.copyWith(
            color: outgoing ? AppFinish.outgoingMeta : palette.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({required this.emoji, required this.count});

  final String emoji;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadius.pill,
        border: Border.all(color: palette.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: emoji,
                style: const TextStyle(
                  fontFamilyFallback: <String>[
                    ...AppTypography.fontFamilyFallback,
                    'Apple Color Emoji',
                    'Noto Color Emoji',
                  ],
                ),
              ),
              TextSpan(text: ' $count'),
            ],
          ),
          style: AppTypography.labelMedium.copyWith(
            color: palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// R16 — More tiles with glyph boxes
// ---------------------------------------------------------------------------

class _TileSamples extends StatelessWidget {
  const _TileSamples();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final entries = <(IconData, String, String)>[
      (
        Icons.people_rounded,
        copy.friends,
        copy.text('Your circle', 'Twój krąg'),
      ),
      (Icons.person_rounded, copy.profile, copy.text('You', 'Ty')),
      (
        Icons.notifications_rounded,
        copy.text('Alerts', 'Powiadomienia'),
        copy.text('Updates', 'Aktualizacje'),
      ),
      (
        Icons.emoji_events_rounded,
        copy.text('Awards', 'Nagrody'),
        copy.text('Progress', 'Postępy'),
      ),
    ];
    final big = _bigText(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (big)
          for (final (icon, label, subtitle) in entries) ...[
            _MoreTile(icon: icon, label: label, subtitle: subtitle, row: true),
            const SizedBox(height: 10),
          ]
        else
          // The More sheet's own rule: two columns below 480 px.
          for (var i = 0; i < entries.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = i; j < i + 2 && j < entries.length; j++) ...[
                  if (j > i) const SizedBox(width: 8),
                  Expanded(
                    child: _MoreTile(
                      icon: entries[j].$1,
                      label: entries[j].$2,
                      subtitle: entries[j].$3,
                    ),
                  ),
                ],
              ],
            ),
          ],
        const _Caption(
          'Kafelek: promień 16, szkło (Ciemny) lub biały z cieniem (Pearl). '
          'Ramka ikony: promień 12, gradient kontenerów schematu.',
        ),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.row = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool row;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final decoration = palette.isDark
        ? BoxDecoration(
            color: palette.glass,
            borderRadius: AppRadius.tile,
            border: Border.all(color: palette.hairline),
          )
        : BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadius.tile,
            border: Border.all(color: palette.hairline),
            boxShadow: palette.blockShadows,
          );
    final glyph = Container(
      width: 40,
      height: 40,
      decoration: AppFinish.glyphBox(scheme),
      child: Icon(icon, size: 22, color: palette.interactiveForeground),
    );
    final texts = <Widget>[
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.titleSmall.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
      ),
    ];
    return DecoratedBox(
      decoration: decoration,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: row
            ? Row(
                children: [
                  glyph,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: texts,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [glyph, const SizedBox(height: 12), ...texts],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// R17 / §4 — the first-run empty state with the real logo
// ---------------------------------------------------------------------------

class _EmptyStateSample extends StatelessWidget {
  const _EmptyStateSample();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YoEmptyState(
          compact: true,
          icon: Icons.hub_outlined,
          leading: const YoBrandMark(size: 72),
          title: copy.text(
            'Your place for shared conversations',
            'Twoje miejsce na wspólne rozmowy',
          ),
          subtitle: copy.text(
            'Create a server or accept an invitation to get started.',
            'Stwórz serwer lub przyjmij zaproszenie, aby zacząć.',
          ),
        ),
        const _Caption(
          'Pusty katalog serwerów: prawdziwe logo zamiast ikony. Przycisk '
          '„Stwórz serwer” dochodzi w etapie Serwery.',
          align: TextAlign.center,
        ),
      ],
    );
  }
}
