import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
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
      builder: (context) {
        final copy = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(
            copy.text(
              'Sign out on every device?',
              'Wylogować na wszystkich urządzeniach?',
            ),
          ),
          content: Text(
            copy.text(
              'This includes this device. You will need to sign in again everywhere. Already-issued access can take up to one hour to expire.',
              'Dotyczy to także tego urządzenia. Na każdym urządzeniu konieczne będzie ponowne logowanie. Wygaśnięcie już przyznanego dostępu może potrwać do godziny.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(copy.text('Sign out everywhere', 'Wyloguj wszędzie')),
            ),
          ],
        );
      },
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
      setState(
        () => _actionError = AppLocalizations.of(context).text(
          error.message,
          'Nie udało się zakończyć wszystkich sesji. Spróbuj ponownie.',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _actionError = AppLocalizations.of(context).text(
          'Your remote sessions were ended, but this device could not finish signing out. Close YO Voice and sign out again.',
          'Pozostałe sesje zostały zakończone, ale nie udało się wylogować tego urządzenia. Zamknij YO Voice i spróbuj wylogować się ponownie.',
        );
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
    final copy = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: YoIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: copy.text('Back', 'Wstecz'),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(copy.text('Devices & sessions', 'Urządzenia i sesje')),
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
                copy.text(
                  'Review this session or securely sign out everywhere.',
                  'Sprawdź bieżącą sesję lub bezpiecznie wyloguj się wszędzie.',
                ),
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
                    deviceLabel: widget.deviceLabel ?? _deviceLabel(context),
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
                              copy.text(
                                'One secure account-wide action',
                                'Jedna bezpieczna czynność dla całego konta',
                              ),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              copy.text(
                                'YO Voice does not receive a trustworthy per-device login list from its authentication provider. Push registrations are not login sessions. To guarantee a real result, YO Voice can end every session together.',
                                'Dostawca uwierzytelniania nie udostępnia YO Voice wiarygodnej listy logowań na poszczególnych urządzeniach. Rejestracje powiadomień push nie są sesjami logowania. Aby zagwarantować skuteczne działanie, YO Voice może zakończyć wszystkie sesje jednocześnie.',
                              ),
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
                    _revoking
                        ? copy.text('Ending sessions…', 'Kończenie sesji…')
                        : copy.text('Sign out everywhere', 'Wyloguj wszędzie'),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                copy.text(
                  'Refresh access is revoked immediately. An access token already issued by Firebase can remain valid for up to one hour.',
                  'Możliwość odświeżenia dostępu jest odbierana natychmiast. Token dostępu wydany wcześniej przez Firebase może pozostać ważny nawet przez godzinę.',
                ),
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
    final copy = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final signedInAt = session.signedInAt;
    final providers = session.providerLabels.isEmpty
        ? copy.text('Firebase account', 'Konto Firebase')
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
                          copy.text('Current', 'Bieżąca'),
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
                      copy.text(
                        'Authenticated ${_formatSessionTime(context, signedInAt)}',
                        'Uwierzytelniono ${_formatSessionTime(context, signedInAt)}',
                      ),
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
    final copy = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colors.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                copy.text(
                  'This session could not be loaded.',
                  'Nie udało się wczytać tej sesji.',
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(copy.text('Retry', 'Spróbuj ponownie')),
            ),
          ],
        ),
      ),
    );
  }
}

String _deviceLabel(BuildContext context) {
  final copy = AppLocalizations.of(context);
  if (kIsWeb) {
    return copy.text('This web browser', 'Ta przeglądarka internetowa');
  }
  if (Platform.isIOS) {
    return copy.text('This iPhone or iPad', 'Ten iPhone lub iPad');
  }
  if (Platform.isAndroid) {
    return copy.text('This Android device', 'To urządzenie z Androidem');
  }
  if (Platform.isMacOS) return copy.text('This Mac', 'Ten Mac');
  if (Platform.isWindows) {
    return copy.text('This Windows device', 'To urządzenie z Windows');
  }
  if (Platform.isLinux) {
    return copy.text('This Linux device', 'To urządzenie z Linuxem');
  }
  return copy.text('This device', 'To urządzenie');
}

String _formatSessionTime(BuildContext context, DateTime value) {
  final copy = AppLocalizations.of(context);
  final local = value.toLocal();
  final now = DateTime.now();
  final difference = now.difference(local);
  if (!difference.isNegative && difference.inMinutes < 1) {
    return copy.text('just now', 'przed chwilą');
  }
  if (!difference.isNegative && difference.inHours < 1) {
    return copy.text(
      '${difference.inMinutes} min ago',
      '${difference.inMinutes} min temu',
    );
  }
  if (!difference.isNegative && difference.inDays < 1) {
    return copy.text(
      '${difference.inHours} hr ago',
      '${difference.inHours} godz. temu',
    );
  }
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}
