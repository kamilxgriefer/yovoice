import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/settings/data/services/session_management_service.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

typedef SignOutCurrentDevice = Future<void> Function();

class DeviceSessionsScreen extends StatefulWidget {
  const DeviceSessionsScreen({
    super.key,
    this.service,
    this.signOutCurrentDevice,
    this.deviceLabel,
  });

  final SessionManagementService? service;
  final SignOutCurrentDevice? signOutCurrentDevice;
  final String? deviceLabel;

  @override
  State<DeviceSessionsScreen> createState() => _DeviceSessionsScreenState();
}

class _DeviceSessionsScreenState extends State<DeviceSessionsScreen> {
  late final SessionManagementService _service =
      widget.service ?? SessionManagementService();
  late Future<CurrentSessionInfo> _session;
  bool _revoking = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _session = _service.currentSession();
  }

  Future<void> _reload() async {
    setState(() => _session = _service.currentSession());
    await _session;
  }

  Future<void> _confirmSignOutEverywhere() async {
    if (_revoking) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out on every device?'),
        content: const Text(
          'This includes this device. You will need to sign in again everywhere. '
          'Already-issued access can take up to one hour to expire.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out everywhere'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _revoking = true;
      _actionError = null;
    });
    try {
      await _service.signOutEverywhere();
      final signOut = widget.signOutCurrentDevice ?? _defaultSignOut;
      await signOut();
    } on SessionManagementFailure catch (error) {
      if (!mounted) return;
      setState(() => _actionError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _actionError =
            'Your remote sessions were ended, but this device could not finish signing out. Close YO Voice and sign out again.';
      });
    } finally {
      if (mounted) setState(() => _revoking = false);
    }
  }

  Future<void> _defaultSignOut() async {
    // AuthService.signOut() owns the FCM-token and presence cleanup for
    // every sign-out path, so this one no longer repeats it. Revoking
    // refresh tokens does not invalidate the ID token already on this
    // device, so that cleanup still runs against a live session here.
    await AuthService().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: YoIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Devices & sessions'),
      ),
      body: SafeArea(
        top: false,
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.form,
          alignment: ResponsiveContentAlignment.topCenter,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
            children: [
              Text(
                'Review this session or securely sign out everywhere.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              FutureBuilder<CurrentSessionInfo>(
                future: _session,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _LoadingSessionCard();
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return _SessionErrorCard(onRetry: _reload);
                  }
                  return _CurrentSessionCard(
                    session: snapshot.requireData,
                    deviceLabel: widget.deviceLabel ?? _deviceLabel(),
                  );
                },
              ),
              const SizedBox(height: 18),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.verified_user_outlined, color: colors.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'One secure account-wide action',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'YO Voice does not receive a trustworthy per-device login list from its authentication provider. '
                              'Push registrations are not login sessions. To guarantee a real result, YO Voice can end every session together.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_actionError != null) ...[
                const SizedBox(height: 18),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _actionError!,
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _revoking ? null : _confirmSignOutEverywhere,
                  icon: _revoking
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onError,
                          ),
                        )
                      : const Icon(Icons.logout_rounded),
                  label: Text(
                    _revoking ? 'Ending sessions…' : 'Sign out everywhere',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Refresh access is revoked immediately. An access token already issued by Firebase can remain valid for up to one hour.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentSessionCard extends StatelessWidget {
  const _CurrentSessionCard({required this.session, required this.deviceLabel});

  final CurrentSessionInfo session;
  final String deviceLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final signedInAt = session.signedInAt;
    final providers = session.providerLabels.isEmpty
        ? 'Firebase account'
        : session.providerLabels.join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.devices_rounded,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          deviceLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Current',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    providers,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (signedInAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Authenticated ${_formatSessionTime(signedInAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingSessionCard extends StatelessWidget {
  const _LoadingSessionCard();

  @override
  Widget build(BuildContext context) => const Card(
    margin: EdgeInsets.zero,
    child: SizedBox(
      height: 124,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
}

class _SessionErrorCard extends StatelessWidget {
  const _SessionErrorCard({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colors.error),
            const SizedBox(width: 12),
            const Expanded(child: Text('This session could not be loaded.')),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String _deviceLabel() {
  if (kIsWeb) return 'This web browser';
  if (Platform.isIOS) return 'This iPhone or iPad';
  if (Platform.isAndroid) return 'This Android device';
  if (Platform.isMacOS) return 'This Mac';
  if (Platform.isWindows) return 'This Windows device';
  if (Platform.isLinux) return 'This Linux device';
  return 'This device';
}

String _formatSessionTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final difference = now.difference(local);
  if (!difference.isNegative && difference.inMinutes < 1) return 'just now';
  if (!difference.isNegative && difference.inHours < 1) {
    return '${difference.inMinutes} min ago';
  }
  if (!difference.isNegative && difference.inDays < 1) {
    return '${difference.inHours} hr ago';
  }
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}
