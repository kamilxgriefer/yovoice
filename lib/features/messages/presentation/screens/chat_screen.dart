import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/core/helpers/error_messages.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.conversationId,
    required this.otherUserId,
    required this.otherDisplayName,
    required this.otherEmail,
    required this.otherPhotoUrl,
    this.messageService,
    this.auth,
    this.contentReportService,
    super.key,
  });

  final String conversationId;
  final String otherUserId;
  final String otherDisplayName;
  final String otherEmail;
  final String otherPhotoUrl;

  /// Optional injection seams, matching the established pattern on
  /// FriendProfileScreen and NotificationsScreen: production passes
  /// nothing and gets the live singletons, tests pass fakes so the
  /// failure paths below can be exercised without a Firebase app.
  final MessageService? messageService;
  final FirebaseAuth? auth;
  final ContentReportService? contentReportService;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF15101E);
  static const Color _surface2 = Color(0xFF1D1628);
  static const Color _border = Color(0xFF30263F);
  static const Color _muted = Color(0xFF9D95AD);
  static const Color _primary = Color(0xFF9D20FF);

  late final MessageService _service =
      widget.messageService ?? MessageService.live;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late final Stream<List<Message>> _messages;
  late final Stream<bool> _typing;
  late final Stream<ChatPresence> _presence;
  StreamSubscription<List<Message>>? _messagesSubscription;
  StreamSubscription<List<OutboxEntry>>? _outboxSubscription;
  StreamSubscription<OutboxEntry>? _deliveredSubscription;

  Timer? _typingTimer;
  Message? _replyTo;
  bool _sending = false;
  bool _sendingMedia = false;
  bool _isMuted = false;
  bool _typingAnnounced = false;
  bool _typingUpdateInFlight = false;
  bool? _pendingTypingState;
  DateTime? _lastTypingHeartbeat;
  bool _suppressTypingListener = false;
  List<OutboxEntry> _outboxEntries = const <OutboxEntry>[];
  final Map<String, OutboxEntry> _awaitingSnapshots = {};
  Set<String> _committedMessageIds = const <String>{};

  /// Typing presence is pushed on every keystroke, so a broken backend
  /// would otherwise either be silent or produce a snackbar storm. It is
  /// reported once per visit and logged every time.
  bool _typingFailureReported = false;

  /// Read receipts follow the conversation snapshot, not the build cycle:
  /// [_newestMarkedMessageId] is the newest message we already marked read
  /// for, so N rebuilds of the same snapshot cost zero extra writes, and a
  /// failure is reported once per visit — same contract as typing above.
  String? _newestMarkedMessageId;
  bool _markReadFailureReported = false;

  String get _currentUserId =>
      (widget.auth ?? FirebaseAuth.instance).currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    // Broadcast so the state's own mark-read listener below and the
    // message list's StreamBuilder can share one service stream.
    _messages = _service
        .watchMessages(widget.conversationId)
        .asBroadcastStream(
          // This screen has two downstream listeners (read receipts and the
          // list), but it owns only one Firestore subscription. Cancel that
          // source when both consumers leave; otherwise every closed chat
          // keeps a live network listener for the rest of the process.
          onCancel: (subscription) => unawaited(subscription.cancel()),
        );
    _typing = _service.watchTyping(
      conversationId: widget.conversationId,
      otherUserId: widget.otherUserId,
    );
    _presence = _service.watchUserPresence(widget.otherUserId);
    _messagesSubscription = _messages.listen(
      _handleMessagesDelivered,
      // The StreamBuilder already renders the failure state; this
      // subscription only exists to drive read receipts.
      onError: (Object _) {},
    );
    _outboxSubscription = _service.outbox.changes.listen(_handleOutboxChanged);
    _deliveredSubscription = _service.outbox.delivered.listen(
      _handleOutboxDelivered,
    );
    unawaited(_loadOutbox());
    _controller.addListener(_handleTyping);
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    unawaited(_messagesSubscription?.cancel());
    unawaited(_outboxSubscription?.cancel());
    unawaited(_deliveredSubscription?.cancel());
    _controller
      ..removeListener(_handleTyping)
      ..dispose();
    _focusNode.dispose();
    // Keep teardown in the same single-flight coalescer as ordinary typing.
    // Otherwise an older slow `true` can arrive after a parallel `false` and
    // leave this user shown as typing after the route is gone.
    _pendingTypingState = false;
    unawaited(_queueTypingUpdate(false));
    super.dispose();
  }

  void _handleTyping() {
    if (_suppressTypingListener) return;
    final hasText = _controller.text.trim().isNotEmpty;
    _typingTimer?.cancel();

    if (hasText) {
      // Typing is a state transition, not a keystroke event. The previous
      // implementation sent one callable transaction for every character,
      // contending with the actual message transaction on the same
      // conversation document.
      final now = DateTime.now();
      final heartbeatDue =
          _lastTypingHeartbeat == null ||
          now.difference(_lastTypingHeartbeat!) >= const Duration(seconds: 4);
      if (!_typingAnnounced || heartbeatDue) {
        _typingAnnounced = true;
        _lastTypingHeartbeat = now;
        unawaited(_queueTypingUpdate(true));
      }
      _typingTimer = Timer(const Duration(seconds: 4), () {
        if (!_typingAnnounced) return;
        _typingAnnounced = false;
        _lastTypingHeartbeat = null;
        unawaited(_queueTypingUpdate(false));
      });
    } else if (_typingAnnounced) {
      _typingAnnounced = false;
      _lastTypingHeartbeat = null;
      unawaited(_queueTypingUpdate(false));
    }
  }

  /// Coalesces typing transitions so at most one callable is in flight.
  /// When the network is slow, only the newest desired state survives.
  Future<void> _queueTypingUpdate(bool isTyping) async {
    _pendingTypingState = isTyping;
    if (_typingUpdateInFlight) return;
    _typingUpdateInFlight = true;
    try {
      while (_pendingTypingState != null) {
        final next = _pendingTypingState!;
        _pendingTypingState = null;
        await _setTyping(next);
      }
    } finally {
      _typingUpdateInFlight = false;
    }
  }

  Future<void> _loadOutbox() async {
    await _service.outbox.load();
    _handleOutboxChanged(_service.outbox.entries);
  }

  bool _belongsToThisChat(OutboxEntry entry) =>
      entry.conversationId == widget.conversationId &&
      entry.recipientId == widget.otherUserId;

  String _canonicalId(OutboxEntry entry) =>
      _service.messageIdForQueuedText(entry, senderId: _currentUserId);

  void _handleOutboxChanged(List<OutboxEntry> entries) {
    if (!mounted) return;
    setState(() {
      _outboxEntries = entries
          .where(_belongsToThisChat)
          .toList(growable: false);
    });
  }

  void _handleOutboxDelivered(OutboxEntry entry) {
    if (!mounted || !_belongsToThisChat(entry)) return;
    final canonicalId = _canonicalId(entry);
    if (_committedMessageIds.contains(canonicalId)) return;
    setState(() => _awaitingSnapshots[entry.id] = entry);
  }

  /// Never let a rejected typing update disappear. It is not worth
  /// interrupting the person mid-sentence more than once, but it must not
  /// be invisible either — silent presence failures are exactly how the
  /// duplicate-send defect stayed hidden.
  Future<void> _setTyping(bool isTyping, {bool announceFailure = true}) async {
    try {
      await _service.setTyping(
        conversationId: widget.conversationId,
        isTyping: isTyping,
      );
    } catch (error) {
      debugPrint('ChatScreen typing presence update failed: $error');

      if (!announceFailure || !mounted || _typingFailureReported) {
        return;
      }

      _typingFailureReported = true;
      _showMessage(
        friendlyErrorMessage(
          error,
          fallback: "Others won't see when you're typing right now.",
        ),
      );
    }
  }

  Future<void> _toggleReaction(Message message, String emoji) async {
    try {
      await _service.toggleReaction(
        conversationId: widget.conversationId,
        messageId: message.id,
        emoji: emoji,
      );
    } catch (error) {
      if (mounted) {
        _showMessage(
          intentionalOrFriendly(
            error,
            fallback: 'Could not update your reaction.',
          ),
        );
      }
    }
  }

  /// Fires once per newest-message advance — never per rebuild. Messages
  /// arrive newest-first (watchMessages orders `sentAt` descending).
  void _handleMessagesDelivered(List<Message> messages) {
    _committedMessageIds = messages.map((message) => message.id).toSet();
    final acknowledged = _awaitingSnapshots.entries
        .where(
          (item) => _committedMessageIds.contains(_canonicalId(item.value)),
        )
        .map((item) => item.key)
        .toList(growable: false);
    if (acknowledged.isNotEmpty && mounted) {
      setState(() {
        for (final id in acknowledged) {
          _awaitingSnapshots.remove(id);
        }
      });
    }
    if (messages.isEmpty) return;
    final newestId = messages.first.id;
    if (newestId == _newestMarkedMessageId) return;
    _newestMarkedMessageId = newestId;
    unawaited(_markRead());
  }

  Future<void> _markRead() async {
    try {
      await _service.markConversationRead(widget.conversationId);
    } catch (error) {
      debugPrint('ChatScreen read-receipt update failed: $error');

      // Let the next conversation change retry instead of pinning the
      // failed newest message as "already marked".
      _newestMarkedMessageId = null;

      if (!mounted || _markReadFailureReported) return;

      // Stale unread badges elsewhere must not fail invisibly — but a
      // snackbar per snapshot would be a storm, so once per visit, like
      // the typing-presence failure above. Never raw exception text.
      _markReadFailureReported = true;
      _showMessage(
        friendlyErrorMessage(
          error,
          fallback: 'Unread counts may not update right now.',
        ),
      );
    }
  }

  Future<void> _send() async {
    final draft = _controller.value;
    final text = draft.text.trim();

    if (text.isEmpty || _sending) {
      return;
    }

    final reply = _replyTo;
    _typingTimer?.cancel();
    _typingAnnounced = false;
    _lastTypingHeartbeat = null;
    unawaited(_queueTypingUpdate(false));
    _suppressTypingListener = true;
    _controller.clear();
    _suppressTypingListener = false;
    setState(() {
      _sending = true;
      _replyTo = null;
    });

    try {
      await _service.queueTextMessage(
        conversationId: widget.conversationId,
        recipientId: widget.otherUserId,
        text: text,
        replyTo: reply,
      );
    } catch (error) {
      if (mounted) {
        // Enqueue is local and normally completes in one frame. Still, keep
        // the composer read-only while it is in flight and defensively merge
        // anything inserted programmatically during that window. A full
        // outbox must never turn "A, send, type B" into the silent loss of A.
        final newerDraft = _controller.text;
        final restoredDraft = newerDraft.isEmpty
            ? draft.text
            : newerDraft == draft.text
            ? newerDraft
            : '${draft.text.trimRight()}\n${newerDraft.trimLeft()}';
        _controller.value = TextEditingValue(
          text: restoredDraft,
          selection: TextSelection.collapsed(offset: restoredDraft.length),
        );
        setState(() => _replyTo ??= reply);
        _showMessage(intentionalOrFriendly(error));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _retryQueuedMessage(OutboxEntry entry) async {
    try {
      await _service.retryFailedMessage(entry.id);
    } catch (error) {
      if (mounted) _showMessage(intentionalOrFriendly(error));
    }
  }

  Future<void> _discardQueuedMessage(OutboxEntry entry) async {
    await _service.discardQueuedMessage(entry.id);
  }

  List<OutboxEntry> _visibleOutboxEntries() {
    final byId = <String, OutboxEntry>{
      for (final entry in _outboxEntries) entry.id: entry,
      for (final entry in _awaitingSnapshots.values) entry.id: entry,
    };
    final visible =
        byId.values
            .where(
              (entry) => !_committedMessageIds.contains(_canonicalId(entry)),
            )
            .toList(growable: false)
          ..sort((a, b) => b.queuedAt.compareTo(a.queuedAt));
    return visible;
  }

  Future<void> _messageActions(Message message) async {
    if (message.isDeleted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 520,
      ),
      builder: (sheetContext) {
        return _MessageActionsSheet(
          isMine: message.isMine(_currentUserId),
          onReaction: (emoji) {
            Navigator.pop(sheetContext);
            unawaited(_toggleReaction(message, emoji));
          },
          onReply: () {
            Navigator.pop(sheetContext);
            setState(() => _replyTo = message);
            _focusNode.requestFocus();
          },
          onEdit: () {
            Navigator.pop(sheetContext);
            unawaited(_editMessage(message));
          },
          onDelete: () {
            Navigator.pop(sheetContext);
            unawaited(_deleteMessage(message));
          },
          onReport: () {
            Navigator.pop(sheetContext);
            unawaited(_reportMessage(message));
          },
        );
      },
    );
  }

  /// Reports one message to moderation.
  ///
  /// This is the reachability that mattered: until now the only report
  /// action in the product was on the *person*, so someone who saw a
  /// single abusive message could report the account and hope a moderator
  /// found the message. `createContentReport` records the exact
  /// conversation and message id, which is what makes the report
  /// reviewable at all — and the server re-checks that the caller is one
  /// of the two participants, so this cannot be used to report a
  /// conversation the caller is not in.
  Future<void> _reportMessage(Message message) async {
    await reportContent(
      context: context,
      service: widget.contentReportService,
      content: ReportedContent.directMessage(
        conversationId: widget.conversationId,
        messageId: message.id,
      ),
      title: 'Report this message',
      subtitle:
          'Your report goes to the YO Voice moderation team with this '
          'message attached. ${widget.otherDisplayName} is not told who '
          'reported it.',
    );
  }

  Future<void> _editMessage(Message message) async {
    final editController = TextEditingController(text: message.content);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _surface,
          title: const Text(
            'Edit message',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: editController,
            autofocus: true,
            maxLines: 5,
            minLines: 1,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Message',
              hintStyle: const TextStyle(color: _muted),
              filled: true,
              fillColor: _surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: _border),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, editController.text),
              style: FilledButton.styleFrom(backgroundColor: _primary),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    editController.dispose();

    if (result == null || result.trim().isEmpty) {
      return;
    }

    try {
      await _service.editMessage(
        conversationId: widget.conversationId,
        messageId: message.id,
        text: result,
      );
    } catch (error) {
      if (mounted) {
        _showMessage(intentionalOrFriendly(error));
      }
    }
  }

  Future<void> _deleteMessage(Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _surface,
          title: const Text(
            'Delete message?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'The message will be replaced with “Message deleted”.',
            style: TextStyle(color: _muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Color(0xFFFF668B)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _service.deleteMessage(
        conversationId: widget.conversationId,
        messageId: message.id,
      );
    } catch (error) {
      if (mounted) {
        _showMessage(intentionalOrFriendly(error));
      }
    }
  }

  Future<void> _toggleMute() async {
    try {
      await _service.setConversationMuted(
        conversationId: widget.conversationId,
        muted: !_isMuted,
      );

      if (mounted) {
        setState(() => _isMuted = !_isMuted);
        _showMessage(
          _isMuted ? 'Conversation muted.' : 'Notifications turned on.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not update notifications.');
      }
    }
  }

  Future<void> _archiveConversation() async {
    try {
      await _service.archiveConversation(widget.conversationId);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not archive this conversation.');
      }
    }
  }

  Future<void> _pickPhoto() async {
    if (_sendingMedia) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
    );
    if (image == null || !mounted) return;
    setState(() => _sendingMedia = true);
    try {
      await _service.sendImageMessage(
        conversationId: widget.conversationId,
        image: image,
      );
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is VoiceRecordingException
              ? [error.message, error.action].whereType<String>().join(' ')
              : intentionalOrFriendly(
                  error,
                  fallback: 'Your photo could not be sent. Try again.',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  Future<void> _recordVoiceMessage() async {
    if (_sendingMedia) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 520,
      ),
      builder: (_) => _VoiceMessageRecorderSheet(
        onSend: (audio, durationSeconds) async {
          await _service.sendVoiceMessage(
            conversationId: widget.conversationId,
            audio: audio,
            durationSeconds: durationSeconds,
          );
        },
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message
                .replaceFirst('Bad state: ', '')
                .replaceFirst('Invalid argument(s): ', ''),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A1939),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.75, -1),
            radius: 1.2,
            colors: [Color(0xFF26103E), Color(0xFF100B1B), _background],
            stops: [0, .35, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.list,
            child: Column(
              children: [
                _ChatHeader(
                  userId: widget.otherUserId,
                  displayName: widget.otherDisplayName,
                  photoUrl: widget.otherPhotoUrl,
                  presenceStream: _presence,
                  muted: _isMuted,
                  onBack: () => Navigator.pop(context),
                  onMute: _toggleMute,
                  onArchive: _archiveConversation,
                  onProfileTap: () => showProfilePreview(
                    context,
                    userId: widget.otherUserId,
                    displayName: widget.otherDisplayName,
                    photoUrl: widget.otherPhotoUrl,
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<Message>>(
                    stream: _messages,
                    builder: (context, snapshot) {
                      final queuedMessages = _visibleOutboxEntries();
                      final hasHistoryError = snapshot.hasError;
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData &&
                          queuedMessages.isEmpty) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: _primary,
                            strokeWidth: 2.5,
                          ),
                        );
                      }

                      if (hasHistoryError && queuedMessages.isEmpty) {
                        return const Center(
                          child: Text(
                            'Could not load this conversation.',
                            style: TextStyle(color: _muted),
                          ),
                        );
                      }

                      final messages = snapshot.data ?? const <Message>[];

                      if (messages.isEmpty && queuedMessages.isEmpty) {
                        return _EmptyConversation(
                          name: widget.otherDisplayName,
                          photoUrl: widget.otherPhotoUrl,
                        );
                      }

                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                        itemCount:
                            queuedMessages.length +
                            messages.length +
                            (hasHistoryError ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Keep the local outbox visible when the server
                          // history stream fails, but never let those local
                          // bubbles imply that the conversation loaded in
                          // full. In a reversed list index zero is pinned next
                          // to the composer, so the warning stays visible.
                          if (hasHistoryError && index == 0) {
                            return const _ConversationHistoryErrorBanner();
                          }

                          final contentIndex =
                              index - (hasHistoryError ? 1 : 0);
                          if (contentIndex < queuedMessages.length) {
                            final entry = queuedMessages[contentIndex];
                            final accepted = !_outboxEntries.any(
                              (queued) => queued.id == entry.id,
                            );
                            return _QueuedTextMessageBubble(
                              key: ValueKey('queued-message-${entry.id}'),
                              entry: entry,
                              accepted: accepted,
                              onRetry: () =>
                                  unawaited(_retryQueuedMessage(entry)),
                              onDiscard: () =>
                                  unawaited(_discardQueuedMessage(entry)),
                            );
                          }

                          final messageIndex =
                              contentIndex - queuedMessages.length;
                          final message = messages[messageIndex];
                          final nextMessage = messageIndex + 1 < messages.length
                              ? messages[messageIndex + 1]
                              : null;
                          final showDate =
                              nextMessage == null ||
                              !_sameDay(message.sentAt, nextMessage.sentAt);

                          return Column(
                            key: ValueKey(message.id),
                            children: [
                              if (showDate) _DateDivider(date: message.sentAt),
                              MessageBubble(
                                message: message,
                                currentUserId: _currentUserId,
                                onLongPress: () => _messageActions(message),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                StreamBuilder<bool>(
                  stream: _typing,
                  builder: (context, snapshot) {
                    if (snapshot.data != true) {
                      return const SizedBox.shrink();
                    }

                    return const _TypingIndicator();
                  },
                ),
                if (_replyTo != null)
                  _ReplyPreview(
                    message: _replyTo!,
                    onClose: () {
                      setState(() => _replyTo = null);
                    },
                  ),
                _Composer(
                  controller: _controller,
                  focusNode: _focusNode,
                  sending: _sending,
                  sendingMedia: _sendingMedia,
                  onSend: _send,
                  onPhoto: _pickPhoto,
                  onVoice: _recordVoiceMessage,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _sameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
    required this.presenceStream,
    required this.muted,
    required this.onBack,
    required this.onMute,
    required this.onArchive,
    required this.onProfileTap,
  });

  final String userId;
  final String displayName;
  final String photoUrl;
  final Stream<ChatPresence> presenceStream;
  final bool muted;
  final VoidCallback onBack;
  final VoidCallback onMute;
  final VoidCallback onArchive;

  /// No dead avatars: tapping the person you're talking to opens their
  /// profile preview.
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 8, 8, 8),
      decoration: const BoxDecoration(
        color: Color(0xCC0E0A15),
        border: Border(bottom: BorderSide(color: _ChatScreenState._border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Back to chats',
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Open $displayName profile',
              child: InkWell(
                onTap: onProfileTap,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      _Avatar(name: displayName, url: photoUrl, radius: 20),
                      const SizedBox(width: 11),
                      Expanded(
                        child: StreamBuilder<ChatPresence>(
                          stream: presenceStream,
                          builder: (context, snapshot) {
                            final presence = snapshot.data;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    UserIdentityBadges(uid: userId),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _presenceText(presence),
                                  style: TextStyle(
                                    color: presence?.isOnline == true
                                        ? const Color(0xFF50DF86)
                                        : _ChatScreenState._muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Deliberately disabled, not a dead tap target: 1:1 calls need
          // signaling that doesn't exist yet (ringing notifications,
          // accept/decline, call session docs — VoiceCallScreen is
          // room-based). Disabled + labeled per ADR-012 until that
          // subsystem is built.
          const IconButton(
            onPressed: null,
            tooltip: 'Voice calls — coming soon',
            icon: Icon(Icons.call_outlined, color: Colors.white38),
          ),
          PopupMenuButton<String>(
            tooltip: 'Conversation options',
            color: _ChatScreenState._surface,
            icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
            onSelected: (value) {
              if (value == 'mute') {
                onMute();
              } else if (value == 'archive') {
                onArchive();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'mute',
                child: Row(
                  children: [
                    Icon(
                      muted
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      muted ? 'Unmute' : 'Mute',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'archive',
                child: Row(
                  children: [
                    Icon(Icons.archive_outlined, color: Colors.white),
                    SizedBox(width: 12),
                    Text('Archive', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _presenceText(ChatPresence? presence) {
    if (presence?.isOnline == true) {
      return 'Active now';
    }

    final lastSeen = presence?.lastSeen;

    if (lastSeen == null) {
      return 'Offline';
    }

    final difference = DateTime.now().difference(lastSeen);

    if (difference.inMinutes < 1) {
      return 'Active just now';
    }

    if (difference.inMinutes < 60) {
      return 'Active ${difference.inMinutes}m ago';
    }

    if (difference.inHours < 24) {
      return 'Active ${difference.inHours}h ago';
    }

    return 'Active ${difference.inDays}d ago';
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.name, required this.photoUrl});

  final String name;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.maxHeight > 56
            ? constraints.maxHeight - 56
            : 0.0;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Avatar(name: name, url: photoUrl, radius: 43),
                  const SizedBox(height: 17),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'You are friends on YO Voice',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _ChatScreenState._muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Say hello 👋',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFD27AFF),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final label = _sameDate(date, now)
        ? 'Today'
        : _sameDate(date, yesterday)
        ? 'Yesterday'
        : '${date.day}/${date.month}/${date.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        label,
        style: const TextStyle(
          color: _ChatScreenState._muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static bool _sameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: _ChatScreenState._surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _ChatScreenState._border),
            ),
            child: const Row(
              children: [
                _TypingDot(delay: 0),
                SizedBox(width: 4),
                _TypingDot(delay: 180),
                SizedBox(width: 4),
                _TypingDot(delay: 360),
              ],
            ),
          ),
          const SizedBox(width: 9),
          const Text(
            'typing…',
            style: TextStyle(color: _ChatScreenState._muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _TypingDot extends StatefulWidget {
  const _TypingDot({required this.delay});

  final int delay;

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _animation = Tween<double>(
      begin: .55,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _delayTimer = Timer(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Color(0xFFC35CFF),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.message, required this.onClose});

  final Message message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF171121),
        border: Border(top: BorderSide(color: _ChatScreenState._border)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 37,
            decoration: BoxDecoration(
              color: const Color(0xFFC05AFF),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(width: 11),
          const Icon(Icons.reply_rounded, color: Color(0xFFC05AFF), size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Replying to message',
                  style: TextStyle(
                    color: Color(0xFFD690FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.previewText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Close reply',
            icon: const Icon(
              Icons.close_rounded,
              color: _ChatScreenState._muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueuedTextMessageBubble extends StatelessWidget {
  const _QueuedTextMessageBubble({
    required this.entry,
    required this.accepted,
    required this.onRetry,
    required this.onDiscard,
    super.key,
  });

  final OutboxEntry entry;
  final bool accepted;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  String get _status {
    if (accepted) return 'Sent';
    return switch (entry.state) {
      OutboxState.pending => 'Sending…',
      OutboxState.retrying => 'Waiting for connection',
      OutboxState.failed => 'Not sent',
    };
  }

  IconData get _statusIcon {
    if (accepted) return Icons.done_rounded;
    return switch (entry.state) {
      OutboxState.pending => Icons.schedule_rounded,
      OutboxState.retrying => Icons.sync_rounded,
      OutboxState.failed => Icons.error_outline_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final failed = !accepted && entry.state == OutboxState.failed;
    final statusColor = failed
        ? const Color(0xFFFF9BB3)
        : const Color(0xFFD9B7F2);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Your message: ${entry.text}.',
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(left: 54, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF9026DF), Color(0xFF641CC2)],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(5),
                    ),
                    border: failed
                        ? Border.all(color: const Color(0xFFFF668B))
                        : null,
                  ),
                  child: Text(
                    entry.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Semantics(
                liveRegion: true,
                label: 'Message status: $_status',
                child: ExcludeSemantics(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 5,
                    runSpacing: 2,
                    children: [
                      Text(
                        MaterialLocalizations.of(context).formatTimeOfDay(
                          TimeOfDay.fromDateTime(entry.queuedAt.toLocal()),
                          alwaysUse24HourFormat:
                              MediaQuery.alwaysUse24HourFormatOf(context),
                        ),
                        style: const TextStyle(
                          color: _ChatScreenState._muted,
                          fontSize: 10,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_statusIcon, size: 14, color: statusColor),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              _status,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (failed) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: onDiscard,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFD9B7F2),
                        minimumSize: const Size(64, 44),
                      ),
                      child: const Text('Remove'),
                    ),
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size(64, 44),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ],
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
    required this.onSend,
    required this.onPhoto,
    required this.onVoice,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool sendingMedia;
  final VoidCallback onSend;
  final VoidCallback onPhoto;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        10,
        9,
        10,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0B16),
        border: Border(top: BorderSide(color: _ChatScreenState._border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            onPressed: sendingMedia ? null : onPhoto,
            tooltip: sendingMedia ? 'Sending attachment' : 'Add photo',
            style: IconButton.styleFrom(
              backgroundColor: _ChatScreenState._surface2,
              foregroundColor: Colors.white,
            ),
            icon: sendingMedia
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.camera_alt_outlined),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _ChatScreenState._surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _ChatScreenState._border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      readOnly: sending,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        hintStyle: TextStyle(color: _ChatScreenState._muted),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(15, 12, 8, 12),
                      ),
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty;

                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        // A local-persistence failure can move through
                        // send -> saving -> send in less than one animation
                        // frame. Keeping outgoing children in the default
                        // Stack then duplicates their keys. Fade in only the
                        // current affordance; the state itself is the useful
                        // feedback here.
                        layoutBuilder: (currentChild, _) =>
                            currentChild ?? const SizedBox.shrink(),
                        child: sending
                            ? IconButton(
                                key: const ValueKey('saving'),
                                onPressed: null,
                                tooltip: 'Saving message',
                                icon: const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : hasText
                            ? IconButton(
                                key: const ValueKey('send'),
                                onPressed: onSend,
                                tooltip: 'Send',
                                icon: const Icon(
                                  Icons.send_rounded,
                                  color: _ChatScreenState._primary,
                                ),
                              )
                            : IconButton(
                                key: const ValueKey('voice'),
                                onPressed: sendingMedia ? null : onVoice,
                                tooltip: 'Record voice message',
                                icon: const Icon(
                                  Icons.mic_none_rounded,
                                  color: Colors.white,
                                ),
                              ),
                      );
                    },
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

class _ConversationHistoryErrorBanner extends StatelessWidget {
  const _ConversationHistoryErrorBanner();

  @override
  Widget build(BuildContext context) {
    const label =
        'Could not load this conversation. Your unsent messages are still shown.';

    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF28182F),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFB8516A)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 20,
                color: Color(0xFFFFA5B9),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Could not load this conversation.',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Your unsent messages are still shown.',
                      style: TextStyle(color: Color(0xFFD8CADC)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceMessageRecorderSheet extends StatefulWidget {
  const _VoiceMessageRecorderSheet({required this.onSend});

  final Future<void> Function(RecordedAudio audio, int durationSeconds) onSend;

  @override
  State<_VoiceMessageRecorderSheet> createState() =>
      _VoiceMessageRecorderSheetState();
}

class _VoiceMessageRecorderSheetState
    extends State<_VoiceMessageRecorderSheet> {
  final VoiceMomentRecorder _recorder = VoiceMomentRecorder();
  Timer? _timer;
  RecordedAudio? _audio;
  int _durationSeconds = 0;
  bool _recording = false;
  bool _publishing = false;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_recorder.dispose());
    unawaited(_audio?.discard());
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_publishing) return;
    if (_recording) {
      await _finishRecording();
      return;
    }
    final previous = _audio;
    _audio = null;
    if (previous != null) await previous.discard();
    try {
      await _recorder.start();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _durationSeconds = 0;
        _error = null;
      });
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        final elapsed = _recorder.elapsed.inSeconds.clamp(0, 60);
        setState(() => _durationSeconds = elapsed);
        if (_recorder.elapsed >= const Duration(seconds: 60)) {
          unawaited(_finishRecording());
        }
      });
    } on VoiceRecordingException catch (error) {
      if (mounted) {
        setState(() {
          _error = [error.message, error.action].whereType<String>().join(' ');
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Recording could not be started. Try again.');
      }
    }
  }

  Future<void> _finishRecording() async {
    if (!_recording) return;
    _timer?.cancel();
    _durationSeconds = _recorder.durationSeconds;
    try {
      final audio = await _recorder.stop();
      if (!mounted) {
        await audio.discard();
        return;
      }
      setState(() {
        _recording = false;
        _audio = audio;
        _error = null;
      });
    } on VoiceRecordingException catch (error) {
      if (mounted) {
        setState(() {
          _recording = false;
          _error = [error.message, error.action].whereType<String>().join(' ');
        });
      }
    }
  }

  Future<void> _send() async {
    final audio = _audio;
    if (audio == null || _publishing) return;
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      await widget.onSend(audio, _durationSeconds);
      _audio = null;
      await audio.discard();
      if (mounted) Navigator.pop(context);
    } on VoiceRecordingException catch (error) {
      if (mounted) {
        setState(() {
          _publishing = false;
          _error = [error.message, error.action].whereType<String>().join(' ');
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _publishing = false;
          _error = intentionalOrFriendly(
            error,
            fallback: 'Your voice message could not be sent. Try again.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTake = _audio != null;
    return Semantics(
      namesRoute: true,
      label: 'Voice message recorder',
      child: Container(
        padding: EdgeInsets.fromLTRB(
          22,
          14,
          22,
          22 + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: const BoxDecoration(
          color: _ChatScreenState._surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: _ChatScreenState._border)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const YoModalSheetChrome(
                sheetLabel: 'voice message recorder',
                surfaceColor: _ChatScreenState._surface,
              ),
              const SizedBox(height: 4),
              Text(
                _recording
                    ? 'Recording voice message…'
                    : hasTake
                    ? 'Voice message ready'
                    : 'Record a voice message',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_durationSeconds ~/ 60}:${(_durationSeconds % 60).toString().padLeft(2, '0')} / 1:00',
                style: const TextStyle(
                  color: _ChatScreenState._muted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFF809D)),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Semantics(
                button: true,
                label: _recording
                    ? 'Stop recording'
                    : hasTake
                    ? 'Record again'
                    : 'Start recording',
                child: IconButton.filled(
                  onPressed: _publishing ? null : _toggleRecording,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(72),
                    backgroundColor: _recording
                        ? const Color(0xFFFF4F78)
                        : _ChatScreenState._primary,
                  ),
                  icon: Icon(
                    _recording ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 34,
                  ),
                ),
              ),
              if (hasTake) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _publishing ? null : _send,
                    icon: _publishing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _publishing ? 'Sending…' : 'Send voice message',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageActionsSheet extends StatelessWidget {
  const _MessageActionsSheet({
    required this.isMine,
    required this.onReaction,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
  });

  final bool isMine;
  final ValueChanged<String> onReaction;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Offered only on someone else's message — see the tile below.
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    const reactions = ['❤️', '😂', '🔥', '😮', '😢', '👍'];

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        18 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF15101E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      // Transparent Material, so the sheet keeps exactly this background
      // while the ListTiles below get a Material to paint their ink on.
      // Without it Flutter asserts that their splashes are invisible —
      // Reply/Edit/Delete were silently rippling behind the container.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const YoModalSheetChrome(
              sheetLabel: 'message actions',
              surfaceColor: Color(0xFF15101E),
            ),
            const SizedBox(height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: reactions
                  .map(
                    (emoji) => InkWell(
                      onTap: () => onReaction(emoji),
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 27),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const Divider(color: _ChatScreenState._border),
            ListTile(
              onTap: onReply,
              leading: const Icon(Icons.reply_rounded, color: Colors.white),
              title: const Text('Reply', style: TextStyle(color: Colors.white)),
            ),
            if (isMine)
              ListTile(
                onTap: onEdit,
                leading: const Icon(Icons.edit_outlined, color: Colors.white),
                title: const Text(
                  'Edit',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            if (isMine)
              ListTile(
                onTap: onDelete,
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFFF668B),
                ),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: Color(0xFFFF668B)),
                ),
              ),
            // Not offered on your own message. Reporting yourself is not
            // a real intent, and every such report is a row a moderator
            // has to open before discovering there is nothing to do.
            if (!isMine)
              ListTile(
                key: const ValueKey('report-message'),
                onTap: onReport,
                leading: const Icon(
                  Icons.flag_outlined,
                  color: Color(0xFFFFB547),
                ),
                title: const Text(
                  'Report message',
                  style: TextStyle(color: Color(0xFFFFB547)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.url, required this.radius});

  final String name;
  final String url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();

    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF7B25E8),
      backgroundImage: url.trim().isNotEmpty ? NetworkImage(url) : null,
      child: url.trim().isEmpty
          ? Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * .65,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }
}
