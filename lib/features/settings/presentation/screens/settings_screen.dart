import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/presentation/screens/blocked_users_screen.dart';
import 'package:yovoice/features/marketing/data/services/public_showcase_consent_service.dart';
import 'package:yovoice/features/notifications/presentation/screens/notification_preferences_screen.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_plans_screen.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/features/settings/presentation/screens/profile_visibility_screen.dart';
import 'package:yovoice/features/settings/presentation/screens/two_factor_authentication_screen.dart';
import 'package:yovoice/features/settings/presentation/widgets/message_privacy_settings_tile.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

const _background = Color(0xFF080711);
const _surface = Color(0xFF14101E);
const _surfaceSoft = Color(0xFF17101F);
const _border = Color(0xFF33263F);
const _muted = Color(0xFF9D95AD);
const _primary = Color(0xFFB348FF);
const _danger = Color(0xFFFF6F9C);
const _success = Color(0xFF3FDA8E);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({this.isRootTab = false, super.key});

  /// True when this screen IS the shell's current content (a desktop
  /// content slot) rather than a pushed route — the same flag
  /// FriendsScreen uses, so a root tab never renders a back button that
  /// has nothing to pop.
  final bool isRootTab;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _profileService = ProfileService();
  final _authService = AuthService();
  final _friendService = FriendService();
  final _entitlementService = EntitlementService();
  final _showcaseConsentService = PublicShowcaseConsentService();

  PackageInfo? _packageInfo;
  final Map<Permission, PermissionStatus> _permissionStatus = {};

  bool _sendingReset = false;
  bool _resendingVerification = false;
  bool _refreshingVerification = false;
  bool _clearingCache = false;
  bool _updatingShowcaseConsent = false;

  Future<void> _setShowcaseConsent({
    required UserProfile profile,
    required bool showProfile,
    required bool showActivity,
  }) async {
    if (_updatingShowcaseConsent) return;
    setState(() => _updatingShowcaseConsent = true);
    try {
      await _showcaseConsentService.setProfileConsent(
        userId: profile.uid,
        showProfile: showProfile,
        showActivity: showActivity,
      );
      _notify(
        showProfile
            ? 'Your public website showcase preferences were saved.'
            : 'Your profile will no longer appear in the website showcase.',
      );
    } catch (error) {
      _notify(friendlyErrorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _updatingShowcaseConsent = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadPermissionStatuses();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _packageInfo = info);
  }

  Future<void> _loadPermissionStatuses() async {
    final results = await Future.wait([
      Permission.microphone.status,
      Permission.camera.status,
      Permission.notification.status,
    ]);
    if (!mounted) return;
    setState(() {
      _permissionStatus[Permission.microphone] = results[0];
      _permissionStatus[Permission.camera] = results[1];
      _permissionStatus[Permission.notification] = results[2];
    });
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFF5C1B33)
              : const Color(0xFF3A1958),
        ),
      );
  }

  Future<void> _requestOrOpenPermission(Permission permission) async {
    final current = _permissionStatus[permission];
    if (current != null && (current.isDenied || current.isRestricted)) {
      final result = await permission.request();
      if (!mounted) return;
      setState(() => _permissionStatus[permission] = result);
      return;
    }
    if (current != null && current.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    final result = await permission.request();
    if (!mounted) return;
    setState(() => _permissionStatus[permission] = result);
  }

  Future<void> _sendPasswordReset(String email) async {
    if (_sendingReset || email.isEmpty) return;
    setState(() => _sendingReset = true);
    try {
      await _authService.sendPasswordResetEmail(email);
      _notify('Password reset email sent to $email.');
    } catch (error) {
      _notify(friendlyErrorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  Future<void> _resendVerification() async {
    if (_resendingVerification) return;
    setState(() => _resendingVerification = true);
    try {
      await _authService.resendVerificationEmail();
      _notify('Verification email sent. Check your inbox.');
    } catch (error) {
      _notify(friendlyErrorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _resendingVerification = false);
    }
  }

  Future<void> _refreshVerification() async {
    if (_refreshingVerification) return;
    setState(() => _refreshingVerification = true);
    try {
      final verified = await _authService.reloadCurrentUser();
      _notify(
        verified
            ? 'Your email is verified.'
            : 'Still not verified — check your inbox for the link.',
        isError: !verified,
      );
      if (mounted) setState(() {});
    } catch (error) {
      _notify(friendlyErrorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _refreshingVerification = false);
    }
  }

  Future<void> _clearImageCache() async {
    if (_clearingCache) return;
    setState(() => _clearingCache = true);
    try {
      final bytesBefore = PaintingBinding.instance.imageCache.currentSizeBytes;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await Future.delayed(const Duration(milliseconds: 300));
      _notify(
        bytesBefore > 0
            ? 'Cleared ${_formatBytes(bytesBefore)} of cached images.'
            : 'Image cache was already empty.',
      );
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      _notify('Could not open $url', isError: true);
    }
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Log out?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'You will need to sign in again to use YO Voice.',
          style: TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (shouldSignOut == true) {
      await _authService.signOut();
    }
  }

  Future<void> _openDeleteAccountRequest() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 560,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _danger.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.warning_rounded, color: _danger),
            ),
            const SizedBox(height: 16),
            const Text(
              'Delete your account',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Self-service account deletion isn\'t available yet. Email support and '
              'we\'ll permanently delete your account, profile and content by hand.',
              style: TextStyle(color: _muted, height: 1.45, fontSize: 13.5),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _danger,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _openUrl(
                    'mailto:support@yovoice.app?subject=Delete%20my%20YO%20Voice%20account',
                  );
                },
                icon: const Icon(Icons.mail_outline_rounded),
                label: const Text('Email support to delete my account'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.list,
          alignment: ResponsiveContentAlignment.topLeft,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 18, 6),
                child: Row(
                  children: [
                    if (!widget.isRootTab) ...[
                      YoIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        iconSize: 18,
                        size: 40,
                        backgroundColor: _surface,
                        borderColor: _border,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 6),
                    ],
                    const Text(
                      'Settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<UserProfile>(
                  stream: _profileService.watchCurrentProfile(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _ErrorBody(
                        message: friendlyErrorMessage(snapshot.error!),
                      );
                    }
                    final profile = snapshot.data;
                    if (profile == null) {
                      return const Center(
                        child: CircularProgressIndicator(color: _primary),
                      );
                    }
                    return _buildContent(context, profile);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, UserProfile profile) {
    final emailVerified = _authService.currentUser?.emailVerified ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 48),
      children: [
        // Identity editing lives on the Profile screen (its Edit button),
        // not in Settings — Settings is configuration, Profile is content.
        // The hero card is the doorway to that surface.
        _ProfileHeroCard(
          profile: profile,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
          ),
        ),
        const SizedBox(height: 22),

        const _GroupLabel('Account'),
        _SettingsGroup(
          children: [
            // Username and account type are read-only summaries here —
            // they're edited from Profile → Edit profile, the single
            // identity-editing surface.
            _SettingsTile(
              icon: Icons.alternate_email_rounded,
              title: 'Username',
              subtitle: profile.username.isEmpty
                  ? 'Not set'
                  : '@${profile.username}',
            ),
            _SettingsTile(
              icon: Icons.mail_outline_rounded,
              title: 'Email',
              subtitle: profile.email,
              trailing: _VerifiedChip(verified: emailVerified),
            ),
            _SettingsTile(
              icon: Icons.workspace_premium_outlined,
              title: 'Account type',
              subtitle: profile.accountType.label,
            ),
            _SettingsTile(
              icon: Icons.event_available_outlined,
              title: 'Member since',
              subtitle: _formatJoinDate(profile.createdAt),
            ),
          ],
        ),
        const SizedBox(height: 22),

        const _GroupLabel('YO Voice Premium'),
        StreamBuilder<SubscriptionEntitlements>(
          stream: _entitlementService.watchCurrentEntitlements(),
          builder: (context, snapshot) {
            final entitlements = snapshot.data ?? SubscriptionEntitlements.free;
            final periodEnd = entitlements.currentPeriodEnd;

            if (!entitlements.isPremium) {
              return _SettingsGroup(
                children: [
                  _SettingsTile(
                    icon: Icons.workspace_premium_outlined,
                    title: 'Upgrade to Premium',
                    subtitle:
                        'Creator profile, Club creation and premium identity',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PremiumScreen(),
                      ),
                    ),
                  ),
                ],
              );
            }

            return _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.workspace_premium_rounded,
                  title: 'YO Voice Premium — ${entitlements.plan.label}',
                  subtitle: entitlements.inGracePeriod
                      ? 'Payment issue — check your billing details'
                      : periodEnd == null
                      ? 'Active'
                      : 'Active through '
                            '${periodEnd.day}.${periodEnd.month}.${periodEnd.year}',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PremiumScreen(),
                    ),
                  ),
                ),
                _SettingsTile(
                  icon: Icons.manage_accounts_outlined,
                  title: 'Manage subscription',
                  // The unified manager decides from trusted billing state
                  // whether this is Stripe, App Store, Play or an admin grant.
                  subtitle: kIsWeb
                      ? 'Purchases and billing management'
                      : 'View your plan and billing options',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PremiumPlansScreen(),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),

        const _GroupLabel('Privacy'),
        _SettingsGroup(
          children: [
            StreamBuilder<List<Object?>>(
              stream: _friendService.watchBlockedUsers(),
              builder: (context, snapshot) {
                final count = snapshot.data?.length;
                return _SettingsTile(
                  icon: Icons.block_rounded,
                  title: 'Blocked users',
                  subtitle: count == null
                      ? 'People you\'ve blocked'
                      : count == 0
                      ? 'No one blocked'
                      : '$count blocked',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BlockedUsersScreen(),
                    ),
                  ),
                );
              },
            ),
            _SettingsTile(
              icon: Icons.visibility_outlined,
              title: 'Profile visibility',
              subtitle: profile.profileVisibility.label,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProfileVisibilityScreen(
                    initialVisibility: profile.profileVisibility,
                  ),
                ),
              ),
            ),
            StreamBuilder<PublicProfileShowcaseConsent>(
              stream: _showcaseConsentService.watchProfileConsent(profile.uid),
              initialData: const PublicProfileShowcaseConsent.hidden(),
              builder: (context, snapshot) {
                final consent =
                    snapshot.data ??
                    const PublicProfileShowcaseConsent.hidden();
                return Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.public_rounded,
                      title: 'Appear on the YO Voice website',
                      subtitle:
                          'Show your display name and profile type on the public internet, including to signed-out visitors and people you have blocked.',
                      trailing: Switch.adaptive(
                        value: consent.showProfile,
                        onChanged: _updatingShowcaseConsent
                            ? null
                            : (value) => _setShowcaseConsent(
                                profile: profile,
                                showProfile: value,
                                showActivity: value && consent.showActivity,
                              ),
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.circle,
                      title: 'Show my recent activity',
                      subtitle:
                          'May show “Active recently” after a fresh app heartbeat — never your last-seen time.',
                      trailing: Switch.adaptive(
                        value: consent.showActivity,
                        onChanged:
                            !consent.showProfile || _updatingShowcaseConsent
                            ? null
                            : (value) => _setShowcaseConsent(
                                profile: profile,
                                showProfile: true,
                                showActivity: value,
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const MessagePrivacySettingsTile(),
          ],
        ),
        const SizedBox(height: 22),

        const _GroupLabel('Security'),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.lock_reset_rounded,
              title: 'Reset password',
              subtitle: 'Send a reset link to ${profile.email}',
              trailing: _sendingReset
                  ? const _MiniSpinner()
                  : const Icon(Icons.chevron_right_rounded, color: _muted),
              onTap: _sendingReset
                  ? null
                  : () => _sendPasswordReset(profile.email),
            ),
            _SettingsTile(
              icon: emailVerified
                  ? Icons.verified_user_rounded
                  : Icons.gpp_maybe_rounded,
              title: 'Email verification',
              subtitle: emailVerified
                  ? 'Your email is verified'
                  : 'Verify your email to unlock posting and rooms',
              trailing: emailVerified
                  ? const Icon(Icons.check_circle_rounded, color: _success)
                  : (_resendingVerification || _refreshingVerification)
                  ? const _MiniSpinner()
                  : const Icon(Icons.chevron_right_rounded, color: _muted),
              onTap: emailVerified
                  ? null
                  : () => _showVerificationSheet(context),
            ),
            _SettingsTile(
              icon: Icons.security_rounded,
              title: 'Two-factor authentication',
              subtitle: 'Use an authenticator code when you sign in',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TwoFactorAuthenticationScreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        const _GroupLabel('Notifications'),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.notifications_active_outlined,
              title: 'Notification preferences',
              subtitle: 'Choose what sends you a push notification',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationPreferencesScreen(),
                ),
              ),
            ),
            _PermissionTile(
              icon: Icons.campaign_outlined,
              title: 'System notifications',
              status: _permissionStatus[Permission.notification],
              onTap: () => _requestOrOpenPermission(Permission.notification),
            ),
          ],
        ),
        const SizedBox(height: 22),

        const _GroupLabel('Appearance'),
        _SettingsGroup(
          children: const [
            _SettingsTile(
              icon: Icons.dark_mode_rounded,
              title: 'Theme',
              subtitle: 'Dark — matches YO Voice\'s design',
              trailing: Icon(Icons.check_circle_rounded, color: _success),
            ),
            _SettingsTile(
              icon: Icons.light_mode_outlined,
              title: 'Light mode',
              subtitle: 'A bright theme for daytime use',
              comingSoon: true,
            ),
          ],
        ),
        const SizedBox(height: 22),

        const _GroupLabel('Language'),
        _SettingsGroup(
          children: const [
            _SettingsTile(
              icon: Icons.translate_rounded,
              title: 'App language',
              subtitle: 'English — more languages are on the way',
              comingSoon: true,
            ),
          ],
        ),
        const SizedBox(height: 22),

        const _GroupLabel('Devices'),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.devices_rounded,
              title: 'This device',
              subtitle: _deviceLabel(),
              trailing: const Icon(Icons.check_circle_rounded, color: _success),
            ),
            const _SettingsTile(
              icon: Icons.important_devices_outlined,
              title: 'Manage other devices',
              subtitle: 'See and sign out of other sessions',
              comingSoon: true,
            ),
          ],
        ),
        const SizedBox(height: 22),

        const _GroupLabel('Storage'),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.cleaning_services_outlined,
              title: 'Clear image cache',
              subtitle: _formatBytes(
                PaintingBinding.instance.imageCache.currentSizeBytes,
              ),
              trailing: _clearingCache
                  ? const _MiniSpinner()
                  : const Icon(Icons.chevron_right_rounded, color: _muted),
              onTap: _clearingCache ? null : _clearImageCache,
            ),
            const _SettingsTile(
              icon: Icons.download_for_offline_outlined,
              title: 'Downloaded audio',
              subtitle: 'Manage offline Voice Moments',
              comingSoon: true,
            ),
          ],
        ),
        const SizedBox(height: 22),

        const _GroupLabel('Permissions'),
        _SettingsGroup(
          children: [
            _PermissionTile(
              icon: Icons.mic_none_rounded,
              title: 'Microphone',
              status: _permissionStatus[Permission.microphone],
              onTap: () => _requestOrOpenPermission(Permission.microphone),
            ),
            _PermissionTile(
              icon: Icons.photo_camera_outlined,
              title: 'Camera',
              status: _permissionStatus[Permission.camera],
              onTap: () => _requestOrOpenPermission(Permission.camera),
            ),
          ],
        ),
        const SizedBox(height: 22),

        const _GroupLabel('Help'),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.help_outline_rounded,
              title: 'Help center',
              subtitle: 'Guides and answers to common questions',
              onTap: () => _openUrl('https://yovoice.app/help-center'),
            ),
            _SettingsTile(
              icon: Icons.support_agent_rounded,
              title: 'Contact support',
              subtitle: 'support@yovoice.app',
              onTap: () => _openUrl('mailto:support@yovoice.app'),
            ),
          ],
        ),
        const SizedBox(height: 22),

        const _GroupLabel('About'),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.info_outline_rounded,
              title: 'Version',
              subtitle: _packageInfo == null
                  ? 'Loading…'
                  : '${_packageInfo!.version} (${_packageInfo!.buildNumber})',
            ),
            _SettingsTile(
              icon: Icons.language_rounded,
              title: 'Visit yovoice.app',
              subtitle: 'Our website',
              onTap: () => _openUrl('https://yovoice.app'),
            ),
          ],
        ),
        const SizedBox(height: 22),

        const _GroupLabel('Legal'),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy policy',
              onTap: () => _openUrl('https://yovoice.app/privacy'),
            ),
            _SettingsTile(
              icon: Icons.gavel_rounded,
              title: 'Terms of service',
              onTap: () => _openUrl('https://yovoice.app/terms'),
            ),
          ],
        ),
        const SizedBox(height: 22),

        const _GroupLabel('Danger zone', danger: true),
        _SettingsGroup(
          danger: true,
          children: [
            _SettingsTile(
              icon: Icons.logout_rounded,
              title: 'Log out',
              danger: true,
              onTap: _confirmSignOut,
            ),
            _SettingsTile(
              icon: Icons.delete_forever_rounded,
              title: 'Delete account',
              subtitle: 'Permanently remove your account and data',
              danger: true,
              onTap: _openDeleteAccountRequest,
            ),
          ],
        ),
      ],
    );
  }

  void _showVerificationSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 560,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.mark_email_unread_rounded,
                  color: _primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Verify your email',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Check your inbox for the verification link, then come back and refresh.',
                style: TextStyle(color: _muted, height: 1.45, fontSize: 13.5),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _resendingVerification
                          ? null
                          : () async {
                              await _resendVerification();
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: _border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _resendingVerification
                          ? const _MiniSpinner()
                          : const Text('Resend email'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _refreshingVerification
                          ? null
                          : () async {
                              await _refreshVerification();
                              if (context.mounted) Navigator.pop(sheetContext);
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: _primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _refreshingVerification
                          ? const _MiniSpinner()
                          : const Text('I\'ve verified'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatJoinDate(DateTime? date) {
    if (date == null) return 'Unknown';
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _deviceLabel() {
    if (kIsWeb) return 'Web browser';
    if (Platform.isIOS) return 'iOS device';
    if (Platform.isAndroid) return 'Android device';
    if (Platform.isMacOS) return 'macOS device';
    if (Platform.isWindows) return 'Windows device';
    if (Platform.isLinux) return 'Linux device';
    return 'This device';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return 'Nothing cached';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB cached';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB cached';
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({required this.profile, required this.onTap});

  final UserProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = profile.photoUrl?.trim();
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF6A00FF), Color(0xFFD12CFF)],
                  ),
                ),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFF281133),
                  backgroundImage: avatar?.isNotEmpty == true
                      ? NetworkImage(avatar!)
                      : null,
                  child: avatar?.isNotEmpty == true
                      ? null
                      : Text(
                          profile.displayName.isEmpty
                              ? '?'
                              : profile.displayName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Edit profile details and photos',
                      style: TextStyle(color: _muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {this.danger = false});
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: danger ? _danger.withValues(alpha: .8) : _muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children, this.danger = false});
  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: danger ? _danger.withValues(alpha: .25) : _border,
        ),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0)
              const Divider(
                height: 1,
                indent: 56,
                endIndent: 16,
                color: _border,
              ),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.comingSoon = false,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool comingSoon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final iconColor = danger ? _danger : _primary;
    final titleColor = danger ? _danger : Colors.white;

    return Opacity(
      opacity: comingSoon ? .55 : 1,
      child: ListTile(
        enabled: !comingSoon,
        onTap: comingSoon ? null : onTap,
        leading: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: titleColor,
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
        trailing: comingSoon
            ? const _ComingSoonBadge()
            : (trailing ??
                  (onTap != null
                      ? const Icon(Icons.chevron_right_rounded, color: _muted)
                      : null)),
      ),
    );
  }
}

