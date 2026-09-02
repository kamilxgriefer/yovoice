import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/moments/data/models/downloaded_voice_moment.dart';
import 'package:yovoice/features/moments/data/services/offline_voice_moment_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class DownloadedAudioScreen extends StatefulWidget {
  const DownloadedAudioScreen({
    this.service,
    this.isRootTab = false,
    super.key,
  });

  final OfflineVoiceMomentService? service;
  final bool isRootTab;

  @override
  State<DownloadedAudioScreen> createState() => _DownloadedAudioScreenState();
}

class _DownloadedAudioScreenState extends State<DownloadedAudioScreen> {
  late final OfflineVoiceMomentService _service =
      widget.service ?? OfflineVoiceMomentService.instance;
  AudioPlayer? _player;
  StreamSubscription<void>? _completionSubscription;
  late Future<List<DownloadedVoiceMoment>> _items = _service.list();
  String? _playingId;
  String? _busyId;
  bool _clearing = false;

  AudioPlayer get _audioPlayer {
    final existing = _player;
    if (existing != null) return existing;
    final created = AudioPlayer();
    _completionSubscription = created.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingId = null);
    });
    return _player = created;
  }

  @override
  void dispose() {
    _completionSubscription?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _items = _service.list());

  void _notice(String message, {bool error = false}) {
    if (!mounted) return;
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: error ? TextStyle(color: colors.onErrorContainer) : null,
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? colors.errorContainer : null,
        ),
      );
  }

  Future<void> _toggle(DownloadedVoiceMoment item) async {
    if (_busyId != null || _clearing) return;
    final copy = AppLocalizations.of(context);
    if (_playingId == item.momentId) {
      await _player!.pause();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    setState(() => _busyId = item.momentId);
    try {
      final offline = await _service.readPlayback(item.momentId);
      if (offline == null) {
        _notice(
          copy.text(
            'This download is missing. Remove it and download it again.',
            'Brakuje pobranego pliku. Usuń go i pobierz ponownie.',
          ),
          error: true,
        );
        _reload();
        return;
      }
      await _audioPlayer.stop();
      await _audioPlayer.play(
        offline.deviceFilePath != null
            ? DeviceFileSource(offline.deviceFilePath!)
            : BytesSource(offline.bytes!),
      );
      if (mounted) setState(() => _playingId = item.momentId);
    } catch (error) {
      _notice(
        error is OfflineAudioException
            ? copy.text(
                error.message,
                'Nie udało się odtworzyć pobranego nagrania.',
              )
            : copy.text(
                'The downloaded audio could not be played.',
                'Nie udało się odtworzyć pobranego nagrania.',
              ),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(DownloadedVoiceMoment item) async {
    if (_busyId != null || _clearing) return;
    final copy = AppLocalizations.of(context);
    setState(() => _busyId = item.momentId);
    try {
      if (_playingId == item.momentId) {
        await _player?.stop();
        _playingId = null;
      }
      await _service.delete(item.momentId);
      _notice(copy.text('Download removed.', 'Usunięto pobrane nagranie.'));
      _reload();
    } catch (error) {
      _notice(
        error is OfflineAudioException
            ? copy.text(
                error.message,
                'Nie udało się usunąć pobranego nagrania.',
              )
            : copy.text(
                'The download could not be removed.',
                'Nie udało się usunąć pobranego nagrania.',
              ),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _clearAll() async {
    if (_busyId != null || _clearing) return;
    final copy = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final copy = AppLocalizations.of(dialogContext);
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(
            copy.text('Remove all downloads?', 'Usunąć wszystkie pobrania?'),
          ),
          content: Text(
            copy.text(
              'Downloaded Voice Moments will no longer be available offline on this device.',
              'Pobrane Voice Moments nie będą już dostępne offline na tym urządzeniu.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.errorContainer,
                foregroundColor: colors.onErrorContainer,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(copy.text('Remove all', 'Usuń wszystkie')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await _player?.stop();
      _playingId = null;
      await _service.clear();
      _notice(
        copy.text(
          'All downloaded audio was removed.',
          'Usunięto wszystkie pobrane nagrania.',
        ),
      );
      _reload();
    } catch (_) {
      _notice(
        copy.text(
          'Downloaded audio could not be cleared.',
          'Nie udało się usunąć pobranych nagrań.',
        ),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: widget.isRootTab
          ? null
          : AppBar(
              title: Text(copy.text('Downloaded audio', 'Pobrane nagrania')),
            ),
      body: SafeArea(
        top: widget.isRootTab,
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.list,
          alignment: ResponsiveContentAlignment.topCenter,
          child: FutureBuilder<List<DownloadedVoiceMoment>>(
            future: _items,
            builder: (context, snapshot) {
              final horizontal = MediaQuery.sizeOf(context).width < 600
                  ? 16.0
                  : 24.0;
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _OfflineState(
                  icon: Icons.cloud_off_rounded,
                  title: copy.text(
                    'Downloads unavailable',
                    'Pobrane nagrania są niedostępne',
                  ),
                  message: snapshot.error is OfflineAudioException
                      ? copy.text(
                          (snapshot.error! as OfflineAudioException).message,
                          'Nie udało się otworzyć pamięci nagrań na tym urządzeniu.',
                        )
                      : copy.text(
                          'YO Voice could not open this device\'s audio storage.',
                          'YO Voice nie może otworzyć pamięci nagrań na tym urządzeniu.',
                        ),
                  action: TextButton(
                    onPressed: _reload,
                    child: Text(copy.text('Try again', 'Spróbuj ponownie')),
                  ),
                );
              }
              final items = snapshot.data ?? const <DownloadedVoiceMoment>[];
              final total = items.fold<int>(
                0,
                (sum, item) => sum + item.byteLength,
              );
              return ListView.separated(
                key: const ValueKey('downloaded-audio-list'),
                padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, 120),
                itemCount: 1 + (items.isEmpty ? 1 : items.length),
                separatorBuilder: (_, index) =>
                    SizedBox(height: index == 0 ? 14 : 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.isRootTab) ...[
                          Text(
                            copy.text('Downloaded audio', 'Pobrane nagrania'),
                            style: theme.textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 18),
                        ],
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final compact =
                                constraints.maxWidth < 420 ||
                                MediaQuery.textScalerOf(context).scale(1) > 1.5;
                            final label = Text(
                              items.isEmpty
                                  ? copy.text(
                                      'No offline audio on this device',
                                      'Brak nagrań offline na tym urządzeniu',
                                    )
                                  : copy.text(
                                      '${items.length} ${items.length == 1 ? 'download' : 'downloads'} · ${_formatBytes(total)}',
                                      '${items.length} ${_polishDownloadCount(items.length)} · ${_formatBytes(total)}',
                                    ),
                              style: theme.textTheme.titleMedium,
                            );
                            final action = items.isEmpty
                                ? null
                                : TextButton.icon(
                                    onPressed: _clearing ? null : _clearAll,
                                    icon: _clearing
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.delete_sweep_outlined,
                                          ),
                                    label: Text(
                                      copy.text('Remove all', 'Usuń wszystkie'),
                                    ),
                                  );
                            if (compact) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  label,
                                  if (action != null) ...[
                                    const SizedBox(height: 4),
                                    action,
                                  ],
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: label),
                                ?action,
                              ],
                            );
                          },
                        ),
                      ],
                    );
                  }
                  if (items.isEmpty) {
                    return _OfflineState(
                      icon: Icons.download_for_offline_outlined,
                      title: copy.text(
                        'Listen without a connection',
                        'Słuchaj bez połączenia z internetem',
                      ),
                      message: copy.text(
                        'Open Moments and use the download button on any published Voice Moment.',
                        'Otwórz Moments i użyj przycisku pobierania przy dowolnym opublikowanym Voice Moment.',
                      ),
                    );
                  }
                  final item = items[index - 1];
                  return _DownloadedAudioCard(
                    item: item,
                    playing: _playingId == item.momentId,
                    busy: _busyId == item.momentId,
                    onPlay: () => _toggle(item),
                    onDelete: () => _delete(item),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DownloadedAudioCard extends StatelessWidget {
  const _DownloadedAudioCard({
    required this.item,
    required this.playing,
    required this.busy,
    required this.onPlay,
    required this.onDelete,
  });

  final DownloadedVoiceMoment item;
  final bool playing;
  final bool busy;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(minHeight: 94),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            IconButton.filled(
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              tooltip: playing
                  ? copy.text(
                      'Pause offline audio',
                      'Wstrzymaj nagranie offline',
                    )
                  : copy.text('Play offline audio', 'Odtwórz nagranie offline'),
              onPressed: busy ? null : onPlay,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.caption.trim().isEmpty
                        ? copy.text('Voice Moment', 'Voice Moment')
                        : item.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.authorName} · ${item.durationLabel} · ${_formatBytes(item.byteLength)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              tooltip: copy.text('Remove download', 'Usuń pobrane nagranie'),
              onPressed: busy ? null : onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineState extends StatelessWidget {
  const _OfflineState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: theme.colorScheme.primary),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (action != null) ...[const SizedBox(height: 10), action!],
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) return '${kilobytes.toStringAsFixed(1)} KB';
  return '${(kilobytes / 1024).toStringAsFixed(1)} MB';
}

String _polishDownloadCount(int count) {
  if (count == 1) return 'pobranie';
  final lastTwo = count % 100;
  final last = count % 10;
  if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
    return 'pobrania';
  }
  return 'pobrań';
}
