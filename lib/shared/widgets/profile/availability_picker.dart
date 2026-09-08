import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/presence/user_availability.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

/// Lets the signed-in user choose the availability their friends see as a
/// ring colour: green available, yellow be right back, red do not disturb,
/// grey invisible. One sheet (narrow) or dialog (wide) for every entry point.
Future<void> showAvailabilityPicker(
  BuildContext context, {
  required UserAvailability current,
  PresenceService? presenceService,
}) async {
  final wide = MediaQuery.sizeOf(context).width >= 900;
  final copy = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);

  Future<void> select(BuildContext sheetContext, UserAvailability value) async {
    Navigator.of(sheetContext).pop();
    if (value == current) return;
    try {
      // Built only when a choice is made, so opening the picker never touches
      // Firebase (previews and captures run without an app).
      await (presenceService ?? PresenceService()).setAvailability(value);
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            copy.text(
              'Could not change your availability. Try again.',
              'Nie udało się zmienić dostępności. Spróbuj ponownie.',
            ),
          ),
        ),
      );
    }
  }

  Widget options(BuildContext sheetContext) => _AvailabilityOptions(
    current: current,
    onSelect: (value) => select(sheetContext, value),
  );

  if (wide) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: dialogContext.appPalette.surfaceRaised,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: options(dialogContext),
          ),
        ),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(
      context,
      maxWidth: 520,
    ),
    builder: (sheetContext) {
      final palette = sheetContext.appPalette;
      return Material(
        color: palette.surfaceRaised,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            8,
            12,
            8,
            18 + MediaQuery.paddingOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              YoModalSheetChrome(
                sheetLabel: copy.text('availability', 'dostępność'),
                surfaceColor: palette.surfaceRaised,
              ),
              options(sheetContext),
            ],
          ),
        ),
      );
    },
  );
}

class _AvailabilityOptions extends StatelessWidget {
  const _AvailabilityOptions({required this.current, required this.onSelect});

  final UserAvailability current;
  final ValueChanged<UserAvailability> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            copy.text('Your availability', 'Twoja dostępność'),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        for (final option in UserAvailability.values)
          ListTile(
            key: ValueKey('availability-option-${option.wire}'),
            selected: option == current,
            onTap: () => onSelect(option),
            leading: AvailabilityDot(
              status: PeopleStatus.fromOwnAvailability(option),
              size: 14,
            ),
            title: Text(
              option.localizedLabel(copy),
              style: TextStyle(color: palette.textPrimary),
            ),
            subtitle: Text(
              option.localizedHint(copy),
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
            trailing: option == current
                ? Icon(
                    Icons.check_rounded,
                    color: palette.interactiveForeground,
                  )
                : null,
          ),
      ],
    );
  }
}

/// A filled circle in a status colour — the ring colour, as a dot.
class AvailabilityDot extends StatelessWidget {
  const AvailabilityDot({required this.status, this.size = 10, super.key});

  final PeopleStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: status.foreground(palette),
        border: Border.all(color: palette.surfaceRaised, width: 1.5),
      ),
    );
  }
}

/// The tappable "● Available ▾" chip shown wherever the signed-in account
/// is presented (profile header, More sheet, desktop profile card).
class AvailabilityChip extends StatelessWidget {
  const AvailabilityChip({
    required this.availability,
    this.presenceService,
    this.compact = false,
    this.dense = false,
    this.hitTargetSize,
    super.key,
  });

  final UserAvailability availability;
  final PresenceService? presenceService;

  /// Dot + caret only, for tight rails.
  final bool compact;

  /// A shorter chip that sits inline with a text line (profile name plate).
  final bool dense;

  /// Minimum size of the tap target on BOTH axes. The visible pill keeps its
  /// size; the reserved band around it forwards taps to the pill, the way
  /// Material buttons meet their 48 px target without growing. Every entry
  /// point that presents the chip as a touch control passes 44; null leaves
  /// the chip exactly as wide and tall as its pill.
  final double? hitTargetSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final status = PeopleStatus.fromOwnAvailability(availability);
    final label = availability.localizedLabel(copy);
    void open() => showAvailabilityPicker(
      context,
      current: availability,
      presenceService: presenceService,
    );
    final pill = Material(
      color: palette.surfaceSunken.withValues(alpha: .85),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        key: const ValueKey('availability-chip'),
        borderRadius: BorderRadius.circular(999),
        onTap: open,
        // The composed phrase on the boundary below is the whole
        // announcement; the pill's own Text would otherwise repeat the
        // status a second time inside it.
        excludeFromSemantics: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 10,
            dense ? 2 : 5,
            compact ? 6 : 8,
            dense ? 2 : 5,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AvailabilityDot(status: status, size: dense ? 8 : 10),
              if (!compact) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: dense ? 11 : 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: dense ? 14 : 16,
                color: palette.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
    final target = hitTargetSize;
    // `container: true` makes this a real semantics boundary. Without it the
    // annotation merges into whatever compatible siblings sit beside the chip
    // — the Home greeting Text nodes — and the whole greeting becomes the
    // accessible name of one giant button.
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: copy.template(
        'Availability: {status}. Change',
        'Dostępność: {status}. Zmień',
        values: <String, Object>{'status': label},
      ),
      onTap: open,
      child: target == null
          ? pill
          : _HitTargetPadding(minSize: Size(target, target), child: pill),
    );
  }
}

/// Centres its child inside at least [minSize] on both axes and forwards a
/// hit anywhere in that band to the child's centre — the same mechanism
/// Material's `_RenderInputPadding` uses for its own minimum tap target, so
/// the pill's ink stays on the pill while the target meets 44 x 44.
class _HitTargetPadding extends SingleChildRenderObjectWidget {
  const _HitTargetPadding({required this.minSize, required super.child});

  final Size minSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHitTargetPadding(minSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHitTargetPadding renderObject,
  ) {
    renderObject.minSize = minSize;
  }
}

class _RenderHitTargetPadding extends RenderShiftedBox {
  _RenderHitTargetPadding(this._minSize) : super(null);

  Size _minSize;
  Size get minSize => _minSize;
  set minSize(Size value) {
    if (value == _minSize) return;
    _minSize = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(child?.getMinIntrinsicWidth(height) ?? 0, minSize.width);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(child?.getMaxIntrinsicWidth(height) ?? 0, minSize.width);

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(child?.getMinIntrinsicHeight(width) ?? 0, minSize.height);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(child?.getMaxIntrinsicHeight(width) ?? 0, minSize.height);

  Size _sizeFor(Size childSize, BoxConstraints constraints) =>
      constraints.constrain(
        Size(
          math.max(childSize.width, minSize.width),
          math.max(childSize.height, minSize.height),
        ),
      );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.constrain(minSize);
    return _sizeFor(child.getDryLayout(constraints.loosen()), constraints);
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(minSize);
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    size = _sizeFor(child.size, constraints);
    (child.parentData! as BoxParentData).offset = Offset(
      (size.width - child.size.width) / 2,
      (size.height - child.size.height) / 2,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTest(result, position: position)) return true;
    final child = this.child;
    if (child == null || !size.contains(position)) return false;
    // Mirror Material's `_RenderInputPadding`: a hit in the band lands on
    // the child's own centre, in the child's coordinates.
    final center = child.size.center(Offset.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(center),
      position: center,
      hitTest: (BoxHitTestResult result, Offset position) {
        assert(position == center);
        return child.hitTest(result, position: center);
      },
    );
  }
}
