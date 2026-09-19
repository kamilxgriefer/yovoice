import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/media/yo_media_send_review.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_company_file.dart';
import '../../data/models/server_member_role.dart';
import '../../data/services/server_company_file_service.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';

typedef ServerCompanyFilePicker =
    Future<ServerCompanyFileSelection?> Function();
typedef ServerCompanyFileOpener = Future<bool> Function(Uri url);

/// The Company server's private, persistent file shelf. Firestore contains
/// descriptors only; every open resolves a fresh short-lived signed URL.
class ServerCompanyFilesBoard extends StatefulWidget {
  const ServerCompanyFilesBoard({
    required this.server,
    required this.channel,
    required this.repository,
    required this.role,
    this.compact = false,
    this.pickFile,
    this.openFile,
    this.online,
    super.key,
  });

  final Server server;
  final ServerChannel channel;
  final ServerCompanyFileRepository repository;
  final ServerMemberRole? role;
  final bool compact;
  final ServerCompanyFilePicker? pickFile;
  final ServerCompanyFileOpener? openFile;
  final Stream<bool>? online;

  @override
  State<ServerCompanyFilesBoard> createState() =>
      _ServerCompanyFilesBoardState();
}

class _ServerCompanyFilesBoardState extends State<ServerCompanyFilesBoard> {
  late Stream<List<ServerCompanyFile>> _files;
  late Stream<bool> _online;
  ServerCompanyFileUploadAttempt? _uploadAttempt;
  String? _busyFileId;
  String? _error;
  double? _uploadProgress;

  bool get _canUpload =>
      widget.role != null && widget.role != ServerMemberRole.guest;

  @override
  void initState() {
    super.initState();
    _listen();
    _online = widget.online ?? _defaultOnline();
  }

