import 'package:flutter/material.dart';

import 'package:yovoice/features/moderation/data/models/moderation_report.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_audit_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/data/staff_directory_service.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_section_shared.dart';
import 'package:yovoice/features/staff/presentation/widgets/room_staff_menu.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/vip_badge.dart';

/// Reports — the live open queue, backed by the same ModerationService
/// and rules the Moderation Center enforces. The full workflow (claim,
/// resolve, remove content) lives there; this section shows the real
/// queue and opens it.
class StaffReportsSection extends StatelessWidget {
  const StaffReportsSection({this.moderationService, super.key});

  final ModerationService? moderationService;

  @override
  Widget build(BuildContext context) {
    final service = moderationService ?? ModerationService();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaffSectionHeader(
          title: 'Reports',
          subtitle:
              'Open community reports, live from the queue. Claiming and '
              'resolving happen in the Moderation Center workflow.',
          trailing: FilledButton.icon(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ModerationCenterScreen(moderationService: moderationService),
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: StaffCenterStyle.accent,
            ),
            icon: const Icon(Icons.shield_rounded, size: 16),
            label: const Text('Open Moderation Center'),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<ModerationReport>>(
            stream: service.watchQueue(status: ReportStatus.open),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const StaffEmptyState(
                  icon: Icons.lock_rounded,
                  message:
                      'The reports queue is readable by moderation staff '
                      'only.',
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final reports = snapshot.data!;
              if (reports.isEmpty) {
                return const StaffEmptyState(
                  message: 'No open reports. The queue is clear.',
                );
              }
              return ListView.separated(
                itemCount: reports.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final report = reports[index];
                  return StaffPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.flag_rounded,
                          size: 16,
                          color: StaffCenterStyle.warn,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${report.reason?.name ?? 'report'} · ${report.targetType?.name ?? ''}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (report.note.trim().isNotEmpty)
                                Text(
                                  report.note,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: StaffCenterStyle.muted,
                                    fontSize: 11.5,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          staffStamp(report.createdAt),
                          style: const TextStyle(
                            color: StaffCenterStyle.faint,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Rooms & Spaces — everything currently live, with the staff room menu
/// (end room and friends) exactly as rooms themselves render it.
class StaffRoomsSection extends StatelessWidget {
  const StaffRoomsSection({
    required this.capabilities,
    this.roomService,
    super.key,
  });

  final StaffCapabilities capabilities;
  final RoomService? roomService;

  @override
  Widget build(BuildContext context) {
    final service = roomService ?? RoomService();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StaffSectionHeader(
          title: 'Rooms & Spaces',
          subtitle:
              'Live rooms across the platform. Staff room controls are the '
              'same tiered menu rooms show in place.',
        ),
        Expanded(
          child: StreamBuilder<List<VoiceRoom>>(
            stream: service.watchLivePublicRooms(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const StaffEmptyState(
                  icon: Icons.error_outline_rounded,
                  message: 'Live rooms could not be loaded.',
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rooms = snapshot.data!;
              if (rooms.isEmpty) {
                return const StaffEmptyState(
                  message: 'Nothing is live right now.',
                );
              }
              return ListView.separated(
                itemCount: rooms.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  return StaffPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          room.isBroadcast
                              ? Icons.podcasts_rounded
                              : Icons.people_alt_rounded,
                          size: 17,
                          color: StaffCenterStyle.good,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                room.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Hosted by ${room.hostName} · '
                                '${room.participantCount} in room',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: StaffCenterStyle.muted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (capabilities.hasRoomModeration)
                          RoomStaffMenu(room: room, capabilities: capabilities),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Sanctions — the real record of warnings, mutes, lifts and bans, from
/// the audit log. Applying a sanction happens on a user (Users → View),
/// so each row links to its target.
class StaffSanctionsSection extends StatefulWidget {
  const StaffSanctionsSection({
    required this.onOpenUser,
    this.auditService,
    super.key,
  });

  final void Function(String uid) onOpenUser;
  final StaffAuditService? auditService;

  static const actions = [
    'warn_user',
    'communication_mute',
    'lift_communication_mute',
    'ban_user',
    'unban_user',
  ];

  @override
  State<StaffSanctionsSection> createState() => _StaffSanctionsSectionState();
}

class _StaffSanctionsSectionState extends State<StaffSanctionsSection> {
  late final StaffAuditService _audit =
      widget.auditService ?? StaffAuditService();

  List<StaffAuditEntry>? _entries;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _entries = null;
    });
    try {
      // One page per sanction action, merged newest-first: the audit
      // browser filters on a single action per query.
      final pages = await Future.wait([
        for (final action in StaffSanctionsSection.actions)
          _audit.list(action: action, limit: 10),
      ]);
      final merged = [for (final page in pages) ...page.entries]
        ..sort(
          (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          ),
        );
      if (mounted) setState(() => _entries = merged.take(30).toList());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaffSectionHeader(
          title: 'Sanctions',
          subtitle:
              'Warnings, communication mutes, lifts and bans as the audit '
              'log recorded them. Apply or lift sanctions from a user\'s '
              'detail view.',
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
                      'Sanction history could not be loaded. It is part of '
                      'the owner\'s audit access.',
                  onRetry: _load,
                )
              : entries == null
              ? const Center(child: CircularProgressIndicator())
              : entries.isEmpty
              ? const StaffEmptyState(message: 'No sanctions recorded.')
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final lifted =
                        entry.action == 'lift_communication_mute' ||
                        entry.action == 'unban_user';
                    return StaffPanel(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            lifted
                                ? Icons.lock_open_rounded
                                : Icons.gavel_rounded,
                            size: 16,
                            color: lifted
                                ? StaffCenterStyle.good
                                : StaffCenterStyle.warn,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.action.replaceAll('_', ' '),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if ((entry.details['reason'] as String?)
                                        ?.isNotEmpty ==
                                    true)
                                  Text(
                                    entry.details['reason'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: StaffCenterStyle.muted,
                                      fontSize: 11.5,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            staffStamp(entry.createdAt),
                            style: const TextStyle(
                              color: StaffCenterStyle.faint,
                              fontSize: 10.5,
                            ),
                          ),
                          if (entry.targetId != null) ...[
                            const SizedBox(width: 6),
                            TextButton(
                              onPressed: () =>
                                  widget.onOpenUser(entry.targetId!),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFD3A5FF),
                                minimumSize: const Size(44, 34),
                              ),
                              child: const Text(
                                'User',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Staff & Roles — everyone holding a staff role, from the directory,
/// plus the role-change record.
class StaffRolesSection extends StatefulWidget {
  const StaffRolesSection({
    required this.onOpenUser,
    this.directoryService,
    this.auditService,
    super.key,
  });

  final void Function(DirectoryUser user) onOpenUser;
  final StaffDirectoryService? directoryService;
  final StaffAuditService? auditService;

  @override
  State<StaffRolesSection> createState() => _StaffRolesSectionState();
}

class _StaffRolesSectionState extends State<StaffRolesSection> {
  late final StaffDirectoryService _directory =
      widget.directoryService ?? StaffDirectoryService();
  late final StaffAuditService _audit =
      widget.auditService ?? StaffAuditService();

  List<DirectoryUser>? _staff;
  List<StaffAuditEntry>? _changes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _staff = null;
      _changes = null;
    });
    try {
      final results = await Future.wait([
        _directory.search(filter: 'staff'),
        _audit.list(action: 'assign_user_role', limit: 10),
      ]);
      if (!mounted) return;
      setState(() {
        _staff = (results[0] as DirectorySearchPage).users;
        _changes = (results[1] as StaffAuditPage).entries;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = _staff;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaffSectionHeader(
          title: 'Staff & Roles',
          subtitle:
              'Every account holding a staff role, and the recorded role '
              'changes. Assignments happen in a user\'s detail view and are '
              'owner-only.',
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
                  message: 'Staff membership could not be loaded.',
                  onRetry: _load,
                )
              : staff == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    if (staff.isEmpty)
                      const StaffEmptyState(
                        message: 'No staff roles are assigned.',
                      )
                    else
                      for (final member in staff)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: StaffPanel(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        member.displayName.isEmpty
                                            ? 'YO Voice user'
                                            : member.displayName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      OfficialRoleBadge(
                                        role: OfficialRole.fromWire(
                                          member.staffRole,
                                        ),
                                        variant: IdentityBadgeVariant.compact,
                                      ),
                                      if (member.isVip)
                                        const VipBadge(
                                          variant: IdentityBadgeVariant.compact,
                                        ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => widget.onOpenUser(member),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFFD3A5FF),
                                  ),
                                  child: const Text('View'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    const SizedBox(height: 8),
                    StaffPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const StaffPanelTitle(title: 'Recent role changes'),
                          if ((_changes ?? const []).isEmpty)
                            const Text(
                              'No role changes recorded.',
                              style: TextStyle(
                                color: StaffCenterStyle.muted,
                                fontSize: 12,
                              ),
                            )
                          else
                            for (final change in _changes!)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.badge_rounded,
                                      size: 13,
                                      color: Color(0xFFA855F7),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${change.details['previousRole'] ?? '?'}'
                                        ' → ${change.details['role'] ?? '?'}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      staffStamp(change.createdAt),
                                      style: const TextStyle(
                                        color: StaffCenterStyle.faint,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Audit Log — the owner's full browser over adminAuditLogs, filterable
/// by action and paginated on the server's cursor.
class StaffAuditSection extends StatefulWidget {
  const StaffAuditSection({
    this.initialAction,
    this.auditService,
    super.key,
  });

  final String? initialAction;
  final StaffAuditService? auditService;

  @override
  State<StaffAuditSection> createState() => _StaffAuditSectionState();
}

class _StaffAuditSectionState extends State<StaffAuditSection> {
  late final StaffAuditService _audit =
      widget.auditService ?? StaffAuditService();

  static const actionFilters = <(String?, String)>[
    (null, 'Everything'),
    ('assign_user_role', 'Role changes'),
    ('communication_mute', 'Mutes'),
    ('ban_user', 'Bans'),
    ('security_alert_non_owner_super_admin', 'Security alerts'),
    ('denied_sanction_attempt', 'Denied attempts'),
  ];

  late String? _action = widget.initialAction;
  List<StaffAuditEntry> _entries = const [];
  String? _cursor;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _failed = false;
      if (!more) {
        _entries = const [];
        _cursor = null;
      }
    });
    try {
      final page = await _audit.list(
        action: _action,
        cursorId: more ? _cursor : null,
      );
      if (!mounted) return;
      setState(() {
        _entries = more ? [..._entries, ...page.entries] : page.entries;
        _cursor = page.cursorId;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StaffSectionHeader(
          title: 'Audit Log',
          subtitle:
              'Every privileged action and every refused attempt, exactly '
              'as recorded. Owner access.',
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (value, label) in actionFilters) ...[
                ChoiceChip(
                  label: Text(label),
                  selected: _action == value,
                  onSelected: (_) {
                    setState(() => _action = value);
                    _load();
                  },
                  labelStyle: TextStyle(
                    color: _action == value
                        ? Colors.white
                        : StaffCenterStyle.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  selectedColor: StaffCenterStyle.accent.withValues(alpha: .35),
                  backgroundColor: StaffCenterStyle.surfaceRaised,
                  side: const BorderSide(color: StaffCenterStyle.border),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _failed
              ? StaffErrorState(
                  message: 'The audit log could not be loaded.',
                  onRetry: _load,
                )
              : _loading && _entries.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _entries.isEmpty
              ? const StaffEmptyState(message: 'No entries for this filter.')
              : ListView.separated(
                  itemCount: _entries.length + (_cursor == null ? 0 : 1),
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    if (index >= _entries.length) {
                      return Center(
                        child: OutlinedButton(
                          onPressed: _loading
                              ? null
                              : () => _load(more: true),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(
                              color: StaffCenterStyle.border,
                            ),
                          ),
                          child: const Text('Load more'),
                        ),
                      );
                    }
                    final entry = _entries[index];
                    final isAlert = entry.action.startsWith('security_alert');
                    return StaffPanel(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 9,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isAlert
                                ? Icons.gpp_maybe_rounded
                                : Icons.receipt_long_rounded,
                            size: 15,
                            color: isAlert
                                ? StaffCenterStyle.bad
                                : StaffCenterStyle.faint,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.action.replaceAll('_', ' '),
                                  style: TextStyle(
                                    color: isAlert
                                        ? StaffCenterStyle.bad
                                        : Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  [
                                    if (entry.actorRole != null)
                                      'by ${entry.actorRole}',
                                    if (entry.targetType != null)
                                      'on ${entry.targetType} ${entry.targetId ?? ''}',
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: StaffCenterStyle.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            staffStamp(entry.createdAt),
                            style: const TextStyle(
                              color: StaffCenterStyle.faint,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
