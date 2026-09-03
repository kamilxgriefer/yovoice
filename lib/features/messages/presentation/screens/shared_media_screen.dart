import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_video_playback_source.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_voice_playback_source.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

typedef SharedMediaFirstPageWatcher =
    Stream<SharedMediaPage> Function(MessageType type);
typedef SharedMediaPageLoader =
    Future<SharedMediaPage> Function(MessageType type, Object cursor);

class SharedMediaScreen extends StatefulWidget {
  const SharedMediaScreen({
    required this.conversationId,
    this.messageService,
    this.messagesStream,
    this.privateMediaLoader,
    this.audioPlayerFactory,
    this.voiceSourcePreparer,
    this.videoSourcePreparer,
    this.firstPageWatcher,
    this.pageLoader,
    super.key,
  });

  final String conversationId;
  final MessageService? messageService;

  /// Injection seam for deterministic loading/error/gallery tests.
  final Stream<List<Message>>? messagesStream;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final AudioPlayer Function()? audioPlayerFactory;
  final DirectVoiceSourcePreparer? voiceSourcePreparer;
  final DirectVideoSourcePreparer? videoSourcePreparer;
  final SharedMediaFirstPageWatcher? firstPageWatcher;
  final SharedMediaPageLoader? pageLoader;

  @override
  State<SharedMediaScreen> createState() => _SharedMediaScreenState();
}

class _SharedMediaScreenState extends State<SharedMediaScreen> {
  late Stream<List<Message>> _messages = _newStream();

  MessageService get _service => widget.messageService ?? MessageService.live;

  Stream<List<Message>> _newStream() =>
      widget.messagesStream ??
      (widget.messageService ?? MessageService.live).watchMessages(
        widget.conversationId,
      );

  void _retry() => setState(() => _messages = _newStream());

  Stream<SharedMediaPage> _watchFirstPage(MessageType type) =>
      widget.firstPageWatcher?.call(type) ??
      _service.watchSharedMediaFirstPage(
        conversationId: widget.conversationId,
        type: type,
      );

