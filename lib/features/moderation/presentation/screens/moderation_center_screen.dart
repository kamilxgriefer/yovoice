import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/features/messages/data/models/global_message.dart';
import 'package:yovoice/features/moderation/data/models/moderation_report.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_reason_labels.dart';
import 'package:yovoice/features/moderation/presentation/widgets/report_audit_timeline.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

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
/// Three intentional layouts share this one widget and all of its
/// state: a phone gets the single-column list→detail flow under a real
/// app bar (Back + Home), a wide tablet or desktop window gets the
/// master-detail split, and inside the desktop shell slot the screen
/// draws its own page header instead of an app bar because the shell
/// owns navigation.
class ModerationCenterScreen extends StatefulWidget {
  const ModerationCenterScreen({
    this.isRootTab = false,
    this.embedded = false,
    this.moderationService,
    super.key,
  });

  final bool isRootTab;

  /// Renders only the moderation workspace, without a nested Scaffold or
  /// navigation chrome. Staff Center uses this mode so Moderation behaves
  /// like every other section in its rail and tab strip.
  final bool embedded;
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

  /// Client-side narrowing of the LOADED page only (id, reason, note,
  /// target) — bounded and honest; server text search does not exist.
  String _searchQuery = '';

  /// Open / In-review totals from the server-side count aggregate.
  /// Null means "could not be counted" and the badge is simply omitted —
  /// never invented.
  final Map<ReportStatus, int?> _statusCounts = {};

  /// Bumping this key re-creates the workspace's StreamBuilder — the
  /// Refresh action and the error state's Retry both use it.
  int _refreshTick = 0;

  Future<void> _loadCounts() async {
    final service = _service;
    if (service == null) return;
    // Both aggregates in flight at once — they are independent server-side
    // counts, and waiting for one before asking for the other doubled the
    // time before the queue header had its numbers.
    const statuses = [ReportStatus.open, ReportStatus.inReview];
    final counts = await Future.wait(statuses.map(service.countByStatus));
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < statuses.length; i++) {
        _statusCounts[statuses[i]] = counts[i];
      }
    });
  }

  void _refresh() {
    setState(() {
      _refreshTick += 1;
      _limit = ModerationService.pageSize;
    });
    unawaited(_loadCounts());
  }

  /// The role as a PERSON reads it — internal claim vocabulary never
  /// reaches the interface.
  String _roleLabel(AppLocalizations copy) => switch (_role) {
    'moderator' => copy.text('Moderator', 'Moderator'),
    'superModerator' => copy.text('Super Moderator', 'Supermoderator'),
    'superAdmin' => copy.text('Admin', 'Administrator'),
    _ => copy.text('Staff', 'Zespół'),
  };

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
    // The staff check and the role read are independent (both read the
    // caller's own profile); running them together removes one full
    // Firestore round trip from the panel's first paint. The role is only
    // kept when the account is confirmed as active staff.
    final results = await Future.wait<Object>([
      service.isActiveStaff(),
      service.currentRole(),
    ]);
    final staff = results[0] as bool;
    final role = staff ? results[1] as String : 'user';
    if (!mounted) return;
    setState(() {
      _isStaff = staff;
      _role = role;
    });
    if (staff) unawaited(_loadCounts());
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
    final copy = AppLocalizations.of(context);
    // The desktop shell slot owns navigation and draws no app bar; a
    // pushed route (mobile, and any direct entry) carries a real app bar
    // with Back and Home so Moderation is never a dead end. This was the
    // mobile navigation bug: `isRootTab` existed but nothing consumed
    // it, and the screen had no app bar at all.
    final inShellSlot =
        widget.isRootTab && MediaQuery.sizeOf(context).width >= 980;

    final content = SafeArea(
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
          key: ValueKey('workspace-$_refreshTick'),
          service: _service!,
          role: _role,
          roleLabel: _roleLabel(copy),
          showHeader: inShellSlot,
          status: _status,
          targetFilter: _targetFilter,
          reasonFilter: _reasonFilter,
          searchQuery: _searchQuery,
          statusCounts: _statusCounts,
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
          onSearch: (query) => setState(() => _searchQuery = query),
          onRefresh: _refresh,
          onSelect: (id) => setState(() => _selectedId = id),
          onLoadMore: () =>
              setState(() => _limit += ModerationService.pageSize),
          onAccessExpired: _handleAccessExpired,
        ),
      },
    );

    if (widget.embedded) {
      return YoImmersiveDarkSurface(
        child: Material(color: AppImmersiveColors.background, child: content),
      );
    }

    final scaffold = Scaffold(
      backgroundColor: AppImmersiveColors.background,
      appBar: inShellSlot
          ? null
          : AppBar(
              backgroundColor: AppImmersiveColors.background,
              foregroundColor: Colors.white,
              centerTitle: false,
              titleSpacing: 0,
              leading: Navigator.of(context).canPop()
                  ? const BackButton()
                  : null,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.shield_rounded,
                    size: 18,
                    color: Color(0xFFD3A5FF),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      copy.text('Moderation', 'Moderacja'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (_isStaff == true) ...[
                    const SizedBox(width: 8),
                    _RoleBadge(label: _roleLabel(copy)),
                  ],
                ],
              ),
              actions: [
                IconButton(
                  tooltip: copy.text('Home', 'Strona główna'),
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  icon: const Icon(Icons.home_rounded),
                ),
              ],
            ),
      body: content,
    );
    return YoImmersiveDarkSurface(child: scaffold);
  }
}