class _ComingSoonBadge extends StatelessWidget {
  const _ComingSoonBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF241B2A),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: _border),
      ),
      child: const Text(
        'COMING SOON',
        style: TextStyle(
          color: _muted,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

class _VerifiedChip extends StatelessWidget {
  const _VerifiedChip({required this.verified});
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final color = verified ? _success : const Color(0xFFFFB547);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Text(
        verified ? 'VERIFIED' : 'UNVERIFIED',
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.status,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final PermissionStatus? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      null => 'Checking…',
      PermissionStatus.granted || PermissionStatus.limited => 'Allowed',
      PermissionStatus.permanentlyDenied => 'Denied — open settings',
      PermissionStatus.denied => 'Not allowed',
      PermissionStatus.restricted => 'Restricted',
      PermissionStatus.provisional => 'Provisional',
    };
    final granted =
        status == PermissionStatus.granted ||
        status == PermissionStatus.limited;

    return _SettingsTile(
      icon: icon,
      title: title,
      subtitle: label,
      trailing: granted
          ? const Icon(Icons.check_circle_rounded, color: _success)
          : const Icon(Icons.chevron_right_rounded, color: _muted),
      onTap: onTap,
    );
  }
}

class _MiniSpinner extends StatelessWidget {
  const _MiniSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: _primary),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
