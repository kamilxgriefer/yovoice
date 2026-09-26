import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/profile/data/services/profile_image_rules.dart';
import 'package:yovoice/shared/widgets/media/yo_recording_countdown.dart';

import '../../data/models/server_family_memory.dart';
import '../../data/models/server_member_role.dart';
import '../../data/services/server_family_memory_service.dart';
import '../theme/server_identity.dart';

typedef ServerFamilyMemoryPhotoBuilder =
    Widget Function(BuildContext context, Uri signedUrl);

/// A server-scoped Family Memory album.
///
/// Firestore provides only safe metadata. Every photo and voice playback is
/// resolved through the short-lived, membership-checked media callable; the
/// widget never asks Firebase Storage for a public download URL.
class ServerFamilyMemoryAlbum extends StatefulWidget {
  const ServerFamilyMemoryAlbum({
    required this.serverId,
    required this.channelId,
    required this.repository,
    required this.currentUserId,
    required this.colors,
    this.role,
    this.serverHeld = false,
    this.compact = false,
    this.embedded = false,
    this.onOpenFullAlbum,
    this.imagePicker,
    this.recorderFactory,
    this.playerFactory,
    this.photoBuilder,
    super.key,
  });

  final String serverId;
  final String channelId;
  final ServerFamilyMemoryRepository repository;
  final String currentUserId;
  final ServerMemberRole? role;
  final ServerIdentityVisuals colors;
  final bool serverHeld;
  final bool compact;

  /// Dashboard mode shows the newest memories without nesting a second
  /// scroller. The channel view uses a lazy sliver grid for the whole feed.
  final bool embedded;
  final VoidCallback? onOpenFullAlbum;

  final ImagePicker? imagePicker;
  final VoiceMomentRecorder Function()? recorderFactory;
  final AudioPlayer Function()? playerFactory;
  final ServerFamilyMemoryPhotoBuilder? photoBuilder;

  @override
  State<ServerFamilyMemoryAlbum> createState() =>
      _ServerFamilyMemoryAlbumState();
}

class _ServerFamilyMemoryAlbumState extends State<ServerFamilyMemoryAlbum> {
  late Stream<List<ServerFamilyMemory>> _memories;
  String? _feedback;
  bool _feedbackIsError = false;

