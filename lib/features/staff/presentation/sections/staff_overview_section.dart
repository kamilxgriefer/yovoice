import 'package:flutter/material.dart';

import 'package:yovoice/features/staff/data/staff_overview_service.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_section_shared.dart';

/// Overview — the Staff Center's opening screen. Every number and every
/// list arrives from getStaffOverview; each card is a door into its
/// filtered section.
class StaffOverviewSection extends StatefulWidget {
  const StaffOverviewSection({
    required this.onOpenUsers,
    required this.onOpenReports,
    required this.onOpenRooms,
    required this.onOpenSanctions,
    required this.onOpenStaffRoles,
    required this.onOpenAudit,
    this.overviewService,
    super.key,
  });

  /// Opens Users with a directory filter preselected.
  final void Function(String filter) onOpenUsers;
  final VoidCallback onOpenReports;
  final VoidCallback onOpenRooms;
  final VoidCallback onOpenSanctions;
  final VoidCallback onOpenStaffRoles;

  /// Opens the audit log, optionally pre-filtered to one action.
  final void Function({String? action}) onOpenAudit;

  final StaffOverviewService? overviewService;

  @override
  State<StaffOverviewSection> createState() => _StaffOverviewSectionState();
}

class _StaffOverviewSectionState extends State<StaffOverviewSection> {
  late final StaffOverviewService _service =
      widget.overviewService ?? StaffOverviewService();

  StaffOverview? _overview;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final overview = await _service.load();
      if (mounted) setState(() => _overview = overview);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaffSectionHeader(
          title: 'Overview',
          subtitle:
              'Live, server-derived state of the platform. Every card opens '
              'its section.',
          trailing: IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(
              Icons.refresh_rounded,
              color: StaffCenterStyle.muted,
            ),
          ),
        ),
        Expanded(
          child: _failed
              ? StaffErrorState(
                  message:
                      'The overview could not be loaded. It is reserved for '
                      'the application owner.',
                  onRetry: _load,
                )
              : overview == null
              ? const Center(child: CircularProgressIndicator())
              : _body(overview),
        ),
      ],
    );
  }

  Widget _body(StaffOverview overview) {
    final counts = overview.counts;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatCard(
                label: 'Total users',
                value: counts.totalUsers,
                icon: Icons.people_alt_rounded,
                color: const Color(0xFF8D5BFF),
                onTap: () => widget.onOpenUsers('all'),
              ),
              _StatCard(
                label: 'Active rooms',
                value: counts.activeRooms,
                icon: Icons.podcasts_rounded,
                color: StaffCenterStyle.good,
                onTap: widget.onOpenRooms,
              ),
              _StatCard(
                label: 'Open reports',
                value: counts.openReports,
                icon: Icons.flag_rounded,
                color: StaffCenterStyle.warn,
                onTap: widget.onOpenReports,
              ),
              _StatCard(
                label: 'Restricted',
                value: counts.restrictedAccounts,
                icon: Icons.voice_over_off_rounded,
                color: StaffCenterStyle.warn,
                onTap: () => widget.onOpenUsers('restricted'),
              ),
              _StatCard(
                label: 'Staff members',
                value: counts.staffMembers,
                icon: Icons.shield_rounded,
                color: const Color(0xFFA855F7),
                onTap: widget.onOpenStaffRoles,
              ),
              _StatCard(
                label: 'VIP users',
                value: counts.vipUsers,
                icon: Icons.diamond_rounded,
                color: const Color(0xFFFFD166),
                onTap: () => widget.onOpenUsers('vip'),
              ),
              _StatCard(
                label: 'Security alerts',
                value: counts.securityAlerts,
                icon: Icons.gpp_maybe_rounded,
                color: StaffCenterStyle.bad,
                onTap: () => widget.onOpenAudit(
                  action: 'security_alert_non_owner_super_admin',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 860;
              final panels = [
                _listPanel(
                  'Latest open reports',
                  widget.onOpenReports,
                  overview.latestOpenReports.isEmpty
                      ? [const StaffEmptyState(message: 'No open reports.')]
                      : [
                          for (final report in overview.latestOpenReports)
                            _line(
                              icon: Icons.flag_rounded,
                              color: StaffCenterStyle.warn,
                              title:
                                  '${report.reason ?? 'report'} · ${report.targetType ?? ''}',
                              trailing: staffStamp(report.createdAt),
                            ),
                        ],
                ),
                _listPanel(
                  'Active rooms',
                  widget.onOpenRooms,
                  overview.activeRooms.isEmpty
                      ? [
                          const StaffEmptyState(
                            message: 'Nothing live right now.',
                          ),
                        ]
                      : [
                          for (final room in overview.activeRooms)
                            _line(
                              icon: Icons.podcasts_rounded,
                              color: StaffCenterStyle.good,
                              title: room.name,
                              trailing: '${room.participantCount} in room',
                            ),
                        ],
                ),
                _listPanel(
                  'Recent sanctions',
                  widget.onOpenSanctions,
                  overview.recentSanctions.isEmpty
                      ? [const StaffEmptyState(message: 'No recent sanctions.')]
                      : [
                          for (final entry in overview.recentSanctions)
                            _line(
                              icon: Icons.gavel_rounded,
                              color: StaffCenterStyle.warn,
                              title: entry.action.replaceAll('_', ' '),
                              trailing: staffStamp(entry.createdAt),
                            ),
                        ],
                ),
                _listPanel(
                  'Recent role changes',
                  widget.onOpenStaffRoles,
                  overview.recentRoleChanges.isEmpty
                      ? [
                          const StaffEmptyState(
                            message: 'No recent role changes.',
                          ),
                        ]
                      : [
                          for (final entry in overview.recentRoleChanges)
                            _line(
                              icon: Icons.badge_rounded,
                              color: const Color(0xFFA855F7),
                              title:
                                  '${entry.previousRole ?? '?'} → ${entry.role ?? '?'}',
                              trailing: staffStamp(entry.createdAt),
                            ),
                        ],
                ),
                _listPanel(
                  'Security alerts',
                  () => widget.onOpenAudit(
                    action: 'security_alert_non_owner_super_admin',
                  ),
                  overview.securityAlerts.isEmpty
                      ? [
                          const StaffEmptyState(
                            message: 'No security alerts. Good.',
                          ),
                        ]
                      : [
                          for (final entry in overview.securityAlerts)
                            _line(
                              icon: Icons.gpp_maybe_rounded,
                              color: StaffCenterStyle.bad,
                              title: 'non-owner superAdmin observed',
                              trailing: staffStamp(entry.createdAt),
                            ),
                        ],
                ),
              ];
              if (!twoColumns) {
                return Column(
                  children: [
                    for (final panel in panels) ...[
                      panel,
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final panel in panels)
                    SizedBox(
                      width: (constraints.maxWidth - 10) / 2,
                      child: panel,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _listPanel(String title, VoidCallback onOpen, List<Widget> children) {
    return StaffPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StaffPanelTitle(title: title, onSeeAll: onOpen),
          ...children,
        ],
      ),
    );
  }

  Widget _line({
    required IconData icon,
    required Color color,
    required String title,
    required String trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ),
          Text(
            trailing,
            style: const TextStyle(
              color: StaffCenterStyle.faint,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: Material(
        color: StaffCenterStyle.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: StaffCenterStyle.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 10),
                Text(
                  '$value',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: StaffCenterStyle.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
