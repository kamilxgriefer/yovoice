import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_audit_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/data/staff_directory_service.dart';
import 'package:yovoice/features/staff/data/staff_overview_service.dart';
import 'package:yovoice/features/staff/presentation/screens/user_management_screen.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_operations_sections.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_overview_section.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_section_shared.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_users_section.dart';

/// The Staff Center — one screen, seven real sections, each rendered
/// only when the SERVER-derived capability that backs it exists:
///
///   Overview, Users, Staff & Roles, Audit Log   owner
///   Reports, Sanctions                          moderation tiers
///   Rooms & Spaces                              room-moderation tiers
///
/// Capabilities are re-verified ON MOUNT rather than trusted from
/// whoever pushed the route; every privileged action inside re-verifies
/// again server-side. An account with no staff sections sees the same
/// refusal it always did.
class StaffCenterScreen extends StatefulWidget {
  const StaffCenterScreen({
    this.capabilityService,
    this.directoryService,
    this.overviewService,
    this.auditService,
    this.moderationService,
    this.roomService,
    this.lookup,
    this.functions,
    this.firestore,
    this.currentUid,
    super.key,
  });

  final StaffCapabilityService? capabilityService;
  final StaffDirectoryService? directoryService;
  final StaffOverviewService? overviewService;
  final StaffAuditService? auditService;
  final ModerationService? moderationService;
  final RoomService? roomService;
  final StaffUserLookup? lookup;
  final FirebaseFunctions? functions;
  final FirebaseFirestore? firestore;

  /// Injected in tests; production reads the signed-in session.
  final String? currentUid;

  @override
  State<StaffCenterScreen> createState() => _StaffCenterScreenState();
}

enum StaffSection {
  overview('Overview', Icons.space_dashboard_rounded),
  users('Users', Icons.people_alt_rounded),
  reports('Reports', Icons.flag_rounded),
  rooms('Rooms & Spaces', Icons.podcasts_rounded),
  sanctions('Sanctions', Icons.gavel_rounded),
  staffRoles('Staff & Roles', Icons.badge_rounded),
  audit('Audit Log', Icons.receipt_long_rounded);

