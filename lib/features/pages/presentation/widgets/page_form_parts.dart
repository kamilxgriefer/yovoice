import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_card_rows.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_profile_parts.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';

// The building blocks the two Page forms share: create A step 2
// (`CreatePageScreen`) and "Edytuj stronę" (`PageEditScreen`), with the
// previews that stand beside them. One implementation, so a field, its
// "Widoczne publicznie" helper and the preview of the profile header look and
// behave the same wherever the owner fills them in.

/// A form section's overline ("KONTAKT"), with an optional trailing note
/// ("wszystko opcjonalne").
class PageFormOverline extends StatelessWidget {
  const PageFormOverline(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final trailing = this.trailing;
    final title = Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: AppTypography.overline.copyWith(
          color: palette.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 12, start: 2),
      child: trailing == null
          ? Row(children: [Expanded(child: title)])
          // The title at the start and the note at the end of one line;
          // when they do not fit side by side (a narrow screen at a large
          // text size, a long translation) the note drops under the title
          // instead of running off the edge.
          : SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [title, trailing],
              ),
            ),
    );
  }
}

/// The helper under a public field: a globe and "Widoczne publicznie",
/// optionally followed by "· [extra]" ("tylko https://").
class PagePublicHelper extends StatelessWidget {
  const PagePublicHelper({this.extra, super.key});

  final String? extra;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final extra = this.extra;
    // The globe follows the reader's text size as the words beside it do.
    final iconSize = MediaQuery.textScalerOf(context).scale(14);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.public_rounded,
            size: iconSize,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            extra == null ? copy.publicHelper : '${copy.publicHelper} · $extra',
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// One text field of a Page form, with the label always floating.
///
/// A one-line value (the server refuses line breaks in it) still wraps on
/// screen and the field grows with it (its character limit bounds it): at a
/// large text size a narrow column would otherwise scroll the value sideways
/// and cut its start ("n–Pt 7:00…"). Enter stays the keyboard's action and
/// never inserts a line break, as in a one-line field.
///
/// [maxLength] shows the counter ("212/300"); [limit] caps the length
/// silently. Under the field stands the "Widoczne publicznie" helper (with
/// [publicExtra]) unless [helperText] replaces it; an [error] replaces both.
class PageFormTextField extends StatelessWidget {
  const PageFormTextField({
    required this.label,
    required this.controller,
    this.fieldKey,
    this.publicExtra,
    this.helperText,
    this.maxLines = 1,
    this.maxLength,
    this.limit,
    this.hint,
    this.error,
    this.keyboard,
    this.focusNode,
    this.enabled = true,
    this.readOnly = false,
    this.suffixIcon,
    this.autofillHints = const <String>[],
    super.key,
  });

  /// The [TextField]'s own key (tests enter text through it).
  final Key? fieldKey;
  final String label;
  final TextEditingController controller;
  final String? publicExtra;

  /// A plain helper line instead of the public one (the name's cooldown).
  final String? helperText;
  final int maxLines;
  final int? maxLength;
  final int? limit;
  final String? hint;
  final String? error;
  final TextInputType? keyboard;
  final FocusNode? focusNode;
  final bool enabled;

  /// The value stays readable and selectable but cannot be changed.
  final bool readOnly;
  final Widget? suffixIcon;

