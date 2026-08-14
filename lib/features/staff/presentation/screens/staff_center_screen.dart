import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/role_identity.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/screens/user_management_screen.dart';

/// The Staff Center hub.
///
/// Re-verifies capabilities ON MOUNT rather than trusting whoever pushed
/// the route: a stale More menu, a saved deep link or a forged navigation
/// all land on the same server answer. Only sections with real backing
/// are listed — today that is User Management, owner-only.
class StaffCenterScreen extends StatefulWidget {
  const StaffCenterScreen({this.capabilityService, super.key});

  final StaffCapabilityService? capabilityService;

  @override
  State<StaffCenterScreen> createState() => _StaffCenterScreenState();
}

class _StaffCenterScreenState extends State<StaffCenterScreen> {
  StaffCapabilities? _capabilities;
  bool _loading = true;

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

  @override
  Widget build(BuildContext context) {
    final capabilities = _capabilities ?? StaffCapabilities.none;

    return Scaffold(
      backgroundColor: const Color(0xFF080711),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080711),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Staff Center',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !capabilities.manageRoles
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'The Staff Center is reserved for the application owner.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFA69CAF), fontSize: 14),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF171121),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF3A2C49)),
                  ),
                  // ListTile paints ink on the nearest Material; without
                  // this it asserts under a decorated box.
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                    leading: const Icon(
                      Icons.manage_accounts_rounded,
                      color: RoleIdentity.ownerColor,
                    ),
                    title: const Text(
                      'User Management',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: const Text(
                      'Look up accounts and assign staff roles',
                      style: TextStyle(color: Color(0xFFA69CAF), fontSize: 12),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF7E7490),
                    ),
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const UserManagementScreen(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
