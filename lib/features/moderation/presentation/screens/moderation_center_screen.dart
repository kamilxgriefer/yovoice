import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/messages/data/models/global_message.dart';
import 'package:yovoice/features/moderation/data/models/moderation_report.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_message_sheet.dart';
import 'package:yovoice/features/moderation/presentation/widgets/report_audit_timeline.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The staff Moderation Center — the report queue and its detail panel,
/// rendered inside the SAME fixed desktop shell as every other
/// destination. It is reached from the desktop More popover, which only
/// lists it for staff.
///
/// Hiding the menu entry is presentation, not security. This screen
/// re-checks authority on mount and renders an access-denied state
/// without loading a single report if the check fails, `firestore.rules`
/// denies the queries outright for non-staff, and every mutation goes
/// through a callable that checks again server-side.
///
/// Desktop-only in this milestone: nothing here is wired into mobile
/// navigation, and no mobile file was touched to build it.
class ModerationCenterScreen extends StatefulWidget {
  const ModerationCenterScreen({
    this.isRootTab = false,
    this.moderationService,
    super.key,
  });

  final bool isRootTab;
  final ModerationService? moderationService;

  @override
  State<ModerationCenterScreen> createState() => _ModerationCenterScreenState();
}

class _ModerationCenterScreenState extends State<ModerationCenterScreen> {
  ModerationService? _service;

  /// null while the authority check is still running — the queue must
  /// not be queried, and "denied" must not flash, before it resolves.
  bool? _isStaff;
  String _role = 'user';

  ReportStatus _status = ReportStatus.open;
  ReportTargetType? _targetFilter;
  ReportReason? _reasonFilter;
  int _limit = ModerationService.pageSize;

  /// Held across snapshots so a live update cannot move the selection.
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    try {
      _service = widget.moderationService ?? ModerationService();
    } catch (_) {
      _service = null;
    }
    _resolveAuthority();
  }

  Future<void> _resolveAuthority() async {
    final service = _service;
    if (service == null) {
      if (mounted) setState(() => _isStaff = false);
      return;
    }
    final staff = await service.isActiveStaff();
    final role = staff ? await service.currentRole() : 'user';
    if (!mounted) return;
    setState(() {
      _isStaff = staff;
      _role = role;
    });
  }

  /// Called when a privileged action comes back as access-expired: the
  /// role was revoked while the panel was open. Sensitive report data is
  /// dropped from the UI immediately rather than left on screen.
  void _handleAccessExpired() {
    if (!mounted) return;
    setState(() {
      _isStaff = false;
      _selectedId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: switch (_isStaff) {
          null => const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ),
          false => const _AccessDenied(),
          true => _ModerationWorkspace(
            service: _service!,
            role: _role,
            status: _status,
            targetFilter: _targetFilter,
            reasonFilter: _reasonFilter,
            limit: _limit,
            selectedId: _selectedId,
            onStatus: (status) => setState(() {
              _status = status;
              _limit = ModerationService.pageSize;
              _selectedId = null;
            }),
            // Narrowing changes which documents the query returns, so
            // the page window resets — keeping it would claim to have
            // paged through a set that was never queried.
            onTargetFilter: (value) => setState(() {
              _targetFilter = value;
              _limit = ModerationService.pageSize;
              _selectedId = null;
            }),
            onReasonFilter: (value) => setState(() {
              _reasonFilter = value;
              _limit = ModerationService.pageSize;
              _selectedId = null;
            }),
            onSelect: (id) => setState(() => _selectedId = id),
            onLoadMore: () =>
                setState(() => _limit += ModerationService.pageSize),
            onAccessExpired: _handleAccessExpired,
          ),
        },
      ),
    );
  }
}

