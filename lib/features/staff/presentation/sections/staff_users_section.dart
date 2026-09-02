import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/role_identity.dart';
import 'package:yovoice/features/staff/data/staff_audit_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/data/staff_directory_service.dart';
import 'package:yovoice/features/staff/presentation/screens/user_management_screen.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_section_shared.dart';
import 'package:yovoice/features/staff/presentation/staff_localized_copy.dart';
import 'package:yovoice/features/staff/presentation/widgets/user_actions_menu.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/identity/decorated_user_avatar.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/vip_badge.dart';

/// Users — the Staff Center's primary section: the owner's search over
/// the server-maintained directory, filters, a paged result list, and
/// the detail drawer with every safe contextual action.
class StaffUsersSection extends StatefulWidget {
  const StaffUsersSection({
    required this.capabilities,
    required this.currentUid,
    this.initialFilter = 'all',
    this.directoryService,
    this.auditService,
    this.lookup,
    this.functions,
    this.firestore,
    super.key,
  });

  final StaffCapabilities capabilities;
  final String currentUid;
  final String initialFilter;
  final StaffDirectoryService? directoryService;
  final StaffAuditService? auditService;
  final StaffUserLookup? lookup;
  final FirebaseFunctions? functions;
  final FirebaseFirestore? firestore;

  static const filters = <(String, String)>[
    ('all', 'All'),
    ('staff', 'Staff'),
    ('vip', 'VIP'),
    ('restricted', 'Restricted'),
    ('banned', 'Banned'),
    ('recent', 'Recently joined'),
  ];

  @override
  State<StaffUsersSection> createState() => _StaffUsersSectionState();
}

class _StaffUsersSectionState extends State<StaffUsersSection> {
  late final StaffDirectoryService _directory =
      widget.directoryService ?? StaffDirectoryService();

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  int _generation = 0;

  late String _filter = widget.initialFilter;
  List<DirectoryUser> _results = const [];
  String? _nextCursor;
  bool _loading = false;
  bool _loadingMore = false;
  DirectorySearchException? _error;
  bool _shortQueryHint = false;

