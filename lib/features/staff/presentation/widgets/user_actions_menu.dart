import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/role_identity.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

/// The ••• menu on a compact profile sheet — and the same component the
/// Staff Center reuses after a lookup, so the two can never disagree.
///
/// Two sections, deliberately separated:
///  - PERSONAL actions every authenticated user has: report, block,
///    personal mute. They affect only the acting user and are never
///    sanctions.
///  - STAFF actions rendered ONLY when the server-derived capabilities
///    include them. No disabled buttons, no greyed hints: an ordinary
///    user's menu contains no trace of the staff section, and a forged
///    menu could still change nothing — every action re-verifies
///    server-side.
class UserActionsMenu extends StatelessWidget {
  const UserActionsMenu({
    required this.targetUid,
    required this.targetName,
    required this.capabilities,
    this.currentUid = '',
    this.isBlocked = false,
    this.isPersonallyMuted = false,
    this.functions,
    this.firestore,
    this.reportService,
    this.friendService,
    this.onChanged,
    super.key,
  });

  final String targetUid;
  final String targetName;
  final StaffCapabilities capabilities;
  final String currentUid;
  final bool isBlocked;
  final bool isPersonallyMuted;

  final FirebaseFunctions? functions;
  final FirebaseFirestore? firestore;
  final ReportService? reportService;
  final FriendService? friendService;
  final VoidCallback? onChanged;

  FirebaseFunctions get _functions =>
      functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  bool get _isSelf => targetUid == currentUid;

  bool get _hasStaffSection =>
      capabilities.warnUsers ||
      capabilities.suspendUsers ||
      capabilities.liftSuspensions ||
      capabilities.permanentBan;