/// What a non-staff account sees. No queue is queried, so there is
/// nothing to leak even if this widget were reached some other way.
class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: .12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: .35),
                ),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: Color(0xFFD3A5FF),
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Moderation is staff only',
              semanticsLabel: 'Moderation is staff only',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This area is limited to accounts with a moderator role. '
              'If your access changed while you were working, sign out '
              'and back in to refresh it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9A90AC),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModerationWorkspace extends StatelessWidget {
  const _ModerationWorkspace({
    required this.service,
    required this.role,
    required this.status,
    required this.targetFilter,
    required this.reasonFilter,
    required this.limit,
    required this.selectedId,
    required this.onStatus,
    required this.onTargetFilter,
    required this.onReasonFilter,
    required this.onSelect,
    required this.onLoadMore,
    required this.onAccessExpired,
  });

  final ModerationService service;
  final String role;
  final ReportStatus status;
  final ReportTargetType? targetFilter;
  final ReportReason? reasonFilter;
  final int limit;
  final String? selectedId;
  final ValueChanged<ReportStatus> onStatus;
  final ValueChanged<ReportTargetType?> onTargetFilter;
  final ValueChanged<ReportReason?> onReasonFilter;
  final ValueChanged<String> onSelect;
  final VoidCallback onLoadMore;
  final VoidCallback onAccessExpired;

  @override
  Widget build(BuildContext context) {
    // Every filter is a server-side clause. The key ties this
    // StreamBuilder to the EXACT active query, so when a filter changes
    // Flutter tears down the old subscription and its state — a late
    // snapshot from the previous query cannot repaint the new queue.
    final queryKey = '${status.name}'
        '|${targetFilter?.name ?? '*'}'
        '|${reasonFilter?.name ?? '*'}'
        '|$limit';

    return StreamBuilder<List<ModerationReport>>(
      key: ValueKey(queryKey),
      stream: service.watchQueue(
        status: status,
        targetType: targetFilter,
        reason: reasonFilter,
        limit: limit,
      ),
      builder: (context, snapshot) {
        final reports = snapshot.data ?? const <ModerationReport>[];
        final selected = reports.where((r) => r.id == selectedId).firstOrNull;

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(role: role),
              const SizedBox(height: 16),
              _Filters(
                status: status,
                targetFilter: targetFilter,
                reasonFilter: reasonFilter,
                onStatus: onStatus,
                onTargetFilter: onTargetFilter,
                onReasonFilter: onReasonFilter,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final queue = _Queue(
                      snapshot: snapshot,
                      reports: reports,
                      limit: limit,
                      selectedId: selectedId,
                      onSelect: onSelect,
                      onLoadMore: onLoadMore,
                    );

                    // Split where there is room; otherwise the detail
                    // takes over the same pane — still one shell, still
                    // no nested route stack.
                    if (constraints.maxWidth < 900) {
                      return selected == null
                          ? queue
                          : _Detail(
                              key: ValueKey(selected.id),
                              report: selected,
                              service: service,
                              role: role,
                              onAccessExpired: onAccessExpired,
                              onBack: () => onSelect(''),
                            );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 380, child: queue),
                        const SizedBox(width: 16),
                        Expanded(
                          child: selected == null
                              ? const _NothingSelected()
                              : _Detail(
                                  key: ValueKey(selected.id),
                                  report: selected,
                                  service: service,
                                  role: role,
                                  onAccessExpired: onAccessExpired,
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.shield_rounded, size: 20, color: Color(0xFFD3A5FF)),
        const SizedBox(width: 10),
        const Text(
          'Moderation',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -.3,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: AppColors.primary.withValues(alpha: .16),
            border: Border.all(color: AppColors.primary.withValues(alpha: .4)),
          ),
          child: Text(
            role,
            style: const TextStyle(
              color: Color(0xFFD3A5FF),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.status,
    required this.targetFilter,
    required this.reasonFilter,
    required this.onStatus,
    required this.onTargetFilter,
    required this.onReasonFilter,
  });

  final ReportStatus status;
  final ReportTargetType? targetFilter;
  final ReportReason? reasonFilter;
  final ValueChanged<ReportStatus> onStatus;
  final ValueChanged<ReportTargetType?> onTargetFilter;
  final ValueChanged<ReportReason?> onReasonFilter;

  static String statusLabel(ReportStatus status) => switch (status) {
    ReportStatus.open => 'Open',
    ReportStatus.inReview => 'In review',
    ReportStatus.resolved => 'Resolved',
    ReportStatus.dismissed => 'Dismissed',
  };

  /// The row's descriptive label.
  static String targetLabel(ReportTargetType type) => switch (type) {
    ReportTargetType.globalMessage => 'Global message',
    ReportTargetType.user => 'Account',
  };

  /// The filter pill's label — plural and shorter, so a filter is never
  /// mistaken for a row at a glance.
  static String targetFilterLabel(ReportTargetType type) => switch (type) {
    ReportTargetType.globalMessage => 'Messages',
    ReportTargetType.user => 'Accounts',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final value in ReportStatus.values)
              _FilterPill(
                label: statusLabel(value),
                selected: value == status,
                onTap: () => onStatus(value),
              ),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _FilterPill(
              label: 'All targets',
              selected: targetFilter == null,
              subtle: true,
              onTap: () => onTargetFilter(null),
            ),
            for (final value in ReportTargetType.values)
              _FilterPill(
                label: targetFilterLabel(value),
                selected: targetFilter == value,
                subtle: true,
                onTap: () => onTargetFilter(value),
              ),
            const SizedBox(width: 6),
            _FilterPill(
              label: 'All reasons',
              selected: reasonFilter == null,
              subtle: true,
              onTap: () => onReasonFilter(null),
            ),
            for (final value in ReportReason.values)
              _FilterPill(
                label: reportReasonLabel(value),
                selected: reasonFilter == value,
                subtle: true,
                onTap: () => onReasonFilter(value),
              ),
          ],
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtle = false,
  });

  final String label;
  final bool selected;
  final bool subtle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            padding: EdgeInsets.symmetric(
              horizontal: subtle ? 11 : 14,
              vertical: subtle ? 6 : 8,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected
                  ? AppColors.primary.withValues(alpha: .22)
                  : Colors.white.withValues(alpha: .03),
              border: Border.all(
                color: selected
                    ? AppColors.primary.withValues(alpha: .55)
                    : const Color(0xFF2E2140),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFB3A8C4),
                fontSize: subtle ? 11 : 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Queue extends StatelessWidget {
  const _Queue({
    required this.snapshot,
    required this.reports,
    required this.limit,
    required this.selectedId,
    required this.onSelect,
    required this.onLoadMore,
  });

  final AsyncSnapshot<List<ModerationReport>> snapshot;
  final List<ModerationReport> reports;
  final int limit;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (snapshot.hasError) {
      final denied = snapshot.error.toString().toLowerCase().contains(
        'permission',
      );
      return _QueueState(
        icon: denied ? Icons.lock_outline_rounded : Icons.error_outline_rounded,
        text: denied
            ? 'Your moderator access has been removed.'
            : 'The queue could not be loaded. Check your connection.',
      );
    }
    if (!snapshot.hasData) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    if (reports.isEmpty) {
      return const _QueueState(
        icon: Icons.inbox_outlined,
        text: 'Nothing here. Reports appear as the community files them.',
      );
    }

    // A full page back means there is very likely more behind it. The
    // page is the SERVER's filtered result, so this is a truthful
    // statement about the whole matching set, not about one slice of a
    // broader query.
    final hasMore = reports.length >= limit;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF120C1D).withValues(alpha: .7),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: reports.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == reports.length) {
            return Center(
              child: TextButton(
                onPressed: onLoadMore,
                child: const Text(
                  'Load more',
                  style: TextStyle(
                    color: Color(0xFFD3A5FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }
          final report = reports[index];
          return _QueueRow(
            key: ValueKey(report.id),
            report: report,
            selected: report.id == selectedId,
            onTap: () => onSelect(report.id),
          );
        },
      ),
    );
  }
}

class _QueueRow extends StatefulWidget {
  const _QueueRow({
    required this.report,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final ModerationReport report;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends State<_QueueRow> {
  bool _hover = false;

  static String age(DateTime? at) {
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final reason = report.reason;

    return Semantics(
      button: true,
      selected: widget.selected,
      label:
          '${reason == null ? 'Report' : reportReasonLabel(reason)}, '
          '${_Filters.statusLabel(report.status)}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: widget.selected
                  ? AppColors.primary.withValues(alpha: .16)
                  : _hover
                  ? Colors.white.withValues(alpha: .04)
                  : Colors.transparent,
              border: Border.all(
                color: widget.selected
                    ? AppColors.primary.withValues(alpha: .5)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        reason == null ? 'Report' : reportReasonLabel(reason),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      age(report.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF7E7895),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  report.targetType == null
                      ? report.targetId
                      : _Filters.targetLabel(report.targetType!),
                  style: const TextStyle(
                    color: Color(0xFF9A90AC),
                    fontSize: 11.5,
                  ),
                ),
                if (report.note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    report.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB3A8C4),
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Row(
                  children: [
                    _StatusChip(status: report.status),
                    if (report.assignedTo != null) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.person_pin_rounded,
                        size: 12,
                        color: Color(0xFF7E7895),
                      ),
                    ],
                    if (report.contentRemoved) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.block_rounded,
                        size: 12,
                        color: Color(0xFFFF7A93),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ReportStatus.open => const Color(0xFFFFB547),
      ReportStatus.inReview => const Color(0xFF5CE1E6),
      ReportStatus.resolved => const Color(0xFF35D07F),
      ReportStatus.dismissed => const Color(0xFF7E7895),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: color.withValues(alpha: .14),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Text(
        _Filters.statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _QueueState extends StatelessWidget {
  const _QueueState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: const Color(0xFF564C63)),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF9A90AC),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: .015),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: const _QueueState(
        icon: Icons.touch_app_outlined,
        text: 'Select a report to review it.',
      ),
    );
  }
}

// ------------------------------------------------------------ detail

class _Detail extends StatefulWidget {
  const _Detail({
    required this.report,
    required this.service,
    required this.role,
    required this.onAccessExpired,
    this.onBack,
    super.key,
  });

  final ModerationReport report;
  final ModerationService service;
  final String role;
  final VoidCallback onAccessExpired;
  final VoidCallback? onBack;

  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  bool _busy = false;
  String? _error;
  String? _success;

  /// Held for the lifetime of ONE user action, so a retry after a
  /// failure reuses it and the server treats it as the same request
  /// instead of applying the action twice.
  String? _requestId;

  ReportResolution _resolution = ReportResolution.noActionNeeded;
  final TextEditingController _note = TextEditingController();

  /// Bumped only after the SERVER confirms an action, which makes the
  /// timeline reload from the first page. Nothing is inserted
  /// optimistically, so a confirmed event appears exactly once.
  int _auditRefresh = 0;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<ModerationResult> Function(String requestId) action, {
    String? confirmTitle,
    String? confirmBody,
  }) async {
    if (_busy) return;

    if (confirmTitle != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _ConfirmDialog(title: confirmTitle, body: confirmBody!),
      );
      if (confirmed != true || !mounted) return;
    }

    final requestId = _requestId ??= ModerationService.newRequestId();
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });

    try {
      final result = await action(requestId);
      if (!mounted) return;
      setState(() {
        // Cleared only on success, so the NEXT action gets a new key.
        _requestId = null;
        _auditRefresh++;
        _success = result.replayed
            ? 'Already applied.'
            : switch (result.status) {
                ReportStatus.inReview => 'Claimed. It is yours to review.',
                ReportStatus.open => 'Released back to the queue.',
                ReportStatus.resolved => result.contentRemoved
                    ? 'Message removed and report resolved.'
                    : 'Report resolved.',
                ReportStatus.dismissed => 'Report dismissed.',
              };
      });
    } on ModerationException catch (error) {
      if (!mounted) return;
      if (error.failure == ModerationFailure.accessExpired) {
        widget.onAccessExpired();
        return;
      }
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final service = widget.service;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF120C1D).withValues(alpha: .7),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        children: [
          Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  onPressed: widget.onBack,
                  tooltip: 'Back to the queue',
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  color: Colors.white,
                ),
              Expanded(
                child: Text(
                  report.reason == null
                      ? 'Report'
                      : reportReasonLabel(report.reason!),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusChip(status: report.status),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            report.id,
            style: const TextStyle(color: Color(0xFF7E7895), fontSize: 10.5),
          ),
          const SizedBox(height: 14),
          if (report.note.isNotEmpty) ...[
            _Field(label: 'Reporter note', value: report.note),
            const SizedBox(height: 12),
          ],
          _Field(
            label: 'Filed',
            value: report.createdAt?.toLocal().toString().split('.').first ?? '—',
          ),
          const SizedBox(height: 12),
          _ReportedAccount(userId: report.reportedUserId, service: service),
          if (report.targetType == ReportTargetType.globalMessage) ...[
            const SizedBox(height: 12),
            _TargetMessage(
              messageId: report.targetId,
              service: service,
            ),
          ],
          if (report.isClosed) ...[
            const SizedBox(height: 12),
            _Field(
              label: 'Outcome',
              value:
                  '${_Filters.statusLabel(report.status)}'
                  '${report.resolution == null ? '' : ' · ${resolutionLabel(report.resolution!)}'}'
                  '${report.contentRemoved ? ' · content removed' : ''}',
            ),
            if ((report.resolutionNote ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              _Field(label: 'Moderator note', value: report.resolutionNote!),
            ],
          ],
          const SizedBox(height: 18),
          ReportAuditTimeline(
            // Keyed on the report so selecting another one rebuilds the
            // widget outright rather than showing the previous report's
            // history under a new header.
            key: ValueKey('audit-${report.id}'),
            reportId: report.id,
            service: service,
            refreshToken: _auditRefresh,
            onAccessExpired: widget.onAccessExpired,
          ),
          const SizedBox(height: 18),
          if (!report.isClosed) _actions(report),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _Banner(
              icon: Icons.error_outline_rounded,
              color: const Color(0xFFFF7A93),
              text: _error!,
            ),
          ],
          if (_success != null) ...[
            const SizedBox(height: 12),
            _Banner(
              icon: Icons.check_circle_outline_rounded,
              color: const Color(0xFF35D07F),
              text: _success!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions(ModerationReport report) {
    final service = widget.service;
    final canRemove = report.targetType == ReportTargetType.globalMessage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (report.status == ReportStatus.open)
          _ActionButton(
            label: 'Claim and review',
            icon: Icons.how_to_reg_rounded,
            busy: _busy,
            onPressed: () => _run(
              (id) => service.claim(report.id, requestId: id),
            ),
          )
        else
          _ActionButton(
            label: 'Release claim',
            icon: Icons.undo_rounded,
            subtle: true,
            busy: _busy,
            onPressed: () => _run(
              (id) => service.release(report.id, requestId: id),
            ),
          ),
        const SizedBox(height: 14),
        const Text(
          'Resolution',
          style: TextStyle(
            color: Color(0xFF9A90AC),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final value in ReportResolution.values)
              _FilterPill(
                label: resolutionLabel(value),
                selected: _resolution == value,
                subtle: true,
                onTap: () => setState(() => _resolution = value),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _note,
          maxLength: ModerationService.maxModeratorNoteLength,
          maxLines: 2,
          style: const TextStyle(color: Colors.white, fontSize: 12.5),
          decoration: InputDecoration(
            counterText: '',
            hintText: 'Internal note (optional)',
            hintStyle: const TextStyle(
              color: Color(0xFF7E7895),
              fontSize: 12.5,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: .03),
            contentPadding: const EdgeInsets.all(11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2E2140)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2E2140)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ActionButton(
              label: 'Resolve',
              icon: Icons.check_rounded,
              busy: _busy,
              onPressed: () => _run(
                (id) => service.resolve(
                  report.id,
                  resolution: _resolution,
                  requestId: id,
                  note: _note.text,
                ),
              ),
            ),
            if (canRemove)
              _ActionButton(
                label: 'Remove message and resolve',
                icon: Icons.delete_outline_rounded,
                danger: true,
                busy: _busy,
                onPressed: () => _run(
                  (id) => service.removeContentAndResolve(
                    report.id,
                    requestId: id,
                    note: _note.text,
                  ),
                  confirmTitle: 'Remove this message?',
                  confirmBody:
                      'The message is hidden from the community and kept '
                      'as evidence. This is recorded against your account '
                      'in the moderation audit log.',
                ),
              ),
            _ActionButton(
              label: 'Dismiss',
              icon: Icons.close_rounded,
              subtle: true,
              busy: _busy,
              onPressed: () => _run(
                (id) => service.dismiss(
                  report.id,
                  resolution: _resolution,
                  requestId: id,
                  note: _note.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Dismissing requires a resolution reason — one is always '
          'selected above.',
          style: TextStyle(color: Color(0xFF7E7895), fontSize: 10.5),
        ),
        // Account actions are ADMIN-only server-side (setUserBan is
        // gated to admin/superAdmin). Rather than offering a button that
        // would be refused, moderators are told where it lives.
        if (widget.role == 'moderator') ...[
          const SizedBox(height: 12),
          _Banner(
            icon: Icons.info_outline_rounded,
            color: const Color(0xFF5CE1E6),
            text:
                'Banning or suspending an account is an administrator '
                'action. Resolve the content here and escalate the '
                'account to an admin.',
          ),
        ],
      ],
    );
  }
}

String resolutionLabel(ReportResolution resolution) => switch (resolution) {
  ReportResolution.contentRemoved => 'Content removed',
  ReportResolution.warningIssued => 'Warning issued',
  ReportResolution.noActionNeeded => 'No action needed',
  ReportResolution.notAViolation => 'Not a violation',
  ReportResolution.duplicate => 'Duplicate',
  ReportResolution.insufficientEvidence => 'Insufficient evidence',
};

/// The reported account's PUBLIC summary only. No email, no phone, no
/// provider data, no internal fields — this reads the same profile
/// document any signed-in member can already read, through the service
/// so the panel is testable and never reaches for a global singleton.
class _ReportedAccount extends StatelessWidget {
  const _ReportedAccount({required this.userId, required this.service});

  final String userId;
  final ModerationService service;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({String? displayName, String? photoUrl})?>(
      future: service.publicProfile(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data == null) {
          return const _Field(
            label: 'Reported account',
            value: 'This account no longer exists.',
          );
        }
        final profile = snapshot.data;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: .02),
            border: Border.all(color: const Color(0xFF241A33)),
          ),
          child: Row(
            children: [
              UserAvatar(
                radius: 18,
                photoUrl: profile?.photoUrl,
                displayName: profile?.displayName,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.displayName?.isNotEmpty == true
                          ? profile!.displayName!
                          : 'Loading…',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      userId,
                      style: const TextStyle(
                        color: Color(0xFF7E7895),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The reported Global message, including its removed state. Content is
/// blanked on soft delete, so a removed message shows AS removed — the
/// text itself survives in the audit record written at removal time.
class _TargetMessage extends StatelessWidget {
  const _TargetMessage({required this.messageId, required this.service});

  final String messageId;
  final ModerationService service;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GlobalMessage?>(
      future: service.targetMessage(messageId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Field(label: 'Reported message', value: 'Loading…');
        }
        final message = snapshot.data;
        if (message == null) {
          return const _Field(
            label: 'Reported message',
            value: 'This message is no longer available.',
          );
        }
        if (message.isDeleted) {
          return _Field(
            label: 'Reported message',
            value: message.removedByModerator
                ? 'Already removed by a moderator.'
                : 'Deleted by its author.',
          );
        }
        return _Field(
          label: 'Reported message',
          value: message.content,
          meta: message.sentAt?.toLocal().toString().split('.').first,
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.meta});

  final String label;
  final String value;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF9A90AC),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: const TextStyle(
            color: Color(0xFFCFC6DC),
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
        if (meta != null)
          Text(
            meta!,
            style: const TextStyle(color: Color(0xFF7E7895), fontSize: 10.5),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
    this.subtle = false,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback onPressed;
  final bool subtle;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final accent = danger
        ? const Color(0xFFFF7A93)
        : subtle
        ? const Color(0xFFB3A8C4)
        : const Color(0xFFD3A5FF);

    return Semantics(
      button: true,
      enabled: !busy,
      label: label,
      child: OutlinedButton.icon(
        // Disabled while a request is in flight, so a double click
        // cannot fire the action twice.
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: accent.withValues(alpha: busy ? .2 : .5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        ),
        icon: busy
            ? const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 16, color: accent),
        label: Text(
          label,
          style: TextStyle(
            color: busy ? const Color(0xFF564C63) : accent,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: .10),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFCFC6DC),
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF120C1D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF2E2140)),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Text(
        body,
        style: const TextStyle(
          color: Color(0xFF9A90AC),
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Color(0xFF9A90AC)),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFF335C),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          child: const Text(
            'Remove message',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
