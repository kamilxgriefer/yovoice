import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/profile/profile_banner.dart';

/// The tone of a Page notice or status pill (R6, R12), from the palette's
/// semantic surfaces.
enum PageTone { success, info, warning, danger, neutral }

(Color, Color) pageToneColors(AppPalette palette, PageTone tone) =>
    switch (tone) {
      PageTone.success => (palette.successSurface, palette.successForeground),
      PageTone.info => (palette.infoSurface, palette.infoForeground),
      PageTone.warning => (palette.warningSurface, palette.warningForeground),
      PageTone.danger => (palette.dangerSurface, palette.dangerForeground),
      PageTone.neutral => (palette.surfaceRaised, palette.textSecondary),
    };

/// An owner or visitor notice (R12): tone surface, tone edge, tone glyph,
/// a title, a body and optional actions.
class PageNotice extends StatelessWidget {
  const PageNotice({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
    super.key,
  });

  final PageTone tone;
  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final (surface, ink) = pageToneColors(palette, tone);
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: AppRadius.tile,
        border: Border.all(
          color: highContrast
              ? ink
              : Color.alphaBlend(ink.withValues(alpha: .38), palette.border),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 22, color: ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: AppTypography.bodyLarge.copyWith(
                      color: palette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: AppTypography.bodyMedium.copyWith(
                    color: palette.textSecondary,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "AKTYWNA" / "WSTRZYMANA" (R6).
class PageStatusPill extends StatelessWidget {
  const PageStatusPill({required this.label, required this.tone, super.key});

  final String label;
  final PageTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final (surface, ink) = pageToneColors(palette, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: AppRadius.pill,
        border: Border.all(
          color: Color.alphaBlend(ink.withValues(alpha: .38), palette.border),
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.count.copyWith(
          color: ink,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

/// The Page cover: the account's own banner through the viewer-authorized
/// media path (the brand gradient when there is none), with the top scrim
/// that keeps the glass controls legible.
class PageCover extends StatelessWidget {
  const PageCover({required this.pageId, this.scrim = true, super.key});

  final String pageId;
  final bool scrim;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ProfileBanner(
        userId: pageId,
        overlay: scrim
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: .35),
                  Colors.black.withValues(alpha: 0),
                ],
                stops: const [0, .56],
              )
            : null,
      ),
    );
  }
}

/// The 44 px glass disc over the cover (Back, ⋯).
class PageGlassButton extends StatelessWidget {
  const PageGlassButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        onTap: onPressed,
        child: Material(
          color: highContrast
              ? Colors.black.withValues(alpha: .78)
              : Colors.white.withValues(alpha: .22),
          shape: CircleBorder(
            side: BorderSide(
              color: highContrast
                  ? AppColors.white
                  : Colors.white.withValues(alpha: .28),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 44,
              child: Icon(icon, color: AppColors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 44 px tonal ⋯ (R7).
class PageDotsButton extends StatelessWidget {
  const PageDotsButton({
    required this.onPressed,
    required this.tooltip,
    this.icon = Icons.more_horiz_rounded,
    super.key,
  });

  final VoidCallback? onPressed;
  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    return IconButton.outlined(
      onPressed: onPressed,
      tooltip: tooltip,
      style:
          AppFinish.tonalNeutral(
            context.appPalette,
            highContrast: highContrast,
          ).merge(
            IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              fixedSize: const Size(44, 44),
            ),
          ),
      icon: Icon(icon, size: 20),
    );
  }
}

/// The tonal R7 button (Wiadomość, Edytuj stronę, Ustawienia strony).
class PageTonalButton extends StatelessWidget {
  const PageTonalButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 44,
    this.expand = false,
    this.trailing,
    this.focusNode,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool expand;
  final Widget? trailing;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final style =
        AppFinish.tonalNeutral(
          context.appPalette,
          highContrast: highContrast,
        ).merge(
          OutlinedButton.styleFrom(
            minimumSize: Size(expand ? double.infinity : 48, height),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        );
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    final Widget labelWidget = trailing == null
        ? text
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: text),
              const SizedBox(width: 2),
              trailing!,
            ],
          );
    return icon == null
        ? OutlinedButton(
            onPressed: onPressed,
            focusNode: focusNode,
            style: style,
            child: labelWidget,
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            focusNode: focusNode,
            style: style,
            icon: Icon(icon, size: 18),
            label: labelWidget,
          );
  }
}

/// A 40 px glyph box (R6/R9 rows).
class PageGlyph extends StatelessWidget {
  const PageGlyph(this.icon, {this.size = 40, this.danger = false, super.key});

  final IconData icon;
  final double size;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: danger
          ? BoxDecoration(
              color: scheme.error.withValues(alpha: .14),
              borderRadius: AppRadius.card,
            )
          : AppFinish.glyphBox(scheme),
      child: Icon(
        icon,
        size: size * .55,
        color: danger ? scheme.error : palette.interactiveForeground,
      ),
    );
  }
}

/// One Informacje row (R9): glyph, label, value; links in the accent.
class PageInfoRow extends StatelessWidget {
  const PageInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final link = onTap != null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          PageGlyph(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: AppTypography.bodyMedium.copyWith(
                    fontSize: 14.5,
                    height: 1.35,
                    color: link
                        ? palette.interactiveForeground
                        : palette.textPrimary,
                    fontWeight: link ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
    if (!link) return MergeSemantics(child: row);
    return MergeSemantics(
      child: Semantics(
        link: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.md,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: row,
          ),
        ),
      ),
    );
  }
}

