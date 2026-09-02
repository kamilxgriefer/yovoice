import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_audit_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/data/staff_directory_service.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_section_shared.dart';
import 'package:yovoice/features/staff/presentation/staff_localized_copy.dart';
import 'package:yovoice/features/staff/presentation/widgets/room_staff_menu.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/vip_badge.dart';

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
    final copy = AppLocalizations.of(context);
    final service = roomService ?? RoomService();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaffSectionHeader(
          title: copy.text('Rooms & Spaces', 'Pokoje i przestrzenie'),
          subtitle: copy.text(
            'Live rooms across the platform. Staff room controls use the same tiered menu shown inside rooms.',
            'Pokoje nadawane na żywo na całej platformie. Narzędzia zespołu są dostępne w tym samym menu co w pokojach.',
          ),
        ),
        Expanded(
          child: StreamBuilder<List<VoiceRoom>>(
            stream: service.watchLivePublicRooms(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return StaffEmptyState(
                  icon: Icons.error_outline_rounded,
                  message: copy.text(
                    'Live rooms could not be loaded.',
                    'Nie udało się wczytać pokojów na żywo.',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return Center(
                  child: Semantics(
                    label: copy.text(
                      'Loading live rooms',
                      'Wczytywanie pokojów na żywo',
                    ),
                    child: const CircularProgressIndicator(),
                  ),
                );
              }
              final rooms = snapshot.data!;
              if (rooms.isEmpty) {
                return StaffEmptyState(
                  message: copy.text(
                    'Nothing is live right now.',
                    'Teraz nic nie jest nadawane na żywo.',
                  ),
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
                                copy.text(
                                  'Hosted by ${room.hostName} · ${room.participantCount} in room',
                                  'Prowadzący: ${room.hostName} · ${localizedStaffParticipantCount(copy, room.participantCount)}',
                                ),
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
    final copy = AppLocalizations.of(context);
    final entries = _entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaffSectionHeader(
          title: copy.text('Sanctions', 'Sankcje'),
          subtitle: copy.text(
            'Warnings, communication mutes, lifts and bans as recorded in the audit log. Apply or lift sanctions from a user\'s detail view.',
            'Ostrzeżenia, wyciszenia komunikacji, zdjęte ograniczenia i blokady zapisane w dzienniku audytu. Sankcje nakładaj lub zdejmuj w szczegółach użytkownika.',
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
                    'Sanction history could not be loaded. It is part of the owner\'s audit access.',
                    'Nie udało się wczytać historii sankcji. Dostęp do niej ma właściciel aplikacji.',
                  ),
                  onRetry: _load,
                )
              : entries == null
              ? Center(
                  child: Semantics(
                    label: copy.text(
                      'Loading sanction history',
                      'Wczytywanie historii sankcji',
                    ),
                    child: const CircularProgressIndicator(),
                  ),
                )
              : entries.isEmpty
              ? StaffEmptyState(
                  message: copy.text(
                    'No sanctions recorded.',
                    'Nie zarejestrowano żadnych sankcji.',
                  ),
                )
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
                                  localizedStaffAuditAction(copy, entry.action),
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
                            staffStamp(copy, entry.createdAt),
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
                              child: Text(
                                copy.text('User', 'Użytkownik'),
                                style: const TextStyle(fontSize: 12),
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
    final copy = AppLocalizations.of(context);
    final staff = _staff;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaffSectionHeader(
          title: copy.text('Staff & Roles', 'Zespół i role'),
          subtitle: copy.text(
            'Every account holding a staff role and every recorded role change. Only the owner can assign roles from a user\'s detail view.',
            'Wszystkie konta z rolą zespołu oraz zarejestrowane zmiany ról. Role może nadawać wyłącznie właściciel w szczegółach użytkownika.',
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
                    'Staff membership could not be loaded.',
                    'Nie udało się wczytać członków zespołu.',
                  ),
                  onRetry: _load,
                )
              : staff == null
              ? Center(
                  child: Semantics(
                    label: copy.text(
                      'Loading staff members',
                      'Wczytywanie członków zespołu',
                    ),
                    child: const CircularProgressIndicator(),
                  ),
                )
              : ListView(
                  children: [
                    if (staff.isEmpty)
                      StaffEmptyState(
                        message: copy.text(
                          'No staff roles are assigned.',
                          'Nie przypisano żadnych ról zespołu.',
                        ),
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
                                            ? copy.text(
                                                'YO Voice user',
                                                'Użytkownik YO Voice',
                                              )
                                            : member.displayName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      StaffOfficialRoleBadge(
                                        role: member.staffRole,
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
                                  child: Text(copy.text('View', 'Wyświetl')),
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
                          StaffPanelTitle(
                            title: copy.text(
                              'Recent role changes',
                              'Ostatnie zmiany ról',
                            ),
                          ),
                          if ((_changes ?? const []).isEmpty)
                            Text(
                              copy.text(
                                'No role changes recorded.',
                                'Nie zarejestrowano żadnych zmian ról.',
                              ),
                              style: const TextStyle(
                                color: StaffCenterStyle.muted,
                                fontSize: 12,
                              ),
                            )
                          else
                            for (final change in _changes!)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
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
                                        '${localizedStaffRole(copy, (change.details['previousRole'] ?? '?').toString())}'
                                        ' → ${localizedStaffRole(copy, (change.details['role'] ?? '?').toString())}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      staffStamp(copy, change.createdAt),
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
  const StaffAuditSection({this.initialAction, this.auditService, super.key});

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
    final copy = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaffSectionHeader(
          title: copy.text('Audit Log', 'Dziennik audytu'),
          subtitle: copy.text(
            'Every privileged action and every refused attempt, exactly as recorded. Owner access.',
            'Wszystkie działania uprzywilejowane i odrzucone próby — dokładnie tak, jak je zarejestrowano. Dostęp ma właściciel.',
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (value, label) in actionFilters) ...[
                ChoiceChip(
                  label: Text(_localizedAuditFilter(copy, value, label)),
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
                  message: copy.text(
                    'The audit log could not be loaded.',
                    'Nie udało się wczytać dziennika audytu.',
                  ),
                  onRetry: _load,
                )
              : _loading && _entries.isEmpty
              ? Center(
                  child: Semantics(
                    label: copy.text(
                      'Loading audit log',
                      'Wczytywanie dziennika audytu',
                    ),
                    child: const CircularProgressIndicator(),
                  ),
                )
              : _entries.isEmpty
              ? StaffEmptyState(
                  message: copy.text(
                    'No entries for this filter.',
                    'Brak wpisów dla wybranego filtra.',
                  ),
                )
              : ListView.separated(
                  itemCount: _entries.length + (_cursor == null ? 0 : 1),
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    if (index >= _entries.length) {
                      return Center(
                        child: OutlinedButton(
                          onPressed: _loading ? null : () => _load(more: true),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(
                              color: StaffCenterStyle.border,
                            ),
                          ),
                          child: Text(copy.text('Load more', 'Wczytaj więcej')),
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
                                  localizedStaffAuditAction(copy, entry.action),
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
                                      copy.text(
                                        'by ${entry.actorRole}',
                                        'przez: ${localizedStaffRole(copy, entry.actorRole!)}',
                                      ),
                                    if (entry.targetType != null)
                                      copy.text(
                                        'on ${entry.targetType} ${entry.targetId ?? ''}',
                                        'cel: ${entry.targetType} ${entry.targetId ?? ''}',
                                      ),
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
                            staffStamp(copy, entry.createdAt),
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

String _localizedAuditFilter(
  AppLocalizations copy,
  String? value,
  String english,
) => switch (value) {
  null => copy.text(english, 'Wszystko'),
  'assign_user_role' => copy.text(english, 'Zmiany ról'),
  'communication_mute' => copy.text(english, 'Wyciszenia'),
  'ban_user' => copy.text(english, 'Blokady'),
  'security_alert_non_owner_super_admin' => copy.text(
    english,
    'Alerty bezpieczeństwa',
  ),
  'denied_sanction_attempt' => copy.text(english, 'Odrzucone próby'),
  _ => english,
};
