import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';

import '../../data/services/server_broadcast_ingress_service.dart';
import '../server_action_failure.dart';

class ServerObsBroadcastSheet extends StatefulWidget {
  const ServerObsBroadcastSheet({
    required this.repository,
    required this.serverId,
    required this.channelId,
    required this.sessionId,
    super.key,
  });

  final ServerBroadcastIngressRepository repository;
  final String serverId;
  final String channelId;
  final String sessionId;

  @override
  State<ServerObsBroadcastSheet> createState() =>
      _ServerObsBroadcastSheetState();
}

class _ServerObsBroadcastSheetState extends State<ServerObsBroadcastSheet> {
  ServerBroadcastIngressReceipt? _receipt;
  Object? _error;
  bool _busy = false;
  bool _revealKey = false;
  String? _copyFeedback;
  Timer? _copyFeedbackTimer;

  @override
  void dispose() {
    _copyFeedbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyCredential(String value, String confirmation) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _copyFeedbackTimer?.cancel();
    setState(() => _copyFeedback = confirmation);
    _copyFeedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copyFeedback = null);
    });
  }

  Future<void> _provision() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await widget.repository.provision(
        serverId: widget.serverId,
        channelId: widget.channelId,
        sessionId: widget.sessionId,
      );
      if (mounted) setState(() => _receipt = receipt);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final receipt = _receipt;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (!largeText) ...[
                  Icon(Icons.live_tv_rounded, color: palette.audioAccent),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      copy.text('OBS Broadcasting', 'Transmisja OBS'),
                      style:
                          (largeText
                                  ? AppTypography.titleLarge
                                  : AppTypography.headlineSmall)
                              .copyWith(color: palette.textPrimary),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              copy.text(
                'Send a real OBS stream to this live stage. The input is bound to this session and removed when LIVE ends.',
                'Wyślij prawdziwą transmisję OBS na tę scenę. Wejście jest przypisane do tej sesji i zostanie usunięte po zakończeniu LIVE.',
              ),
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            ...[
              copy.text(
                '1. Start or join this LIVE as its host.',
                '1. Uruchom lub dołącz do tego LIVE jako prowadzący.',
              ),
              copy.text(
                '2. Generate the private streaming details below.',
                '2. Wygeneruj poniżej prywatne dane transmisji.',
              ),
              copy.text(
                '3. In OBS open Settings → Stream and choose Service: Custom.',
                '3. W OBS otwórz Ustawienia → Stream i wybierz Usługa: Własna.',
              ),
              copy.text(
                '4. Paste Server and Stream Key, then press Start Streaming in OBS.',
                '4. Wklej adres serwera i klucz transmisji, a następnie kliknij Rozpocznij transmisję w OBS.',
              ),
            ].map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  line,
                  style: AppTypography.bodyMedium.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (receipt == null)
              FilledButton.icon(
                key: const ValueKey('server-obs-provision'),
                onPressed: _busy ? null : _provision,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.key_rounded),
                label: Text(
                  _busy
                      ? copy.text(
                          'Generating streaming details…',
                          'Generowanie danych transmisji…',
                        )
                      : copy.text(
                          'Generate streaming details',
                          'Wygeneruj dane transmisji',
                        ),
                ),
              )
            else ...[
              _CredentialRow(
                keySuffix: 'server',
                label: copy.text('Server URL', 'Adres serwera'),
                value: receipt.serverUrl,
                copyTooltip: copy.text(
                  'Copy server URL',
                  'Skopiuj adres serwera',
                ),
                onCopy: () => _copyCredential(
                  receipt.serverUrl,
                  copy.text('Server URL copied', 'Skopiowano adres serwera'),
                ),
              ),
              const SizedBox(height: 12),
              _CredentialRow(
                keySuffix: 'stream-key',
                label: copy.text('Stream Key', 'Klucz transmisji'),
                value: _revealKey ? receipt.streamKey : '••••••••••••••••',
                copyTooltip: copy.text(
                  'Copy Stream Key',
                  'Skopiuj klucz transmisji',
                ),
                onCopy: () => _copyCredential(
                  receipt.streamKey,
                  copy.text('Stream Key copied', 'Skopiowano klucz transmisji'),
                ),
                trailing: IconButton(
                  key: const ValueKey('server-obs-reveal-key'),
                  tooltip: _revealKey
                      ? copy.text('Hide key', 'Ukryj klucz')
                      : copy.text('Show key', 'Pokaż klucz'),
                  onPressed: () => setState(() => _revealKey = !_revealKey),
                  icon: Icon(
                    _revealKey
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              if (_copyFeedback != null) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Row(
                    key: const ValueKey('server-obs-copy-feedback'),
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                        color: palette.audioAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _copyFeedback!,
                          style: AppTypography.labelMedium.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                copy.text(
                  'Keep the Stream Key private. Copy it before closing; YO Voice does not store the key.',
                  'Nie udostępniaj klucza transmisji. Skopiuj go przed zamknięciem; YO Voice nie zapisuje klucza.',
                ),
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  serverActionFailureCopy(
                    _error!,
                    copy,
                    fallback: copy.text(
                      'OBS setup is temporarily unavailable. Try again.',
                      'Konfiguracja OBS jest chwilowo niedostępna. Spróbuj ponownie.',
                    ),
                  ),
                  key: const ValueKey('server-obs-error'),
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.dangerForeground,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              copy.text(
                'On iPhone direct sharing captures the YO Voice app. To broadcast other apps, use OBS on a computer.',
                'Na iPhonie bezpośrednie udostępnianie obejmuje aplikację YO Voice. Aby transmitować inne aplikacje, użyj OBS na komputerze.',
              ),
              style: AppTypography.bodySmall.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({
    required this.keySuffix,
    required this.label,
    required this.value,
    required this.copyTooltip,
    required this.onCopy,
    this.trailing,
  });

  final String keySuffix;
  final String label;
  final String value;
  final String copyTooltip;
  final VoidCallback onCopy;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.labelSmall.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    value,
                    key: ValueKey('server-obs-$keySuffix'),
                    style: AppTypography.bodyMedium.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            ?trailing,
            IconButton(
              key: ValueKey('server-obs-copy-$keySuffix'),
              tooltip: copyTooltip,
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
