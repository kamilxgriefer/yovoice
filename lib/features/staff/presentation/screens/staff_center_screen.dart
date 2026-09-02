import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';
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
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

/// The Staff Center — one screen, seven real sections, each rendered
/// only when the SERVER-derived capability that backs it exists:
///
///   Overview, Users, Staff & Roles, Audit Log   owner
///   Moderation Center, Sanctions                moderation tiers
///   Rooms & Spaces                              room-moderation tiers
///
/// Capabilities are re-verified ON MOUNT rather than trusted from
/// whoever pushed the route; every privileged action inside re-verifies
/// again server-side. An account with no staff sections sees the same
/// refusal it always did.
class StaffCenterScreen extends StatefulWidget {
  const StaffCenterScreen({
    this.isRootTab = false,
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

  /// True when rendered as the desktop shell's content slot — the shell
  /// owns navigation, so this screen draws NO app bar there and shows a
  /// `Staff tools / Staff Center` context label instead. When pushed as
  /// a route (mobile), the app bar carries Back and Home.
  final bool isRootTab;

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
  overview(Icons.space_dashboard_rounded),
  moderation(Icons.shield_rounded),
  users(Icons.people_alt_rounded),
  rooms(Icons.podcasts_rounded),
  sanctions(Icons.gavel_rounded),
  staffRoles(Icons.badge_rounded),
  audit(Icons.receipt_long_rounded);

  const StaffSection(this.icon);

  final IconData icon;
}

String _localizedSectionLabel(AppLocalizations copy, StaffSection section) =>
    switch (section) {
      StaffSection.overview => copy.text('Overview', 'Przegląd'),
      StaffSection.moderation => copy.text(
        'Moderation Center',
        'Centrum moderacji',
      ),
      StaffSection.users => copy.text('Users', 'Użytkownicy'),
      StaffSection.rooms => copy.text(
        'Rooms & Spaces',
        'Pokoje i przestrzenie',
      ),
      StaffSection.sanctions => copy.text('Sanctions', 'Sankcje'),
      StaffSection.staffRoles => copy.text('Staff & Roles', 'Zespół i role'),
      StaffSection.audit => copy.text('Audit Log', 'Dziennik audytu'),
    };

class _StaffCenterScreenState extends State<StaffCenterScreen> {
  StaffCapabilities? _capabilities;
  bool _loading = true;
  bool _mobileTabsCollapsed = false;

  StaffSection _section = StaffSection.overview;
  String _usersFilter = 'all';
  String? _auditAction;

  // Remounts Users when a navigation asks for a fresh filter.
  int _usersEpoch = 0;
  int _auditEpoch = 0;

  void _selectSection(StaffSection section) {
    setState(() {
      _section = section;
      _mobileTabsCollapsed = false;
    });
  }

  bool _handleMobileScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is! ScrollUpdateNotification ||
        notification.scrollDelta == null) {
      return false;
    }

    final delta = notification.scrollDelta!;
    final shouldCollapse = delta > 2 && notification.metrics.pixels > 24;
    final shouldExpand = delta < -2;
    if (shouldCollapse && !_mobileTabsCollapsed) {
      setState(() => _mobileTabsCollapsed = true);
    } else if (shouldExpand && _mobileTabsCollapsed) {
      setState(() => _mobileTabsCollapsed = false);
    }
    return false;
  }

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
              _section =
                  _visibleSections(capabilities).firstOrNull ??
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
    if (caps.handleAssignedReports) StaffSection.moderation,
    if (caps.manageRoles) StaffSection.users,
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
    final copy = AppLocalizations.of(context);
    final capabilities = _capabilities ?? StaffCapabilities.none;
    final sections = _visibleSections(capabilities);

    // Inside the desktop shell's content slot the shell owns navigation
    // and this screen must not add its own chrome; pushed as a mobile
    // route it carries a real app bar with Back and Home so it is never
    // a navigation dead end.
    final inShellSlot =
        widget.isRootTab && MediaQuery.sizeOf(context).width >= 980;
    final compactNavigation = MediaQuery.sizeOf(context).width < 980;

    final content = Scaffold(
      backgroundColor: StaffCenterStyle.background,
      appBar: inShellSlot
          ? null
          : AppBar(
              backgroundColor: StaffCenterStyle.background,
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
                    Icons.admin_panel_settings_rounded,
                    size: 18,
                    color: Color(0xFFD3A5FF),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      copy.text('Staff Center', 'Centrum zespołu'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                if (compactNavigation && sections.isNotEmpty)
                  PopupMenuButton<StaffSection>(
                    tooltip: copy.text(
                      'Choose Staff Center section',
                      'Wybierz sekcję Centrum zespołu',
                    ),
                    initialValue: _section,
                    onSelected: _selectSection,
                    icon: const Icon(Icons.view_list_rounded),
                    itemBuilder: (context) => [
                      for (final section in sections)
                        PopupMenuItem<StaffSection>(
                          value: section,
                          child: Row(
                            children: [
                              Icon(section.icon, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _localizedSectionLabel(copy, section),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                IconButton(
                  tooltip: copy.text('Home', 'Strona główna'),
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  icon: const Icon(Icons.home_rounded),
                ),
              ],
            ),
      body: ResponsiveContentFrame(
        width: ResponsiveContentWidth.workbench,
        child: _loading
            ? Center(
                child: Semantics(
                  label: copy.text(
                    'Loading Staff Center',
                    'Wczytywanie Centrum zespołu',
                  ),
                  child: const CircularProgressIndicator(),
                ),
              )
            : sections.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    copy.text(
                      'The Staff Center is reserved for the application owner and staff.',
                      'Centrum zespołu jest dostępne wyłącznie dla właściciela aplikacji i uprawnionych członków zespołu.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFA69CAF),
                      fontSize: 14,
                    ),
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
                      AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: _mobileTabsCollapsed
                            ? const SizedBox.shrink(
                                key: ValueKey('staff-mobile-tabs-collapsed'),
                              )
                            : KeyedSubtree(
                                key: const ValueKey(
                                  'staff-mobile-section-tabs',
                                ),
                                child: _tabs(sections),
                              ),
                      ),
                      Expanded(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _handleMobileScroll,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                            child: _sectionBody(capabilities),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }

  Widget _rail(List<StaffSection> sections) {
    final copy = AppLocalizations.of(context);
    return Container(
      width: 218,
      color: const Color(0xFF0B0813),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
        children: [
          // The desktop slot has no app bar; this is where the page says
          // where it lives.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              copy.text(
                'Staff tools / Staff Center',
                'Narzędzia zespołu / Centrum zespołu',
              ),
              style: const TextStyle(
                color: StaffCenterStyle.faint,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
              ),
            ),
          ),
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
                            _localizedSectionLabel(copy, section),
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
    final copy = AppLocalizations.of(context);
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
                label: Text(_localizedSectionLabel(copy, section)),
                selected: _section == section,
                onSelected: (_) => _selectSection(section),
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
              setState(() => _section = StaffSection.moderation),
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
      case StaffSection.moderation:
        final copy = AppLocalizations.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StaffSectionHeader(
              title: copy.text('Moderation Center', 'Centrum moderacji'),
              subtitle: copy.text(
                'Review, claim and resolve community reports without leaving Staff Center.',
                'Przeglądaj, przejmuj i rozwiązuj zgłoszenia społeczności bez opuszczania Centrum zespołu.',
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ModerationCenterScreen(
                embedded: true,
                moderationService: widget.moderationService,
              ),
            ),
          ],
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