  @override
  void didUpdateWidget(ServerCompanyFilesBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.server.id != widget.server.id ||
        oldWidget.channel.id != widget.channel.id ||
        oldWidget.repository != widget.repository) {
      _listen();
      _uploadAttempt = null;
      _busyFileId = null;
      _error = null;
    }
    if (oldWidget.online != widget.online) {
      _online = widget.online ?? _defaultOnline();
    }
  }

  void _listen() {
    _files = widget.repository.watchCompanyFiles(
      widget.server.id,
      widget.channel.id,
    );
  }

  Future<void> _chooseAndUpload() async {
    if (!_canUpload || _uploadProgress != null || _busyFileId != null) return;
    try {
      final selection = await (widget.pickFile ?? _pickCompanyFile)();
      if (selection == null || !mounted) return;
      final decision = await _reviewSelection(selection);
      if (decision == null || !mounted) return;
      if (decision.choice == YoMediaSendChoice.chooseAnother) {
        return _chooseAndUpload();
      }
      _uploadAttempt = widget.repository.newCompanyFileUploadAttempt(
        serverId: widget.server.id,
        channelId: widget.channel.id,
        selection: selection,
      );
      await _publishUpload();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _failure(error));
    }
  }

  /// Nothing reaches the shelf before the member has seen what they picked
  /// (ADR-210). The upload itself stays on the board, with its progress row.
  Future<YoMediaSendDecision?> _reviewSelection(
    ServerCompanyFileSelection selection,
  ) {
    final copy = AppLocalizations.of(context);
    final isImage = selection.contentType.startsWith('image/');
    return showYoMediaSendReview(
      context,
      item: YoPickedMedia(
        file: XFile.fromData(
          selection.bytes,
          name: selection.displayName,
          mimeType: selection.contentType,
        ),
        kind: isImage ? YoPickedMediaKind.image : YoPickedMediaKind.document,
        sizeBytes: selection.bytes.lengthInBytes,
        displayName: selection.displayName,
        contentType: selection.contentType,
        bytes: selection.bytes,
      ),
      limits: const YoMediaSendLimits(
        maxImageBytes: serverCompanyFileMaxBytes,
        maxDocumentBytes: serverCompanyFileMaxBytes,
      ),
      title: copy.text('Upload this file?', 'Dodać ten plik?'),
      sendLabel: copy.serverCompanyFileUpload,
      destinationLabel: copy.template(
        'To {name}',
        'Do: {name}',
        values: <String, Object>{'name': copy.serverCompanyFilesTitle},
      ),
    );
  }

  Future<void> _publishUpload() async {
    final attempt = _uploadAttempt;
    if (attempt == null || _uploadProgress != null) return;
    setState(() {
      _uploadProgress = 0;
      _error = null;
    });
    try {
      await widget.repository.publishCompanyFile(
        attempt,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _uploadProgress = progress.clamp(0.0, 1.0).toDouble());
        },
      );
      if (!mounted) return;
      setState(() {
        _uploadAttempt = null;
        _uploadProgress = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploadProgress = null;
        _error = _failure(error);
      });
    }
  }

  Future<void> _open(ServerCompanyFile file) async {
    if (_busyFileId != null || _uploadProgress != null) return;
    setState(() {
      _busyFileId = file.id;
      _error = null;
    });
    try {
      final access = await widget.repository.getCompanyFileAccess(file: file);
      if (!access.expiresAt.isAfter(DateTime.now().toUtc())) {
        throw const FormatException('The Company File access grant expired.');
      }
      final opened = await (widget.openFile ?? _openExternally)(access.url);
      if (!opened) throw StateError('The Company File could not be opened.');
      if (mounted) setState(() => _busyFileId = null);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyFileId = null;
        _error = _failure(error);
      });
    }
  }

  Future<void> _delete(ServerCompanyFile file) async {
    final copy = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(copy.serverCompanyFileDeleteTitle),
        content: Text(copy.serverCompanyFileDeleteBody(file.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(copy.serverCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(copy.serverCompanyFileDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busyFileId != null) return;
    setState(() {
      _busyFileId = file.id;
      _error = null;
    });
    try {
      await widget.repository.deleteCompanyFile(
        file: file,
        requestId: widget.repository.newRequestId(),
      );
      if (mounted) setState(() => _busyFileId = null);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyFileId = null;
        _error = _failure(error);
      });
    }
  }

  String _failure(Object error) => serverActionFailureCopy(
    error,
    AppLocalizations.of(context),
    fallback: AppLocalizations.of(context).serverCompanyFileActionFailed,
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: _online,
    initialData: true,
    builder: (context, onlineSnapshot) {
      final online = onlineSnapshot.data ?? true;
      return StreamBuilder<List<ServerCompanyFile>>(
        stream: _files,
        builder: (context, snapshot) {
          if (snapshot.hasError && !snapshot.hasData) {
            if (!online) return _OfflineState(compact: widget.compact);
            return SingleChildScrollView(
              child: YoErrorState(
                error: snapshot.error,
                compact: widget.compact,
                onRetry: () => setState(_listen),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final files = snapshot.data!;
          if (files.isEmpty && !online) {
            return _OfflineState(compact: widget.compact);
          }
          if (files.isEmpty) {
            final copy = AppLocalizations.of(context);
            return SingleChildScrollView(
              child: YoEmptyState(
                icon: Icons.folder_outlined,
                title: copy.serverCompanyFilesEmptyTitle,
                subtitle: copy.serverCompanyFilesEmptyBody,
                actionLabel: _canUpload ? copy.serverCompanyFileUpload : null,
                onAction: _canUpload ? _chooseAndUpload : null,
                compact: widget.compact,
              ),
            );
          }
          return _content(files, online);
        },
      );
    },
  );

  Widget _content(List<ServerCompanyFile> files, bool online) {
    final copy = AppLocalizations.of(context);
    return CustomScrollView(
      key: const ValueKey('server-company-files-board'),
      slivers: [
        SliverToBoxAdapter(
          child: _FilesHeader(
            server: widget.server,
            compact: widget.compact,
            showUpload: _canUpload,
            onUpload: _canUpload && online && _uploadProgress == null
                ? _chooseAndUpload
                : null,
          ),
        ),
        if (!online)
          SliverToBoxAdapter(
            child: _MessageBanner(
              key: const ValueKey('server-company-files-offline-banner'),
              icon: Icons.cloud_off_rounded,
              message: copy.serverCompanyFilesOfflineCached,
              danger: false,
              compact: widget.compact,
            ),
          ),
        if (_uploadProgress case final progress?)
          SliverToBoxAdapter(
            child: _UploadProgress(
              progress: progress,
              displayName: _uploadAttempt?.selection.displayName ?? '',
              compact: widget.compact,
            ),
          ),
        if (_error case final error?)
          SliverToBoxAdapter(
            child: _MessageBanner(
              key: const ValueKey('server-company-file-error'),
              icon: Icons.error_outline_rounded,
              message: error,
              danger: true,
              compact: widget.compact,
              actionLabel: _uploadAttempt == null
                  ? null
                  : copy.serverCompanyFileRetry,
              onAction: _uploadAttempt == null || !online
                  ? null
                  : _publishUpload,
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            widget.compact ? 12 : 20,
            0,
            widget.compact ? 12 : 20,
            28,
          ),
          sliver: SliverList.separated(
            itemCount: files.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final file = files[index];
              final canDelete =
                  online &&
                  widget.role != null &&
                  widget.role != ServerMemberRole.guest &&
                  (widget.role?.canModerate == true ||
                      file.ownerId == widget.repository.currentUserId);
              return _FileCard(
                file: file,
                busy: _busyFileId == file.id,
                online: online,
                onOpen: () => _open(file),
                onDelete: canDelete ? () => _delete(file) : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilesHeader extends StatelessWidget {
  const _FilesHeader({
    required this.server,
    required this.compact,
    required this.showUpload,
    required this.onUpload,
  });

  final Server server;
  final bool compact;
  final bool showUpload;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    final intro = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.folder_copy_outlined, size: 32, color: colors.foreground),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  copy.serverCompanyFilesTitle,
                  style: AppTypography.titleLarge.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                copy.serverCompanyFilesBody,
                style: AppTypography.bodyMedium.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final upload = FilledButton.icon(
      key: const ValueKey('server-company-file-upload'),
      onPressed: onUpload,
      icon: const Icon(Icons.upload_file_rounded),
      label: Text(copy.serverCompanyFileUpload),
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
    );
    return Container(
      margin: EdgeInsets.all(compact ? 12 : 20),
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        color: colors.cardWash,
        borderRadius: AppRadius.lg,
        border: Border.all(color: colors.iconBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                intro,
                if (showUpload) ...[const SizedBox(height: 16), upload],
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: intro),
              if (showUpload) ...[const SizedBox(width: 18), upload],
            ],
          );
        },
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.file,
    required this.busy,
    required this.online,
    required this.onOpen,
    required this.onDelete,
  });

  final ServerCompanyFile file;
  final bool busy;
  final bool online;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final localizations = MaterialLocalizations.of(context);
    final created = file.createdAt.toLocal();
    return Semantics(
      container: true,
      label:
          '${file.displayName}. ${file.ownerDisplayName}. '
          '${_fileType(copy, file.file.contentType)}.',
      child: Container(
        key: ValueKey('server-company-file-${file.id}'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadius.lg,
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: palette.infoSurface,
                    borderRadius: AppRadius.md,
                  ),
                  child: Icon(
                    _fileIcon(file.file.contentType),
                    color: palette.infoForeground,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.displayName,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleMedium.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${file.ownerDisplayName} · '
                        '${localizations.formatShortDate(created)} · '
                        '${_fileSize(file.file.size)}',
                        style: AppTypography.bodySmall.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  key: ValueKey('server-company-file-open-${file.id}'),
                  onPressed: busy || !online ? null : onOpen,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new_rounded),
                  label: Text(copy.serverCompanyFileOpen),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                ),
                if (onDelete != null)
                  OutlinedButton.icon(
                    key: ValueKey('server-company-file-delete-${file.id}'),
                    onPressed: busy ? null : onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(copy.serverCompanyFileDelete),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: palette.dangerForeground,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadProgress extends StatelessWidget {
  const _UploadProgress({
    required this.progress,
    required this.displayName,
    required this.compact,
  });

  final double progress;
  final String displayName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      label: copy.serverCompanyFileUploading(displayName),
      child: Container(
        key: const ValueKey('server-company-file-progress'),
        margin: EdgeInsets.fromLTRB(
          compact ? 12 : 20,
          0,
          compact ? 12 : 20,
          12,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.appPalette.infoSurface,
          borderRadius: AppRadius.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              copy.serverCompanyFileUploading(displayName),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress),
          ],
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    required this.icon,
    required this.message,
    required this.danger,
    required this.compact,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String message;
  final bool danger;
  final bool compact;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final foreground = danger
        ? palette.dangerForeground
        : palette.warningForeground;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: EdgeInsets.fromLTRB(
          compact ? 12 : 20,
          0,
          compact ? 12 : 20,
          12,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: danger ? palette.dangerSurface : palette.warningSurface,
          borderRadius: AppRadius.md,
        ),
        child: Row(
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 8),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfflineState extends StatelessWidget {
  const _OfflineState({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return SingleChildScrollView(
      key: const ValueKey('server-company-files-offline'),
      child: YoEmptyState(
        icon: Icons.cloud_off_rounded,
        title: copy.serverCompanyFilesOfflineTitle,
        subtitle: copy.serverCompanyFilesOfflineBody,
        compact: compact,
      ),
    );
  }
}

Future<ServerCompanyFileSelection?> _pickCompanyFile() async {
  const group = XTypeGroup(
    label: 'Documents and images',
    extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'txt'],
    mimeTypes: [
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/webp',
      'text/plain',
    ],
    uniformTypeIdentifiers: [
      'com.adobe.pdf',
      'public.jpeg',
      'public.png',
      'org.webmproject.webp',
      'public.plain-text',
    ],
  );
  final file = await openFile(acceptedTypeGroups: const [group]);
  if (file == null) return null;
  final length = await file.length();
  if (length < 1 || length > serverCompanyFileMaxBytes) {
    throw const FormatException('Choose a file no larger than 25 MB.');
  }
  final bytes = await file.readAsBytes();
  if (bytes.lengthInBytes != length) {
    throw const FormatException('The selected file could not be read.');
  }
  final contentType = detectServerCompanyFileContentType(bytes);
  if (contentType == null) {
    throw const FormatException('Choose a PDF, JPG, PNG, WEBP or TXT file.');
  }
  return ServerCompanyFileSelection(
    displayName: file.name.trim(),
    contentType: contentType,
    bytes: bytes,
  );
}

Future<bool> _openExternally(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

Stream<bool> _defaultOnline() async* {
  final connectivity = Connectivity();
  try {
    yield _hasConnection(await connectivity.checkConnectivity());
  } catch (_) {
    // Connectivity is a UI hint. A plugin probe failure must not block the
    // real Firestore/callable operation, which remains authoritative.
    yield true;
  }
  yield* connectivity.onConnectivityChanged.map(_hasConnection);
}

bool _hasConnection(List<ConnectivityResult> results) =>
    results.any((result) => result != ConnectivityResult.none);

IconData _fileIcon(String contentType) => switch (contentType) {
  'application/pdf' => Icons.picture_as_pdf_outlined,
  'text/plain' => Icons.description_outlined,
  _ => Icons.image_outlined,
};

String _fileType(AppLocalizations copy, String contentType) =>
    switch (contentType) {
      'application/pdf' => 'PDF',
      'image/jpeg' => 'JPG',
      'image/png' => 'PNG',
      'image/webp' => 'WEBP',
      'text/plain' => copy.serverCompanyFileTextType,
      _ => copy.serverCompanyFileGenericType,
    };

String _fileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}
