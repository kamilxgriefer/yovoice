import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

Future<PermissionSetupOutcome?> showPermissionSetupSheet(
  BuildContext context, {
  required String userId,
  PermissionReadinessService? service,
  bool recordSkip = true,
}) async {
  final route = showModalBottomSheet<PermissionSetupOutcome>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .58),
    builder: (_) => PopScope(
      canPop: false,
      child: PermissionSetupSheet(
        userId: userId,
        service: service,
        recordSkip: recordSkip,
      ),
    ),
  );
  return route;
}

class PermissionSetupSheet extends StatefulWidget {
  const PermissionSetupSheet({
    required this.userId,
    this.service,
    this.recordSkip = true,
    super.key,
  });

  final String userId;
  final PermissionReadinessService? service;
  final bool recordSkip;

  @override
  State<PermissionSetupSheet> createState() => _PermissionSetupSheetState();
}

class _PermissionSetupSheetState extends State<PermissionSetupSheet>
    with WidgetsBindingObserver {
  late final PermissionReadinessService _service =
      widget.service ?? PermissionReadinessService.instance;
  PermissionReadinessSnapshot? _snapshot;
  bool _busy = false;
  bool _prepared = false;
  bool _refreshOnResume = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _refreshOnResume) {
      _refreshOnResume = false;
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    try {
      final snapshot = await _service.snapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).text(
          'Could not read system permission status.',
          'Nie udało się odczytać stanu uprawnień systemowych.',
        );
      });
    }
  }

  Future<void> _continue() async {
    if (_busy) return;
    if (_prepared) {
      Navigator.of(context).pop(PermissionSetupOutcome.completed);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await _service.prepareFromUserGesture(
        userId: widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _prepared = true;
      });
      if (snapshot.hasSettingsOnlyPermission) {
        _refreshOnResume = true;
        final opened = await _service.openSettings();
        if (!mounted) return;
        if (!opened) {
          setState(() {
            _error = kIsWeb
                ? AppLocalizations.of(context).text(
                    'Open this site\'s browser settings to change blocked permissions.',
                    'Otwórz ustawienia tej witryny w przeglądarce, aby zmienić zablokowane uprawnienia.',
                  )
                : AppLocalizations.of(context).text(
                    'Open device Settings to change blocked permissions.',
                    'Otwórz ustawienia urządzenia, aby zmienić zablokowane uprawnienia.',
                  );
          });
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).text(
          'Permission setup did not finish. You can try again.',
          'Konfiguracja uprawnień nie została ukończona. Możesz spróbować ponownie.',
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    if (_busy) return;
    if (widget.recordSkip) {
      try {
        await _service.skip(widget.userId);
      } catch (error) {
        debugPrint('Permission setup skip could not be saved: $error');
      }
    }
    if (mounted) Navigator.of(context).pop(PermissionSetupOutcome.skipped);
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final maxHeight = MediaQuery.sizeOf(context).height * .9;
    return Material(
      color: palette.surfaceRaised,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            bottom: 24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YoModalSheetChrome(
                sheetLabel: copy.text(
                  'Permission setup',
                  'Konfiguracja uprawnień',
                ),
                surfaceColor: palette.surfaceRaised,
                onClose: _skip,
                horizontalPadding: 0,
              ),
              const SizedBox(height: 8),
              Icon(
                Icons.privacy_tip_rounded,
                size: 42,
                color: palette.interactiveForeground,
              ),
              const SizedBox(height: 14),
              Text(
                copy.text(
                  'Set up calls and alerts',
                  'Skonfiguruj połączenia i powiadomienia',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                copy.text(
                  'YO Voice will ask the system for notification, microphone and camera access in that order. Your choices stay under your control in Settings.',
                  'YO Voice poprosi system kolejno o dostęp do powiadomień, mikrofonu i aparatu. W każdej chwili możesz zmienić swoje decyzje w ustawieniach.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              for (final permission in AppPermissionKind.values) ...[
                _PermissionStatusRow(
                  permission: permission,
                  status: _snapshot?[permission],
                ),
                if (permission != AppPermissionKind.camera)
                  const SizedBox(height: 10),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 14),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    key: const ValueKey('permission-setup-error'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                key: const ValueKey('permission-setup-primary'),
                onPressed: _busy ? null : _continue,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _prepared
                            ? Icons.check_rounded
                            : Icons.arrow_forward_rounded,
                      ),
                label: Text(
                  _prepared
                      ? copy.text('Done', 'Gotowe')
                      : copy.text(
                          'Review permissions',
                          'Skonfiguruj uprawnienia',
                        ),
                ),
              ),
              TextButton(
                key: const ValueKey('permission-setup-skip'),
                onPressed: _busy ? null : _skip,
                child: Text(copy.text('Not now', 'Nie teraz')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionStatusRow extends StatelessWidget {
  const _PermissionStatusRow({required this.permission, required this.status});

  final AppPermissionKind permission;
  final AppPermissionAccess? status;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final (icon, title) = switch (permission) {
      AppPermissionKind.notifications => (
        Icons.notifications_none_rounded,
        copy.text('Notifications', 'Powiadomienia'),
      ),
      AppPermissionKind.microphone => (
        Icons.mic_none_rounded,
        copy.text('Microphone', 'Mikrofon'),
      ),
      AppPermissionKind.camera => (
        Icons.photo_camera_outlined,
        copy.text('Camera', 'Aparat'),
      ),
    };
    final resolved = status;
    final (statusIcon, statusText, statusColor) = switch (resolved) {
      AppPermissionAccess.granted => (
        Icons.check_circle_rounded,
        copy.text('Allowed', 'Dozwolone'),
        palette.successForeground,
      ),
      AppPermissionAccess.limited => (
        Icons.check_circle_outline_rounded,
        copy.text('Limited', 'Ograniczone'),
        palette.successForeground,
      ),
      AppPermissionAccess.permanentlyDenied => (
        Icons.settings_rounded,
        copy.text('Change in Settings', 'Zmień w ustawieniach'),
        Theme.of(context).colorScheme.error,
      ),
      AppPermissionAccess.restricted => (
        Icons.lock_outline_rounded,
        copy.text('Restricted by device', 'Ograniczone przez urządzenie'),
        palette.textSecondary,
      ),
      AppPermissionAccess.unavailable => (
        Icons.remove_circle_outline_rounded,
        copy.text('Unavailable', 'Niedostępne'),
        palette.textSecondary,
      ),
      AppPermissionAccess.denied => (
        Icons.radio_button_unchecked_rounded,
        copy.text('Not allowed yet', 'Jeszcze niedozwolone'),
        palette.textSecondary,
      ),
      null => (
        Icons.more_horiz_rounded,
        copy.text('Checking…', 'Sprawdzanie…'),
        palette.textSecondary,
      ),
    };

    return Semantics(
      label: '$title, $statusText',
      child: Container(
        key: ValueKey('permission-status-${permission.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: palette.interactiveForeground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(statusIcon, size: 20, color: statusColor),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                statusText,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