  /// [TextField]'s own default (an empty list): the platform may still offer
  /// its autofill. Null would switch autofill off for the field.
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final multiLine = maxLines > 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        key: fieldKey,
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        readOnly: readOnly,
        autofillHints: autofillHints,
        maxLines: multiLine ? maxLines : null,
        minLines: multiLine ? 3 : 1,
        maxLength: maxLength,
        inputFormatters: [
          if (!multiLine) FilteringTextInputFormatter.singleLineFormatter,
          if (limit != null) LengthLimitingTextInputFormatter(limit),
        ],
        keyboardType: multiLine
            ? TextInputType.multiline
            : keyboard ?? TextInputType.text,
        // R1 (UI.md): a one-line field is always followed by another field
        // here, so Return walks the form; the long-form ones keep Return as
        // a line break and finish with the Done bar (R3).
        textInputAction: multiLine ? null : TextInputAction.next,
        style: AppTypography.bodyLarge.copyWith(
          color: enabled && !readOnly
              ? palette.textPrimary
              : palette.textSecondary,
          fontSize: 16,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          errorText: error,
          errorMaxLines: 3,
          helper: error != null
              ? null
              : helperText == null
              ? PagePublicHelper(extra: publicExtra)
              : null,
          helperText: error == null ? helperText : null,
          helperMaxLines: 6,
          suffixIcon: suffixIcon,
          counterStyle: AppTypography.bodySmall.copyWith(
            color: palette.textTertiary,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// A form field that opens a picker (category, linked server, birth date) or,
/// when [locked], only shows a value that cannot be changed (the Page type,
/// D16) with the lock in place of the chevron.
class PageFormPickerField extends StatelessWidget {
  const PageFormPickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.fieldKey,
    this.helperText,
    this.helper,
    this.error,
    this.suffix = Icons.expand_more_rounded,
    this.focusNode,
    this.locked = false,
    this.lockedLabel,
    this.helperMaxLines = 3,
    super.key,
  });

  final int helperMaxLines;

  /// The tappable area's key (tests tap it).
  final Key? fieldKey;
  final String label;
  final String? value;

  /// Null disables the field (a read-only form).
  final VoidCallback? onTap;
  final String? helperText;
  final Widget? helper;
  final String? error;
  final IconData suffix;
  final FocusNode? focusNode;
  final bool locked;

  /// What a screen reader hears for the lock.
  final String? lockedLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final dimmed = locked || onTap == null;
    final decorator = InputDecorator(
      isEmpty: value == null,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        enabled: !dimmed,
        helper: error == null ? helper : null,
        helperText: error == null && helper == null ? helperText : null,
        helperMaxLines: helperMaxLines,
        errorMaxLines: 3,
        errorText: error,
        suffixIcon: Icon(
          locked ? Icons.lock_outline_rounded : suffix,
          size: locked ? 20 : null,
          color: dimmed ? palette.textTertiary : palette.textSecondary,
          semanticLabel: locked ? lockedLabel : null,
        ),
      ),
      child: Text(
        value ?? '',
        style: AppTypography.bodyLarge.copyWith(
          color: dimmed ? palette.textSecondary : palette.textPrimary,
          fontSize: 16,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: locked
          ? MergeSemantics(
              child: KeyedSubtree(key: fieldKey, child: decorator),
            )
          : Semantics(
              button: true,
              // Only a disabled field says so; an enabled one keeps the
              // plain button semantics it always had.
              enabled: onTap == null ? false : null,
              child: InkWell(
                key: fieldKey,
                focusNode: focusNode,
                onTap: onTap,
                borderRadius: AppRadius.md,
                child: decorator,
              ),
            ),
    );
  }
}

/// The pinned bottom action of a Page form on a phone: the page background,
/// a hairline on top and the safe-area inset under [child].
class PageBottomActionBar extends StatelessWidget {
  const PageBottomActionBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

/// The Page as one row of the Content wall (the suggestion row), as a
/// picture: inert, out of the focus order and hidden from screen readers (the
/// form beside it says everything it shows).
class PageWallPreviewRow extends StatelessWidget {
  const PageWallPreviewRow({
    required this.pageId,
    required this.name,
    required this.kind,
    required this.category,
    required this.followerCount,
    this.cardKey,
    this.faceImage,
    this.mediaService,
    this.mediaRevision,
    super.key,
  });

  final String pageId;
  final String name;
  final PageKind kind;
  final String category;
  final int followerCount;

  /// The card's own key.
  final Key? cardKey;

  /// A photo the owner chose and has not saved yet.
  final ImageProvider<Object>? faceImage;

  /// Test seam; the app uses the shared service.
  final ProfileMediaService? mediaService;
  final Object? mediaRevision;

  @override
  Widget build(BuildContext context) {
    final card = PageCard(
      pageId: pageId,
      displayName: name,
      kind: kind,
      category: category,
      followerCount: followerCount,
      onYoVoiceSinceMs: null,
      viewerFollows: false,
      lastPostAtMs: null,
    );
    return ExcludeFocus(
      child: IgnorePointer(
        child: YoCard(
          key: cardKey,
          semanticButton: false,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: PageListRow(
            card: card,
            follow: PageFollowBinding(
              follows: (_) => false,
              busy: (_) => false,
              onToggle: (_) {},
            ),
            onOpen: () {},
            showMeta: false,
            divider: false,
            faceImage: faceImage,
            mediaService: mediaService,
            mediaRevision: mediaRevision,
          ),
        ),
      ),
    );
  }
}

/// The profile header as visitors get it: the approved profile B header laid
/// out at the phone width (390) and scaled to the card. Inert, out of the
/// focus order and hidden from screen readers; its buttons are pictures, not
/// controls.
///
/// [coverImage] and [faceImage] stand in for the stored cover and photo (a
/// picture the owner just chose and has not saved yet).
class PageProfilePreviewHeader extends StatelessWidget {
  const PageProfilePreviewHeader({
    required this.pageId,
    required this.name,
    required this.kind,
    required this.followerCount,
    required this.description,
    this.frameKey,
    this.coverImage,
    this.faceImage,
    this.mediaService,
    this.mediaRevision,
    super.key,
  });

  final String pageId;
  final String name;
  final PageKind kind;