/// A titled card (R9 sections).
class PageSectionCard extends StatelessWidget {
  const PageSectionCard({
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 10),
    this.onTap,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return YoCard(
      padding: padding,
      semanticButton: false,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: AppTypography.sectionTitle.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// An info line with a leading glyph (R6/R9 footnotes).
class PageFootnote extends StatelessWidget {
  const PageFootnote(
    this.text, {
    this.icon = Icons.info_outline_rounded,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 0),
    super.key,
  });

  final String text;
  final IconData icon;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One photo of a post, square, through its own 90 s grant (the Zdjęcia
/// tab and the desktop photo preview).
class PagePhotoTile extends StatefulWidget {
  const PagePhotoTile({
    required this.post,
    required this.image,
    required this.service,
    required this.label,
    this.onTap,
    super.key,
  });

  final PagePostView post;
  final PageMediaView image;
  final PagesService service;
  final String label;
  final VoidCallback? onTap;

  @override
  State<PagePhotoTile> createState() => _PagePhotoTileState();
}

class _PagePhotoTileState extends State<PagePhotoTile> {
  PageMediaGrant? _grant;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(PagePhotoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.mediaId != widget.image.mediaId) {
      _grant = null;
      _failed = false;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final grants = await widget.service.mediaAccess(widget.post.postId, [
        widget.image.mediaId,
      ]);
      if (!mounted) return;
      setState(() {
        _grant = grants[widget.image.mediaId];
        _failed = _grant == null;
      });
    } on PagesException {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final grant = _grant;
    final Widget content = grant != null
        ? Image.network(
            grant.url.toString(),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : ColoredBox(color: palette.surfaceMuted),
            errorBuilder: (context, _, _) => ColoredBox(
              color: palette.surfaceMuted,
              child: Icon(
                Icons.broken_image_outlined,
                color: palette.textTertiary,
              ),
            ),
          )
        : ColoredBox(
            color: palette.surfaceMuted,
            child: _failed
                ? Icon(Icons.broken_image_outlined, color: palette.textTertiary)
                : null,
          );
    final tile = ClipRRect(
      borderRadius: AppRadius.sm,
      child: SizedBox.expand(child: content),
    );
    return Semantics(
      image: true,
      button: widget.onTap != null,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: widget.onTap == null
          ? tile
          : GestureDetector(onTap: widget.onTap, child: tile),
    );
  }
}

/// Every image of [posts] in a square grid of [columns].
class PagePhotoGridView extends StatelessWidget {
  const PagePhotoGridView({
    required this.posts,
    required this.service,
    required this.pageName,
    this.columns = 3,
    this.limit,
    this.onOpen,
    super.key,
  });

  final List<PagePostView> posts;
  final PagesService service;
  final String pageName;
  final int columns;
  final int? limit;
  final void Function(PagePostView post)? onOpen;

  @override
  Widget build(BuildContext context) {
    final copy = PagesCopy(AppLocalizations.of(context));
    final entries = <(PagePostView, PageMediaView)>[
      for (final post in posts)
        for (final image in post.images) (post, image),
    ];
    final shown = limit == null ? entries : entries.take(limit!).toList();
    return GridView.count(
      crossAxisCount: columns,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < shown.length; i++)
          PagePhotoTile(
            key: ValueKey('page-photo-${shown[i].$2.mediaId}'),
            post: shown[i].$1,
            image: shown[i].$2,
            service: service,
            label: copy.photoLabel(i + 1, entries.length, pageName),
            onTap: onOpen == null ? null : () => onOpen!(shown[i].$1),
          ),
      ],
    );
  }
}

/// The status of an owner's Page as a pill (R6).
({String label, PageTone tone}) pageStatusPill(
  PagesCopy copy,
  PageHeaderState state,
) => switch (state) {
  PageHeaderState.active => (label: copy.statusActive, tone: PageTone.success),
  PageHeaderState.paused => (label: copy.statusPaused, tone: PageTone.warning),
  PageHeaderState.readOnly => (
    label: copy.statusReadOnly,
    tone: PageTone.warning,
  ),
  PageHeaderState.hidden => (label: copy.statusHidden, tone: PageTone.neutral),
  PageHeaderState.suspended => (
    label: copy.statusSuspended,
    tone: PageTone.danger,
  ),
};
