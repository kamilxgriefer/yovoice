import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/clubs/data/models/club_chat_authority.dart';
import 'package:yovoice/features/clubs/data/models/club_member.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/media/data/services/gif_message_controller.dart';
import 'package:yovoice/features/media/data/services/gif_transport.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart'
    show
        DirectMessageMediaPickAction,
        DirectMessagePhotoPicker,
        DirectMessageVideoPicker;
import 'package:yovoice/features/messages/presentation/widgets/direct_media_fullscreen_viewer.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_picked_video_inspector.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_context_action.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/interactions/message_reactions.dart';
import 'package:yovoice/shared/widgets/inputs/yo_composer_panel.dart';
import 'package:yovoice/shared/widgets/inputs/yo_gif_send_status.dart';
import 'package:yovoice/shared/widgets/inputs/yo_text_field.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/media/yo_gif_view.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';

/// A text channel's thread: the existing club message store read at
/// `clubs/{serverId}/channels/{channelId}/messages` and written through
/// `sendClubMessage`, which already enforces V1 channel access
/// (`assertServerChannelAccessIfVersioned`). No parallel message path.
///
/// Draws no app bar: it is a scene inside the shell at every width.
class ServerTextChannelScene extends StatefulWidget {
  const ServerTextChannelScene({
    required this.server,
    required this.channel,
    required this.currentUserId,
    this.chatService,
    this.gifService,
    this.gifMessageInvoker,
    this.moderatorIds = const {},
    this.compact = false,
    this.onOpenProfile,
    this.photoPicker,
    this.videoPicker,
    this.videoInspector,
    this.mediaImageBuilder,
    super.key,
  });

  final Server server;
  final ServerChannel channel;

  /// The viewer, for "mine" styling only; authority comes from the service.
  final String currentUserId;

  /// Test seam; production builds the real service.
  final ClubChatService? chatService;
  final GifCatalogService? gifService;
  final GifMessageInvoker? gifMessageInvoker;

  /// The ids the server's own member roster returns with moderator power or
  /// above. A badge is drawn for exactly these and for nobody else: the
  /// message document carries no role, so an unread roster means no badge —
  /// never a guessed one (board 02's live chat).
  final Set<String> moderatorIds;

  /// Tighter paddings inside a context panel.
  final bool compact;

  /// Test seam; production opens the shared profile preview sheet.
  final void Function(String userId, String displayName)? onOpenProfile;

  /// Test seams for the photo/video pipeline; production uses ImagePicker,
  /// the shared picked-video inspector and Image.network over the grant URL.
  final DirectMessagePhotoPicker? photoPicker;
  final DirectMessageVideoPicker? videoPicker;
  final DirectMessageVideoInspector? videoInspector;
  final Widget Function(BuildContext context, Uri url)? mediaImageBuilder;

  @override
  State<ServerTextChannelScene> createState() => _ServerTextChannelSceneState();
}

class _ServerTextChannelSceneState extends State<ServerTextChannelScene> {
  /// Built on first use, never in `initState`: a held root reads nothing, so
  /// it must not even construct a message service.
  ClubChatService? _built;
  ClubChatService get _service =>
      _built ??= widget.chatService ?? ClubChatService();
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final GifCatalogService _gifService =
      widget.gifService ??
      GifCatalogService(transport: FunctionsGifTransport());
  late GifMessageController _gifDelivery;
  Stream<List<ClubMessage>>? _messages;
  Stream<ClubChatAuthority>? _authority;
  bool _sending = false;
  bool _sendingMedia = false;
  double? _mediaProgress;
  YoComposerPanelTab? _composerPanel;

  /// How much of the scene the composer (or the read-only notice) may take
  /// before it starts scrolling inside its own band.
  static const _footShare = .62;

  bool get _announcement =>
      widget.channel.kind == ServerChannelKind.announcements ||
      widget.channel.kind == ServerChannelKind.rules;

  @override
  void initState() {
    super.initState();
    _gifDelivery = _createGifDelivery();
    _listen();
  }

  GifMessageController _createGifDelivery() => GifMessageController(
    callable: 'sendClubMessage',
    target: {'clubId': widget.server.id, 'channelId': widget.channel.id},
    currentUserId: () => widget.currentUserId,
    invoke: widget.gifMessageInvoker,
  );