  @override
  void initState() {
    super.initState();
    // The section opens showing real accounts, not an empty pane.
    _runSearch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _query => _searchController.text.trim();

  bool get _queryIsNameLike =>
      _query.isNotEmpty && !_query.contains('@') || _query.startsWith('@');

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    final stripped = _query.startsWith('@') ? _query.substring(1) : _query;
    // A 1-character name is a hint, not an error and not a request.
    if (_query.isNotEmpty && _queryIsNameLike && stripped.trim().length < 2) {
      setState(() => _shortQueryHint = true);
      return;
    }
    if (_shortQueryHint) setState(() => _shortQueryHint = false);
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  void _onSubmitted(String _) {
    _debounce?.cancel();
    _runSearch();
  }

  Future<void> _runSearch() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _directory.search(query: _query, filter: _filter);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = page.users;
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } on DirectorySearchException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _directory.search(
        query: _query,
        filter: _filter,
        cursor: cursor,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = [..._results, ...page.users];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } on DirectorySearchException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingMore = false;
        _error = error;
      });
    }
  }

  void _clear() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _filter = 'all';
      _shortQueryHint = false;
    });
    _runSearch();
  }

  /// Refreshes ONE row in place after a drawer action, keeping the rest
  /// of the list, the filters and the scroll position untouched.
  Future<void> _refreshRow(String uid) async {
    PublicIdentityRepository.instance.invalidate(uid);
    try {
      final page = await _directory.search(query: uid);
      if (!mounted) return;
      final fresh = page.users.where((row) => row.uid == uid).firstOrNull;
      if (fresh == null) return;
      setState(() {
        _results = [
          for (final row in _results)
            if (row.uid == uid) fresh else row,
        ];
      });
    } on DirectorySearchException {
      // The row keeps its previous data; the next full search refreshes.
    }
  }

  Future<void> _openDetail(DirectoryUser user) async {
    await showUserDetailDrawer(
      context,
      user: user,
      capabilities: widget.capabilities,
      currentUid: widget.currentUid,
      lookup: widget.lookup,
      auditService: widget.auditService,
      functions: widget.functions,
      firestore: widget.firestore,
      onUserChanged: _refreshRow,
    );
  }

  String _errorMessage(DirectorySearchException error) {
    final copy = AppLocalizations.of(context);
    return switch (error.kind) {
      DirectorySearchErrorKind.permission => copy.text(
        'User search is reserved for the application owner.',
        'Wyszukiwanie użytkowników jest dostępne wyłącznie dla właściciela aplikacji.',
      ),
      DirectorySearchErrorKind.network => copy.text(
        'The server could not be reached. Check your connection.',
        'Nie udało się połączyć z serwerem. Sprawdź połączenie.',
      ),
      DirectorySearchErrorKind.invalidQuery => copy.text(
        'Enter a valid name, username, email address or account ID.',
        'Zapytanie jest nieprawidłowe. Sprawdź wpisane dane.',
      ),
      DirectorySearchErrorKind.server => copy.text(
        'The search failed on the server. Try again.',
        'Wyszukiwanie na serwerze nie powiodło się. Spróbuj ponownie.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaffSectionHeader(
          title: copy.text('Users', 'Użytkownicy'),
          subtitle: copy.text(
            'Search by name, @username, email or uid — case and spacing never matter. Every action here is verified server-side.',
            'Szukaj po nazwie, @pseudonimie, adresie e-mail lub UID — wielkość liter i odstępy nie mają znaczenia. Każde działanie jest weryfikowane na serwerze.',
          ),
        ),
        _searchField(),
        const SizedBox(height: 10),
        _filterChips(),
        const SizedBox(height: 12),
        Expanded(child: _resultsArea()),
      ],
    );
  }

  Widget _searchField() {
    final copy = AppLocalizations.of(context);
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      onChanged: _onQueryChanged,
      onSubmitted: _onSubmitted,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: copy.text(
          'Search users — Sieeema, @sieeema, email or uid…',
          'Szukaj — Sieeema, @sieeema, e-mail lub UID…',
        ),
        hintStyle: const TextStyle(color: StaffCenterStyle.faint, fontSize: 14),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: StaffCenterStyle.muted,
        ),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: copy.text('Clear', 'Wyczyść'),
                onPressed: _clear,
                icon: const Icon(
                  Icons.close_rounded,
                  color: StaffCenterStyle.muted,
                ),
              ),
        filled: true,
        fillColor: StaffCenterStyle.surfaceRaised,
        helperText: _shortQueryHint
            ? copy.text(
                'Type at least 2 characters to search by name.',
                'Wpisz co najmniej 2 znaki, aby wyszukać po nazwie.',
              )
            : null,
        helperStyle: const TextStyle(
          color: StaffCenterStyle.warn,
          fontSize: 11.5,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: StaffCenterStyle.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: StaffCenterStyle.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: StaffCenterStyle.accent),
        ),
      ),
    );
  }

  Widget _filterChips() {
    final copy = AppLocalizations.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (value, label) in StaffUsersSection.filters) ...[
            ChoiceChip(
              label: Text(_localizedUserFilter(copy, value, label)),
              selected: _filter == value,
              onSelected: (_) {
                setState(() => _filter = value);
                _runSearch();
              },
              labelStyle: TextStyle(
                color: _filter == value ? Colors.white : StaffCenterStyle.muted,
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
    );
  }

  Widget _resultsArea() {
    final copy = AppLocalizations.of(context);
    final error = _error;
    if (_loading) {
      return Center(
        child: Semantics(
          label: copy.text('Searching users', 'Wyszukiwanie użytkowników'),
          child: const CircularProgressIndicator(),
        ),
      );
    }
    if (error != null) {
      return StaffErrorState(
        message: _errorMessage(error),
        onRetry: _runSearch,
        onClear: _clear,
      );
    }
    if (_results.isEmpty) {
      return StaffEmptyState(
        icon: Icons.person_search_rounded,
        message: _query.isEmpty
            ? copy.text(
                'No accounts match this filter yet.',
                'Żadne konto nie pasuje jeszcze do tego filtra.',
              )
            : copy.text(
                'No account matches "$_query". Uid, email, @username, or a name of at least two characters all work.',
                'Nie znaleziono konta pasującego do „$_query”. Możesz użyć UID, adresu e-mail, @pseudonimu albo nazwy zawierającej co najmniej dwa znaki.',
              ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizedStaffResultCount(
            copy,
            _results.length,
            moreAvailable: _nextCursor != null,
          ),
          style: const TextStyle(
            color: StaffCenterStyle.faint,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: _results.length + (_nextCursor == null ? 0 : 1),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index >= _results.length) {
                return Center(
                  child: OutlinedButton(
                    onPressed: _loadingMore ? null : _loadMore,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: StaffCenterStyle.border),
                    ),
                    child: _loadingMore
                        ? Semantics(
                            label: copy.text(
                              'Loading more users',
                              'Wczytywanie kolejnych użytkowników',
                            ),
                            child: const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Text(copy.text('Load more', 'Wczytaj więcej')),
                  ),
                );
              }
              final user = _results[index];
              return _UserRow(user: user, onView: () => _openDetail(user));
            },
          ),
        ),
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user, required this.onView});

  final DirectoryUser user;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return StaffPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacksActions = constraints.maxWidth < 560;
          final showsUid = constraints.maxWidth >= 700;
          final identity = Expanded(child: _identity(copy, showsUid: showsUid));

          if (stacksActions) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_avatar(), const SizedBox(width: 12), identity],
                ),
                const SizedBox(height: 9),
                Align(
                  alignment: Alignment.centerRight,
                  child: _viewButton(copy),
                ),
              ],
            );
          }

          return Row(
            children: [
              _avatar(),
              const SizedBox(width: 12),
              identity,
              const SizedBox(width: 8),
              _viewButton(copy),
            ],
          );
        },
      ),
    );
  }

  Widget _avatar() => DecoratedUserAvatar(
    radius: 21,
    photoUrl: user.photoUrl,
    displayName: user.displayName,
  );

  Widget _identity(AppLocalizations copy, {required bool showsUid}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              user.displayName.isEmpty
                  ? copy.text('YO Voice user', 'Użytkownik YO Voice')
                  : user.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            StaffOfficialRoleBadge(
              role: user.staffRole,
              variant: IdentityBadgeVariant.compact,
            ),
            if (user.isVip)
              const VipBadge(variant: IdentityBadgeVariant.compact),
            AccountStatusChip(status: user.status),
          ],
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 10,
          runSpacing: 3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (user.username.isNotEmpty)
              Text(
                '@${user.username}',
                style: const TextStyle(
                  color: StaffCenterStyle.muted,
                  fontSize: 11.5,
                ),
              ),
            if (showsUid) CopyableUid(uid: user.uid),
            if (user.createdAt != null)
              Text(
                copy
                    .text('joined {time}', 'Dołączenie: {time}')
                    .replaceAll('{time}', staffStamp(copy, user.createdAt)),
                style: const TextStyle(
                  color: StaffCenterStyle.faint,
                  fontSize: 10.5,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _viewButton(AppLocalizations copy) {
    return FilledButton.tonal(
      onPressed: onView,
      style: FilledButton.styleFrom(
        backgroundColor: StaffCenterStyle.surfaceRaised,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 44),
      ),
      child: Text(
        copy.text('View', 'Wyświetl'),
        style: const TextStyle(fontSize: 12.5),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The user detail drawer
// ---------------------------------------------------------------------------

Future<void> showUserDetailDrawer(
  BuildContext context, {
  required DirectoryUser user,
  required StaffCapabilities capabilities,
  required String currentUid,
  StaffUserLookup? lookup,
  StaffAuditService? auditService,
  FirebaseFunctions? functions,
  FirebaseFirestore? firestore,
  Future<void> Function(String uid)? onUserChanged,
}) {
  final copy = AppLocalizations.of(context);
  final width = MediaQuery.sizeOf(context).width;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: copy.text(
      'Close user detail',
      'Zamknij szczegóły użytkownika',
    ),
    barrierColor: Colors.black.withValues(alpha: .6),
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: width < 640 ? width : 560,
        height: double.infinity,
        child: UserDetailDrawer(
          user: user,
          capabilities: capabilities,
          currentUid: currentUid,
          lookup: lookup,
          auditService: auditService,
          functions: functions,
          firestore: firestore,
          onUserChanged: onUserChanged,
        ),
      ),
    ),
  );
}

class UserDetailDrawer extends StatefulWidget {
  const UserDetailDrawer({
    required this.user,
    required this.capabilities,
    required this.currentUid,
    this.lookup,
    this.auditService,
    this.functions,
    this.firestore,
    this.onUserChanged,
    super.key,
  });

  final DirectoryUser user;
  final StaffCapabilities capabilities;
  final String currentUid;
  final StaffUserLookup? lookup;
  final StaffAuditService? auditService;
  final FirebaseFunctions? functions;
  final FirebaseFirestore? firestore;
  final Future<void> Function(String uid)? onUserChanged;

  @override
  State<UserDetailDrawer> createState() => _UserDetailDrawerState();
}

class _UserDetailDrawerState extends State<UserDetailDrawer> {
  late final StaffUserLookup _lookup = widget.lookup ?? StaffUserLookup();
  late final StaffAuditService _audit =
      widget.auditService ?? StaffAuditService();

  FirebaseFunctions get _functions =>
      widget.functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
  FirebaseFirestore get _firestore =>
      widget.firestore ?? FirebaseFirestore.instance;

  late DirectoryUser _user = widget.user;
  ManagedUser? _authoritative;
  bool _authoritativeFailed = false;
  List<StaffAuditEntry>? _history;
  bool _historyFailed = false;
  List<({String id, String name, bool isLive})>? _hostedRooms;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  bool get _isSelf => _user.uid == widget.currentUid;

  String _displayName(AppLocalizations copy) => _user.displayName.isEmpty
      ? copy.text('YO Voice user', 'Użytkownik YO Voice')
      : _user.displayName;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    // Authoritative account state, straight from the server's own view.
    _lookup
        .lookup(_user.uid)
        .then((managed) {
          if (mounted) setState(() => _authoritative = managed);
        })
        .catchError((_) {
          if (mounted) setState(() => _authoritativeFailed = true);
        });
    // Moderation, sanction and role history for THIS account.
    _audit
        .list(targetId: _user.uid, limit: 20)
        .then((page) {
          if (mounted) setState(() => _history = page.entries);
        })
        .catchError((_) {
          if (mounted) setState(() => _historyFailed = true);
        });
    // Public rooms this account hosts — the query mirrors what any
    // signed-in client may already read.
    _firestore
        .collection('rooms')
        .where('hostId', isEqualTo: _user.uid)
        .where('visibility', isEqualTo: 'public')
        .limit(5)
        .get()
        .then((snapshot) {
          if (!mounted) return;
          setState(
            () => _hostedRooms = [
              for (final doc in snapshot.docs)
                (
                  id: doc.id,
                  name: (doc.data()['name'] as String?)?.trim() ?? '',
                  isLive: doc.data()['isLive'] == true,
                ),
            ],
          );
        })
        .catchError((_) {
          if (mounted) setState(() => _hostedRooms = const []);
        });
  }

  Future<void> _afterChange(String note) async {
    setState(() {
      _message = note;
      _messageIsError = false;
    });
    await widget.onUserChanged?.call(_user.uid);
    // Re-pull the row's own view of the account too.
    try {
      final refreshed = await StaffDirectoryService(
        functions: widget.functions,
      ).search(query: _user.uid);
      final fresh = refreshed.users
          .where((u) => u.uid == _user.uid)
          .firstOrNull;
      if (fresh != null && mounted) setState(() => _user = fresh);
    } on DirectorySearchException {
      // Keep showing what we have; the section refresh already ran.
    }
    _authoritative = null;
    _authoritativeFailed = false;
    _history = null;
    _historyFailed = false;
    _loadDetail();
  }

  /// A reason-required confirmation used by every privileged action.
  Future<String?> _confirmWithReason({
    required String title,
    required String description,
    required String confirmLabel,
    Color confirmColor = StaffCenterStyle.accent,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: title,
        description: description,
        confirmLabel: confirmLabel,
        confirmColor: confirmColor,
      ),
    );
  }

  Future<void> _changeRole() async {
    final authoritative = _authoritative;
    if (authoritative == null || _busy) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => _RolePickerDialog(currentRole: authoritative.role),
    );
    if (selected == null || selected == authoritative.role || !mounted) return;

    final copy = AppLocalizations.of(context);
    final displayName = _displayName(copy);
    final roleLabel = selected == 'user'
        ? copy.text('an ordinary user', 'zwykły użytkownik')
        : localizedStaffRole(copy, selected);
    final reason = await _confirmWithReason(
      title: copy.text('Change role', 'Zmień rolę'),
      description: copy.text(
        '$displayName: ${authoritative.role} → $selected. The change is verified and recorded server-side.',
        '$displayName: ${localizedStaffRole(copy, authoritative.role)} → ${localizedStaffRole(copy, selected)}. Zmiana zostanie zweryfikowana i zapisana na serwerze.',
      ),
      confirmLabel: copy.text('Confirm change', 'Potwierdź zmianę'),
    );
    if (reason == null || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _functions
          .httpsCallable('assignUserRole')
          .call<Map<String, dynamic>>({
            'uid': _user.uid,
            'role': selected,
            'reason': reason,
            // The stale-result guard: the role this drawer BELIEVES the
            // account holds; the server refuses if it moved.
            'expectedRole': authoritative.role,
          });
      if (!mounted) return;
      await _afterChange(
        copy.text(
          '$displayName is now $roleLabel.',
          '$displayName ma teraz rolę: $roleLabel.',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = _readable(error);
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setBan(bool banned) async {
    if (_busy) return;
    final copy = AppLocalizations.of(context);
    final displayName = _displayName(copy);
    final reason = await _confirmWithReason(
      title: banned
          ? copy.text('Ban account', 'Zablokuj konto')
          : copy.text('Lift ban', 'Zdejmij blokadę'),
      description: banned
          ? copy.text(
              '$displayName will be banned. Their session tokens are revoked server-side.',
              'Konto $displayName zostanie zablokowane, a tokeny sesji zostaną unieważnione na serwerze.',
            )
          : copy.text(
              '$displayName will be unbanned and may sign in again.',
              'Blokada konta $displayName zostanie zdjęta. Użytkownik będzie mógł zalogować się ponownie.',
            ),
      confirmLabel: banned
          ? copy.text('Ban', 'Zablokuj')
          : copy.text('Unban', 'Odblokuj'),
      confirmColor: banned ? StaffCenterStyle.bad : StaffCenterStyle.good,
    );
    if (reason == null || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _functions.httpsCallable('setUserBan').call<Map<String, dynamic>>({
        'uid': _user.uid,
        'banned': banned,
        'reason': reason,
      });
      if (!mounted) return;
      await _afterChange(
        banned
            ? copy.text(
                '$displayName is banned.',
                'Konto $displayName zostało zablokowane.',
              )
            : copy.text(
                'The ban on $displayName was lifted.',
                'Zdjęto blokadę konta $displayName.',
              ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = _readable(error);
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _readable(Object error) {
    final copy = AppLocalizations.of(context);
    return friendlyErrorMessage(
      error,
      copy: copy,
      fallback: copy.text(
        'That action could not be completed. Please try again.',
        'Nie udało się wykonać działania. Spróbuj ponownie.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final capabilities = widget.capabilities;
    return Material(
      color: StaffCenterStyle.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      copy.text('User detail', 'Szczegóły użytkownika'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: copy.text('Close', 'Zamknij'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                children: [
                  _identityHeader(),
                  if (_message != null) ...[
                    const SizedBox(height: 10),
                    _messageBanner(),
                  ],
                  const SizedBox(height: 14),
                  _authoritativePanel(),
                  const SizedBox(height: 12),
                  if (!_isSelf && capabilities.manageRoles) ...[
                    _ownerActionsPanel(),
                    const SizedBox(height: 12),
                  ],
                  if (_isSelf)
                    StaffPanel(
                      child: Text(
                        copy.text(
                          'This is your own account. The owner cannot target themselves — protections apply server-side too.',
                          'To Twoje konto. Właściciel nie może wykonywać działań wobec siebie — zabezpieczenia obowiązują również na serwerze.',
                        ),
                        style: const TextStyle(
                          color: StaffCenterStyle.muted,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _hostedRoomsPanel(),
                  const SizedBox(height: 12),
                  _historyPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identityHeader() {
    final copy = AppLocalizations.of(context);
    return StaffPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedUserAvatar(
            radius: 30,
            photoUrl: _user.photoUrl,
            displayName: _user.displayName,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _user.displayName.isEmpty
                      ? copy.text('YO Voice user', 'Użytkownik YO Voice')
                      : _user.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (_user.username.isNotEmpty)
                  Text(
                    '@${_user.username}',
                    style: const TextStyle(
                      color: StaffCenterStyle.muted,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StaffOfficialRoleBadge(
                      role: _user.staffRole,
                      variant: IdentityBadgeVariant.compact,
                    ),
                    if (_user.isVip)
                      const VipBadge(variant: IdentityBadgeVariant.compact),
                    AccountStatusChip(status: _user.status),
                  ],
                ),
                const SizedBox(height: 7),
                CopyableUid(uid: _user.uid),
              ],
            ),
          ),
          if (!_isSelf)
            UserActionsMenu(
              targetUid: _user.uid,
              targetName: _user.displayName.isEmpty
                  ? copy.text('this user', 'ten użytkownik')
                  : _user.displayName,
              capabilities: widget.capabilities,
              currentUid: widget.currentUid,
              functions: widget.functions,
              firestore: widget.firestore,
              onChanged: () => _afterChange(copy.text('Done.', 'Gotowe.')),
            ),
        ],
      ),
    );
  }

  Widget _messageBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: (_messageIsError ? StaffCenterStyle.bad : StaffCenterStyle.good)
            .withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              (_messageIsError ? StaffCenterStyle.bad : StaffCenterStyle.good)
                  .withValues(alpha: .4),
        ),
      ),
      child: Text(
        _message!,
        style: TextStyle(
          color: _messageIsError ? StaffCenterStyle.bad : StaffCenterStyle.good,
          fontSize: 12.5,
        ),
      ),
    );
  }

  Widget _authoritativePanel() {
    final copy = AppLocalizations.of(context);
    final authoritative = _authoritative;
    return StaffPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StaffPanelTitle(
            title: copy.text(
              'Authoritative status',
              'Stan potwierdzony przez serwer',
            ),
          ),
          if (authoritative == null && !_authoritativeFailed)
            Text(
              copy.text('Loading from the server…', 'Wczytywanie z serwera…'),
              style: const TextStyle(
                color: StaffCenterStyle.faint,
                fontSize: 12,
              ),
            )
          else if (_authoritativeFailed)
            Text(
              copy.text(
                'The authoritative record could not be loaded. Actions stay available and are re-verified server-side.',
                'Nie udało się wczytać potwierdzonego rekordu. Działania pozostają dostępne i będą ponownie zweryfikowane na serwerze.',
              ),
              style: const TextStyle(
                color: StaffCenterStyle.warn,
                fontSize: 12,
              ),
            )
          else ...[
            _factRow(
              copy.text('Role (server record)', 'Rola (rekord serwera)'),
              authoritative!.role == 'user'
                  ? copy.text(
                      'user (ordinary account)',
                      'użytkownik (zwykłe konto)',
                    )
                  : localizedStaffRole(copy, authoritative.role),
            ),
            _factRow(
              copy.text('VIP entitlement', 'Uprawnienie VIP'),
              authoritative.isVip
                  ? copy.text('active', 'aktywne')
                  : copy.text('none', 'brak'),
            ),
            _factRow(
              copy.text('Account', 'Konto'),
              authoritative.banned
                  ? copy.text('BANNED', 'ZABLOKOWANE')
                  : copy.text('in good standing', 'bez ograniczeń'),
            ),
            if (_user.restricted)
              _factRow(
                copy.text('Restriction', 'Ograniczenie'),
                copy.text(
                  'communication mute active',
                  'aktywne wyciszenie komunikacji',
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _factRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                color: StaffCenterStyle.faint,
                fontSize: 11.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ownerActionsPanel() {
    final copy = AppLocalizations.of(context);
    final banned = _authoritative?.banned ?? _user.banned;
    return StaffPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StaffPanelTitle(
            title: copy.text('Owner actions', 'Działania właściciela'),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy || _authoritative == null ? null : _changeRole,
                icon: const Icon(Icons.badge_rounded, size: 16),
                label: Text(
                  copy.text('Change staff role', 'Zmień rolę zespołu'),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: StaffCenterStyle.border),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _setBan(!banned),
                icon: Icon(
                  banned ? Icons.lock_open_rounded : Icons.gavel_rounded,
                  size: 16,
                ),
                label: Text(
                  banned
                      ? copy.text('Unban account', 'Odblokuj konto')
                      : copy.text('Ban account', 'Zablokuj konto'),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: banned
                      ? StaffCenterStyle.good
                      : StaffCenterStyle.bad,
                  side: const BorderSide(color: StaffCenterStyle.border),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            copy.text(
              'Warnings, mutes and lifting restrictions live in the ••• menu above — the same tiered menu every staff surface uses. VIP is an entitlement and is never touched by a role change.',
              'Ostrzeżenia, wyciszenia i zdejmowanie ograniczeń znajdziesz w menu ••• powyżej — tym samym na każdej powierzchni zespołu. VIP jest uprawnieniem i zmiana roli nigdy go nie modyfikuje.',
            ),
            style: const TextStyle(
              color: StaffCenterStyle.faint,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hostedRoomsPanel() {
    final copy = AppLocalizations.of(context);
    final rooms = _hostedRooms;
    return StaffPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StaffPanelTitle(
            title: copy.text(
              'Public rooms hosted',
              'Prowadzone pokoje publiczne',
            ),
          ),
          if (rooms == null)
            Text(
              copy.text('Loading…', 'Wczytywanie…'),
              style: const TextStyle(
                color: StaffCenterStyle.faint,
                fontSize: 12,
              ),
            )
          else if (rooms.isEmpty)
            Text(
              copy.text('No public rooms.', 'Brak pokojów publicznych.'),
              style: const TextStyle(
                color: StaffCenterStyle.muted,
                fontSize: 12,
              ),
            )
          else
            for (final room in rooms)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(
                      room.isLive
                          ? Icons.podcasts_rounded
                          : Icons.meeting_room_rounded,
                      size: 14,
                      color: room.isLive
                          ? StaffCenterStyle.good
                          : StaffCenterStyle.faint,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        room.name.isEmpty
                            ? copy.text('Room', 'Pokój')
                            : room.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    if (room.isLive)
                      Text(
                        copy.text('LIVE', 'NA ŻYWO'),
                        style: const TextStyle(
                          color: StaffCenterStyle.good,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _historyPanel() {
    final copy = AppLocalizations.of(context);
    final history = _history;
    return StaffPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StaffPanelTitle(
            title: copy.text(
              'Moderation & role history',
              'Historia moderacji i ról',
            ),
          ),
          if (history == null && !_historyFailed)
            Text(
              copy.text('Loading…', 'Wczytywanie…'),
              style: const TextStyle(
                color: StaffCenterStyle.faint,
                fontSize: 12,
              ),
            )
          else if (_historyFailed)
            Text(
              copy.text(
                'History is available to the application owner only.',
                'Historia jest dostępna wyłącznie dla właściciela aplikacji.',
              ),
              style: const TextStyle(
                color: StaffCenterStyle.muted,
                fontSize: 12,
              ),
            )
          else if (history!.isEmpty)
            Text(
              copy.text(
                'No recorded moderation or role events.',
                'Brak zarejestrowanych zdarzeń moderacji lub zmian ról.',
              ),
              style: const TextStyle(
                color: StaffCenterStyle.muted,
                fontSize: 12,
              ),
            )
          else
            for (final entry in history)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            localizedStaffAuditAction(copy, entry.action),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
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
                    if ((entry.details['reason'] as String?)?.isNotEmpty ==
                        true)
                      Text(
                        entry.details['reason'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: StaffCenterStyle.muted,
                          fontSize: 11.5,
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _RolePickerDialog extends StatefulWidget {
  const _RolePickerDialog({required this.currentRole});

  final String currentRole;

  @override
  State<_RolePickerDialog> createState() => _RolePickerDialogState();
}

class _RolePickerDialogState extends State<_RolePickerDialog> {
  late String _selected = widget.currentRole;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: StaffCenterStyle.surface,
      title: Text(
        copy.text('Assign role', 'Przypisz rolę'),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final role in UserManagementScreen.assignableRoles)
              RadioListTile<String>(
                value: role,
                // ignore: deprecated_member_use
                groupValue: _selected,
                // ignore: deprecated_member_use
                onChanged: (value) =>
                    setState(() => _selected = value ?? _selected),
                activeColor: RoleIdentity.colorFor(role),
                title: Text(
                  role == 'user'
                      ? copy.text(
                          'User (no staff role)',
                          'Użytkownik (bez roli zespołu)',
                        )
                      : localizedStaffRole(copy, role),
                  style: TextStyle(
                    color: role == 'user'
                        ? Colors.white
                        : RoleIdentity.colorFor(role),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(copy.text('Cancel', 'Anuluj')),
        ),
        FilledButton(
          onPressed: _selected == widget.currentRole
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: Text(copy.text('Continue', 'Dalej')),
        ),
      ],
    );
  }
}

/// Confirmation with a REQUIRED reason — the shape every privileged
/// action shares.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.description,
    required this.confirmLabel,
    required this.confirmColor,
  });

  final String title;
  final String description;
  final String confirmLabel;
  final Color confirmColor;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: StaffCenterStyle.surface,
      title: Text(
        widget.title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.description,
              style: const TextStyle(
                color: StaffCenterStyle.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              onChanged: (_) => setState(() {}),
              maxLength: 300,
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                labelText: copy.text('Reason (required)', 'Powód (wymagany)'),
                labelStyle: const TextStyle(color: StaffCenterStyle.muted),
                counterStyle: const TextStyle(color: StaffCenterStyle.faint),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(copy.text('Cancel', 'Anuluj')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: widget.confirmColor),
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_reason.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

String _localizedUserFilter(
  AppLocalizations copy,
  String value,
  String english,
) => switch (value) {
  'all' => copy.text(english, 'Wszyscy'),
  'staff' => copy.text(english, 'Zespół'),
  'vip' => copy.text(english, 'VIP'),
  'restricted' => copy.text(english, 'Ograniczone'),
  'banned' => copy.text(english, 'Zablokowane'),
  'recent' => copy.text(english, 'Ostatnio dołączyli'),
  _ => english,
};