  @override
  Widget build(BuildContext context) {
    if (_isSelf) return const SizedBox.shrink();

    return PopupMenuButton<_UserAction>(
      tooltip: 'User actions',
      icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFFB8AFC2)),
      color: const Color(0xFF171121),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF3A2C49)),
      ),
      itemBuilder: (context) => [
        // ------------------------------------------------ personal
        const PopupMenuItem(
          value: _UserAction.report,
          child: _Row(icon: Icons.flag_outlined, label: 'Report user'),
        ),
        PopupMenuItem(
          value: _UserAction.toggleBlock,
          child: _Row(
            icon: Icons.block_rounded,
            label: isBlocked ? 'Unblock user' : 'Block user',
          ),
        ),
        PopupMenuItem(
          value: _UserAction.togglePersonalMute,
          child: _Row(
            icon: isPersonallyMuted
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            label: isPersonallyMuted ? 'Unmute for me' : 'Mute for me',
          ),
        ),
        // ------------------------------------------------ staff
        if (_hasStaffSection) const PopupMenuDivider(),
        if (capabilities.warnUsers)
          const PopupMenuItem(
            value: _UserAction.warn,
            child: _Row(
              icon: Icons.report_gmailerrorred_rounded,
              label: 'Warn user…',
              staff: true,
            ),
          ),
        if (capabilities.suspendUsers) ...[
          const PopupMenuItem(
            value: _UserAction.communicationMute,
            child: _Row(
              icon: Icons.mic_off_rounded,
              label: 'Mute communication…',
              staff: true,
            ),
          ),
          const PopupMenuItem(
            value: _UserAction.suspend,
            child: _Row(
              icon: Icons.pause_circle_outline_rounded,
              label: 'Suspend account…',
              staff: true,
            ),
          ),
        ],
        if (capabilities.liftSuspensions) ...[
          const PopupMenuItem(
            value: _UserAction.liftMute,
            child: _Row(
              icon: Icons.mic_rounded,
              label: 'Lift communication mute…',
              staff: true,
            ),
          ),
          const PopupMenuItem(
            value: _UserAction.liftSuspension,
            child: _Row(
              icon: Icons.play_circle_outline_rounded,
              label: 'Lift suspension…',
              staff: true,
            ),
          ),
        ],
        if (capabilities.permanentBan) ...[
          const PopupMenuItem(
            value: _UserAction.permanentBan,
            child: _Row(
              icon: Icons.gavel_rounded,
              label: 'Ban permanently…',
              staff: true,
              color: RoleIdentity.ownerColor,
            ),
          ),
          const PopupMenuItem(
            value: _UserAction.unban,
            child: _Row(
              icon: Icons.restart_alt_rounded,
              label: 'Unban account…',
              staff: true,
            ),
          ),
        ],
      ],
      onSelected: (action) => _handle(context, action),
    );
  }

  // ------------------------------------------------------------ actions

  Future<void> _handle(BuildContext context, _UserAction action) async {
    switch (action) {
      case _UserAction.report:
        await _report(context);
      case _UserAction.toggleBlock:
        await _personal(context, () async {
          final service = friendService ?? FriendService();
          isBlocked
              ? await service.unblockUser(targetUid)
              : await service.blockUser(targetUid);
        }, isBlocked ? 'Unblocked $targetName.' : 'Blocked $targetName.');
      case _UserAction.togglePersonalMute:
        await _personal(context, () async {
          final db = firestore ?? FirebaseFirestore.instance;
          final ref = db
              .collection('users')
              .doc(currentUid)
              .collection('muted')
              .doc(targetUid);
          isPersonallyMuted
              ? await ref.delete()
              : await ref.set({'mutedAt': FieldValue.serverTimestamp()});
        }, isPersonallyMuted
            ? 'Unmuted $targetName for you.'
            : 'Muted $targetName for you only.');
      case _UserAction.warn:
        await _sanction(context,
            title: 'Warn $targetName',
            confirmLabel: 'Send warning',
            durations: null,
            onConfirm: (reason, _) => _applySanction('warn', reason));
      case _UserAction.communicationMute:
        await _sanction(context,
            title: 'Mute communication — $targetName',
            confirmLabel: 'Apply mute',
            durations: _durations(),
            scopeNote: 'Scope: platform-wide public communication.',
            onConfirm: (reason, hours) =>
                _applySanction('communicationMute', reason, hours));
      case _UserAction.liftMute:
        await _sanction(context,
            title: 'Lift communication mute — $targetName',
            confirmLabel: 'Lift mute',
            durations: null,
            onConfirm: (reason, _) => _applySanction('liftMute', reason));
      case _UserAction.suspend:
        await _sanction(context,
            title: 'Suspend $targetName',
            confirmLabel: 'Suspend account',
            durations: _durations(forSuspension: true),
            onConfirm: (reason, hours) => _setBan(true, reason, hours));
      case _UserAction.liftSuspension:
        await _sanction(context,
            title: 'Lift suspension — $targetName',
            confirmLabel: 'Lift suspension',
            durations: null,
            onConfirm: (reason, _) => _setBan(false, reason, 0));
      case _UserAction.permanentBan:
        await _sanction(context,
            title: 'Ban $targetName permanently',
            confirmLabel: 'Ban permanently',
            durations: null,
            destructive: true,
            onConfirm: (reason, _) => _setBan(true, reason, 0));
      case _UserAction.unban:
        await _sanction(context,
            title: 'Unban $targetName',
            confirmLabel: 'Unban account',
            durations: null,
            onConfirm: (reason, _) => _setBan(false, reason, 0));
    }
  }

  /// Bounded, tier-appropriate duration choices. The server re-validates
  /// every value; this list only offers what the tier could ever get.
  List<int>? _durations({bool forSuspension = false}) {
    final limit = capabilities.suspensionLimitHours;
    final all = [1, 6, 12, 24, 72, 168, 336, 720];
    final within = limit == null
        ? all
        : all.where((h) => h <= limit).toList(growable: false);
    // The owner (limit == null) may also choose indefinite (0) — for a
    // mute always, for a suspension it means a permanent ban and is
    // offered through the dedicated menu entry instead.
    return limit == null && !forSuspension ? [...within, 0] : within;
  }

  Future<void> _applySanction(String action, String reason,
      [int? hours]) async {
    await _functions.httpsCallable('applySanction').call<Map<String, dynamic>>({
      'action': action,
      'uid': targetUid,
      'reason': reason,
      'durationHours': ?hours,
    });
  }

  Future<void> _setBan(bool banned, String reason, int hours) async {
    await _functions.httpsCallable('setUserBan').call<Map<String, dynamic>>({
      'uid': targetUid,
      'banned': banned,
      'reason': reason,
      'durationHours': hours,
    });
  }

  Future<void> _report(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await (reportService ?? ReportService()).report(
        targetType: ReportTargetType.user,
        targetId: targetUid,
        reportedUserId: targetUid,
        reason: ReportReason.harassment,
        note: 'Reported from profile',
      );
      messenger?.showSnackBar(
        SnackBar(content: Text('Reported $targetName. Our team will review.')),
      );
    } catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(_readable(error))));
    }
  }

  Future<void> _personal(
    BuildContext context,
    Future<void> Function() act,
    String successMessage,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await act();
      messenger?.showSnackBar(SnackBar(content: Text(successMessage)));
      onChanged?.call();
    } catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(_readable(error))));
    }
  }

  Future<void> _sanction(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required List<int>? durations,
    required Future<void> Function(String reason, int hours) onConfirm,
    String? scopeNote,
    bool destructive = false,
  }) async {
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SanctionDialog(
        title: title,
        confirmLabel: confirmLabel,
        targetName: targetName,
        durations: durations,
        scopeNote: scopeNote,
        destructive: destructive,
        onConfirm: onConfirm,
      ),
    );
    if (done == true) onChanged?.call();
  }

  static String _readable(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), '')
      .replaceFirst('Exception: ', '');
}

