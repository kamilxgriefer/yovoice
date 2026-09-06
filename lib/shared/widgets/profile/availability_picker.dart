import 'package:flutter/material.dart';

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
    super.key,
  });

  final UserAvailability availability;
  final PresenceService? presenceService;

  /// Dot + caret only, for tight rails.
  final bool compact;

  /// A shorter chip that sits inline with a text line (profile name plate).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final status = PeopleStatus.fromOwnAvailability(availability);
    final label = availability.localizedLabel(copy);
    return Semantics(
      button: true,
      label: copy.template(
        'Availability: {status}. Change',
        'Dostępność: {status}. Zmień',
        values: <String, Object>{'status': label},
      ),
      child: Material(
        color: palette.surfaceSunken.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          key: const ValueKey('availability-chip'),
          borderRadius: BorderRadius.circular(999),
          onTap: () => showAvailabilityPicker(
            context,
            current: availability,
            presenceService: presenceService,
          ),
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
      ),
    );
  }
}
