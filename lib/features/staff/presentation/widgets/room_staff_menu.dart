import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/role_identity.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

/// The staff shield on a room banner.
///
/// Renders NOTHING unless the server-derived capabilities include a room
/// action for this account — an ordinary user's banner is byte-for-byte
/// what it always was. The shield's colour is the tier: crimson for the
/// owner, coral for super moderation, violet for a moderator.
///
/// Every action here is re-authorized server-side; this menu is a door,
/// not a lock.
class RoomStaffMenu extends StatelessWidget {
  const RoomStaffMenu({
    required this.room,
    required this.capabilities,
    this.functions,
    this.onRoomDeleted,
    super.key,
  });

  final VoiceRoom room;
  final StaffCapabilities capabilities;

  /// Injected in tests; production resolves the regional instance.
  final FirebaseFunctions? functions;

  final VoidCallback? onRoomDeleted;

  FirebaseFunctions get _functions =>
      functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  Color get _tierColor => capabilities.isOwner
      ? RoleIdentity.ownerColor
      : capabilities.endAnyRoom
      ? RoleIdentity.superModeratorColor
      : RoleIdentity.moderatorColor;

  @override
  Widget build(BuildContext context) {
    if (!capabilities.hasRoomModeration) return const SizedBox.shrink();
    final copy = AppLocalizations.of(context);

    return PopupMenuButton<_StaffAction>(
      tooltip: copy.text('Staff actions', 'Działania zespołu'),
      icon: Icon(Icons.shield_rounded, color: _tierColor, size: 20),
      color: const Color(0xFF171121),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _tierColor.withValues(alpha: .45)),
      ),
      itemBuilder: (context) => [
        if (capabilities.endPublicRoomWithReason && !capabilities.endAnyRoom)
          PopupMenuItem(
            value: _StaffAction.endWithReason,
            child: _MenuRow(
              icon: Icons.stop_circle_outlined,
              label: copy.text('End public room…', 'Zakończ pokój publiczny…'),
            ),
          ),
        if (capabilities.endAnyRoom)
          PopupMenuItem(
            value: _StaffAction.end,
            child: _MenuRow(
              icon: Icons.stop_circle_outlined,
              label: copy.text('End room…', 'Zakończ pokój…'),
            ),
          ),
        if (capabilities.quarantineSpaces)
          PopupMenuItem(
            value: _StaffAction.quarantine,
            child: _MenuRow(
              icon: Icons.gpp_maybe_outlined,
              label: copy.text('Quarantine…', 'Poddaj kwarantannie…'),
            ),
          ),
        if (capabilities.permanentDeleteSpaces)
          PopupMenuItem(
            value: _StaffAction.deletePermanently,
            child: _MenuRow(
              icon: Icons.delete_forever_rounded,
              label: copy.text('Delete permanently…', 'Usuń trwale…'),
              color: RoleIdentity.ownerColor,
            ),
          ),
      ],
      onSelected: (action) => _handle(context, action),
    );
  }

  Future<void> _handle(BuildContext context, _StaffAction action) async {
    final copy = AppLocalizations.of(context);
    switch (action) {
      case _StaffAction.endWithReason:
      case _StaffAction.end:
        await _withReason(
          context,
          title: copy.text(
            'End "${room.name}"?',
            'Zakończyć pokój „${room.name}”?',
          ),
          confirmLabel: copy.text('End room', 'Zakończ pokój'),
          onConfirm: (reason) => _functions
              .httpsCallable('forceEndRoom')
              .call<Map<String, dynamic>>({
                'roomId': room.id,
                'reason': reason,
              }),
        );
      case _StaffAction.quarantine:
        await _withReason(
          context,
          title: copy.text(
            'Quarantine "${room.name}"?',
            'Poddaj pokój „${room.name}” kwarantannie?',
          ),
          confirmLabel: copy.text('Quarantine', 'Poddaj kwarantannie'),
          onConfirm: (reason) => _functions
              .httpsCallable('setRoomModerationStatus')
              .call<Map<String, dynamic>>({
                'roomId': room.id,
                'status': 'quarantined',
                'reason': reason,
              }),
        );
      case _StaffAction.deletePermanently:
        final deleted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              OwnerDeleteRoomDialog(room: room, functions: _functions),
        );
        if (deleted == true) onRoomDeleted?.call();
    }
  }

  Future<void> _withReason(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required Future<void> Function(String reason) onConfirm,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: title,
        confirmLabel: confirmLabel,
        color: _tierColor,
        onConfirm: onConfirm,
      ),
    );
  }
}