  /// The account's followers, which are the Page's (ADR-234).
  final int followerCount;
  final String description;

  /// The clipped frame's own key.
  final Key? frameKey;
  final ImageProvider<Object>? coverImage;
  final ImageProvider<Object>? faceImage;

  /// Test seam; the app uses the shared service.
  final ProfileMediaService? mediaService;
  final Object? mediaRevision;

  /// The phone width the header is laid out at before it is fitted to the
  /// card; a caption under it is never wider.
  static const double layoutWidth = 390;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    const cover = 150.0;
    const face = 80.0;
    final tonal = AppFinish.tonalNeutral(palette);
    final header = SizedBox(
      width: layoutWidth,
      child: ColoredBox(
        color: palette.background,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: cover + face / 2 + 3,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: cover,
                    child: PageCover(
                      pageId: pageId,
                      scrim: false,
                      localImage: coverImage,
                      mediaService: mediaService,
                      mediaRevision: mediaRevision,
                    ),
                  ),
                  Positioned(
                    left: 13,
                    top: cover - face / 2 - 3,
                    child: PageFace(
                      pageId: pageId,
                      name: name,
                      kind: kind,
                      size: face,
                      ring: 3,
                      ringColor: palette.background,
                      localImage: faceImage,
                      mediaService: mediaService,
                      mediaRevision: mediaRevision,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: MediaQuery.withNoTextScaling(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NameWithVipMark(
                      uid: pageId,
                      name: name,
                      maxLines: 2,
                      style: AppTypography.screenTitle.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      copy.headerMeta(kind, followerCount),
                      style: AppTypography.bodySmall.copyWith(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMedium.copyWith(
                          fontSize: 14,
                          height: 1.5,
                          color: palette.textPrimary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: YoGradientFilledButton(
                            onPressed: () {},
                            minimumSize: const Size(132, 44),
                            icon: const Icon(Icons.add_rounded, size: 20),
                            child: Text(copy.follow),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {},
                          style: tonal.merge(
                            OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                            ),
                          ),
                          icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                          ),
                          label: Text(copy.message),
                        ),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          onPressed: () {},
                          style: tonal.merge(
                            IconButton.styleFrom(
                              minimumSize: const Size(44, 44),
                              fixedSize: const Size(44, 44),
                            ),
                          ),
                          icon: const Icon(Icons.more_horiz_rounded, size: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return ExcludeFocus(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: ClipRRect(
            key: frameKey,
            borderRadius: AppRadius.block,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: AppRadius.block,
                border: Border.all(color: palette.border),
              ),
              child: FittedBox(fit: BoxFit.fitWidth, child: header),
            ),
          ),
        ),
      ),
    );
  }
}

/// A box that sticks to the top of the viewport while the rest of its
/// [SliverCrossAxisGroup] scrolls, and that the group pushes up at its end
/// so it never hangs below the form (CSS `position: sticky` with `top: 0`;
/// the box brings its own top padding). It is painted and hit-tested where
/// it sticks, so what it holds stays usable. When the box is taller than the
/// viewport it scrolls like any other content, so nothing in it is ever out
/// of reach.
class PageStickySliver extends SingleChildRenderObjectWidget {
  const PageStickySliver({required Widget super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPageStickySliver();
}

class _RenderPageStickySliver extends RenderSliverSingleBoxAdapter {
  bool _pinned = true;

  @override
  double childMainAxisPosition(RenderBox child) =>
      _pinned ? 0 : -constraints.scrollOffset;

  @override
  void performLayout() {
    final box = child;
    if (box == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    box.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final extent = box.size.height;
    _pinned = extent <= constraints.viewportMainAxisExtent;
    if (!_pinned) {
      final paintExtent = calculatePaintOffset(
        constraints,
        from: 0,
        to: extent,
      );
      geometry = SliverGeometry(
        scrollExtent: extent,
        paintExtent: paintExtent,
        maxPaintExtent: extent,
        hitTestExtent: paintExtent,
        cacheExtent: calculateCacheOffset(constraints, from: 0, to: extent),
        hasVisualOverflow:
            extent > constraints.remainingPaintExtent ||
            constraints.scrollOffset > 0,
      );
      setChildParentData(box, constraints, geometry!);
      return;
    }
    (box.parentData! as SliverPhysicalParentData).paintOffset = Offset.zero;
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintOrigin: constraints.overlap,
      paintExtent: math.min(
        extent,
        constraints.remainingPaintExtent - constraints.overlap,
      ),
      layoutExtent: (extent - constraints.scrollOffset).clamp(
        0,
        constraints.remainingPaintExtent,
      ),
      maxPaintExtent: extent,
      cacheExtent: calculateCacheOffset(constraints, from: 0, to: extent),
      hasVisualOverflow: true,
    );
  }
}