  Future<SharedMediaPage> _loadPage(MessageType type, Object cursor) =>
      widget.pageLoader?.call(type, cursor) ??
      _service.loadSharedMediaPage(
        conversationId: widget.conversationId,
        type: type,
        cursor: cursor,
      );

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        key: const ValueKey('shared-media-screen'),
        backgroundColor: palette.background,
        appBar: AppBar(
          backgroundColor: palette.navigationSurface,
          foregroundColor: palette.textPrimary,
          title: Text(copy.text('Shared media', 'Udostępnione multimedia')),
          bottom: TabBar(
            labelColor: palette.focus,
            unselectedLabelColor: palette.textSecondary,
            indicatorColor: palette.focus,
            tabs: [
              Tab(
                icon: const Icon(Icons.photo_library_outlined),
                text: copy.text('Photos', 'Zdjęcia'),
              ),
              Tab(
                icon: const Icon(Icons.videocam_outlined),
                text: copy.text('Videos', 'Filmy'),
              ),
              Tab(
                icon: const Icon(Icons.mic_none_rounded),
                text: copy.text('Voice', 'Głosowe'),
              ),
            ],
          ),
        ),
        body: ResponsiveContentFrame(
          width: ResponsiveContentWidth.list,
          child: widget.messagesStream == null
              ? TabBarView(
                  children: <Widget>[
                    _PagedSharedMediaTab(
                      key: ValueKey(
                        '${widget.conversationId}-${MessageType.image.name}',
                      ),
                      type: MessageType.image,
                      firstPage: _watchFirstPage(MessageType.image),
                      loadPage: (cursor) =>
                          _loadPage(MessageType.image, cursor),
                      builder: (context, messages, footer) => _PhotosTab(
                        messages: messages,
                        privateMediaLoader: widget.privateMediaLoader,
                        paginationFooter: footer,
                      ),
                    ),
                    _PagedSharedMediaTab(
                      key: ValueKey(
                        '${widget.conversationId}-${MessageType.video.name}',
                      ),
                      type: MessageType.video,
                      firstPage: _watchFirstPage(MessageType.video),
                      loadPage: (cursor) =>
                          _loadPage(MessageType.video, cursor),
                      builder: (context, messages, footer) => _VideosTab(
                        messages: messages,
                        privateMediaLoader: widget.privateMediaLoader,
                        videoSourcePreparer: widget.videoSourcePreparer,
                        paginationFooter: footer,
                      ),
                    ),
                    _PagedSharedMediaTab(
                      key: ValueKey(
                        '${widget.conversationId}-${MessageType.voice.name}',
                      ),
                      type: MessageType.voice,
                      firstPage: _watchFirstPage(MessageType.voice),
                      loadPage: (cursor) =>
                          _loadPage(MessageType.voice, cursor),
                      builder: (context, messages, footer) => _VoiceTab(
                        messages: messages,
                        privateMediaLoader: widget.privateMediaLoader,
                        audioPlayerFactory: widget.audioPlayerFactory,
                        voiceSourcePreparer: widget.voiceSourcePreparer,
                        paginationFooter: footer,
                      ),
                    ),
                  ],
                )
              : StreamBuilder<List<Message>>(
                  stream: _messages,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return Center(
                        child: Semantics(
                          label: copy.text(
                            'Loading shared media',
                            'Wczytywanie udostępnionych multimediów',
                          ),
                          child: CircularProgressIndicator(
                            color: palette.focus,
                          ),
                        ),
                      );
                    }
                    if (snapshot.hasError && !snapshot.hasData) {
                      return _SharedMediaError(onRetry: _retry);
                    }

                    final history = (snapshot.data ?? const <Message>[])
                        .where(
                          (message) =>
                              !message.isDeleted &&
                              (message.mediaUrl?.trim().isNotEmpty ?? false),
                        )
                        .toList(growable: false);
                    final photos = history
                        .where((message) => message.type == MessageType.image)
                        .toList(growable: false);
                    final voices = history
                        .where((message) => message.type == MessageType.voice)
                        .toList(growable: false);
                    final videos = history
                        .where((message) => message.type == MessageType.video)
                        .toList(growable: false);

                    return TabBarView(
                      children: [
                        _PhotosTab(
                          messages: photos,
                          privateMediaLoader: widget.privateMediaLoader,
                          paginationFooter: null,
                        ),
                        _VideosTab(
                          messages: videos,
                          privateMediaLoader: widget.privateMediaLoader,
                          videoSourcePreparer: widget.videoSourcePreparer,
                          paginationFooter: null,
                        ),
                        _VoiceTab(
                          messages: voices,
                          privateMediaLoader: widget.privateMediaLoader,
                          audioPlayerFactory: widget.audioPlayerFactory,
                          voiceSourcePreparer: widget.voiceSourcePreparer,
                          paginationFooter: null,
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }
}

typedef _SharedMediaTabBuilder =
    Widget Function(
      BuildContext context,
      List<Message> messages,
      Widget? paginationFooter,
    );

class _PagedSharedMediaTab extends StatefulWidget {
  const _PagedSharedMediaTab({
    required this.type,
    required this.firstPage,
    required this.loadPage,
    required this.builder,
    super.key,
  });

  final MessageType type;
  final Stream<SharedMediaPage> firstPage;
  final Future<SharedMediaPage> Function(Object cursor) loadPage;
  final _SharedMediaTabBuilder builder;

  @override
  State<_PagedSharedMediaTab> createState() => _PagedSharedMediaTabState();
}

class _PagedSharedMediaTabState extends State<_PagedSharedMediaTab>
    with AutomaticKeepAliveClientMixin {
  StreamSubscription<SharedMediaPage>? _subscription;
  SharedMediaPage? _firstPage;
  final List<Message> _older = <Message>[];
  Object? _nextCursor;
  Object? _firstPageError;
  Object? _nextPageError;
  bool _waitingForFirstPage = true;
  bool _loadingNextPage = false;
  bool _hasMore = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    _waitingForFirstPage = _firstPage == null;
    _firstPageError = null;
    _subscription = widget.firstPage.listen(
      (page) {
        if (!mounted) return;
        setState(() {
          final previous = _firstPage?.messages ?? const <Message>[];
          final currentIds = page.messages.map((item) => item.id).toSet();
          final hiddenIds = page.hiddenMessageIds;
          _older.removeWhere((message) => hiddenIds.contains(message.id));
          for (final message in previous.reversed) {
            if (!currentIds.contains(message.id) &&
                !hiddenIds.contains(message.id) &&
                !_older.any((item) => item.id == message.id)) {
              _older.insert(0, message);
            }
          }
          _firstPage = page;
          _waitingForFirstPage = false;
          _firstPageError = null;
          if (_nextCursor == null) {
            _nextCursor = page.cursor;
            _hasMore = page.hasMore;
          }
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        setState(() {
          _waitingForFirstPage = false;
          _firstPageError = error;
        });
      },
    );
  }

  List<Message> get _visibleMessages {
    final byId = <String, Message>{};
    for (final message in <Message>[...?_firstPage?.messages, ..._older]) {
      byId.putIfAbsent(message.id, () => message);
    }
    final result = byId.values
        .where(
          (message) =>
              message.type == widget.type &&
              !message.isDeleted &&
              (message.mediaUrl?.trim().isNotEmpty ?? false),
        )
        .toList(growable: false);
    result.sort((first, second) {
      final byTime = second.sentAt.compareTo(first.sentAt);
      return byTime != 0 ? byTime : second.id.compareTo(first.id);
    });
    return result;
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor ?? _firstPage?.cursor;
    if (_loadingNextPage || !_hasMore || cursor == null) return;
    setState(() {
      _loadingNextPage = true;
      _nextPageError = null;
    });
    try {
      final page = await widget.loadPage(cursor);
      if (!mounted) return;
      setState(() {
        final knownIds = <String>{
          ...?_firstPage?.messages.map((item) => item.id),
          ..._older.map((item) => item.id),
        };
        _older.addAll(
          page.messages.where((message) => knownIds.add(message.id)),
        );
        _nextCursor = page.cursor;
        _hasMore = page.hasMore && page.cursor != null;
      });
    } catch (error) {
      if (mounted) setState(() => _nextPageError = error);
    } finally {
      if (mounted) setState(() => _loadingNextPage = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_waitingForFirstPage && _firstPage == null) {
      return Center(
        child: Semantics(
          label: AppLocalizations.of(context).text(
            'Loading shared media',
            'Wczytywanie udostępnionych multimediów',
          ),
          child: CircularProgressIndicator(color: context.appPalette.focus),
        ),
      );
    }
    if (_firstPageError != null && _firstPage == null) {
      return _SharedMediaError(onRetry: _subscribe);
    }
    final footer = _hasMore || _loadingNextPage || _nextPageError != null
        ? _SharedMediaPaginationFooter(
            loading: _loadingNextPage,
            failed: _nextPageError != null,
            onPressed: _loadMore,
          )
        : null;
    return widget.builder(context, _visibleMessages, footer);
  }
}

class _SharedMediaPaginationFooter extends StatelessWidget {
  const _SharedMediaPaginationFooter({
    required this.loading,
    required this.failed,
    required this.onPressed,
  });

  final bool loading;
  final bool failed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Semantics(
        liveRegion: failed,
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: loading ? null : onPressed,
            icon: loading
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.focus,
                    ),
                  )
                : Icon(failed ? Icons.refresh_rounded : Icons.history_rounded),
            label: Text(
              failed
                  ? copy.text(
                      'Try loading older media again',
                      'Spróbuj ponownie',
                    )
                  : copy.text('Load older media', 'Wczytaj starsze multimedia'),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideosTab extends StatelessWidget {
  const _VideosTab({
    required this.messages,
    required this.privateMediaLoader,
    required this.videoSourcePreparer,
    required this.paginationFooter,
  });

  final List<Message> messages;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final DirectVideoSourcePreparer? videoSourcePreparer;
  final Widget? paginationFooter;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    if (messages.isEmpty) {
      return _MediaTabWithFooter(
        footer: paginationFooter,
        child: _EmptyMediaTab(
          icon: Icons.video_library_outlined,
          title: copy.text(
            'No shared videos yet',
            'Brak udostępnionych filmów',
          ),
          detail: copy.text(
            'Videos sent in this conversation will appear here.',
            'Filmy wysłane w tej rozmowie pojawią się tutaj.',
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 820
            ? 4
            : constraints.maxWidth >= 560
            ? 3
            : 2;
        return _MediaTabWithFooter(
          footer: paginationFooter,
          child: GridView.builder(
            key: const PageStorageKey('shared-media-videos'),
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 28),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 16 / 11,
            ),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              return Semantics(
                container: true,
                label: copy.text('Shared video', 'Udostępniony film'),
                child: DirectMessageMediaPreview(
                  message: message,
                  photoWidth: double.infinity,
                  photoHeight: double.infinity,
                  privateMediaLoader: privateMediaLoader,
                  videoSourcePreparer: videoSourcePreparer,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _PhotosTab extends StatelessWidget {
  const _PhotosTab({
    required this.messages,
    required this.privateMediaLoader,
    required this.paginationFooter,
  });

  final List<Message> messages;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final Widget? paginationFooter;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    if (messages.isEmpty) {
      return _MediaTabWithFooter(
        footer: paginationFooter,
        child: _EmptyMediaTab(
          icon: Icons.photo_library_outlined,
          title: copy.text('No shared photos yet', 'Brak udostępnionych zdjęć'),
          detail: copy.text(
            'Photos sent in this conversation will appear here.',
            'Zdjęcia wysłane w tej rozmowie pojawią się tutaj.',
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 820
            ? 4
            : constraints.maxWidth >= 560
            ? 3
            : 2;
        return _MediaTabWithFooter(
          footer: paginationFooter,
          child: GridView.builder(
            key: const PageStorageKey('shared-media-photos'),
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 28),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1,
            ),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              return Semantics(
                container: true,
                image: true,
                label: copy.text('Shared photo', 'Udostępnione zdjęcie'),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: ColoredBox(
                    color: context.appPalette.surfaceRaised,
                    child: DirectMessageMediaPreview(
                      message: message,
                      photoWidth: double.infinity,
                      photoHeight: double.infinity,
                      privateMediaLoader: privateMediaLoader,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _VoiceTab extends StatelessWidget {
  const _VoiceTab({
    required this.messages,
    required this.privateMediaLoader,
    required this.audioPlayerFactory,
    required this.voiceSourcePreparer,
    required this.paginationFooter,
  });

  final List<Message> messages;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final AudioPlayer Function()? audioPlayerFactory;
  final DirectVoiceSourcePreparer? voiceSourcePreparer;
  final Widget? paginationFooter;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    if (messages.isEmpty) {
      return _MediaTabWithFooter(
        footer: paginationFooter,
        child: _EmptyMediaTab(
          icon: Icons.mic_none_rounded,
          title: copy.text(
            'No shared voice messages yet',
            'Brak udostępnionych wiadomości głosowych',
          ),
          detail: copy.text(
            'Voice messages sent in this conversation will appear here.',
            'Wiadomości głosowe wysłane w tej rozmowie pojawią się tutaj.',
          ),
        ),
      );
    }
    return _MediaTabWithFooter(
      footer: paginationFooter,
      child: ListView.separated(
        key: const PageStorageKey('shared-media-voice'),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
        itemCount: messages.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final message = messages[index];
          return Semantics(
            container: true,
            label: copy.text('Shared voice message', 'Wiadomość głosowa'),
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: context.appPalette.surfaceRaised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.appPalette.border),
              ),
              child: DirectMessageMediaPreview(
                message: message,
                privateMediaLoader: privateMediaLoader,
                audioPlayerFactory: audioPlayerFactory,
                voiceSourcePreparer: voiceSourcePreparer,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MediaTabWithFooter extends StatelessWidget {
  const _MediaTabWithFooter({required this.child, required this.footer});

  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(child: child),
        ?footer,
      ],
    );
  }
}

class _EmptyMediaTab extends StatelessWidget {
  const _EmptyMediaTab({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Semantics(
          container: true,
          label: '$title. $detail',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: palette.textTertiary),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharedMediaError extends StatelessWidget {
  const _SharedMediaError({required this.onRetry});

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
            Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              copy.text(
                'Could not load shared media.',
                'Nie udało się wczytać udostępnionych multimediów.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textPrimary),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(copy.text('Try again', 'Spróbuj ponownie')),
            ),
          ],
        ),
      ),
    );
  }
}