/// The small, secondary effective-role badge — always the human
/// vocabulary, never an internal claim name.
class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: AppColors.primary.withValues(alpha: .14),
        border: Border.all(color: AppColors.primary.withValues(alpha: .35)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFD3A5FF),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
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
    final copy = AppLocalizations.of(context);
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
            Text(
              copy.text(
                'Moderation is staff only',
                'Moderacja jest dostępna tylko dla zespołu',
              ),
              semanticsLabel: copy.text(
                'Moderation is staff only',
                'Moderacja jest dostępna tylko dla zespołu',
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              copy.text(
                'This area is limited to accounts with a moderator role. '
                    'If your access changed while you were working, sign out '
                    'and back in to refresh it.',
                'Ten obszar jest dostępny wyłącznie dla kont z rolą '
                    'moderatora. Jeśli Twoje uprawnienia zmieniły się podczas '
                    'pracy, wyloguj się i zaloguj ponownie.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
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
    required this.roleLabel,
    required this.showHeader,
    required this.status,
    required this.targetFilter,
    required this.reasonFilter,
    required this.searchQuery,
    required this.statusCounts,
    required this.limit,
    required this.selectedId,
    required this.onStatus,
    required this.onTargetFilter,
    required this.onReasonFilter,
    required this.onSearch,
    required this.onRefresh,
    required this.onSelect,
    required this.onLoadMore,
    required this.onAccessExpired,
    super.key,
  });

  final ModerationService service;
  final String role;
  final String roleLabel;

  /// True in the desktop shell slot, where this widget draws its own
  /// page header (the pushed route's app bar covers it otherwise).
  final bool showHeader;
  final ReportStatus status;
  final ReportTargetType? targetFilter;
  final ReportReason? reasonFilter;
  final String searchQuery;
  final Map<ReportStatus, int?> statusCounts;
  final int limit;
  final String? selectedId;
  final ValueChanged<ReportStatus> onStatus;
  final ValueChanged<ReportTargetType?> onTargetFilter;
  final ValueChanged<ReportReason?> onReasonFilter;
  final ValueChanged<String> onSearch;
  final VoidCallback onRefresh;
  final ValueChanged<String> onSelect;
  final VoidCallback onLoadMore;
  final VoidCallback onAccessExpired;

  bool get _hasActiveFilters => targetFilter != null || reasonFilter != null;

  /// Client-side narrowing of the LOADED page only — bounded, and
  /// clearly scoped: it never claims to search the whole collection.
  List<ModerationReport> _searched(
    List<ModerationReport> reports,
    AppLocalizations copy,
  ) {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return reports;
    return [
      for (final report in reports)
        if (report.id.toLowerCase().contains(query) ||
            report.note.toLowerCase().contains(query) ||
            report.targetId.toLowerCase().contains(query) ||
            (report.reason != null &&
                reportReasonLabel(
                  report.reason!,
                  copy: copy,
                ).toLowerCase().contains(query)))
          report,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    // Every filter is a server-side clause. The key ties this
    // StreamBuilder to the EXACT active query, so when a filter changes
    // Flutter tears down the old subscription and its state — a late
    // snapshot from the previous query cannot repaint the new queue.
    final queryKey =
        '${status.name}'
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
        final loaded = snapshot.data ?? const <ModerationReport>[];
        final reports = _searched(loaded, copy);
        final selected = reports.where((r) => r.id == selectedId).firstOrNull;

        return LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 700;
            final split = constraints.maxWidth >= 900;

            // Very large screens keep a sane line length instead of a
            // panoramic wall.
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showHeader) ...[
                  _WorkspaceHeader(roleLabel: roleLabel, onRefresh: onRefresh),
                  const SizedBox(height: 14),
                ],
                _SummaryStrip(
                  narrow: narrow,
                  statusCounts: statusCounts,
                  loadedCount: loaded.length,
                  status: status,
                ),
                const SizedBox(height: 12),
                _StatusTabs(
                  status: status,
                  statusCounts: statusCounts,
                  onStatus: onStatus,
                ),
                const SizedBox(height: 10),
                _Toolbar(
                  narrow: narrow,
                  searchQuery: searchQuery,
                  activeFilterCount:
                      (targetFilter == null ? 0 : 1) +
                      (reasonFilter == null ? 0 : 1),
                  onSearch: onSearch,
                  onRefresh: onRefresh,
                  onOpenFilters: () => _openFilters(context, narrow),
                ),
                if (_hasActiveFilters) ...[
                  const SizedBox(height: 8),
                  _ActiveFilterChips(
                    targetFilter: targetFilter,
                    reasonFilter: reasonFilter,
                    onTargetFilter: onTargetFilter,
                    onReasonFilter: onReasonFilter,
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: _content(
                    snapshot: snapshot,
                    reports: reports,
                    loadedCount: loaded.length,
                    selected: selected,
                    split: split,
                  ),
                ),
              ],
            );

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    narrow ? 14 : 24,
                    narrow ? 10 : 18,
                    narrow ? 14 : 24,
                    narrow ? 10 : 20,
                  ),
                  child: content,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _content({
    required AsyncSnapshot<List<ModerationReport>> snapshot,
    required List<ModerationReport> reports,
    required int loadedCount,
    required ModerationReport? selected,
    required bool split,
  }) {
    final queue = _Queue(
      snapshot: snapshot,
      reports: reports,
      loadedCount: loadedCount,
      searchActive: searchQuery.trim().isNotEmpty,
      filtersActive: _hasActiveFilters,
      limit: limit,
      selectedId: selectedId,
      onSelect: onSelect,
      onLoadMore: onLoadMore,
      onRetry: onRefresh,
      onClearFilters: () {
        onTargetFilter(null);
        onReasonFilter(null);
        onSearch('');
      },
    );

    // Below the split threshold the detail takes over the same pane —
    // still one shell, still no nested route stack, with an explicit
    // way back to the queue.
    if (!split) {
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
        SizedBox(width: 400, child: queue),
        Container(
          width: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: const Color(0xFF241A33),
        ),
        Expanded(
          child: selected != null
              ? _Detail(
                  key: ValueKey(selected.id),
                  report: selected,
                  service: service,
                  role: role,
                  onAccessExpired: onAccessExpired,
                )
              // "Select a report" only makes sense when there is
              // something to select; an empty queue keeps its one
              // coherent empty state and this pane stays quiet.
              : reports.isEmpty
              ? const SizedBox.shrink()
              : const _NothingSelected(),
        ),
      ],
    );
  }

  Future<void> _openFilters(BuildContext context, bool narrow) async {
    final result = narrow
        ? await showModalBottomSheet<(ReportTargetType?, ReportReason?)?>(
            context: context,
            useSafeArea: true,
            isScrollControlled: true,
            backgroundColor: const Color(0xFF151020),
            showDragHandle: false,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (_) => _FilterPanel(
              targetFilter: targetFilter,
              reasonFilter: reasonFilter,
              asSheet: true,
            ),
          )
        : await showDialog<(ReportTargetType?, ReportReason?)?>(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: const Color(0xFF151020),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _FilterPanel(
                  targetFilter: targetFilter,
                  reasonFilter: reasonFilter,
                  asSheet: false,
                ),
              ),
            ),
          );
    if (result == null) return;
    onTargetFilter(result.$1);
    onReasonFilter(result.$2);
  }
}