  bool get _canCreate =>
      !widget.serverHeld &&
      widget.role != null &&
      widget.role != ServerMemberRole.guest;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant ServerFamilyMemoryAlbum oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverId != widget.serverId ||
        oldWidget.channelId != widget.channelId ||
        oldWidget.repository != widget.repository) {
      _bind();
    }
  }

  void _bind() {
    _memories = widget.repository.watchFamilyMemories(
      widget.serverId,
      widget.channelId,
    );
  }

  void _retryFeed() {
    setState(() {
      _feedback = null;
      _bind();
    });
  }

  Future<void> _compose() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FamilyMemoryComposer(
        serverId: widget.serverId,
        channelId: widget.channelId,
        repository: widget.repository,
        colors: widget.colors,
        imagePicker: widget.imagePicker,
        recorderFactory: widget.recorderFactory,
        playerFactory: widget.playerFactory,
      ),
    );
    if (!mounted || saved != true) return;
    final copy = AppLocalizations.of(context);
    setState(() {
      _feedback = copy.text(
        'Your Family Memory is in the album.',
        'Rodzinne wspomnienie jest już w albumie.',
      );
      _feedbackIsError = false;
    });
  }

  void _reportFailure(Object error) {
    if (!mounted) return;
    final copy = AppLocalizations.of(context);
    setState(() {
      _feedback = _familyMemoryFailureCopy(error, copy);
      _feedbackIsError = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ServerFamilyMemory>>(
      stream: _memories,
      builder: (context, snapshot) {
        final header = _AlbumHeader(
          colors: widget.colors,
          canCreate: _canCreate,
          onCreate: _compose,
          onOpenFullAlbum: widget.embedded ? widget.onOpenFullAlbum : null,
          compact: widget.compact,
        );
        final feedback = _feedback == null
            ? null
            : _AlbumFeedback(message: _feedback!, isError: _feedbackIsError);
        if (widget.embedded) {
          return _embedded(context, snapshot, header, feedback);
        }
        return _full(context, snapshot, header, feedback);
      },
    );
  }

  Widget _embedded(
    BuildContext context,
    AsyncSnapshot<List<ServerFamilyMemory>> snapshot,
    Widget header,
    Widget? feedback,
  ) {
    final palette = context.appPalette;
    final memories = snapshot.data ?? const <ServerFamilyMemory>[];
    return Container(
      key: const ValueKey('server-family-memory-album-preview'),
      padding: EdgeInsets.all(widget.compact ? 16 : 20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.xl,
        border: Border.all(color: widget.colors.iconBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (feedback != null) ...[
            const SizedBox(height: AppSpacing.md),
            feedback,
          ],
          const SizedBox(height: AppSpacing.md),
          if (snapshot.hasError)
            _AlbumError(onRetry: _retryFeed)
          else if (!snapshot.hasData)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (memories.isEmpty)
            const _AlbumEmpty()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth >= 880
                    ? 3
                    : constraints.maxWidth >= 560
                    ? 2
                    : 1;
                final shown = memories.take(count).toList(growable: false);
                const gap = AppSpacing.md;
                final width = count == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - gap * (count - 1)) / count;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final memory in shown)
                      SizedBox(
                        width: width,
                        height: 390,
                        child: _memoryCard(memory),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _full(
    BuildContext context,
    AsyncSnapshot<List<ServerFamilyMemory>> snapshot,
    Widget header,
    Widget? feedback,
  ) {
    final memories = snapshot.data ?? const <ServerFamilyMemory>[];
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final cardExtent = 390.0 + ((textScale - 1).clamp(0, 1).toDouble() * 76);
    return CustomScrollView(
      key: const ValueKey('server-family-memory-album'),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            widget.compact ? 16 : 24,
            widget.compact ? 16 : 24,
            widget.compact ? 16 : 24,
            12,
          ),
          sliver: SliverToBoxAdapter(child: header),
        ),
        if (feedback != null)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              widget.compact ? 16 : 24,
              0,
              widget.compact ? 16 : 24,
              12,
            ),
            sliver: SliverToBoxAdapter(child: feedback),
          ),
        if (snapshot.hasError)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _AlbumError(onRetry: _retryFeed),
          )
        else if (!snapshot.hasData)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (memories.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: _AlbumEmpty())
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              widget.compact ? 16 : 24,
              4,
              widget.compact ? 16 : 24,
              32,
            ),
            sliver: SliverGrid.builder(
              itemCount: memories.length,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: widget.compact ? 520 : 390,
                mainAxisExtent: cardExtent,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
              ),
              itemBuilder: (context, index) => _memoryCard(memories[index]),
            ),
          ),
      ],
    );
  }

  Widget _memoryCard(ServerFamilyMemory memory) => _FamilyMemoryCard(
    key: ValueKey('server-family-memory-${memory.id}'),
    memory: memory,
    repository: widget.repository,
    colors: widget.colors,
    canDelete:
        memory.authorId == widget.currentUserId ||
        (widget.role?.canModerate ?? false),
    onFailure: _reportFailure,
    playerFactory: widget.playerFactory,
    photoBuilder: widget.photoBuilder,
  );
}

class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({
    required this.colors,
    required this.canCreate,
    required this.onCreate,
    required this.compact,
    this.onOpenFullAlbum,
  });

  final ServerIdentityVisuals colors;
  final bool canCreate;
  final VoidCallback onCreate;
  final bool compact;
  final VoidCallback? onOpenFullAlbum;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 44 : 52,
                height: compact ? 44 : 52,
                decoration: BoxDecoration(
                  color: colors.iconSurface,
                  borderRadius: AppRadius.md,
                  border: Border.all(color: colors.iconBorder),
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  color: colors.foreground,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.text('Family memories', 'Rodzinne wspomnienia'),
                      style: AppTypography.titleLarge.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      copy.text(
                        'A private album where every photo keeps the voice behind it.',
                        'Prywatny album, w którym każde zdjęcie zachowuje głos tej chwili.',
                      ),
                      style: AppTypography.bodyMedium.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (onOpenFullAlbum case final open?)
              OutlinedButton.icon(
                key: const ValueKey('server-family-memory-open-all'),
                onPressed: open,
                icon: const Icon(Icons.grid_view_rounded),
                label: Text(copy.text('Open album', 'Otwórz album')),
              ),
            if (canCreate)
              FilledButton.icon(
                key: const ValueKey('server-family-memory-add'),
                onPressed: onCreate,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.cta,
                  foregroundColor: colors.onCta,
                  minimumSize: const Size(148, 48),
                ),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(copy.text('Add memory', 'Dodaj wspomnienie')),
              ),
          ],
        ),
      ],
    );
  }
}

