import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_focus_ink.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';

/// The R7 tonal pill of the Treści renders: neutral glass (or the accent
/// wash), 16 px side padding, w700 label, an optional leading icon. It
/// grows with the reader's text above its [height].
class PagesTonalButton extends StatelessWidget {
  const PagesTonalButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.height = 44,
    this.accent = false,
    this.focusNode,
    super.key,
  });

  final FocusNode? focusNode;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// A leading widget in place of [icon] (the busy spinner of
  /// [PagesLoadMoreButton]).
  final Widget? leading;
  final double height;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final base = accent
        ? AppFinish.tonalAccent(palette, highContrast: highContrast)
        : AppFinish.tonalNeutral(palette, highContrast: highContrast);
    final style = base.copyWith(
      minimumSize: WidgetStatePropertyAll(Size(48, height)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      textStyle: WidgetStatePropertyAll(
        AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w700),
      ),
      iconSize: const WidgetStatePropertyAll(18),
    );
    final text = Text(label, textAlign: TextAlign.center);
    final lead = leading ?? (icon == null ? null : Icon(icon));
    return lead == null
        ? OutlinedButton(
            onPressed: onPressed,
            focusNode: focusNode,
            style: style,
            child: text,
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            focusNode: focusNode,
            style: style,
            icon: lead,
            label: text,
          );
  }
}

/// "Wczytaj więcej" for every paged Pages list (the wall, a Page's wall,
/// the comment thread, Find Pages).
///
/// The button stays mounted through its busy state (the spinner sits inside
/// it and the label says "Wczytywanie…"), so keyboard focus is never
/// dropped, and the outcome is announced: how many items arrived, or that
/// the page failed and the button now retries. Callers keep it mounted
/// with [visible] false once there is nothing more, so the last page's
/// arrival is still announced after the button itself is gone.
class PagesLoadMoreButton extends StatefulWidget {
  const PagesLoadMoreButton({
    required this.loading,
    required this.failed,
    required this.itemCount,
    required this.onPressed,
    this.visible = true,
    this.height = 48,
    super.key,
  });

  /// False draws nothing (no more pages) but keeps announcing.
  final bool visible;
  final bool loading;
  final bool failed;

  /// The list's length, to announce how many items a page added.
  final int itemCount;
  final VoidCallback onPressed;
  final double height;

  @override
  State<PagesLoadMoreButton> createState() => _PagesLoadMoreButtonState();
}

class _PagesLoadMoreButtonState extends State<PagesLoadMoreButton> {
  int? _countBefore;

  @override
  void didUpdateWidget(PagesLoadMoreButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.loading && widget.loading) {
      _countBefore = oldWidget.itemCount;
    }
    if (oldWidget.loading && !widget.loading) {
      final before = _countBefore ?? oldWidget.itemCount;
      _countBefore = null;
      final copy = PagesCopy(AppLocalizations.of(context));
      final added = widget.itemCount - before;
      if (widget.failed) {
        announcePages(context, copy.loadMoreFailed, assertive: true);
      } else if (added > 0) {
        announcePages(context, copy.loadedMore(added));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    final copy = PagesCopy(AppLocalizations.of(context));
    final palette = context.appPalette;
    final loading = widget.loading;
    return PagesTonalButton(
      key: const ValueKey('pages-load-more'),
      label: loading
          ? copy.loadingEllipsis
          : widget.failed
          ? copy.tryAgain
          : copy.loadMore,
      icon: widget.failed && !loading ? Icons.refresh_rounded : null,
      leading: loading
          ? SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.interactiveForeground,
              ),
            )
          : null,
      height: widget.height,
      // Busy stays enabled (and focusable); a second press is ignored.
      onPressed: loading ? _ignorePress : widget.onPressed,
    );
  }
}

void _ignorePress() {}

/// The Treści canvas every Pages screen is drawn on (the approved renders'
/// `palette.backgroundGradient`: the violet top glow over the canvas) with
/// the YO mark of [YoPageBackground]. Opaque, so a route pushed on Treści's
/// own navigator never shows the one below; flat under high contrast.
class PagesCanvas extends StatelessWidget {
  const PagesCanvas({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    return DecoratedBox(
      key: const ValueKey('pages-canvas'),
      decoration: BoxDecoration(
        color: palette.background,
        gradient: highContrast ? null : palette.backgroundGradient,
      ),
      child: YoPageBackground(decoration: const BoxDecoration(), child: child),
    );
  }
}

/// A Treści state (R4): the 76 px glyph disc, title, body and up to two
/// actions and a status pill, laid out like `YoEmptyState` so every state
/// of the destination reads as one family.
class PagesStateBlock extends StatelessWidget {
  const PagesStateBlock({
    required this.icon,
    required this.title,
    this.body,
    this.primaryLabel,
    this.onPrimary,
    this.secondary,
    this.pill,
    this.liveRegion = false,
    super.key,
  });

  /// True for a state that replaces results in place (Find's "Nic nie
  /// znaleziono"): the title and body are one live region.
  final bool liveRegion;

  final IconData icon;
  final String title;
  final String? body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  /// A tonal action under the primary one (E2 "Utwórz swoją stronę", E4
  /// "Znajdź więcej stron").
  final Widget? secondary;

