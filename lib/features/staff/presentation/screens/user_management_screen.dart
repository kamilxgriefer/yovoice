import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/role_identity.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/widgets/user_actions_menu.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// What a lookup returned: the authoritative role from the server, VIP
/// separately (it is an entitlement, not a role), and account status.
@immutable
class ManagedUser {
  const ManagedUser({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.role,
    required this.banned,
    required this.isVip,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String username;
  final String role;
  final bool banned;
  final bool isVip;
  final String? photoUrl;
}

/// Exact lookup by uid, email or username.
///
/// uid and email resolve through the getUserRole callable — the
/// authoritative answer, straight from Auth claims plus the user
/// document. A username is first resolved to a uid with one exact-match
/// query, then follows the same path, so every result the screen shows
/// came from the server's own view of the account. VIP is read from the
/// public badge mirror, because a grant document is private to its
/// holder even from this screen.
class StaffUserLookup {
  StaffUserLookup({FirebaseFunctions? functions, FirebaseFirestore? firestore})
    : _functionsOverride = functions,
      _firestoreOverride = firestore;

  final FirebaseFunctions? _functionsOverride;
  final FirebaseFirestore? _firestoreOverride;

  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  Future<ManagedUser?> lookup(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty) return null;

    String? uid;
    String? email;
    if (input.contains('@')) {
      email = input.toLowerCase();
    } else {
      // Try the input as a uid first; fall back to an exact username.
      final direct = await _firestore.collection('users').doc(input).get();
      if (direct.exists) {
        uid = input;
      } else {
        final byUsername = await _firestore
            .collection('users')
            .where('username', isEqualTo: input.toLowerCase())
            .limit(1)
            .get();
        if (byUsername.docs.isEmpty) return null;
        uid = byUsername.docs.single.id;
      }
    }

    final result = await _functions
        .httpsCallable('getUserRole')
        .call<Map<String, dynamic>>({
      'uid': ?uid,
      'email': ?email,
    });
    final data = Map<String, dynamic>.from(result.data);
    final resolvedUid = data['uid'] as String;

    // VIP from the public mirror — derived server-side, readable by GET.
    bool isVip = false;
    try {
      final badge =
          await _firestore.collection('publicBadges').doc(resolvedUid).get();
      isVip = badge.data()?['isVip'] == true;
    } catch (_) {
      isVip = false;
    }

    return ManagedUser(
      uid: resolvedUid,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? (data['displayName'] as String).trim()
          : 'YO Voice user',
      username: (data['username'] as String?)?.trim() ?? '',
      role: data['role'] as String? ?? 'user',
      banned: data['banned'] == true,
      isVip: isVip,
      photoUrl: data['photoUrl'] as String?,
    );
  }
}

/// User Management — the owner's role-assignment surface.
///
/// Reachable only behind the owner-gated Staff Center entry, and every
/// assignment lands on assignUserRole, which re-verifies ownership
/// server-side: this screen could be opened by force and still could not
/// change anything.
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({
    this.lookup,
    this.functions,
    this.currentUid,
    this.capabilityService,
    super.key,
  });

  /// Feeds the shared ••• actions menu beside a looked-up account, so
  /// Staff Center and the profile sheet offer the identical action set.
  final StaffCapabilityService? capabilityService;

  final StaffUserLookup? lookup;
  final FirebaseFunctions? functions;

  /// Injected in tests; production reads the signed-in session.
  final String? currentUid;