/// The desktop page header: identity on the left, actions on the right,
/// context above — the persistent sidebar already owns navigation, so
/// there is deliberately no Back or Home here.
class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.roleLabel, required this.onRefresh});

  final String roleLabel;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          copy.text(
            'Staff tools / Moderation',
            'Narzędzia zespołu / Moderacja',
          ),
          style: const TextStyle(
            color: Color(0xFF7E7895),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .4,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(
              Icons.shield_rounded,
              size: 20,
              color: Color(0xFFD3A5FF),
            ),
            const SizedBox(width: 10),
            Text(
              copy.text('Moderation', 'Moderacja'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -.3,
              ),
            ),
            const SizedBox(width: 10),
            _RoleBadge(label: roleLabel),
            const Spacer(),
            IconButton(
              tooltip: copy.text('Refresh', 'Odśwież'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFFA69CAF)),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          copy.text(
            'Review community reports and take action.',
            'Weryfikuj zgłoszenia społeczności i podejmuj działania.',
          ),
          style: const TextStyle(color: Color(0xFFA69CAF), fontSize: 12.5),
        ),
      ],
    );
  }
}

/// Compact, truthful numbers: server-side aggregates where they exist,
/// the loaded-page count for the current view, nothing invented. On a
/// phone it is a horizontally scrollable strip that stays out of the
/// way.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.narrow,
    required this.statusCounts,
    required this.loadedCount,
    required this.status,
  });

  final bool narrow;
  final Map<ReportStatus, int?> statusCounts;
  final int loadedCount;
  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final cards = <Widget>[
      if (statusCounts[ReportStatus.open] != null)
        _SummaryCard(
          label: _Filters.statusLabel(ReportStatus.open, copy: copy),
          value: '${statusCounts[ReportStatus.open]}',
          color: const Color(0xFFFFB547),
        ),
      if (statusCounts[ReportStatus.inReview] != null)
        _SummaryCard(
          label: _Filters.statusLabel(ReportStatus.inReview, copy: copy),
          value: '${statusCounts[ReportStatus.inReview]}',
          color: const Color(0xFF8D5BFF),
        ),
      _SummaryCard(
        label: copy.text(
          'Loaded · ${_Filters.statusLabel(status)}',
          'Wczytane · ${_Filters.statusLabel(status, copy: copy)}',
        ),
        value: '$loadedCount',
        color: const Color(0xFF35D07F),
      ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final card in cards) ...[card, const SizedBox(width: 8)],
      ],
    );
    if (!narrow) return row;
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: row);
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF120C1D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFA69CAF),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// One selected status, always. A segmented row on desktop; the same
/// row scrolls horizontally on a phone instead of wrapping into a wall.
class _StatusTabs extends StatelessWidget {
  const _StatusTabs({
    required this.status,
    required this.statusCounts,
    required this.onStatus,
  });

  final ReportStatus status;
  final Map<ReportStatus, int?> statusCounts;
  final ValueChanged<ReportStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final tabs = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF120C1D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in ReportStatus.values)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: _StatusTab(
                label: _Filters.statusLabel(value, copy: copy),
                count: statusCounts[value],
                selected: status == value,
                onTap: () => onStatus(value),
              ),
            ),
        ],
      ),
    );
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs);
  }
}

class _StatusTab extends StatelessWidget {
  const _StatusTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: .28)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFFA69CAF),
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF241A33),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Color(0xFFD3A5FF),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Search, the filter door, and refresh — the wall of permanent pills is
/// gone; active filters render as removable chips underneath.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.narrow,
    required this.searchQuery,
    required this.activeFilterCount,
    required this.onSearch,
    required this.onRefresh,
    required this.onOpenFilters,
  });

  final bool narrow;
  final String searchQuery;
  final int activeFilterCount;
  final ValueChanged<String> onSearch;
  final VoidCallback onRefresh;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              onChanged: onSearch,
              controller: null,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: copy.text(
                  'Search loaded reports…',
                  'Szukaj we wczytanych zgłoszeniach…',
                ),
                hintStyle: const TextStyle(
                  color: Color(0xFF7E7895),
                  fontSize: 12.5,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Color(0xFFA69CAF),
                ),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF120C1D),
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(color: Color(0xFF241A33)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(color: Color(0xFF241A33)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onOpenFilters,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF241A33)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
          icon: const Icon(Icons.tune_rounded, size: 16),
          label: Text(
            activeFilterCount == 0
                ? copy.text('Filters', 'Filtry')
                : copy.text(
                    'Filters · $activeFilterCount',
                    'Filtry · $activeFilterCount',
                  ),
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        if (narrow) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: copy.text('Refresh', 'Odśwież'),
            onPressed: onRefresh,
            icon: const Icon(
              Icons.refresh_rounded,
              color: Color(0xFFA69CAF),
              size: 20,
            ),
          ),
        ],
      ],
    );
  }
}

