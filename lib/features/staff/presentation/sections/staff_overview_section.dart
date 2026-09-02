import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/staff/data/staff_overview_service.dart';
import 'package:yovoice/features/staff/presentation/staff_localized_copy.dart';
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
    final copy = AppLocalizations.of(context);
    final overview = _overview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaffSectionHeader(
          title: copy.text('Overview', 'Przegląd'),
          subtitle: copy.text(
            'Live, server-derived state of the platform. Every card opens its section.',
            'Aktualny stan platformy na podstawie danych z serwera. Każda karta otwiera odpowiednią sekcję.',
          ),
          trailing: IconButton(
            tooltip: copy.text('Refresh', 'Odśwież'),
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
                  message: copy.text(
                    'The overview could not be loaded. It is reserved for the application owner.',
                    'Nie udało się wczytać przeglądu. Ta sekcja jest dostępna wyłącznie dla właściciela aplikacji.',
                  ),
                  onRetry: _load,
                )
              : overview == null
              ? Center(
                  child: Semantics(
                    label: copy.text(
                      'Loading staff overview',
                      'Wczytywanie przeglądu zespołu',
                    ),
                    child: const CircularProgressIndicator(),
                  ),
                )
              : _body(overview),
        ),
      ],
    );
  }

  Widget _body(StaffOverview overview) {
    final copy = AppLocalizations.of(context);
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
                label: copy.text('Total users', 'Wszyscy użytkownicy'),
                value: counts.totalUsers,
                icon: Icons.people_alt_rounded,
                color: const Color(0xFF8D5BFF),
                onTap: () => widget.onOpenUsers('all'),
              ),
              _StatCard(
                label: copy.text('Active rooms', 'Aktywne pokoje'),
                value: counts.activeRooms,
                icon: Icons.podcasts_rounded,
                color: StaffCenterStyle.good,
                onTap: widget.onOpenRooms,
              ),
              _StatCard(
                label: copy.text('Open reports', 'Otwarte zgłoszenia'),
                value: counts.openReports,
                icon: Icons.flag_rounded,
                color: StaffCenterStyle.warn,
                onTap: widget.onOpenReports,
              ),
              _StatCard(
                label: copy.text('Restricted', 'Ograniczone konta'),
                value: counts.restrictedAccounts,
                icon: Icons.voice_over_off_rounded,
                color: StaffCenterStyle.warn,
                onTap: () => widget.onOpenUsers('restricted'),
              ),
              _StatCard(
                label: copy.text('Staff members', 'Członkowie zespołu'),
                value: counts.staffMembers,
                icon: Icons.shield_rounded,
                color: const Color(0xFFA855F7),
                onTap: widget.onOpenStaffRoles,
              ),
              _StatCard(
                label: copy.text('VIP users', 'Użytkownicy VIP'),
                value: counts.vipUsers,
                icon: Icons.diamond_rounded,
                color: const Color(0xFFFFD166),
                onTap: () => widget.onOpenUsers('vip'),
              ),
              _StatCard(
                label: copy.text('Security alerts', 'Alerty bezpieczeństwa'),
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
                  copy.text(
                    'Latest open reports',
                    'Najnowsze otwarte zgłoszenia',
                  ),
                  widget.onOpenReports,
                  overview.latestOpenReports.isEmpty
                      ? [
                          StaffEmptyState(
                            message: copy.text(
                              'No open reports.',
                              'Brak otwartych zgłoszeń.',
                            ),
                          ),
                        ]
                      : [
                          for (final report in overview.latestOpenReports)
                            _line(
                              icon: Icons.flag_rounded,
                              color: StaffCenterStyle.warn,
                              title:
                                  '${report.reason ?? copy.text('report', 'zgłoszenie')} · ${report.targetType ?? ''}',
                              trailing: staffStamp(copy, report.createdAt),
                            ),
                        ],
                ),
                _listPanel(
                  copy.text('Active rooms', 'Aktywne pokoje'),
                  widget.onOpenRooms,
                  overview.activeRooms.isEmpty
                      ? [
                          StaffEmptyState(
                            message: copy.text(
                              'Nothing live right now.',
                              'Teraz nic nie jest nadawane na żywo.',
                            ),
                          ),
                        ]
                      : [
                          for (final room in overview.activeRooms)
                            _line(
                              icon: Icons.podcasts_rounded,
                              color: StaffCenterStyle.good,
                              title: room.name,
                              trailing: localizedStaffParticipantCount(
                                copy,
                                room.participantCount,
                              ),
                            ),
                        ],
                ),
                _listPanel(
                  copy.text('Recent sanctions', 'Ostatnie sankcje'),
                  widget.onOpenSanctions,
                  overview.recentSanctions.isEmpty
                      ? [
                          StaffEmptyState(
                            message: copy.text(
                              'No recent sanctions.',
                              'Brak ostatnich sankcji.',
                            ),
                          ),
                        ]
                      : [
                          for (final entry in overview.recentSanctions)
                            _line(
                              icon: Icons.gavel_rounded,
                              color: StaffCenterStyle.warn,
                              title: localizedStaffAuditAction(
                                copy,
                                entry.action,
                              ),
                              trailing: staffStamp(copy, entry.createdAt),
                            ),
                        ],
                ),
                _listPanel(
                  copy.text('Recent role changes', 'Ostatnie zmiany ról'),
                  widget.onOpenStaffRoles,
                  overview.recentRoleChanges.isEmpty
                      ? [
                          StaffEmptyState(
                            message: copy.text(
                              'No recent role changes.',
                              'Brak ostatnich zmian ról.',
                            ),
                          ),
                        ]
                      : [
                          for (final entry in overview.recentRoleChanges)
                            _line(
                              icon: Icons.badge_rounded,
                              color: const Color(0xFFA855F7),
                              title:
                                  '${localizedStaffRole(copy, entry.previousRole ?? '?')} → ${localizedStaffRole(copy, entry.role ?? '?')}',
                              trailing: staffStamp(copy, entry.createdAt),
                            ),
                        ],
                ),
                _listPanel(
                  copy.text('Security alerts', 'Alerty bezpieczeństwa'),
                  () => widget.onOpenAudit(
                    action: 'security_alert_non_owner_super_admin',
                  ),
                  overview.securityAlerts.isEmpty
                      ? [
                          StaffEmptyState(
                            message: copy.text(
                              'No security alerts. Good.',
                              'Brak alertów bezpieczeństwa.',
                            ),
                          ),
                        ]
                      : [
                          for (final entry in overview.securityAlerts)
                            _line(
                              icon: Icons.gpp_maybe_rounded,
                              color: StaffCenterStyle.bad,
                              title: copy.text(
                                'non-owner superAdmin observed',
                                'Wykryto superadministratora niebędącego właścicielem',
                              ),
                              trailing: staffStamp(copy, entry.createdAt),
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