class _AlbumFeedback extends StatelessWidget {
  const _AlbumFeedback({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: ValueKey(
          isError
              ? 'server-family-memory-feedback-error'
              : 'server-family-memory-feedback-success',
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError ? palette.dangerSurface : palette.successSurface,
          borderRadius: AppRadius.md,
        ),
        child: Text(
          message,
          style: AppTypography.bodySmall.copyWith(
            color: isError
                ? palette.dangerForeground
                : palette.successForeground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _AlbumEmpty extends StatelessWidget {
  const _AlbumEmpty();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 38,
              color: palette.textTertiary,
            ),
            const SizedBox(height: 10),
            Text(
              copy.text(
                'No Family Memories yet',
                'Nie ma jeszcze rodzinnych wspomnień',
              ),
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium.copyWith(
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              copy.text(
                'Add a photo and record the voice that belongs with it.',
                'Dodaj zdjęcie i nagraj głos, który do niego należy.',
              ),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumError extends StatelessWidget {
  const _AlbumError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, color: palette.textTertiary),
            const SizedBox(height: 10),
            Text(
              copy.text(
                'The private album could not be loaded.',
                'Nie udało się wczytać prywatnego albumu.',
              ),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const ValueKey('server-family-memory-feed-retry'),
              onPressed: onRetry,
              child: Text(copy.text('Try again', 'Spróbuj ponownie')),
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilyMemoryCard extends StatefulWidget {
  const _FamilyMemoryCard({
    required this.memory,
    required this.repository,
    required this.colors,
    required this.canDelete,
    required this.onFailure,
    this.playerFactory,
    this.photoBuilder,
    super.key,
  });

  final ServerFamilyMemory memory;
  final ServerFamilyMemoryRepository repository;
  final ServerIdentityVisuals colors;
  final bool canDelete;
  final ValueChanged<Object> onFailure;
  final AudioPlayer Function()? playerFactory;
  final ServerFamilyMemoryPhotoBuilder? photoBuilder;

  @override
  State<_FamilyMemoryCard> createState() => _FamilyMemoryCardState();
}

class _FamilyMemoryCardState extends State<_FamilyMemoryCard> {
  late Future<ServerFamilyMemoryMediaAccess> _access;
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerState;
  StreamSubscription<void>? _completion;
  bool _playing = false;
  bool _playBusy = false;
  bool _deleteBusy = false;
  String? _deleteRequestId;

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  @override
  void didUpdateWidget(covariant _FamilyMemoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memory.id != widget.memory.id ||
        oldWidget.memory.revision != widget.memory.revision ||
        oldWidget.repository != widget.repository) {
      _deleteRequestId = null;
      _loadAccess();
    }
  }

  void _loadAccess() {
    _access = widget.repository.getFamilyMemoryMediaAccess(
      serverId: widget.memory.serverId,
      channelId: widget.memory.channelId,
      memoryId: widget.memory.id,
    );
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = (widget.playerFactory ?? AudioPlayer.new)();
    _playerState = player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
    });
    _completion = player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _playing = false);
    });
    return _player = player;
  }

  Future<void> _togglePlayback() async {
    if (_playBusy) return;
    setState(() => _playBusy = true);
    try {
      final player = _ensurePlayer();
      if (_playing) {
        await player.pause();
      } else {
        final access = await widget.repository.getFamilyMemoryMediaAccess(
          serverId: widget.memory.serverId,
          channelId: widget.memory.channelId,
          memoryId: widget.memory.id,
        );
        await player.play(UrlSource(access.voice.url.toString()));
      }
    } catch (error) {
      widget.onFailure(error);
    } finally {
      if (mounted) setState(() => _playBusy = false);
    }
  }

  Future<void> _delete() async {
    if (_deleteBusy) return;
    final copy = AppLocalizations.of(context);
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.text('Delete this memory?', 'Usunąć to wspomnienie?')),
        content: Text(
          copy.text(
            'The photo and voice recording will be removed from the family album.',
            'Zdjęcie i nagranie głosowe zostaną usunięte z rodzinnego albumu.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(copy.text('Keep', 'Zostaw')),
          ),
          FilledButton(
            key: const ValueKey('server-family-memory-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(copy.text('Delete', 'Usuń')),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    late final String requestId;
    try {
      requestId = _deleteRequestId ??= widget.repository
          .newFamilyMemoryRequestId();
    } catch (error) {
      widget.onFailure(error);
      return;
    }
    setState(() => _deleteBusy = true);
    try {
      await widget.repository.deleteFamilyMemory(
        serverId: widget.memory.serverId,
        channelId: widget.memory.channelId,
        memoryId: widget.memory.id,
        expectedRevision: widget.memory.revision,
        requestId: requestId,
      );
      _deleteRequestId = null;
    } catch (error) {
      widget.onFailure(error);
    } finally {
      if (mounted) setState(() => _deleteBusy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_playerState?.cancel());
    unawaited(_completion?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final duration = Duration(milliseconds: widget.memory.voice.durationMs!);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: FutureBuilder<ServerFamilyMemoryMediaAccess>(
              future: _access,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Material(
                    color: palette.surfaceSunken,
                    child: InkWell(
                      key: ValueKey(
                        'server-family-memory-photo-retry-${widget.memory.id}',
                      ),
                      onTap: () => setState(_loadAccess),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              color: palette.textSecondary,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              copy.text('Load photo', 'Wczytaj zdjęcie'),
                              style: AppTypography.labelMedium.copyWith(
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                final access = snapshot.data;
                if (access == null) {
                  return ColoredBox(
                    color: palette.surfaceSunken,
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }
                final builder = widget.photoBuilder;
                return builder != null
                    ? builder(context, access.photo.url)
                    : Image.network(
                        access.photo.url.toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: palette.surfaceSunken,
                          child: Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: palette.textTertiary,
                            ),
                          ),
                        ),
                      );
              },
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.memory.authorDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        _compactDate(context, widget.memory.createdAt),
                        style: AppTypography.bodySmall.copyWith(
                          color: palette.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  if (widget.memory.caption.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      widget.memory.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          key: ValueKey(
                            'server-family-memory-play-${widget.memory.id}',
                          ),
                          onPressed: _playBusy ? null : _togglePlayback,
                          icon: _playBusy
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                          label: Text(
                            '${_playing ? copy.text('Pause', 'Pauza') : copy.text('Listen', 'Posłuchaj')} '
                            '${_durationLabel(duration)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (widget.canDelete) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          key: ValueKey(
                            'server-family-memory-delete-${widget.memory.id}',
                          ),
                          onPressed: _deleteBusy ? null : _delete,
                          tooltip: copy.text(
                            'Delete memory',
                            'Usuń wspomnienie',
                          ),
                          icon: _deleteBusy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyMemoryComposer extends StatefulWidget {
  const _FamilyMemoryComposer({
    required this.serverId,
    required this.channelId,
    required this.repository,
    required this.colors,
    this.imagePicker,
    this.recorderFactory,
    this.playerFactory,
  });

  final String serverId;
  final String channelId;
  final ServerFamilyMemoryRepository repository;
  final ServerIdentityVisuals colors;
  final ImagePicker? imagePicker;
  final VoiceMomentRecorder Function()? recorderFactory;
  final AudioPlayer Function()? playerFactory;

  @override
  State<_FamilyMemoryComposer> createState() => _FamilyMemoryComposerState();
}

class _FamilyMemoryComposerState extends State<_FamilyMemoryComposer> {
  static const _maxPhotoBytes = 8 * 1024 * 1024;
  static const _maxDuration = Duration(seconds: 30);

  final _caption = TextEditingController();
  late final ImagePicker _picker = widget.imagePicker ?? ImagePicker();
  late final VoiceMomentRecorder _recorder =
      widget.recorderFactory?.call() ?? VoiceMomentRecorder();
  final RecordingLimitCues _limitCues = RecordingLimitCues();
  AudioPlayer? _previewPlayer;
  StreamSubscription<void>? _previewCompletion;
  Timer? _ticker;
  Uint8List? _photoBytes;
  String? _photoContentType;
  RecordedAudio? _voice;
  int? _voiceDurationMs;
  ServerFamilyMemoryPublishAttempt? _attempt;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _stopping = false;

  /// The note was ended by the 0:30 cap rather than by the person.
  bool _stoppedAtCap = false;

  /// Runs for [recordingAutoStopTapGrace] after the automatic stop at 0:30.
  Timer? _capStopGrace;
  bool _previewing = false;
  bool _busy = false;
  bool _published = false;
  String? _notice;

  bool get _ready =>
      _photoBytes != null && _voice != null && _voiceDurationMs != null;

  Future<void> _pickPhoto() async {
    if (_busy) return;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;
      final length = await picked.length();
      if (length < 128 || length > _maxPhotoBytes) {
        throw const ServerFamilyMemoryException(
          ServerFamilyMemoryFailure.invalidInput,
        );
      }
      final bytes = await picked.readAsBytes();
      final format = ProfileImageRules.detectFormat(bytes);
      if (format == null || bytes.lengthInBytes != length) {
        throw const ServerFamilyMemoryException(
          ServerFamilyMemoryFailure.invalidInput,
        );
      }
      setState(() {
        _photoBytes = bytes;
        _photoContentType = format.mimeType;
        _attempt = null;
        _notice = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _notice = _familyMemoryFailureCopy(
          error,
          AppLocalizations.of(context),
        ),
      );
    }
  }

  Future<void> _toggleRecording() async {
    if (_busy || _stopping) return;
    if (_recording) {
      await _finishRecording();
      return;
    }
    // A Finish aimed at the last second that lands just after the automatic
    // stop must not start a new take over the kept one.
    if (_capStopGrace?.isActive ?? false) return;
    if (_voice != null) {
      final replace = await confirmReplaceRecording(context);
      if (!replace || !mounted || _recording || _busy || _stopping) return;
    }
    try {
      await _stopPreview();
      final previous = _voice;
      _voice = null;
      _voiceDurationMs = null;
      _attempt = null;
      if (previous != null) await previous.discard();
      await _recorder.start();
      if (!mounted) {
        await _recorder.cancel();
        return;
      }
      _limitCues.reset();
      setState(() {
        _recording = true;
        _elapsed = Duration.zero;
        _stoppedAtCap = false;
        _notice = null;
      });
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted || !_recording || _stopping) return;
        final elapsed = _recorder.elapsed;
        setState(() => _elapsed = elapsed);
        if (elapsed >= _maxDuration) {
          unawaited(_finishRecording(atCap: true));
          return;
        }
        _limitCues.onTick(context, elapsed, _maxDuration);
      });
    } on VoiceRecordingException catch (error) {
      if (!mounted) return;
      setState(
        () => _notice = _recordingFailureCopy(
          error,
          AppLocalizations.of(context),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _notice = _familyMemoryFailureCopy(
          error,
          AppLocalizations.of(context),
        ),
      );
    }
  }

  /// Ends the note and keeps it. [atCap] marks the automatic stop at 0:30:
  /// the note is still kept, never discarded, and the person is told why the
  /// recording ended.
  Future<void> _finishRecording({bool atCap = false}) async {
    if (!_recording || _stopping) return;
    _stopping = true;
    _ticker?.cancel();
    try {
      final audio = await _recorder.stop();
      final durationMs = _recorder.elapsed.inMilliseconds
          .clamp(1000, 30000)
          .toInt();
      if (!mounted) {
        await audio.discard();
        return;
      }
      setState(() {
        _voice = audio;
        _voiceDurationMs = durationMs;
        _elapsed = Duration(milliseconds: durationMs);
        _recording = false;
        _stoppedAtCap = atCap;
        _attempt = null;
        _notice = null;
      });
      if (atCap) {
        _capStopGrace?.cancel();
        _capStopGrace = Timer(recordingAutoStopTapGrace, () {});
        _limitCues.onAutomaticStop(
          context,
          AppLocalizations.of(context).text(
            'Recording stopped at the 0:30 limit. Your voice is ready to save.',
            'Nagrywanie zatrzymało się na limicie 0:30. Głos jest gotowy do zapisania.',
          ),
        );
      }
    } on VoiceRecordingException catch (error) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _notice = _recordingFailureCopy(error, AppLocalizations.of(context));
      });
    } finally {
      _stopping = false;
    }
  }

  AudioPlayer _ensurePreviewPlayer() {
    final existing = _previewPlayer;
    if (existing != null) return existing;
    final player = (widget.playerFactory ?? AudioPlayer.new)();
    _previewCompletion = player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _previewing = false);
    });
    return _previewPlayer = player;
  }

  Future<void> _togglePreview() async {
    final audio = _voice;
    if (audio == null || _busy) return;
    try {
      final player = _ensurePreviewPlayer();
      if (_previewing) {
        await player.pause();
        if (mounted) setState(() => _previewing = false);
      } else {
        await player.play(audio.playbackSource);
        if (mounted) setState(() => _previewing = true);
      }
    } catch (_) {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      setState(() {
        _notice = copy.text(
          'The recording preview could not be played. You can record it again.',
          'Nie udało się odtworzyć podglądu. Możesz nagrać głos ponownie.',
        );
      });
    }
  }

  Future<void> _stopPreview() async {
    try {
      await _previewPlayer?.stop();
    } catch (_) {
      // Playback cleanup does not replace the action the person requested.
    }
    if (mounted) setState(() => _previewing = false);
  }

  Future<void> _publish() async {
    if (_busy || !_ready) return;
    final copy = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await _stopPreview();
      final attempt = _attempt ??= widget.repository
          .newFamilyMemoryPublishAttempt(
            serverId: widget.serverId,
            channelId: widget.channelId,
            caption: _caption.text,
            photoBytes: _photoBytes!,
            photoContentType: _photoContentType!,
            voice: _voice!,
            voiceDurationMs: _voiceDurationMs!,
          );
      await widget.repository.publishFamilyMemory(attempt);
      _published = true;
      await _voice?.discard();
      _voice = null;
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      if (error is ServerFamilyMemoryException &&
          error.failure == ServerFamilyMemoryFailure.expiredReservation) {
        // A replay of an expired reservation can never become valid. Keep
        // both local assets, but mint a fresh reserve/finalize identity on the
        // next press so retry can actually recover.
        _attempt = null;
      }
      setState(() {
        _busy = false;
        _notice = _familyMemoryFailureCopy(error, copy);
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _capStopGrace?.cancel();
    _caption.dispose();
    unawaited(_previewCompletion?.cancel());
    unawaited(_previewPlayer?.dispose());
    if (_recording) unawaited(_recorder.cancel());
    unawaited(_recorder.dispose());
    if (!_published) unawaited(_voice?.discard());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return PopScope(
      canPop: !_busy,
      child: Material(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: FractionallySizedBox(
          heightFactor: .92,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  24 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            copy.text(
                              'Add a Family Memory',
                              'Dodaj rodzinne wspomnienie',
                            ),
                            style: AppTypography.headlineSmall.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).pop(false),
                          tooltip: copy.text('Close', 'Zamknij'),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      copy.text(
                        'Choose one photo, then record up to 30 seconds of the voice you want to keep with it.',
                        'Wybierz jedno zdjęcie, a potem nagraj do 30 sekund głosu, który chcesz z nim zachować.',
                      ),
                      style: AppTypography.bodyMedium.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _ComposerPhoto(
                      bytes: _photoBytes,
                      busy: _busy || _attempt != null,
                      onPick: _pickPhoto,
                      colors: widget.colors,
                    ),
                    const SizedBox(height: 14),
                    _ComposerVoice(
                      recording: _recording,
                      stopping: _stopping,
                      secondsLeft: recordingSecondsLeft(_elapsed, _maxDuration),
                      stoppedAtCap: _stoppedAtCap,
                      hasVoice: _voice != null,
                      previewing: _previewing,
                      elapsed: _elapsed,
                      busy: _busy,
                      locked: _attempt != null,
                      onRecord: _toggleRecording,
                      onPreview: _togglePreview,
                      colors: widget.colors,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const ValueKey('server-family-memory-caption'),
                      controller: _caption,
                      enabled: !_busy && _attempt == null,
                      maxLength: 500,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: copy.text(
                          'Caption (optional)',
                          'Podpis (opcjonalnie)',
                        ),
                        hintText: copy.text(
                          'What should your family remember?',
                          'Co rodzina ma zapamiętać?',
                        ),
                      ),
                    ),
                    if (_notice case final notice?) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          key: const ValueKey('server-family-memory-notice'),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: palette.dangerSurface,
                            borderRadius: AppRadius.md,
                          ),
                          child: Text(
                            notice,
                            style: AppTypography.bodySmall.copyWith(
                              color: palette.dangerForeground,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      key: const ValueKey('server-family-memory-publish'),
                      onPressed: _ready && !_busy ? _publish : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.colors.cta,
                        foregroundColor: widget.colors.onCta,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_outline_rounded),
                      label: Text(
                        _busy
                            ? copy.text(
                                'Saving securely…',
                                'Bezpieczne zapisywanie…',
                              )
                            : copy.text(
                                'Save to family album',
                                'Zapisz w rodzinnym albumie',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerPhoto extends StatelessWidget {
  const _ComposerPhoto({
    required this.bytes,
    required this.busy,
    required this.onPick,
    required this.colors,
  });

  final Uint8List? bytes;
  final bool busy;
  final VoidCallback onPick;
  final ServerIdentityVisuals colors;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return AspectRatio(
      aspectRatio: 16 / 7,
      child: Material(
        color: palette.surfaceSunken,
        borderRadius: AppRadius.lg,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('server-family-memory-pick-photo'),
          onTap: busy ? null : onPick,
          child: bytes == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 34,
                      color: colors.foreground,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      copy.text('Choose a photo', 'Wybierz zdjęcie'),
                      style: AppTypography.labelLarge.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      copy.text(
                        'JPG, PNG or WebP · up to 8 MB',
                        'JPG, PNG lub WebP · do 8 MB',
                      ),
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(bytes!, fit: BoxFit.cover),
                    Align(
                      alignment: AlignmentDirectional.bottomEnd,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: FilledButton.tonalIcon(
                          onPressed: busy ? null : onPick,
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: Text(copy.text('Change', 'Zmień')),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ComposerVoice extends StatelessWidget {
  const _ComposerVoice({
    required this.recording,
    required this.stopping,
    required this.secondsLeft,
    required this.stoppedAtCap,
    required this.hasVoice,
    required this.previewing,
    required this.elapsed,
    required this.busy,
    required this.locked,
    required this.onRecord,
    required this.onPreview,
    required this.colors,
  });

  final bool recording;
  final bool stopping;
  final int? secondsLeft;
  final bool stoppedAtCap;
  final bool hasVoice;
  final bool previewing;
  final Duration elapsed;
  final bool busy;
  final bool locked;
  final VoidCallback onRecord;
  final VoidCallback onPreview;
  final ServerIdentityVisuals colors;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardWash,
        borderRadius: AppRadius.lg,
        border: Border.all(color: colors.iconBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(context, copy, palette),
          // Below the row, so the Finish button never moves in the last
          // seconds; the slot is held for the whole take.
          if (recording) ...[
            const SizedBox(height: AppRhythm.tight),
            YoRecordingCountdown(secondsLeft: secondsLeft),
          ] else if (hasVoice && stoppedAtCap) ...[
            const SizedBox(height: AppRhythm.tight),
            Text(
              copy.text(
                'Stopped at the 0:30 limit. Your voice is ready to save.',
                'Zatrzymano na limicie 0:30. Głos jest gotowy do zapisania.',
              ),
              key: const ValueKey('server-family-memory-stopped-at-limit'),
              style: AppTypography.bodySmall.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AppLocalizations copy, AppPalette palette) {
    return Row(
      children: [
        FilledButton.icon(
          key: const ValueKey('server-family-memory-record'),
          onPressed: busy || stopping || locked ? null : onRecord,
          style: FilledButton.styleFrom(
            backgroundColor: recording ? palette.dangerForeground : colors.cta,
            foregroundColor: recording ? palette.dangerSurface : colors.onCta,
            minimumSize: const Size(148, 48),
          ),
          icon: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded),
          label: Text(
            recording
                ? copy.text('Finish', 'Zakończ')
                : hasVoice
                ? copy.text('Record again', 'Nagraj ponownie')
                : copy.text('Record voice', 'Nagraj głos'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                recording
                    ? copy.text('Recording…', 'Nagrywanie…')
                    : hasVoice
                    ? copy.text('Voice ready', 'Głos gotowy')
                    : copy.text('Up to 30 seconds', 'Do 30 sekund'),
                style: AppTypography.labelLarge.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_durationLabel(elapsed)} / 0:30',
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        if (hasVoice && !recording)
          IconButton.filledTonal(
            key: const ValueKey('server-family-memory-preview'),
            onPressed: busy ? null : onPreview,
            tooltip: previewing
                ? copy.text('Pause preview', 'Wstrzymaj podgląd')
                : copy.text('Play preview', 'Odtwórz podgląd'),
            icon: Icon(
              previewing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
      ],
    );
  }
}

String _compactDate(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final material = MaterialLocalizations.of(context);
  return material.formatShortDate(local);
}

String _durationLabel(Duration value) {
  final total = value.inSeconds.clamp(0, 5999);
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

String _recordingFailureCopy(
  VoiceRecordingException error,
  AppLocalizations copy,
) => switch (error.problem) {
  VoiceRecordingProblem.platformCannotRecord => copy.text(
    'Voice recording is not available on this device or browser.',
    'Nagrywanie głosu nie jest dostępne na tym urządzeniu lub w tej przeglądarce.',
  ),
  VoiceRecordingProblem.microphoneBlocked => copy.text(
    'Allow microphone access in your device or browser settings, then try again.',
    'Zezwól na mikrofon w ustawieniach urządzenia lub przeglądarki i spróbuj ponownie.',
  ),
  VoiceRecordingProblem.microphonePromptDismissed => copy.text(
    'Start recording again and allow microphone access.',
    'Rozpocznij nagrywanie ponownie i zezwól na dostęp do mikrofonu.',
  ),
  VoiceRecordingProblem.microphoneNotFound => copy.text(
    'No microphone was found.',
    'Nie znaleziono mikrofonu.',
  ),
  VoiceRecordingProblem.microphoneUnavailable => copy.text(
    'The microphone is busy in another app. Close it there and try again.',
    'Mikrofon jest używany przez inną aplikację. Zamknij ją i spróbuj ponownie.',
  ),
  VoiceRecordingProblem.captureFailed ||
  VoiceRecordingProblem.recordingUnusable ||
  VoiceRecordingProblem.uploadFailed => copy.text(
    'The voice recording could not be prepared. Record it again.',
    'Nie udało się przygotować nagrania głosowego. Nagraj je ponownie.',
  ),
};

String _familyMemoryFailureCopy(Object error, AppLocalizations copy) {
  final failure = error is ServerFamilyMemoryException
      ? error.failure
      : ServerFamilyMemoryFailure.unavailable;
  return switch (failure) {
    ServerFamilyMemoryFailure.permission => copy.text(
      'You no longer have permission to change this family album.',
      'Nie masz już uprawnień do zmiany tego rodzinnego albumu.',
    ),
    ServerFamilyMemoryFailure.quota => copy.text(
      'The Family Memory upload limit is reached. Try again later.',
      'Limit przesyłania rodzinnych wspomnień został wyczerpany. Spróbuj później.',
    ),
    ServerFamilyMemoryFailure.expiredReservation => copy.text(
      'The secure upload expired. Keep this sheet open and try again.',
      'Bezpieczne przesyłanie wygasło. Zostaw ten ekran otwarty i spróbuj ponownie.',
    ),
    ServerFamilyMemoryFailure.changed => copy.text(
      'The album changed during this action. Review it and try again.',
      'Album zmienił się podczas tej operacji. Sprawdź go i spróbuj ponownie.',
    ),
    ServerFamilyMemoryFailure.missing => copy.text(
      'This Family Memory is no longer available.',
      'To rodzinne wspomnienie nie jest już dostępne.',
    ),
    ServerFamilyMemoryFailure.invalidInput => copy.text(
      'Choose a JPG, PNG or WebP under 8 MB and record 1–30 seconds of voice.',
      'Wybierz JPG, PNG lub WebP do 8 MB i nagraj 1–30 sekund głosu.',
    ),
    ServerFamilyMemoryFailure.corruptData => copy.text(
      'This Family Memory needs repair before it can be opened.',
      'To rodzinne wspomnienie wymaga naprawy, zanim będzie można je otworzyć.',
    ),
    ServerFamilyMemoryFailure.unavailable => copy.text(
      'The Family Memory could not be saved. Check your connection and try again.',
      'Nie udało się zapisać rodzinnego wspomnienia. Sprawdź połączenie i spróbuj ponownie.',
    ),
  };
}