class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({
    required this.targetFilter,
    required this.reasonFilter,
    required this.onTargetFilter,
    required this.onReasonFilter,
  });

  final ReportTargetType? targetFilter;
  final ReportReason? reasonFilter;
  final ValueChanged<ReportTargetType?> onTargetFilter;
  final ValueChanged<ReportReason?> onReasonFilter;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (targetFilter != null)
          InputChip(
            label: Text(_Filters.targetLabel(targetFilter!, copy: copy)),
            labelStyle: const TextStyle(color: Colors.white, fontSize: 11.5),
            deleteIconColor: const Color(0xFFA69CAF),
            backgroundColor: AppColors.primary.withValues(alpha: .2),
            side: BorderSide(color: AppColors.primary.withValues(alpha: .4)),
            onDeleted: () => onTargetFilter(null),
          ),
        if (reasonFilter != null)
          InputChip(
            label: Text(reportReasonLabel(reasonFilter!, copy: copy)),
            labelStyle: const TextStyle(color: Colors.white, fontSize: 11.5),
            deleteIconColor: const Color(0xFFA69CAF),
            backgroundColor: AppColors.primary.withValues(alpha: .2),
            side: BorderSide(color: AppColors.primary.withValues(alpha: .4)),
            onDeleted: () => onReasonFilter(null),
          ),
      ],
    );
  }
}

/// The filter editor — a bottom sheet on phones, a compact dialog on
/// desktop. Draft state lives HERE; nothing applies until Apply.
class _FilterPanel extends StatefulWidget {
  const _FilterPanel({
    required this.targetFilter,
    required this.reasonFilter,
    required this.asSheet,
  });

  final ReportTargetType? targetFilter;
  final ReportReason? reasonFilter;
  final bool asSheet;

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  late ReportTargetType? _target = widget.targetFilter;
  late ReportReason? _reason = widget.reasonFilter;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                copy.text('Filter reports', 'Filtruj zgłoszenia'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _target = null;
                _reason = null;
              }),
              child: Text(copy.text('Clear all', 'Wyczyść wszystko')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          copy.text('TARGET TYPE', 'TYP CELU'),
          style: const TextStyle(
            color: Color(0xFF7E7895),
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _draftChip(
              copy.text('All targets', 'Wszystkie cele'),
              _target == null,
              () {
                setState(() => _target = null);
              },
            ),
            for (final value in ReportTargetType.values)
              _draftChip(
                _Filters.targetLabel(value, copy: copy),
                _target == value,
                () {
                  setState(() => _target = value);
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          copy.text('REASON', 'POWÓD'),
          style: const TextStyle(
            color: Color(0xFF7E7895),
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _draftChip(
              copy.text('All reasons', 'Wszystkie powody'),
              _reason == null,
              () {
                setState(() => _reason = null);
              },
            ),
            for (final value in ReportReason.values)
              _draftChip(
                reportReasonLabel(value, copy: copy),
                _reason == value,
                () {
                  setState(() => _reason = value);
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            const SizedBox(width: 6),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.of(context).pop((_target, _reason)),
              child: Text(copy.text('Apply filters', 'Zastosuj filtry')),
            ),
          ],
        ),
      ],
    );

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.asSheet)
            YoModalSheetChrome(
              sheetLabel: copy.text('report filters', 'filtry zgłoszeń'),
              surfaceColor: Color(0xFF151020),
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                18,
                widget.asSheet ? 2 : 18,
                18,
                widget.asSheet
                    ? 14 + MediaQuery.viewInsetsOf(context).bottom
                    : 18,
              ),
              child: body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _draftChip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFFA69CAF),
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
      selectedColor: AppColors.primary.withValues(alpha: .35),
      backgroundColor: const Color(0xFF120C1D),
      side: const BorderSide(color: Color(0xFF241A33)),
    );
  }
}

/// Label helpers shared by the tabs, chips, queue rows and the detail
/// outcome line.
abstract final class _Filters {
  static String statusLabel(ReportStatus status, {AppLocalizations? copy}) {
    final english = switch (status) {
      ReportStatus.open => 'Open',
      ReportStatus.inReview => 'In review',
      ReportStatus.resolved => 'Resolved',
      ReportStatus.dismissed => 'Dismissed',
    };
    final polish = switch (status) {
      ReportStatus.open => 'Otwarte',
      ReportStatus.inReview => 'W trakcie weryfikacji',
      ReportStatus.resolved => 'Rozstrzygnięte',
      ReportStatus.dismissed => 'Odrzucone',
    };
    return copy?.text(english, polish) ?? english;
  }