enum _UserAction {
  report,
  toggleBlock,
  togglePersonalMute,
  warn,
  communicationMute,
  liftMute,
  suspend,
  liftSuspension,
  permanentBan,
  unban,
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.staff = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final bool staff;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint =
        color ?? (staff ? RoleIdentity.moderatorColor : const Color(0xFFE4DEED));
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

/// One dialog for every staff action: mandatory reason, bounded duration
/// where the action takes one, the target and expiry restated before the
/// button, busy protection, and the UI only moves after the server said
/// yes.
class SanctionDialog extends StatefulWidget {
  const SanctionDialog({
    required this.title,
    required this.confirmLabel,
    required this.targetName,
    required this.durations,
    required this.onConfirm,
    this.scopeNote,
    this.destructive = false,
    super.key,
  });

  final String title;
  final String confirmLabel;
  final String targetName;
  final List<int>? durations;
  final Future<void> Function(String reason, int hours) onConfirm;
  final String? scopeNote;
  final bool destructive;

  @override
  State<SanctionDialog> createState() => _SanctionDialogState();
}

class _SanctionDialogState extends State<SanctionDialog> {
  final _reason = TextEditingController();
  int? _hours;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final durations = widget.durations;
    if (durations != null && durations.isNotEmpty) _hours = durations.first;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _valid =>
      _reason.text.trim().length >= 3 &&
      (widget.durations == null || _hours != null);

  String get _expiryLine {
    if (widget.durations == null || _hours == null) return '';
    if (_hours == 0) return 'Expiry: never (indefinite).';
    final expiry = DateTime.now().add(Duration(hours: _hours!));
    return 'Expiry: ${_hours}h — until ${expiry.toLocal()}'.split('.').first;
  }

  Future<void> _submit() async {
    if (_busy || !_valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm(_reason.text.trim(), _hours ?? 0);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = UserActionsMenu._readable(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.destructive
        ? RoleIdentity.ownerColor
        : RoleIdentity.moderatorColor;
    return AlertDialog(
      backgroundColor: const Color(0xFF171121),
      title: Text(
        widget.title,
        style: TextStyle(color: accent, fontSize: 16.5),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Target: ${widget.targetName}',
              style: const TextStyle(
                color: Color(0xFFE4DEED),
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.scopeNote != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.scopeNote!,
                style: const TextStyle(color: Color(0xFFA69CAF), fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              enabled: !_busy,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                labelStyle: TextStyle(color: Color(0xFFB8AFC2)),
              ),
            ),
            if (widget.durations != null) ...[
              DropdownButtonFormField<int>(
                initialValue: _hours,
                dropdownColor: const Color(0xFF21172D),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Duration',
                  labelStyle: TextStyle(color: Color(0xFFB8AFC2)),
                ),
                items: [
                  for (final h in widget.durations!)
                    DropdownMenuItem(
                      value: h,
                      child: Text(h == 0 ? 'Indefinite' : '$h hours'),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _hours = value),
              ),
              const SizedBox(height: 6),
              Text(
                _expiryLine,
                style: const TextStyle(color: Color(0xFFA69CAF), fontSize: 12),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style:
                    const TextStyle(color: Color(0xFFFF9BB0), fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || !_valid ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: accent),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