  /// Exactly what the server accepts — superAdmin is deliberately not
  /// offered anywhere, that identity belongs to the owner alone.
  static const assignableRoles = <String>[
    'user',
    'guideMaster',
    'support',
    'auditor',
    'moderator',
    'superModerator',
  ];

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF171121);
  static const _border = Color(0xFF3A2C49);
  static const _muted = Color(0xFFA69CAF);

  final _search = TextEditingController();
  late final StaffUserLookup _lookup = widget.lookup ?? StaffUserLookup();

  FirebaseFunctions get _functions =>
      widget.functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  String get _myUid {
    if (widget.currentUid != null) return widget.currentUid!;
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  ManagedUser? _user;
  StaffCapabilities _capabilities = StaffCapabilities.none;
  String? _selectedRole;
  bool _searching = false;
  bool _assigning = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    (widget.capabilityService ?? StaffCapabilityService()).load().then((
      capabilities,
    ) {
      if (mounted) setState(() => _capabilities = capabilities);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _runLookup() async {
    if (_searching) return;
    setState(() {
      _searching = true;
      _message = null;
      _user = null;
      _selectedRole = null;
    });
    try {
      final user = await _lookup.lookup(_search.text);
      if (!mounted) return;
      setState(() {
        _user = user;
        _selectedRole = user?.role;
        if (user == null) {
          _message = 'No account matches that uid, email or username.';
          _messageIsError = true;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = _readable(error);
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  String _readable(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), '')
      .replaceFirst('Exception: ', '');

  Future<void> _confirmAndAssign() async {
    final user = _user;
    final newRole = _selectedRole;
    if (user == null || newRole == null || newRole == user.role || _assigning) {
      return;
    }

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ConfirmRoleDialog(user: user, newRole: newRole),
    );
    if (reason == null || !mounted) return;

    setState(() {
      _assigning = true;
      _message = null;
    });
    try {
      await _functions
          .httpsCallable('assignUserRole')
          .call<Map<String, dynamic>>({
        'uid': user.uid,
        'role': newRole,
        'reason': reason,
        // The stale-result guard: the role this screen BELIEVES the
        // account holds. If it moved, the server refuses and we re-look.
        'expectedRole': user.role,
      });
      if (!mounted) return;
      await _runLookup();
      if (!mounted) return;
      setState(() {
        _message =
            '${user.displayName} is now ${_roleLabel(newRole)}. They may '
            'need to sign in again before the change fully applies.';
        _messageIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = _readable(error);
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  static String _roleLabel(String role) =>
      role == 'user' ? 'an ordinary user' : RoleIdentity.labelFor(role);

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final isSelf = user != null && user.uid == _myUid;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'User Management',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
            children: [
              const Text(
                'Look up an account by exact uid, email or username, then '
                'assign or revoke a staff role. Every change is verified '
                'and recorded server-side.',
                style: TextStyle(color: _muted, fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      enabled: !_searching,
                      onSubmitted: (_) => _runLookup(),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'uid, email or username',
                        labelStyle: const TextStyle(color: Color(0xFFB8AFC2)),
                        filled: true,
                        fillColor: _surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _searching ? null : _runLookup,
                      style: FilledButton.styleFrom(
                        backgroundColor: RoleIdentity.ownerColor,
                      ),
                      child: _searching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Look up'),
                    ),
                  ),
                ],
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: TextStyle(
                    color: _messageIsError
                        ? const Color(0xFFFF9BB0)
                        : const Color(0xFF8CEFC0),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
              if (user != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          UserAvatar(
                            radius: 22,
                            photoUrl: user.photoUrl,
                            displayName: user.displayName,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.displayName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (user.username.isNotEmpty)
                                  Text(
                                    '@${user.username}',
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          _StatusChip(
                            label: user.banned ? 'BANNED' : 'ACTIVE',
                            color: user.banned
                                ? RoleIdentity.ownerColor
                                : const Color(0xFF22C55E),
                          ),
                          // The SAME actions component the profile sheet
                          // uses — one matrix, two surfaces.
                          UserActionsMenu(
                            targetUid: user.uid,
                            targetName: user.displayName,
                            capabilities: _capabilities,
                            currentUid: _myUid,
                            functions: widget.functions,
                            onChanged: _runLookup,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _StatusChip(
                            label: user.role == 'user'
                                ? 'ROLE: USER'
                                : RoleIdentity.labelFor(user.role),
                            color: RoleIdentity.colorFor(user.role),
                          ),
                          // VIP is an entitlement, shown SEPARATELY from
                          // the staff role — assigning a role never
                          // touches it.
                          if (user.isVip)
                            const _StatusChip(
                              label: 'VIP',
                              color: RoleIdentity.vipColor,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        user.uid,
                        style: const TextStyle(
                          color: Color(0xFF746A80),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (isSelf)
                  const Text(
                    'You cannot change your own role.',
                    style: TextStyle(color: _muted, fontSize: 13),
                  )
                else ...[
                  const Text(
                    'Assign role',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final role in UserManagementScreen.assignableRoles)
                    RadioListTile<String>(
                      value: role,
                      // ignore: deprecated_member_use
                      groupValue: _selectedRole,
                      // ignore: deprecated_member_use
                      onChanged: _assigning
                          ? null
                          : (value) => setState(() => _selectedRole = value),
                      activeColor: RoleIdentity.colorFor(role),
                      title: Text(
                        role == 'user'
                            ? 'User (no staff role)'
                            : RoleIdentity.labelFor(role),
                        style: TextStyle(
                          color: role == 'user'
                              ? Colors.white
                              : RoleIdentity.colorFor(role),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      dense: true,
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed:
                          _assigning ||
                              _selectedRole == null ||
                              _selectedRole == user.role
                          ? null
                          : _confirmAndAssign,
                      style: FilledButton.styleFrom(
                        backgroundColor: RoleIdentity.ownerColor,
                      ),
                      child: _assigning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Change role',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: .6,
        ),
      ),
    );
  }
}

/// Old role → new role, in the target's name, with a mandatory reason.
/// Pops the reason on confirm; null on cancel.
class _ConfirmRoleDialog extends StatefulWidget {
  const _ConfirmRoleDialog({required this.user, required this.newRole});

  final ManagedUser user;
  final String newRole;

  @override
  State<_ConfirmRoleDialog> createState() => _ConfirmRoleDialogState();
}

class _ConfirmRoleDialogState extends State<_ConfirmRoleDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _label(String role) =>
      role == 'user' ? 'User' : RoleIdentity.labelFor(role);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF171121),
      title: const Text(
        'Confirm role change',
        style: TextStyle(color: Colors.white, fontSize: 17),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.user.displayName}: '
            '${_label(widget.user.role)} → ${_label(widget.newRole)}',
            style: const TextStyle(
              color: Color(0xFFE4DEED),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLength: 500,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Reason (required)',
              labelStyle: TextStyle(color: Color(0xFFB8AFC2)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _reason.text.trim().length < 3
              ? null
              : () => Navigator.of(context).pop(_reason.text.trim()),
          style: FilledButton.styleFrom(
            backgroundColor: RoleIdentity.ownerColor,
          ),
          child: const Text('Confirm change'),
        ),
      ],
    );
  }
}