  static String targetLabel(ReportTargetType target, {AppLocalizations? copy}) {
    final english = switch (target) {
      ReportTargetType.globalMessage => 'Message',
      ReportTargetType.reel => 'Reel',
      ReportTargetType.voiceMoment => 'Voice Moment',
      ReportTargetType.voiceMomentComment => 'Voice Moment comment',
      ReportTargetType.user => 'Account',
    };
    final polish = switch (target) {
      ReportTargetType.globalMessage => 'Wiadomość',
      ReportTargetType.reel => 'Rolka',
      ReportTargetType.voiceMoment => 'Voice Moment',
      ReportTargetType.voiceMomentComment => 'Komentarz Voice Momentu',
      ReportTargetType.user => 'Konto',
    };
    return copy?.text(english, polish) ?? english;
  }
}

class _Queue extends StatelessWidget {
  const _Queue({
    required this.snapshot,
    required this.reports,
    required this.loadedCount,
    required this.searchActive,
    required this.filtersActive,
    required this.limit,
    required this.selectedId,
    required this.onSelect,
    required this.onLoadMore,
    required this.onRetry,
    required this.onClearFilters,
  });

  final AsyncSnapshot<List<ModerationReport>> snapshot;

  /// After the client-side search narrowing.
  final List<ModerationReport> reports;