  @override
  void didUpdateWidget(ServerTextChannelScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id ||
        oldWidget.server.id != widget.server.id) {
      _gifDelivery.dispose();
      _gifDelivery = _createGifDelivery();
      _composerPanel = null;
    }
    if (oldWidget.channel.id != widget.channel.id ||
        oldWidget.server.id != widget.server.id ||
        oldWidget.server.isHeld != widget.server.isHeld) {
      _listen();
    }
  }

  void _listen() {
    // Rules deny message reads on a held root (`isClubMember` requires an
    // active root), so nothing is subscribed while the server is preparing.
    if (widget.server.isHeld) {
      _messages = null;
      _authority = null;
      return;
    }
    // Resolved once per channel, never per build: a rebuilt stream would
    // resubscribe and flash the spinner over a thread still on screen.
    _messages = _service.watchMessages(
      clubId: widget.server.id,
      channelId: widget.channel.id,
    );
    _authority = _service.watchAuthority(widget.server.id);
  }

  @override
  void dispose() {
    _gifDelivery.dispose();
    if (widget.gifService == null) _gifService.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggleComposerPanel() {
    final opening = _composerPanel == null;
    setState(() {
      _composerPanel = opening ? YoComposerPanelTabStore.instance.value : null;
    });
    // The helpers own the wire order: show before hide when opening from an
    // idle composer, an explicit show when closing (a focused node cannot be
    // re-requested).
    if (opening) {
      unawaited(yoFocusComposerBehindPanel(_focus));
    } else {
      unawaited(yoShowSystemKeyboard(_focus));
    }
  }

  void _selectComposerTab(YoComposerPanelTab tab) {
    setState(() => _composerPanel = tab);
    unawaited(YoComposerPanelTabStore.instance.remember(tab));
  }

  /// A tap on the thread — anywhere that is not the composer — puts the
  /// keyboard, or the panel standing in for it, away. Flutter's tap-outside
  /// default does nothing for touch on Android and iOS.
  void _dismissComposer() {
    if (_composerPanel != null) setState(() => _composerPanel = null);
    _focus.unfocus();
  }

  void _insertEmoji(String emoji) {
    yoInsertEmojiAtCaret(_controller, emoji);
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final copy = AppLocalizations.of(context);
    setState(() => _sending = true);
    try {
      await _service.sendTextMessage(
        clubId: widget.server.id,
        channelId: widget.channel.id,
        text: text,
      );
      _controller.clear();
      // Focus is left exactly where the user put it. The send button sits in
      // the composer's tap region, so tapping it never dropped focus in the
      // first place — and a keyboard put away during a slow send must not
      // climb back when the send completes.
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(copy.serverSendFailed)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Whether the viewer may be OFFERED reactions: any non-guest member. The
  /// callable is the authority (restricted grant, mute, verified email) and
  /// decides every request; this only avoids offering a guest a sheet whose
  /// every action the server would refuse.
  static bool _mayOfferReactions(ClubChatAuthority authority) {
    final role = authority.role;
    return role != null && role != ClubRole.guest;
  }

  // ------------------------------------------------- channel photos/videos

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// The direct-message picker sheet, with the same four options and copy.
  Future<DirectMessageMediaPickAction?> _chooseMediaAction() {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final label = copy.text('Add media', 'Dodaj multimedia');
    return showModalBottomSheet<DirectMessageMediaPickAction>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 520,
      ),
      builder: (sheetContext) => Material(
        key: const ValueKey('server-media-picker'),
        color: palette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              YoModalSheetChrome(
                sheetLabel: label,
                surfaceColor: palette.surfaceRaised,
              ),
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(copy.text('Take photo', 'Zrób zdjęcie')),
                onTap: () => Navigator.pop(
                  sheetContext,
                  DirectMessageMediaPickAction.takePhoto,
                ),
              ),
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(copy.text('Photo library', 'Biblioteka zdjęć')),
                onTap: () => Navigator.pop(
                  sheetContext,
                  DirectMessageMediaPickAction.photoLibrary,
                ),
              ),
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.videocam_outlined),
                title: Text(copy.text('Record video', 'Nagraj film')),
                subtitle: Text(
                  copy.text('Up to 60 seconds', 'Maksymalnie 60 sekund'),
                ),
                onTap: () => Navigator.pop(
                  sheetContext,
                  DirectMessageMediaPickAction.recordVideo,
                ),
              ),
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.video_library_outlined),
                title: Text(copy.text('Video library', 'Biblioteka filmów')),
                onTap: () => Navigator.pop(
                  sheetContext,
                  DirectMessageMediaPickAction.videoLibrary,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAttachment() async {
    if (_sendingMedia) return;
    // Dropped before the sheet, exactly as the direct chat does: a focused
    // composer would otherwise bring the keyboard back over the picker.
    _focus.unfocus();
    final action = await _chooseMediaAction();
    if (action == null || !mounted) return;
    switch (action) {
      case DirectMessageMediaPickAction.takePhoto:
        return _sendPickedPhoto(ImageSource.camera);
      case DirectMessageMediaPickAction.photoLibrary:
        return _sendPickedPhoto(ImageSource.gallery);
      case DirectMessageMediaPickAction.recordVideo:
        return _sendPickedVideo(ImageSource.camera);
      case DirectMessageMediaPickAction.videoLibrary:
        return _sendPickedVideo(ImageSource.gallery);
    }
  }

  /// The direct-message MIME contract: only the three image types the
  /// reservation, Storage rules and the trusted probe all accept.
  static String? _imageContentType(XFile image) {
    final declared = image.mimeType?.split(';').first.trim().toLowerCase();
    if (declared == 'image/jpeg' ||
        declared == 'image/png' ||
        declared == 'image/webp') {
      return declared;
    }
    final name = image.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    return null;
  }

  static String? _videoContentType(XFile video) {
    final declared = video.mimeType?.split(';').first.trim().toLowerCase();
    if (declared == 'video/mp4' ||
        declared == 'video/quicktime' ||
        declared == 'video/webm') {
      return declared;
    }
    final name = video.name.toLowerCase();
    if (name.endsWith('.mov')) return 'video/quicktime';
    if (name.endsWith('.webm')) return 'video/webm';
    if (name.endsWith('.mp4') || name.endsWith('.m4v')) return 'video/mp4';
    return null;
  }

  Future<void> _sendPickedPhoto(ImageSource source) async {
    final copy = AppLocalizations.of(context);
    final failure = copy.text(
      'Your photo could not be sent. Try again.',
      'Nie udało się wysłać zdjęcia. Spróbuj ponownie.',
    );
    final picker = widget.photoPicker;
    final image = picker != null
        ? await picker(source)
        : await ImagePicker().pickImage(
            source: source,
            maxWidth: 2048,
            maxHeight: 2048,
            imageQuality: 88,
          );
    if (image == null || !mounted) return;
    final contentType = _imageContentType(image);
    if (contentType == null) {
      _showMessage(failure);
      return;
    }
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    // The same bounds the reservation and Storage rules enforce; refusing
    // here keeps a doomed upload off the wire.
    if (bytes.lengthInBytes < 128 || bytes.lengthInBytes > 8 * 1024 * 1024) {
      _showMessage(failure);
      return;
    }
    await _sendMedia(
      type: 'image',
      contentType: contentType,
      bytes: bytes,
      failure: failure,
    );
  }

  Future<void> _sendPickedVideo(ImageSource source) async {
    final copy = AppLocalizations.of(context);
    final failure = copy.text(
      'Your video could not be sent. Choose a video up to 60 seconds and try again.',
      'Nie udało się wysłać filmu. Wybierz film do 60 sekund i spróbuj ponownie.',
    );
    final picker = widget.videoPicker;
    final video = picker != null
        ? await picker(source)
        : await ImagePicker().pickVideo(
            source: source,
            maxDuration: const Duration(seconds: 60),
          );
    if (video == null || !mounted) return;
    final contentType = _videoContentType(video);
    if (contentType == null) {
      _showMessage(failure);
      return;
    }
    final Duration duration;
    try {
      duration = await (widget.videoInspector ?? inspectPickedDirectVideo)(
        video,
      );
    } catch (_) {
      _showMessage(failure);
      return;
    }
    final durationSeconds = (duration.inMilliseconds + 999) ~/ 1000;
    final bytes = await video.readAsBytes();
    if (!mounted) return;
    if (durationSeconds < 1 ||
        durationSeconds > 60 ||
        bytes.lengthInBytes < 1024 ||
        bytes.lengthInBytes > 64 * 1024 * 1024) {
      _showMessage(failure);
      return;
    }
    await _sendMedia(
      type: 'video',
      contentType: contentType,
      bytes: bytes,
      durationSeconds: durationSeconds,
      failure: failure,
    );
  }

  Future<void> _sendMedia({
    required String type,
    required String contentType,
    required Uint8List bytes,
    required String failure,
    int? durationSeconds,
  }) async {
    setState(() {
      _sendingMedia = true;
      _mediaProgress = null;
    });
    try {
      await _service.sendServerMediaMessage(
        serverId: widget.server.id,
        channelId: widget.channel.id,
        type: type,
        contentType: contentType,
        bytes: bytes,
        durationSeconds: durationSeconds,
        onProgress: (progress) {
          if (mounted) setState(() => _mediaProgress = progress.clamp(0, 1));
        },
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        serverActionFailureCopy(
          error,
          AppLocalizations.of(context),
          fallback: failure,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sendingMedia = false;
          _mediaProgress = null;
        });
      }
    }
  }

  Future<void> _openMessageActions(
    ClubMessage message,
    ClubChatAuthority authority,
  ) async {
    if (message.isDeleted) return;
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final mine = message.reactions[widget.currentUserId];
    final isAuthor = message.senderId == widget.currentUserId;
    final canReact = _mayOfferReactions(authority);
    final canRemove = authority.isModeratingOthers(message);
    // Dropped before the sheet so the route does not hand focus back to the
    // composer (and the keyboard back over the thread) when it closes.
    _focus.unfocus();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 520,
      ),
      builder: (sheetContext) => Container(
        key: const ValueKey('server-message-actions'),
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          18 + MediaQuery.paddingOf(sheetContext).bottom,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              YoModalSheetChrome(
                sheetLabel: copy.text('message actions', 'opcje wiadomości'),
                surfaceColor: palette.surfaceRaised,
              ),
              const SizedBox(height: 1),
              if (canReact)
                MessageReactionPickerRow(
                  selected: mine,
                  onReaction: (value) =>
                      Navigator.pop(sheetContext, 'reaction:$value'),
                ),
              if (isAuthor || canRemove) ...[
                if (canReact) Divider(color: palette.border),
                // The author takes their own message back; a moderator
                // removes somebody else's through the existing rank-ordered
                // moderateClubMessage. Never both on one message.
                ListTile(
                  key: ValueKey(
                    isAuthor
                        ? 'server-message-delete'
                        : 'server-message-remove',
                  ),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    isAuthor ? 'delete' : 'remove',
                  ),
                  leading: Icon(
                    isAuthor
                        ? Icons.delete_outline_rounded
                        : Icons.gavel_rounded,
                    color: palette.dangerForeground,
                  ),
                  title: Text(
                    isAuthor
                        ? copy.text('Delete message', 'Usuń wiadomość')
                        : copy.text('Remove message', 'Usuń wiadomość'),
                    style: TextStyle(color: palette.dangerForeground),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice.startsWith('reaction:')) {
      await _toggleReaction(message, choice.substring('reaction:'.length));
      return;
    }
    if (!await _confirmRemoval(isAuthor: choice == 'delete')) return;
    await _removeMessage(message, asAuthor: choice == 'delete');
  }

  Future<bool> _confirmRemoval({required bool isAuthor}) async {
    final copy = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isAuthor
              ? copy.text('Delete message', 'Usuń wiadomość')
              : copy.text('Remove message', 'Usuń wiadomość'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(copy.text('Cancel', 'Anuluj')),
          ),
          TextButton(
            key: const ValueKey('server-message-remove-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              isAuthor
                  ? copy.text('Delete', 'Usuń')
                  : copy.text('Remove', 'Usuń'),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _removeMessage(
    ClubMessage message, {
    required bool asAuthor,
  }) async {
    try {
      if (asAuthor) {
        await _service.deleteOwnServerMessage(
          serverId: widget.server.id,
          channelId: widget.channel.id,
          messageId: message.id,
        );
      } else {
        await _service.deleteMessage(
          clubId: widget.server.id,
          channelId: widget.channel.id,
          message: message,
        );
        _service.forgetServerMediaGrant(
          serverId: widget.server.id,
          channelId: widget.channel.id,
          messageId: message.id,
        );
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        serverActionFailureCopy(error, AppLocalizations.of(context)),
      );
    }
  }

  Future<void> _toggleReaction(ClubMessage message, String emoji) async {
    try {
      await _service.toggleServerReaction(
        serverId: widget.server.id,
        channelId: widget.channel.id,
        messageId: message.id,
        emoji: emoji,
      );
    } catch (error) {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            serverActionFailureCopy(
              error,
              copy,
              fallback: copy.text(
                'Could not update your reaction.',
                'Nie udało się zmienić reakcji.',
              ),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    if (widget.server.isHeld) {
      // Rules deny message reads on a held root (`isClubMember` requires an
      // active root), so the thread is not even subscribed.
      return SingleChildScrollView(
        child: YoEmptyState(
          icon: Icons.forum_outlined,
          title: copy.channelEmptyTitle(widget.channel.kind),
          subtitle: copy.serverHeldBody,
          compact: widget.compact,
        ),
      );
    }
    final currentUserId = widget.currentUserId;
    // Unknown is not read-only: until the viewer's membership row has been
    // read, the composer (and the emoji button and panel inside it) stays.
    final pending = ClubChatAuthority(
      viewerId: currentUserId,
      membershipResolved: false,
    );
    return StreamBuilder<ClubChatAuthority>(
      stream: _authority,
      initialData: pending,
      builder: (context, authoritySnapshot) {
        final authority = authoritySnapshot.data ?? pending;
        // The composer gives way to the read-only sentence only on a
        // RESOLVED refusal (announcements for a non-moderator, a guest, a
        // non-member, a mute, an unverified email). It used to give way on
        // "not known yet" as well, which took the emoji input away on every
        // channel open and for good whenever the first membership snapshot
        // was slow or never came. `sendClubMessage` authorizes every send.
        final canWrite = !authority.showsReadOnlyNotice(
          announcement: _announcement,
        );
        // The whole footer is ONE tap region with the text field: the send
        // button, the panel toggle, an emoji or a GIF is not "tapping
        // outside" the composer and must not put the keyboard away. Joining
        // the field's own group keeps the selection handles inside as well.
        final foot = TextFieldTapRegion(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canWrite)
                _Composer(
                  controller: _controller,
                  focusNode: _focus,
                  sending: _sending,
                  sendingMedia: _sendingMedia,
                  panelOpen: _composerPanel != null,
                  hint: copy.serverMessageHint(widget.channel.name),
                  sendLabel: copy.serverSend,
                  attachLabel: copy.text('Add media', 'Dodaj multimedia'),
                  onSend: _send,
                  onAttach: _pickAttachment,
                  onTogglePanel: _toggleComposerPanel,
                  onDismiss: _dismissComposer,
                  compact: widget.compact,
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    _announcement
                        ? copy.serverAnnouncementsOnlyBody
                        : copy.serverReadOnlyBody,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              if (_sendingMedia)
                Padding(
                  key: const ValueKey('server-media-upload'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Semantics(
                    label: copy.text('Sending…', 'Wysyłanie…'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          copy.text('Sending…', 'Wysyłanie…'),
                          style: AppTypography.labelSmall.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: AppRadius.pill,
                          child: LinearProgressIndicator(
                            value: _mediaProgress,
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              YoGifSendStatus(controller: _gifDelivery),
              if (canWrite && _composerPanel != null)
                Flexible(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final available = constraints.maxHeight.isFinite
                          ? constraints.maxHeight
                          : 260.0;
                      final panelHeight = available
                          .clamp(128.0, widget.compact ? 260.0 : 340.0)
                          .toDouble();
                      return SingleChildScrollView(
                        child: YoComposerPanel(
                          tab: _composerPanel!,
                          onTabChanged: _selectComposerTab,
                          onEmojiSelected: _insertEmoji,
                          onBackspace: () => yoDeleteBackAtCaret(_controller),
                          gifService: _gifService
                            ..locale = copy.locale.languageCode,
                          gifDelivery: _gifDelivery,
                          onGifSelected: (asset) =>
                              unawaited(_gifDelivery.send(asset)),
                          gifAutoLoad:
                              AppPreferencesScope.maybeOf(
                                context,
                              )?.value.gifAutoLoadEnabled ??
                              true,
                          compact: widget.compact || available < 300,
                          height: panelHeight,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
        // The composer — or the read-only sentence standing in for it — is the
        // one part of this scene that cannot shrink, and it is mounted in
        // columns whose height belongs to somebody else (the desktop context
        // panel, a phone tab). At 200 % text a short column made it taller
        // than the whole scene and the surface drew the overflow banner. It
        // now keeps a bounded share and scrolls inside it, so the thread above
        // is squeezed rather than the layout broken; at every ordinary size
        // this changes nothing, because the cap is larger than the composer.
        return LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              Expanded(child: _thread(copy, currentUserId, authority)),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight.isFinite
                      ? constraints.maxHeight * _footShare
                      : double.infinity,
                ),
                // At large text sizes the closed composer is taller than the
                // context column's share (notably the 1100 px desktop tier).
                // Keep its controls reachable by scrolling that fixed footer
                // band. An open emoji/GIF panel needs the bounded height so
                // its Flexible child can divide the same band safely.
                child: _composerPanel == null
                    ? SingleChildScrollView(reverse: true, child: foot)
                    : foot,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _thread(
    AppLocalizations copy,
    String currentUserId,
    ClubChatAuthority authority,
  ) => StreamBuilder<List<ClubMessage>>(
    stream: _messages,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return SingleChildScrollView(
          child: YoErrorState(
            error: snapshot.error,
            compact: widget.compact,
            onRetry: () => setState(_listen),
          ),
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData) {
        return Center(
          child: Semantics(
            label: copy.serverChat,
            child: const CircularProgressIndicator(),
          ),
        );
      }
      final messages = snapshot.data ?? const <ClubMessage>[];
      if (messages.isEmpty) {
        return SingleChildScrollView(
          child: YoEmptyState(
            icon: _announcement
                ? Icons.campaign_outlined
                : Icons.forum_outlined,
            title: copy.serverNoMessagesTitle,
            subtitle: copy.serverNoMessagesBody(widget.channel.name),
            compact: widget.compact,
          ),
        );
      }
      return ListView.builder(
        key: const ValueKey('server-message-list'),
        reverse: true,
        // A drag on the thread puts the keyboard away.
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          widget.compact ? 12 : 16,
          12,
          widget.compact ? 12 : 16,
          16,
        ),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[index];
          return _MessageTile(
            message: message,
            isMine: message.senderId == currentUserId,
            type: widget.server,
            isModerator: widget.moderatorIds.contains(message.senderId),
            onOpenProfile: widget.onOpenProfile,
            onOpenActions:
                !message.isDeleted &&
                    (_mayOfferReactions(authority) ||
                        message.senderId == currentUserId ||
                        authority.isModeratingOthers(message))
                ? () => unawaited(_openMessageActions(message, authority))
                : null,
            loadMediaGrant: ({bool refresh = false}) =>
                _service.serverMediaGrant(
                  serverId: widget.server.id,
                  channelId: widget.channel.id,
                  messageId: message.id,
                  refresh: refresh,
                ),
            mediaImageBuilder: widget.mediaImageBuilder,
          );
        },
      );
    },
  );
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.isMine,
    required this.type,
    this.isModerator = false,
    this.onOpenProfile,
    this.onOpenActions,
    required this.loadMediaGrant,
    this.mediaImageBuilder,
  });
  final ClubMessage message;
  final bool isMine;
  final Server type;
  final bool isModerator;

  /// Test seam; production opens the shared profile preview sheet.
  final void Function(String userId, String displayName)? onOpenProfile;

  /// The message actions sheet (reactions). Long-press on touch, right-click
  /// on a pointer, Enter/Space/context-menu key and a semantics action — the
  /// same `AccessibleContextAction` the direct-message bubble uses. Null for
  /// a removed message or a viewer who may not react.
  final VoidCallback? onOpenActions;

  /// Asks the service for this message's short-lived media grant; requests
  /// from the visible tiles are batched and cached there.
  final Future<ServerMediaGrant?> Function({bool refresh}) loadMediaGrant;

  /// Test seam for the grant-backed image.
  final Widget Function(BuildContext context, Uri url)? mediaImageBuilder;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = ServerIdentity.of(
      type.type,
    ).resolve(Theme.of(context).brightness);
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(message.sentAt.toLocal()));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AccessibleContextAction(
        onOpen: onOpenActions,
        semanticLabel: isMine
            ? copy.text(
                'Open actions for your message',
                'Otwórz opcje swojej wiadomości',
              )
            : copy.text(
                'Open actions for this message',
                'Otwórz opcje tej wiadomości',
              ),
        borderRadius: 12,
        child: _body(context, copy, palette, colors, time),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
    String time,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The avatar is the same "who is this?" affordance it is in
        // Moments and every chat surface — a complete button, not an
        // inert picture (the thread carries no other way to reach a
        // member's profile).
        AccessibleTapRegion(
          onTap: () {
            final open = onOpenProfile;
            if (open != null) {
              open(message.senderId, message.senderName);
              return;
            }
            unawaited(
              showProfilePreview(
                context,
                userId: message.senderId,
                displayName: message.senderName,
              ),
            );
          },
          // The name is substituted AFTER localization: a key built by
          // interpolation can never be looked up outside EN/PL, which left
          // the label and the tooltip in raw English in 41 locales.
          semanticLabel: copy.template(
            'Open profile of {name}',
            'Otwórz profil: {name}',
            values: <String, Object>{'name': message.senderName},
          ),
          tooltip: copy.template(
            'Open profile of {name}',
            'Otwórz profil: {name}',
            values: <String, Object>{'name': message.senderName},
          ),
          circular: true,
          child: ExcludeSemantics(
            child: UserAvatar(
              radius: 18,
              userId: message.senderId,
              displayName: message.senderName,
              backgroundColor: colors.iconSurface,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
                decoration: BoxDecoration(
                  color: isMine ? colors.selectedWash : palette.surface,
                  borderRadius: AppRadius.md,
                  border: Border.all(
                    color: isMine ? colors.iconBorder : palette.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Text(
                          message.senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelMedium.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                        Text(
                          time,
                          style: AppTypography.labelSmall.copyWith(
                            color: palette.textTertiary,
                          ),
                        ),
                        if (isModerator)
                          Container(
                            key: ValueKey(
                              'server-moderator-badge-${message.id}',
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.selectedWash,
                              borderRadius: AppRadius.pill,
                              border: Border.all(color: colors.iconBorder),
                            ),
                            child: Text(
                              copy.serverModerator,
                              style: AppTypography.labelSmall.copyWith(
                                color: colors.selectedForeground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (!message.isDeleted && message.gif != null)
                      YoGifView(
                        asset: message.gif!,
                        autoLoad:
                            AppPreferencesScope.maybeOf(
                              context,
                            )?.value.gifAutoLoadEnabled ??
                            true,
                      )
                    // A photo or video: the descriptor travels on the
                    // message, the bytes come from a short-lived grant. An
                    // installed build that does not know these fields draws
                    // `content` ('Photo'/'Video') instead, which is exactly
                    // why the server writes it.
                    else if (!message.isDeleted && message.media != null)
                      _ServerMediaView(
                        key: ValueKey('server-message-media-${message.id}'),
                        media: message.media!,
                        loadGrant: loadMediaGrant,
                        imageBuilder: mediaImageBuilder,
                      )
                    else
                      Text(
                        message.isDeleted
                            ? copy.serverMessageDeleted
                            : message.content,
                        style: AppTypography.bodyMedium.copyWith(
                          color: message.isDeleted
                              ? palette.textTertiary
                              : palette.textPrimary,
                          fontStyle: message.isDeleted
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                  ],
                ),
              ),
              // The direct-message reaction pill, under the bubble.
              if (message.reactions.isNotEmpty) ...[
                const SizedBox(height: 3),
                MessageReactionSummaryPill(
                  key: ValueKey('server-message-reactions-${message.id}'),
                  reactions: message.reactions.values,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One photo or video bubble, backed by a short-lived, generation-bound grant.
///
/// The grant is fetched when the tile is first built — the thread's ListView
/// builds only what is visible, so a 250-message channel asks for the handful
/// on screen and the service batches those into one callable. A grant that is
/// refused or reports the message unavailable degrades to the same
/// 'Photo'/'Video' line an older install shows; it never leaks an error.
class _ServerMediaView extends StatefulWidget {
  const _ServerMediaView({
    required this.media,
    required this.loadGrant,
    this.imageBuilder,
    super.key,
  });

  final ClubMessageMedia media;
  final Future<ServerMediaGrant?> Function({bool refresh}) loadGrant;
  final Widget Function(BuildContext context, Uri url)? imageBuilder;

  @override
  State<_ServerMediaView> createState() => _ServerMediaViewState();
}

class _ServerMediaViewState extends State<_ServerMediaView> {
  late Future<ServerMediaGrant?> _grant;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _grant = widget.loadGrant();
  }

  @override
  void didUpdateWidget(_ServerMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.generation != widget.media.generation ||
        oldWidget.media.storagePath != widget.media.storagePath) {
      _reload();
    }
  }

  void _reload() {
    setState(() => _grant = widget.loadGrant(refresh: true));
  }

  /// 280 on a phone, 360 on a tablet column, 420 on a desktop thread: a
  /// bubble is a readable measure, never the full width of the surface.
  double _maxWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return 280;
    if (width < 1024) return 360;
    return 420;
  }

  Future<void> _openImage(Uri url) async {
    await showDirectImageFullscreenViewer(
      context,
      imageProvider: NetworkImage(url.toString()),
    );
  }

  Future<void> _openVideo() async {
    if (_opening) return;
    setState(() => _opening = true);
    VideoPlayerController? controller;
    try {
      // A fresh grant: playback may start long after the bubble appeared.
      final grant = await widget.loadGrant(refresh: true);
      if (grant == null || !mounted) return;
      await showDirectVideoFullscreenViewer(
        context,
        controllerLoader: () async {
          final created = VideoPlayerController.networkUrl(grant.url);
          await created.initialize();
          controller = created;
          return created;
        },
      );
    } catch (_) {
      if (mounted) _reload();
    } finally {
      await controller?.dispose();
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final label = widget.media.isVideo
        ? copy.text('Video', 'Film')
        : copy.text('Photo', 'Zdjęcie');
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _maxWidth(context)),
      child: ClipRRect(
        borderRadius: AppRadius.md,
        child: AspectRatio(
          aspectRatio: widget.media.isVideo ? 16 / 9 : 4 / 3,
          child: FutureBuilder<ServerMediaGrant?>(
            future: _grant,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return ColoredBox(
                  color: palette.surfaceSunken,
                  child: Center(
                    child: Semantics(
                      label: label,
                      child: const CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return _MediaPlaceholder(
                  key: const ValueKey('server-media-retry'),
                  icon: Icons.refresh_rounded,
                  label: widget.media.isVideo
                      ? copy.text('Play video', 'Odtwórz film')
                      : copy.text('Load photo', 'Wczytaj zdjęcie'),
                  onTap: _reload,
                );
              }
              final grant = snapshot.data;
              if (grant == null) {
                // Unavailable: removed, or its object is gone. The same line
                // an older install shows.
                return _MediaPlaceholder(
                  icon: widget.media.isVideo
                      ? Icons.videocam_off_outlined
                      : Icons.broken_image_outlined,
                  label: label,
                );
              }
              if (widget.media.isVideo) {
                return _VideoPoster(
                  label: copy.text('Play video', 'Odtwórz film'),
                  durationSeconds: widget.media.durationSeconds,
                  busy: _opening,
                  onTap: _openVideo,
                );
              }
              final builder = widget.imageBuilder;
              return Semantics(
                label: label,
                button: true,
                child: InkWell(
                  onTap: () => unawaited(_openImage(grant.url)),
                  child: builder != null
                      ? builder(context, grant.url)
                      : Image.network(
                          grant.url.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _MediaPlaceholder(
                            icon: Icons.broken_image_outlined,
                            label: label,
                          ),
                        ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({
    required this.icon,
    required this.label,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: palette.textSecondary),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.labelMedium.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return ColoredBox(color: palette.surfaceSunken, child: content);
    }
    return Material(
      color: palette.surfaceSunken,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class _VideoPoster extends StatelessWidget {
  const _VideoPoster({
    required this.label,
    required this.durationSeconds,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final int? durationSeconds;
  final bool busy;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final seconds = durationSeconds ?? 0;
    return Semantics(
      label: label,
      button: true,
      child: Material(
        color: palette.surfaceSunken,
        child: InkWell(
          key: const ValueKey('server-media-play'),
          onTap: busy ? null : () => unawaited(onTap()),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: busy
                    ? const CircularProgressIndicator(strokeWidth: 2.4)
                    : Icon(
                        Icons.play_circle_fill_rounded,
                        size: 54,
                        color: palette.textPrimary,
                      ),
              ),
              if (seconds > 0)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surfaceRaised,
                      borderRadius: AppRadius.pill,
                      border: Border.all(color: palette.border),
                    ),
                    child: Text(
                      '0:${seconds.toString().padLeft(2, '0')}',
                      style: AppTypography.labelSmall.copyWith(
                        color: palette.textSecondary,
                      ),
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.sendingMedia,
    required this.panelOpen,
    required this.hint,
    required this.sendLabel,
    required this.attachLabel,
    required this.onSend,
    required this.onAttach,
    required this.onTogglePanel,
    required this.onDismiss,
    required this.compact,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;

  /// One photo or video at a time: the attach button waits for the upload.
  final bool sendingMedia;
  final bool panelOpen;
  final String hint;
  final String sendLabel;
  final String attachLabel;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onTogglePanel;

  /// A tap anywhere that is not part of the composer's tap region.
  final VoidCallback onDismiss;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 8, compact ? 8 : 12, 12),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.appPalette.border)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        YoEmojiComposerButton(
          open: panelOpen,
          onPressed: onTogglePanel,
          size: 44,
          iconSize: 20,
        ),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            key: const ValueKey('server-attach'),
            onPressed: sendingMedia ? null : onAttach,
            tooltip: attachLabel,
            iconSize: 20,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: YoTextField(
            key: const ValueKey('server-composer'),
            controller: controller,
            focusNode: focusNode,
            onTapOutside: (_) => onDismiss(),
            hint: hint,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          height: 48,
          child: sending
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              : IconButton.filled(
                  key: const ValueKey('server-send'),
                  onPressed: onSend,
                  tooltip: sendLabel,
                  icon: const Icon(Icons.send_rounded, size: 20),
                ),
        ),
      ],
    ),
  );
}