enum _StaffAction { endWithReason, end, quarantine, deletePermanently }

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? const Color(0xFFE4DEED);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: tint),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: tint, fontSize: 13.5),
          ),
        ),
      ],
    );
  }
}

/// A mandatory-reason confirmation used by the moderation tiers.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.confirmLabel,
    required this.color,
    required this.onConfirm,
  });

  final String title;
  final String confirmLabel;
  final Color color;
  final Future<void> Function(String reason) onConfirm;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _reason.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm(_reason.text.trim());
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        final copy = AppLocalizations.of(context);
        setState(() {
          _busy = false;
          _error = friendlyErrorMessage(
            error,
            fallback: copy.text(
              'Could not complete this action. Please try again.',
              'Nie udało się wykonać działania. Spróbuj ponownie.',
            ),
            copy: copy,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: const Color(0xFF171121),
      title: Text(
        widget.title,
        style: const TextStyle(color: Colors.white, fontSize: 17),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _reason,
            enabled: !_busy,
            maxLength: 500,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: copy.text('Reason (required)', 'Powód (wymagany)'),
              labelStyle: const TextStyle(color: Color(0xFFB8AFC2)),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFFF9BB0),
                  fontSize: 12.5,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(copy.text('Cancel', 'Anuluj')),
        ),
        FilledButton(
          onPressed: _busy || _reason.text.trim().isEmpty ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: widget.color),
          child: _busy
              ? Semantics(
                  label: copy.text(
                    'Applying room action',
                    'Wykonywanie działania w pokoju',
                  ),
                  child: const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// The owner's permanent-deletion confirmation.
///
/// Requires a reason AND the exact room name typed back, disables the
/// destructive button while a submission is in flight, and pops with
/// success only after the server confirmed — the banner disappears
/// because the deletion happened, never optimistically.
class OwnerDeleteRoomDialog extends StatefulWidget {
  const OwnerDeleteRoomDialog({
    required this.room,
    required this.functions,
    super.key,
  });

  final VoiceRoom room;
  final FirebaseFunctions functions;

  @override
  State<OwnerDeleteRoomDialog> createState() => _OwnerDeleteRoomDialogState();
}

class _OwnerDeleteRoomDialogState extends State<OwnerDeleteRoomDialog> {
  final _reason = TextEditingController();
  final _confirmName = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _valid =>
      _reason.text.trim().isNotEmpty &&
      _confirmName.text.trim() == widget.room.name.trim();

  @override
  void dispose() {
    _reason.dispose();
    _confirmName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The typed NAME is the human check; the id is the API contract.
      await widget.functions
          .httpsCallable('adminDeleteRoom')
          .call<Map<String, dynamic>>({
            'roomId': widget.room.id,
            'reason': _reason.text.trim(),
            'confirmation': widget.room.id,
          });
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        final copy = AppLocalizations.of(context);
        setState(() {
          _busy = false;
          _error = friendlyErrorMessage(
            error,
            fallback: copy.text(
              'Could not permanently delete the room. Please try again.',
              'Nie udało się trwale usunąć pokoju. Spróbuj ponownie.',
            ),
            copy: copy,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: const Color(0xFF171121),
      title: Text(
        copy.text('Delete permanently', 'Usuń trwale'),
        style: const TextStyle(color: RoleIdentity.ownerColor, fontSize: 17),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              copy.text(
                'This removes "${widget.room.name}" and everything in it. There is no undo.',
                'Usuniesz pokój „${widget.room.name}” wraz z całą jego zawartością. Tej operacji nie można cofnąć.',
              ),
              style: const TextStyle(
                color: Color(0xFFB6ACBB),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reason,
              enabled: !_busy,
              maxLength: 500,
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: copy.text('Reason (required)', 'Powód (wymagany)'),
                labelStyle: const TextStyle(color: Color(0xFFB8AFC2)),
              ),
            ),
            TextField(
              controller: _confirmName,
              enabled: !_busy,
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: copy.text(
                  'Type the room name to confirm',
                  'Wpisz nazwę pokoju, aby potwierdzić',
                ),
                hintText: widget.room.name,
                labelStyle: const TextStyle(color: Color(0xFFB8AFC2)),
                hintStyle: const TextStyle(color: Color(0xFF746A80)),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFFF9BB0),
                    fontSize: 12.5,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(copy.text('Cancel', 'Anuluj')),
        ),
        FilledButton(
          onPressed: _busy || !_valid ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: RoleIdentity.ownerColor,
          ),
          child: _busy
              ? Semantics(
                  label: copy.text(
                    'Deleting room permanently',
                    'Trwałe usuwanie pokoju',
                  ),
                  child: const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Text(copy.text('Delete permanently', 'Usuń trwale')),
        ),
      ],
    );
  }
}