  /// What the server actually returned, before search narrowing —
  /// distinguishes "queue empty" from "search/filters matched nothing".
  final int loadedCount;
  final bool searchActive;
  final bool filtersActive;
  final int limit;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    if (snapshot.hasError) {
      final denied = snapshot.error.toString().toLowerCase().contains(
        'permission',
      );
      return _QueueState(
        icon: denied ? Icons.lock_outline_rounded : Icons.error_outline_rounded,
        title: denied
            ? copy.text('Access removed', 'Dostęp odebrany')
            : copy.text(
                'Reports could not be loaded',
                'Nie udało się wczytać zgłoszeń',
              ),
        text: denied
            ? copy.text(
                'Your moderator access has been removed.',
                'Twoje uprawnienia moderatorskie zostały odebrane.',
              )
            : copy.text(
                'Check your connection and try again.',
                'Sprawdź połączenie z internetem i spróbuj ponownie.',
              ),
        actionLabel: denied ? null : copy.text('Retry', 'Spróbuj ponownie'),
        onAction: denied ? null : onRetry,
      );
    }
    if (!snapshot.hasData) {
      // A restrained skeleton: three quiet card shapes, the same height
      // real rows take, so the finished list does not shift the layout.
      return ListView(
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              height: 76,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFF120C1D).withValues(alpha: .6),
                border: Border.all(color: const Color(0xFF1C1428)),
              ),
            ),
        ],
      );
    }
    if (reports.isEmpty) {
      // ONE coherent empty state, chosen by cause.
      if (loadedCount > 0 || searchActive || filtersActive) {
        return _QueueState(
          icon: Icons.filter_alt_off_rounded,
          title: copy.text('No matching reports', 'Brak pasujących zgłoszeń'),
          text: copy.text(
            'Try changing or clearing your filters.',
            'Zmień lub wyczyść filtry.',
          ),
          actionLabel: copy.text('Clear filters', 'Wyczyść filtry'),
          onAction: onClearFilters,
        );
      }
      return _QueueState(
        icon: Icons.inbox_outlined,
        title: copy.text('No reports here', 'Brak zgłoszeń'),
        text: copy.text(
          'New community reports will appear here.',
          'Nowe zgłoszenia społeczności pojawią się tutaj.',
        ),
      );
    }

    // A full page back means there is very likely more behind it. The
    // page is the SERVER's filtered result, so this is a truthful
    // statement about the whole matching set, not about one slice of a
    // broader query.
    final hasMore = loadedCount >= limit;

    return ListView.builder(
      itemCount: reports.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == reports.length) {
          return Center(
            child: TextButton(
              onPressed: onLoadMore,
              child: Text(
                copy.text('Load more', 'Wczytaj więcej'),
                style: const TextStyle(
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
  bool _focused = false;
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'Moderation report queue row',
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  static String age(DateTime? at, {AppLocalizations? copy}) {
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 60) {
      final minutes = diff.inMinutes.clamp(1, 59);
      return copy?.isPolish == true ? '$minutes min' : '${minutes}m';
    }
    if (diff.inHours < 24) {
      return copy?.isPolish == true
          ? '${diff.inHours} godz.'
          : '${diff.inHours}h';
    }
    if (copy?.isPolish == true) {
      return diff.inDays == 1 ? '1 dzień' : '${diff.inDays} dni';
    }
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final report = widget.report;
    final reason = report.reason;

    return Semantics(
      button: true,
      selected: widget.selected,
      label:
          '${reason == null ? copy.text('Report', 'Zgłoszenie') : reportReasonLabel(reason, copy: copy)}, '
          '${_Filters.statusLabel(report.status, copy: copy)}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            focusNode: _focusNode,
            onTap: widget.onTap,
            onFocusChange: (value) => setState(() => _focused = value),
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: widget.selected
                    ? AppColors.primary.withValues(alpha: .16)
                    : _hover || _focused
                    ? Colors.white.withValues(alpha: .04)
                    : Colors.transparent,
                border: Border.all(
                  color: widget.selected || _focused
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
                          reason == null
                              ? copy.text('Report', 'Zgłoszenie')
                              : reportReasonLabel(reason, copy: copy),
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
                        age(report.createdAt, copy: copy),
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
                        : _Filters.targetLabel(report.targetType!, copy: copy),
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
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
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
        _Filters.statusLabel(status, copy: copy),
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
  const _QueueState({
    required this.icon,
    required this.title,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

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
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF9A90AC),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF34263F)),
                ),
                child: Text(actionLabel!),
              ),
            ],
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
    final copy = AppLocalizations.of(context);
    return _QueueState(
      icon: Icons.touch_app_outlined,
      title: copy.text('Select a report', 'Wybierz zgłoszenie'),
      text: copy.text(
        'Choose a report from the queue to review its details.',
        'Wybierz zgłoszenie z kolejki, aby sprawdzić jego szczegóły.',
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
    String? confirmActionLabel,
  }) async {
    if (_busy) return;
    final copy = AppLocalizations.of(context);

    if (confirmTitle != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _ConfirmDialog(
          title: confirmTitle,
          body: confirmBody!,
          actionLabel: confirmActionLabel,
        ),
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
            ? copy.text('Already applied.', 'Ta czynność została już wykonana.')
            : switch (result.status) {
                ReportStatus.inReview => copy.text(
                  'Claimed. It is yours to review.',
                  'Zgłoszenie przejęte. Możesz rozpocząć weryfikację.',
                ),
                ReportStatus.open => copy.text(
                  'Released back to the queue.',
                  'Zgłoszenie wróciło do kolejki.',
                ),
                ReportStatus.resolved =>
                  result.contentRemoved
                      ? switch (widget.report.targetType) {
                          ReportTargetType.reel => copy.text(
                            'Reel hidden and report resolved.',
                            'Rolka ukryta, a zgłoszenie rozstrzygnięte.',
                          ),
                          ReportTargetType.voiceMoment => copy.text(
                            'Voice Moment removed and report resolved.',
                            'Voice Moment usunięty, a zgłoszenie rozstrzygnięte.',
                          ),
                          ReportTargetType.voiceMomentComment => copy.text(
                            'Voice Moment comment removed and report resolved.',
                            'Komentarz Voice Momentu usunięty, a zgłoszenie rozstrzygnięte.',
                          ),
                          _ => copy.text(
                            'Message removed and report resolved.',
                            'Wiadomość usunięta, a zgłoszenie rozstrzygnięte.',
                          ),
                        }
                      : copy.text(
                          'Report resolved.',
                          'Zgłoszenie rozstrzygnięte.',
                        ),
                ReportStatus.dismissed => copy.text(
                  'Report dismissed.',
                  'Zgłoszenie odrzucone.',
                ),
              };
      });
    } on ModerationException catch (error) {
      if (!mounted) return;
      if (error.failure == ModerationFailure.accessExpired) {
        widget.onAccessExpired();
        return;
      }
      setState(
        () => _error = copy.text(
          _englishModerationFailure(error.failure),
          _polishModerationFailure(error.failure),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final report = widget.report;
    final service = widget.service;

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 18),
      children: [
        Row(
          children: [
            if (widget.onBack != null)
              IconButton(
                onPressed: widget.onBack,
                tooltip: copy.text('Back to the queue', 'Wróć do kolejki'),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                color: Colors.white,
              ),
            Expanded(
              child: Text(
                report.reason == null
                    ? copy.text('Report', 'Zgłoszenie')
                    : reportReasonLabel(report.reason!, copy: copy),
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
          _Field(
            label: copy.text('Reporter note', 'Notatka osoby zgłaszającej'),
            value: report.note,
          ),
          const SizedBox(height: 12),
        ],
        _Field(
          label: copy.text('Filed', 'Zgłoszono'),
          value: report.createdAt?.toLocal().toString().split('.').first ?? '—',
        ),
        const SizedBox(height: 12),
        if (report.targetType == ReportTargetType.voiceMoment ||
            report.targetType == ReportTargetType.voiceMomentComment) ...[
          _TargetReference(report: report),
          const SizedBox(height: 12),
        ],
        if (report.reportedUserId.isNotEmpty)
          _ReportedAccount(userId: report.reportedUserId, service: service)
        else
          _Field(
            label: copy.text('Reported account', 'Zgłoszone konto'),
            value: copy.text(
              'Author identity was not retained in this earlier report.',
              'To wcześniejsze zgłoszenie nie zawiera identyfikatora autora.',
            ),
          ),
        if (report.targetType == ReportTargetType.globalMessage) ...[
          const SizedBox(height: 12),
          _TargetMessage(messageId: report.targetId, service: service),
        ],
        if (report.isClosed) ...[
          const SizedBox(height: 12),
          _Field(
            label: copy.text('Outcome', 'Wynik'),
            value:
                '${_Filters.statusLabel(report.status, copy: copy)}'
                '${report.resolution == null ? '' : ' · ${resolutionLabel(report.resolution!, copy: copy)}'}'
                '${report.contentRemoved ? ' · ${copy.text('content removed', 'treść usunięta')}' : ''}',
          ),
          if ((report.resolutionNote ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            _Field(
              label: copy.text('Moderator note', 'Notatka moderatora'),
              value: report.resolutionNote!,
            ),
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
    );
  }

  Widget _actions(ModerationReport report) {
    final copy = AppLocalizations.of(context);
    final service = widget.service;
    final isReel = report.targetType == ReportTargetType.reel;
    final isVoiceMoment = report.targetType == ReportTargetType.voiceMoment;
    final isVoiceComment =
        report.targetType == ReportTargetType.voiceMomentComment;
    final canRemove =
        report.targetType == ReportTargetType.globalMessage ||
        isReel ||
        isVoiceMoment ||
        isVoiceComment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (report.status == ReportStatus.open)
          _ActionButton(
            label: copy.text('Claim and review', 'Przejmij i zweryfikuj'),
            icon: Icons.how_to_reg_rounded,
            busy: _busy,
            onPressed: () =>
                _run((id) => service.claim(report.id, requestId: id)),
          )
        else
          _ActionButton(
            label: copy.text('Release claim', 'Zwolnij przypisanie'),
            icon: Icons.undo_rounded,
            subtle: true,
            busy: _busy,
            onPressed: () =>
                _run((id) => service.release(report.id, requestId: id)),
          ),
        const SizedBox(height: 14),
        Text(
          copy.text('Resolution', 'Rozstrzygnięcie'),
          style: const TextStyle(
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
              ChoiceChip(
                label: Text(resolutionLabel(value, copy: copy)),
                selected: _resolution == value,
                onSelected: (_) => setState(() => _resolution = value),
                labelStyle: TextStyle(
                  color: _resolution == value
                      ? Colors.white
                      : const Color(0xFFA69CAF),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
                selectedColor: AppColors.primary.withValues(alpha: .35),
                backgroundColor: const Color(0xFF120C1D),
                side: const BorderSide(color: Color(0xFF241A33)),
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
            hintText: copy.text(
              'Internal note (optional)',
              'Notatka wewnętrzna (opcjonalnie)',
            ),
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
              label: copy.text('Resolve', 'Rozstrzygnij'),
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
                label: switch (report.targetType) {
                  ReportTargetType.reel => copy.text(
                    'Hide Reel and resolve',
                    'Ukryj rolkę i rozstrzygnij',
                  ),
                  ReportTargetType.voiceMoment => copy.text(
                    'Remove Voice Moment and resolve',
                    'Usuń Voice Moment i rozstrzygnij',
                  ),
                  ReportTargetType.voiceMomentComment => copy.text(
                    'Remove Voice Moment comment and resolve',
                    'Usuń komentarz Voice Momentu i rozstrzygnij',
                  ),
                  _ => copy.text(
                    'Remove message and resolve',
                    'Usuń wiadomość i rozstrzygnij',
                  ),
                },
                icon: Icons.delete_outline_rounded,
                danger: true,
                busy: _busy,
                onPressed: () => _run(
                  (id) => service.removeContentAndResolve(
                    report.id,
                    requestId: id,
                    note: _note.text,
                  ),
                  confirmTitle: switch (report.targetType) {
                    ReportTargetType.reel => copy.text(
                      'Hide this Reel?',
                      'Ukryć tę rolkę?',
                    ),
                    ReportTargetType.voiceMoment => copy.text(
                      'Remove this Voice Moment?',
                      'Usunąć ten Voice Moment?',
                    ),
                    ReportTargetType.voiceMomentComment => copy.text(
                      'Remove this Voice Moment comment?',
                      'Usunąć ten komentarz Voice Momentu?',
                    ),
                    _ => copy.text(
                      'Remove this message?',
                      'Usunąć tę wiadomość?',
                    ),
                  },
                  confirmActionLabel: switch (report.targetType) {
                    ReportTargetType.reel => copy.text(
                      'Hide Reel',
                      'Ukryj rolkę',
                    ),
                    ReportTargetType.voiceMoment => copy.text(
                      'Remove Voice Moment',
                      'Usuń Voice Moment',
                    ),
                    ReportTargetType.voiceMomentComment => copy.text(
                      'Remove comment',
                      'Usuń komentarz',
                    ),
                    _ => copy.text('Remove message', 'Usuń wiadomość'),
                  },
                  confirmBody: isReel
                      ? copy.text(
                          'The Reel is hidden from feeds and playback while its '
                              'media is kept as evidence. This is recorded '
                              'against your account in the moderation audit log.',
                          'Rolka zostanie ukryta w kanałach i odtwarzaczu, a jej '
                              'media zachowane jako dowód. Ta czynność zostanie '
                              'przypisana do Twojego konta w dzienniku audytu '
                              'moderacji.',
                        )
                      : isVoiceMoment || isVoiceComment
                      ? copy.text(
                          'The reported Voice content is removed and its media '
                              'cleanup is queued. This is recorded against your '
                              'account in the moderation audit log.',
                          'Zgłoszona treść głosowa zostanie usunięta, a jej media '
                              'przekazane do bezpiecznego czyszczenia. Ta czynność '
                              'zostanie przypisana do Twojego konta w dzienniku '
                              'audytu moderacji.',
                        )
                      : copy.text(
                          'The message is hidden from the community and kept '
                              'as evidence. This is recorded against your account '
                              'in the moderation audit log.',
                          'Wiadomość zostanie ukryta przed społecznością i '
                              'zachowana jako dowód. Ta czynność zostanie '
                              'przypisana do Twojego konta w dzienniku audytu '
                              'moderacji.',
                        ),
                ),
              ),
            _ActionButton(
              label: copy.text('Dismiss', 'Odrzuć'),
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
        Text(
          copy.text(
            'Dismissing requires a resolution reason — one is always '
                'selected above.',
            'Odrzucenie wymaga wskazania powodu rozstrzygnięcia — jeden '
                'z powodów jest zawsze wybrany powyżej.',
          ),
          style: const TextStyle(color: Color(0xFF7E7895), fontSize: 10.5),
        ),
        // Account actions are ADMIN-only server-side (setUserBan is
        // gated to admin/superAdmin). Rather than offering a button that
        // would be refused, moderators are told where it lives.
        if (widget.role == 'moderator') ...[
          const SizedBox(height: 12),
          _Banner(
            icon: Icons.info_outline_rounded,
            color: const Color(0xFF5CE1E6),
            text: copy.text(
              'Banning or suspending an account is an administrator '
                  'action. Resolve the content here and escalate the '
                  'account to an admin.',
              'Zablokowanie lub zawieszenie konta wymaga uprawnień '
                  'administratora. Rozpatrz treść tutaj, a sprawę konta '
                  'przekaż administratorowi.',
            ),
          ),
        ],
      ],
    );
  }
}

String resolutionLabel(ReportResolution resolution, {AppLocalizations? copy}) {
  final english = switch (resolution) {
    ReportResolution.contentRemoved => 'Content removed',
    ReportResolution.warningIssued => 'Warning issued',
    ReportResolution.noActionNeeded => 'No action needed',
    ReportResolution.notAViolation => 'Not a violation',
    ReportResolution.duplicate => 'Duplicate',
    ReportResolution.insufficientEvidence => 'Insufficient evidence',
  };
  final polish = switch (resolution) {
    ReportResolution.contentRemoved => 'Treść usunięta',
    ReportResolution.warningIssued => 'Wydano ostrzeżenie',
    ReportResolution.noActionNeeded => 'Brak potrzeby działania',
    ReportResolution.notAViolation => 'Brak naruszenia',
    ReportResolution.duplicate => 'Duplikat',
    ReportResolution.insufficientEvidence => 'Niewystarczające dowody',
  };
  return copy?.text(english, polish) ?? english;
}

String _polishModerationFailure(ModerationFailure failure) => switch (failure) {
  ModerationFailure.conflict =>
    'To zgłoszenie jest teraz obsługiwane przez inną osobę. Odśwież kolejkę.',
  ModerationFailure.alreadyHandled => 'To zgłoszenie zostało już rozpatrzone.',
  ModerationFailure.accessExpired =>
    'Dostęp moderatorski wygasł. Zaloguj się ponownie.',
  ModerationFailure.missing =>
    'Nie znaleziono tego zgłoszenia lub zgłoszonej treści.',
  ModerationFailure.unknown =>
    'Nie udało się wykonać tej czynności. Sprawdź połączenie i spróbuj ponownie.',
};

String _englishModerationFailure(
  ModerationFailure failure,
) => switch (failure) {
  ModerationFailure.conflict =>
    'Another moderator is handling this report. Refresh the queue.',
  ModerationFailure.alreadyHandled => 'This report has already been handled.',
  ModerationFailure.accessExpired =>
    'Your moderation access expired. Sign in again.',
  ModerationFailure.missing =>
    'This report or its reported content could not be found.',
  ModerationFailure.unknown =>
    'That action could not be completed. Check your connection and try again.',
};

/// Immutable target identity copied into the report at creation time.
///
/// Voice content may already be deleting or fully gone when a moderator opens
/// the queue. Rendering these report-owned ids keeps the evidence useful and,
/// critically, never turns the panel into a second read path for private media.
class _TargetReference extends StatelessWidget {
  const _TargetReference({required this.report});

  final ModerationReport report;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final type = report.targetType;
    final label = switch (type) {
      ReportTargetType.voiceMoment => copy.text(
        'Reported Voice Moment',
        'Zgłoszony Voice Moment',
      ),
      ReportTargetType.voiceMomentComment => copy.text(
        'Reported Voice Moment comment',
        'Zgłoszony komentarz Voice Momentu',
      ),
      _ => copy.text('Reported target', 'Zgłoszony cel'),
    };
    final value = switch (type) {
      ReportTargetType.voiceMoment =>
        '${copy.text('Moment ID', 'ID Momentu')}: ${report.momentId ?? report.targetId}',
      ReportTargetType.voiceMomentComment =>
        '${copy.text('Moment ID', 'ID Momentu')}: ${report.momentId ?? '—'}\n'
            '${copy.text('Comment ID', 'ID komentarza')}: ${report.commentId ?? report.targetId}',
      _ => report.targetId.isEmpty ? '—' : report.targetId,
    };
    return _Field(label: label, value: value, meta: report.contextPath);
  }
}

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
    final copy = AppLocalizations.of(context);
    return FutureBuilder<({String? displayName, String? photoUrl})?>(
      future: service.publicProfile(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data == null) {
          return _Field(
            label: copy.text('Reported account', 'Zgłoszone konto'),
            value: copy.text(
              'This account no longer exists.',
              'To konto już nie istnieje.',
            ),
            meta: userId,
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
                userId: userId,
                photoUrl: profile?.photoUrl,
                displayName: profile?.displayName,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          profile?.displayName?.isNotEmpty == true
                              ? profile!.displayName!
                              : copy.text('Loading…', 'Wczytywanie…'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        UserIdentityBadges(uid: userId),
                      ],
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
    final copy = AppLocalizations.of(context);
    return FutureBuilder<GlobalMessage?>(
      future: service.targetMessage(messageId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _Field(
            label: copy.text('Reported message', 'Zgłoszona wiadomość'),
            value: copy.text('Loading…', 'Wczytywanie…'),
          );
        }
        final message = snapshot.data;
        if (message == null) {
          return _Field(
            label: copy.text('Reported message', 'Zgłoszona wiadomość'),
            value: copy.text(
              'This message is no longer available.',
              'Ta wiadomość nie jest już dostępna.',
            ),
          );
        }
        if (message.isDeleted) {
          return _Field(
            label: copy.text('Reported message', 'Zgłoszona wiadomość'),
            value: message.removedByModerator
                ? copy.text(
                    'Already removed by a moderator.',
                    'Wiadomość została już usunięta przez moderatora.',
                  )
                : copy.text(
                    'Deleted by its author.',
                    'Wiadomość została usunięta przez autora.',
                  ),
          );
        }
        return _Field(
          label: copy.text('Reported message', 'Zgłoszona wiadomość'),
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
  const _Banner({required this.icon, required this.color, required this.text});

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
  const _ConfirmDialog({
    required this.title,
    required this.body,
    this.actionLabel,
  });

  final String title;
  final String body;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
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
          child: Text(
            copy.text('Cancel', 'Anuluj'),
            style: const TextStyle(color: Color(0xFF9A90AC)),
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
          child: Text(
            actionLabel ?? copy.text('Remove message', 'Usuń wiadomość'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