  /// A status pill (E9 "Chwilowo wyłączone").
  final String? pill;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final duration = AppMotion.resolve(context, AppMotion.entrance);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: AppMotion.entranceCurve,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.primary.withValues(alpha: .18),
                      colors.secondary.withValues(alpha: .1),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 34,
                  color: palette.interactiveForeground,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              liveRegion: liveRegion ? true : null,
              container: liveRegion,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTypography.titleLarge.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  if (body != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      body!,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (primaryLabel != null && onPrimary != null) ...[
              const SizedBox(height: AppSpacing.lg),
              YoButton(
                label: primaryLabel!,
                onPressed: onPrimary,
                fullWidth: false,
                height: 48,
              ),
            ],
            if (secondary != null) ...[
              SizedBox(
                height: primaryLabel != null && onPrimary != null
                    ? AppRhythm.item
                    : AppSpacing.lg,
              ),
              secondary!,
            ],
            if (pill != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: palette.glass,
                  borderRadius: AppRadius.pill,
                  border: Border.all(color: palette.hairlineControl),
                ),
                child: Text(
                  pill!,
                  style: AppTypography.count.copyWith(
                    color: palette.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone(this.width, this.height, {this.radius = AppRadius.sm});

  final double width;
  final double height;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.appPalette.surfaceMuted,
      borderRadius: radius,
    ),
  );
}

/// The loading card (R4 "loading"): static bones, no shimmer, so Reduce
/// Motion needs nothing special.
class PagesSkeletonCard extends StatelessWidget {
  const PagesSkeletonCard({this.media = false, super.key});

  final bool media;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: YoCard(
        padding: EdgeInsets.zero,
        semanticButton: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  _Bone(40, 40, radius: AppRadius.md),
                  SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Bone(150, 14),
                        SizedBox(height: 8),
                        _Bone(92, 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bone(double.infinity, 13),
                  SizedBox(height: 9),
                  _Bone(double.infinity, 13),
                  SizedBox(height: 9),
                  _Bone(190, 13),
                ],
              ),
            ),
            if (media) ...[
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) => _Bone(
                  constraints.maxWidth,
                  constraints.maxWidth * 5 / 4 * .62,
                  radius: BorderRadius.zero,
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// The phone "Utwórz swoją stronę" card above the feed (R5): VIPs without
/// a Page, dismissible per device.
class CreatePageCard extends StatelessWidget {
  const CreatePageCard({
    required this.onStart,
    required this.onDismiss,
    super.key,
  });

  final VoidCallback onStart;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final copy = PagesCopy(AppLocalizations.of(context));
    return YoCard(
      key: const ValueKey('pages-create-card'),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 4, 14),
      semanticButton: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 44,
              height: 44,
              decoration: AppFinish.glyphBox(
                scheme,
                highContrast: highContrast,
              ),
              child: Icon(
                Icons.add_business_outlined,
                size: 22,
                color: palette.interactiveForeground,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Semantics(
                  header: true,
                  child: Text(
                    copy.createYourPage,
                    style: AppTypography.rowTitle.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  copy.createCardBody,
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                PagesTonalButton(
                  label: copy.getStarted,
                  icon: Icons.arrow_forward_rounded,
                  height: 36,
                  accent: true,
                  onPressed: onStart,
                ),
              ],
            ),
          ),
          YoIconButton(
            icon: Icons.close_rounded,
            onPressed: onDismiss,
            tooltip: copy.hide,
            size: 44,
            iconSize: 20,
            backgroundColor: Colors.transparent,
            borderColor: Colors.transparent,
          ),
        ],
      ),
    );
  }
}

/// The owner's composer entry on the wall (R5, IA S1): face 40, the
/// "Napisz coś…" pill, mic 44 and photos 44. Each part opens the composer
/// on its own mode (text, voice, photos).
class OwnerComposerEntry extends StatelessWidget {
  const OwnerComposerEntry({
    required this.pageId,
    required this.pageName,
    required this.kind,
    required this.onCompose,
    this.wide = false,
    super.key,
  });

  final String pageId;
  final String pageName;
  final PageKind? kind;
  final ValueChanged<PagePostKind> onCompose;

  /// Desktop names the Page in the prompt ("Napisz coś jako …").
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final prompt = wide ? copy.writeAs(pageName) : copy.writeSomething;
    return YoCard(
      key: const ValueKey('pages-composer-entry'),
      padding: const EdgeInsets.all(16),
      semanticButton: false,
      child: Row(
        children: [
          PageFace(pageId: pageId, name: pageName, kind: kind, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              button: true,
              label: prompt,
              onTap: () => onCompose(PagePostKind.text),
              excludeSemantics: true,
              child: InkWell(
                key: const ValueKey('pages-composer-entry-text'),
                onTap: () => onCompose(PagePostKind.text),
                customBorder: const StadiumBorder(),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: AlignmentDirectional.centerStart,
                  decoration: ShapeDecoration(
                    color: palette.surfaceRaised,
                    shape: StadiumBorder(
                      side: BorderSide(color: palette.border),
                    ),
                  ),
                  child: Text(
                    prompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.rowPreview.copyWith(
                      color: palette.textTertiary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          YoIconButton(
            key: const ValueKey('pages-composer-entry-voice'),
            icon: Icons.mic_none_rounded,
            onPressed: () => onCompose(PagePostKind.voice),
            tooltip: copy.recordVoicePost,
            size: 44,
            iconSize: 21,
          ),
          const SizedBox(width: 8),
          YoIconButton(
            key: const ValueKey('pages-composer-entry-photo'),
            icon: Icons.photo_library_outlined,
            onPressed: () => onCompose(PagePostKind.photo),
            tooltip: copy.addPhotos,
            size: 44,
            iconSize: 20,
          ),
        ],
      ),
    );
  }
}