  const StaffSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _StaffCenterScreenState extends State<StaffCenterScreen> {
  StaffCapabilities? _capabilities;
  bool _loading = true;

  StaffSection _section = StaffSection.overview;
  String _usersFilter = 'all';
  String? _auditAction;

  // Remounts Users when a navigation asks for a fresh filter.
  int _usersEpoch = 0;
  int _auditEpoch = 0;

  String get _currentUid {
    if (widget.currentUid != null) return widget.currentUid!;
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    (widget.capabilityService ?? StaffCapabilityService())
        .load(refresh: true)
        .then((capabilities) {
          if (mounted) {
            setState(() {
              _capabilities = capabilities;
              _loading = false;
              _section = _visibleSections(capabilities).firstOrNull ??
                  StaffSection.overview;
            });
          }
        })
        .catchError((_) {
          if (mounted) {
            setState(() {
              _capabilities = StaffCapabilities.none;
              _loading = false;
            });
          }
        });
  }

  /// Which sections THIS account's server-derived capabilities back.
  List<StaffSection> _visibleSections(StaffCapabilities caps) => [
    if (caps.manageRoles) StaffSection.overview,
    if (caps.manageRoles) StaffSection.users,
    if (caps.handleAssignedReports) StaffSection.reports,
    if (caps.hasRoomModeration) StaffSection.rooms,
    if (caps.warnUsers || caps.suspendUsers) StaffSection.sanctions,
    if (caps.manageRoles) StaffSection.staffRoles,
    if (caps.fullAuditAccess) StaffSection.audit,
  ];

  void _openUsers(String filter) {
    setState(() {
      _usersFilter = filter;
      _usersEpoch += 1;
      _section = StaffSection.users;
    });
  }

  void _openAudit({String? action}) {
    setState(() {
      _auditAction = action;
      _auditEpoch += 1;
      _section = StaffSection.audit;
    });
  }

  Future<void> _openUserByUid(String uid) async {
    final capabilities = _capabilities ?? StaffCapabilities.none;
    try {
      final page = await (widget.directoryService ?? StaffDirectoryService())
          .search(query: uid);
      final user = page.users.where((row) => row.uid == uid).firstOrNull;
      if (user == null || !mounted) return;
      await showUserDetailDrawer(
        context,
        user: user,
        capabilities: capabilities,
        currentUid: _currentUid,
        lookup: widget.lookup,
        auditService: widget.auditService,
        functions: widget.functions,
        firestore: widget.firestore,
      );
    } on DirectorySearchException {
      // The row stays where it was; the section's own errors handle the
      // visible path.
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = _capabilities ?? StaffCapabilities.none;
    final sections = _visibleSections(capabilities);

    return Scaffold(
      backgroundColor: StaffCenterStyle.background,
      appBar: AppBar(
        backgroundColor: StaffCenterStyle.background,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Staff Center',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : sections.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'The Staff Center is reserved for the application owner '
                  'and staff.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFA69CAF), fontSize: 14),
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _rail(sections),
                      const VerticalDivider(
                        width: 1,
                        color: StaffCenterStyle.border,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
                          child: _sectionBody(capabilities),
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _tabs(sections),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        child: _sectionBody(capabilities),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _rail(List<StaffSection> sections) {
    return Container(
      width: 218,
      color: const Color(0xFF0B0813),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
        children: [
          for (final section in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: _section == section
                    ? StaffCenterStyle.accent.withValues(alpha: .16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _section = section),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          section.icon,
                          size: 17,
                          color: _section == section
                              ? const Color(0xFFD3A5FF)
                              : StaffCenterStyle.muted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            section.label,
                            style: TextStyle(
                              color: _section == section
                                  ? Colors.white
                                  : StaffCenterStyle.muted,
                              fontSize: 13,
                              fontWeight: _section == section
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabs(List<StaffSection> sections) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: StaffCenterStyle.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final section in sections) ...[
              ChoiceChip(
                avatar: Icon(
                  section.icon,
                  size: 14,
                  color: _section == section
                      ? Colors.white
                      : StaffCenterStyle.muted,
                ),
                label: Text(section.label),
                selected: _section == section,
                onSelected: (_) => setState(() => _section = section),
                labelStyle: TextStyle(
                  color: _section == section
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
    );
  }

  Widget _sectionBody(StaffCapabilities capabilities) {
    switch (_section) {
      case StaffSection.overview:
        return StaffOverviewSection(
          overviewService: widget.overviewService,
          onOpenUsers: _openUsers,
          onOpenReports: () =>
              setState(() => _section = StaffSection.reports),
          onOpenRooms: () => setState(() => _section = StaffSection.rooms),
          onOpenSanctions: () =>
              setState(() => _section = StaffSection.sanctions),
          onOpenStaffRoles: () =>
              setState(() => _section = StaffSection.staffRoles),
          onOpenAudit: _openAudit,
        );
      case StaffSection.users:
        return StaffUsersSection(
          key: ValueKey('users-$_usersEpoch-$_usersFilter'),
          capabilities: capabilities,
          currentUid: _currentUid,
          initialFilter: _usersFilter,
          directoryService: widget.directoryService,
          auditService: widget.auditService,
          lookup: widget.lookup,
          functions: widget.functions,
          firestore: widget.firestore,
        );
      case StaffSection.reports:
        return StaffReportsSection(
          moderationService: widget.moderationService,
        );
      case StaffSection.rooms:
        return StaffRoomsSection(
          capabilities: capabilities,
          roomService: widget.roomService,
        );
      case StaffSection.sanctions:
        return StaffSanctionsSection(
          auditService: widget.auditService,
          onOpenUser: _openUserByUid,
        );
      case StaffSection.staffRoles:
        return StaffRolesSection(
          directoryService: widget.directoryService,
          auditService: widget.auditService,
          onOpenUser: (user) async {
            await showUserDetailDrawer(
              context,
              user: user,
              capabilities: capabilities,
              currentUid: _currentUid,
              lookup: widget.lookup,
              auditService: widget.auditService,
              functions: widget.functions,
              firestore: widget.firestore,
            );
          },
        );
      case StaffSection.audit:
        return StaffAuditSection(
          key: ValueKey('audit-$_auditEpoch-${_auditAction ?? ''}'),
          initialAction: _auditAction,
          auditService: widget.auditService,
        );
    }
  }
}
