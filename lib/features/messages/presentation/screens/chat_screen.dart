import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';

import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/models/direct_call.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/calls/presentation/screens/direct_call_screen.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/active_conversation_registry.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/shared_media_screen.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_picked_video_inspector.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

typedef DirectMessagePhotoPicker = Future<XFile?> Function(ImageSource source);
typedef DirectMessageVideoPicker = Future<XFile?> Function(ImageSource source);

enum DirectMessageMediaPickAction {
  takePhoto,
  photoLibrary,
  recordVideo,
  videoLibrary,
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.conversationId,
    required this.otherUserId,
    required this.otherDisplayName,
    required this.otherEmail,
    required this.otherPhotoUrl,
    this.otherProfileUpdatedAt,
    this.messageService,
    this.profileMediaService,
    this.firestore,
    this.auth,
    this.contentReportService,
    this.directCallService,
    this.voiceCallService,
    this.profileService,
    this.photoPicker,
    this.videoPicker,
    this.videoInspector,
    this.profilePreviewAction,
    super.key,
  });

  final String conversationId;
  final String otherUserId;
  final String otherDisplayName;
  final String otherEmail;
  final String otherPhotoUrl;
  final DateTime? otherProfileUpdatedAt;

  /// Optional injection seams, matching the established pattern on
  /// FriendProfileScreen and NotificationsScreen: production passes
  /// nothing and gets the live singletons, tests pass fakes so the
  /// failure paths below can be exercised without a Firebase app.
  final MessageService? messageService;
  final ProfileMediaService? profileMediaService;
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final ContentReportService? contentReportService;
  final DirectCallGateway? directCallService;
  final VoiceCallService? voiceCallService;
  final ProfileService? profileService;
  final DirectMessagePhotoPicker? photoPicker;
  final DirectMessageVideoPicker? videoPicker;
  final DirectMessageVideoInspector? videoInspector;

  /// Deterministic seam for navigation regression tests. Production leaves
  /// this null and opens the canonical profile preview.
  final Future<void> Function()? profilePreviewAction;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final FirebaseFirestore _firestore =
      widget.firestore ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final MessageService? _ownedMessageService =
      widget.messageService == null &&
          (widget.firestore != null || widget.auth != null)
      ? MessageService(firestore: _firestore, auth: _auth)
      : null;
  late final MessageService _service =
      widget.messageService ?? _ownedMessageService ?? MessageService.live;
  late final ProfileMediaService? _profileMediaService =
      widget.profileMediaService ??
      (widget.auth != null ? ProfileMediaService(auth: _auth) : null);
  late final DirectCallGateway _calls =
      widget.directCallService ??
      DirectCallService(firestore: _firestore, auth: _auth);
  late final VoiceCallService _voice =
      widget.voiceCallService ?? VoiceCallService.instance;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late final Stream<List<Message>> _messages;
  late final Stream<bool> _typing;
  late final Stream<ChatPresence> _presence;
  StreamSubscription<UserProfile>? _profileSubscription;
  StreamSubscription<List<Message>>? _messagesSubscription;
  StreamSubscription<List<OutboxEntry>>? _outboxSubscription;
  StreamSubscription<OutboxEntry>? _deliveredSubscription;
  StreamSubscription<List<DirectAttachmentOutboxEntry>>?
  _mediaOutboxSubscription;

  Timer? _typingTimer;
  Message? _replyTo;
  bool _sending = false;
  bool _sendingMedia = false;
  bool _mediaPickerOpen = false;
  bool _startingCall = false;
  bool _profilePreviewOpen = false;
  bool _sharedMediaOpen = false;
  bool _isMuted = false;
  bool _typingAnnounced = false;
  bool _typingUpdateInFlight = false;
  bool? _pendingTypingState;
  DateTime? _lastTypingHeartbeat;
  bool _suppressTypingListener = false;
  List<OutboxEntry> _outboxEntries = const <OutboxEntry>[];
  List<DirectAttachmentOutboxEntry> _mediaOutboxEntries =
      const <DirectAttachmentOutboxEntry>[];
  final Map<String, OutboxEntry> _awaitingSnapshots = {};
  Set<String> _committedMessageIds = const <String>{};
  Map<String, Message> _committedMessagesById = const <String, Message>{};
  List<Message> _latestMessages = const <Message>[];
  List<Message>? _pendingMediaReconciliation;
  bool _mediaReconciliationInFlight = false;

  /// Read receipts follow the conversation snapshot, not the build cycle:
  /// [_newestMarkedMessageId] is the newest incoming unread message we already
  /// marked, so N rebuilds (and snapshots containing only our own messages)
  /// cost zero extra writes.
  String? _newestMarkedMessageId;
  bool _markReadRequested = false;
  bool _markReadInFlight = false;
  Timer? _markReadRetryTimer;
  int _markReadRetryAttempt = 0;
  late final String _registeredConversationId;
  late String _otherDisplayName;
  late String _otherPhotoUrl;
  DateTime? _otherProfileUpdatedAt;

  String get _currentUserId => _auth.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _registeredConversationId = widget.conversationId;
    _otherDisplayName = widget.otherDisplayName;
    _otherPhotoUrl = widget.otherPhotoUrl;
    _otherProfileUpdatedAt = widget.otherProfileUpdatedAt;
    ActiveConversationRegistry.instance.enter(_registeredConversationId);
    try {
      final profiles =
          widget.profileService ??
          ProfileService(firestore: _firestore, auth: _auth);
      _profileSubscription = profiles
          .watchProfile(widget.otherUserId)
          .listen(_handleProfileIdentity, onError: (Object _) {});
    } catch (_) {
      // Preview/test routes may not have a Firebase app. The route snapshot
      // remains a safe offline fallback in that deliberately degraded mode.
      _profileSubscription = null;
    }
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
    final mediaOutbox = _service.attachmentOutbox;
    _mediaOutboxEntries = mediaOutbox.entries
        .where((entry) => entry.conversationId == widget.conversationId)
        .toList(growable: false);
    _mediaOutboxSubscription = mediaOutbox.changes.listen(
      _handleMediaOutboxChanged,
    );
    unawaited(_loadOutbox());
    _controller.addListener(_handleTyping);
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      oldWidget.conversationId == widget.conversationId,
      'A ChatScreen state cannot be reused for a different conversation.',
    );
  }

  @override
  void dispose() {
    ActiveConversationRegistry.instance.leave(_registeredConversationId);
    _typingTimer?.cancel();
    final shouldClearTyping = _typingAnnounced;
    _typingAnnounced = false;
    _lastTypingHeartbeat = null;
    _markReadRetryTimer?.cancel();
    _pendingMediaReconciliation = null;
    unawaited(_messagesSubscription?.cancel());
    unawaited(_profileSubscription?.cancel());
    unawaited(_outboxSubscription?.cancel());
    unawaited(_deliveredSubscription?.cancel());
    unawaited(_mediaOutboxSubscription?.cancel());
    unawaited(_ownedMessageService?.dispose());
    _controller
      ..removeListener(_handleTyping)
      ..dispose();
    _focusNode.dispose();
    // Keep teardown in the same single-flight coalescer as ordinary typing.
    // Otherwise an older slow `true` can arrive after a parallel `false` and
    // leave this user shown as typing after the route is gone.
    if (shouldClearTyping) {
      _pendingTypingState = false;
      unawaited(_queueTypingUpdate(false));
    }
    super.dispose();
  }

  void _handleProfileIdentity(UserProfile profile) {
    if (!mounted) return;
    final name = profile.displayName.trim().isEmpty
        ? _otherDisplayName
        : profile.displayName.trim();
    // null is authoritative: it means the user deliberately removed their
    // avatar, not that the profile failed to load.
    final photoUrl = profile.photoUrl?.trim() ?? '';
    final profileUpdatedAt = profile.profileUpdatedAt;
    if (name == _otherDisplayName &&
        photoUrl == _otherPhotoUrl &&
        profileUpdatedAt == _otherProfileUpdatedAt) {
      return;
    }
    setState(() {
      _otherDisplayName = name;
      _otherPhotoUrl = photoUrl;
      _otherProfileUpdatedAt = profileUpdatedAt;
    });
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
    try {
      await _service.attachmentOutbox.load();
      _handleMediaOutboxChanged(_service.attachmentOutbox.entries);
    } catch (error) {
      debugPrint('ChatScreen media outbox load failed: $error');
    }
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

  void _handleMediaOutboxChanged(List<DirectAttachmentOutboxEntry> entries) {
    if (!mounted) return;
    setState(() {
      _mediaOutboxEntries = entries
          .where((entry) => entry.conversationId == widget.conversationId)
          .toList(growable: false);
    });
    _scheduleMediaReconciliation(_latestMessages);
  }

  void _handleOutboxDelivered(OutboxEntry entry) {
    if (!mounted || !_belongsToThisChat(entry)) return;
    final canonicalId = _canonicalId(entry);
    if (_committedMessageIds.contains(canonicalId)) return;
    setState(() => _awaitingSnapshots[entry.id] = entry);
  }

  /// Typing presence is an ephemeral enhancement, not a user action that can
  /// be repaired from inside the conversation. Keep failures observable in
  /// diagnostics without covering the composer with an unactionable warning.
  Future<void> _setTyping(bool isTyping) async {
    try {
      await _service.setTyping(
        conversationId: widget.conversationId,
        isTyping: isTyping,
      );
    } catch (error) {
      debugPrint('ChatScreen typing presence update failed: $error');
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
        final copy = AppLocalizations.of(context);
        _showMessage(
          intentionalOrFriendly(
            error,
            fallback: copy.text(
              'Could not update your reaction.',
              'Nie udało się zmienić reakcji.',
            ),
          ),
        );
      }
    }
  }

  /// Fires once per newest-message advance — never per rebuild. Messages
  /// arrive newest-first (watchMessages orders `sentAt` descending).
  void _handleMessagesDelivered(List<Message> messages) {
    _latestMessages = List<Message>.unmodifiable(messages);
    _committedMessagesById = <String, Message>{
      for (final message in messages) message.id: message,
    };
    _committedMessageIds = _committedMessagesById.keys.toSet();
    _scheduleMediaReconciliation(messages);
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
    final unreadIncoming = messages.where(
      (message) =>
          message.senderId != _currentUserId &&
          !message.readBy.contains(_currentUserId),
    );
    if (unreadIncoming.isEmpty) return;
    final newestId = unreadIncoming.first.id;
    if (newestId == _newestMarkedMessageId) return;
    _newestMarkedMessageId = newestId;
    _markReadRequested = true;
    unawaited(_drainMarkRead());
  }

  bool _matchesCommittedMedia(DirectAttachmentOutboxEntry entry) {
    final reservation = entry.reservation;
    if (reservation == null || reservation.messageId.isEmpty) return false;
    final message = _committedMessagesById[reservation.messageId];
    return message != null &&
        message.senderId == _currentUserId &&
        message.conversationId == entry.conversationId &&
        message.type != MessageType.text &&
        message.type == entry.type;
  }

  void _scheduleMediaReconciliation(List<Message> messages) {
    if (!mounted || messages.isEmpty || _mediaOutboxEntries.isEmpty) return;
    if (!_mediaOutboxEntries.any(_matchesCommittedMedia)) return;
    _pendingMediaReconciliation = List<Message>.unmodifiable(messages);
    if (_mediaReconciliationInFlight) return;
    _mediaReconciliationInFlight = true;
    scheduleMicrotask(_drainMediaReconciliation);
  }

  Future<void> _drainMediaReconciliation() async {
    try {
      while (mounted) {
        final messages = _pendingMediaReconciliation;
        if (messages == null) break;
        _pendingMediaReconciliation = null;
        try {
          await _service.reconcileCommittedAttachments(messages);
        } catch (error) {
          // Keep the durable entry if persistence/cleanup fails. A later
          // snapshot or outbox change retries this idempotent reconciliation.
          debugPrint('ChatScreen media reconciliation failed: $error');
        }
      }
    } finally {
      _mediaReconciliationInFlight = false;
      if (mounted && _pendingMediaReconciliation != null) {
        _mediaReconciliationInFlight = true;
        scheduleMicrotask(_drainMediaReconciliation);
      }
    }
  }

  /// Serialises read-cursor work and coalesces snapshot bursts. Firestore can
  /// emit once per message updated by a paged mark-read; starting another
  /// callable for every such snapshot both races the cursor and consumes the
  /// per-minute integrity limit.
  Future<void> _drainMarkRead() async {
    if (_markReadInFlight) return;
    _markReadInFlight = true;
    try {
      while (_markReadRequested) {
        _markReadRequested = false;
        final attemptedNewestMessageId = _newestMarkedMessageId;
        try {
          await _service.markConversationRead(widget.conversationId);
          _markReadRetryAttempt = 0;
          _markReadRetryTimer?.cancel();
          _markReadRetryTimer = null;
        } catch (error) {
          debugPrint('ChatScreen read-receipt update failed: $error');

          // Do not erase a newer request that arrived while this page was in
          // flight. With no newer request, let the next relevant snapshot
          // retry instead of pinning the failed message as already marked.
          if (_newestMarkedMessageId == attemptedNewestMessageId) {
            _newestMarkedMessageId = null;
            _scheduleMarkReadRetry();
          }

          // This is background bookkeeping, not an action the person can
          // repair from inside the conversation. Send/media/call failures
          // remain explicitly actionable; receipts stay silent and retry.
        }
      }
    } finally {
      _markReadInFlight = false;
      // A synchronous snapshot callback can queue work between the final
      // while-condition and this finally block. Do not strand that request.
      if (_markReadRequested) unawaited(_drainMarkRead());
    }
  }

  void _scheduleMarkReadRetry() {
    if (!mounted || _markReadRetryTimer != null) return;
    const delays = <Duration>[
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
      Duration(seconds: 30),
    ];
    final delay = delays[_markReadRetryAttempt.clamp(0, delays.length - 1)];
    _markReadRetryAttempt++;
    _markReadRetryTimer = Timer(delay, () {
      _markReadRetryTimer = null;
      if (!mounted) return;
      _markReadRequested = true;
      unawaited(_drainMarkRead());
    });
  }

  Future<void> _startDirectCall({
    DirectCallMediaType mediaType = DirectCallMediaType.audio,
  }) async {
    if (_startingCall) return;
    final voice = _voice;
    if (voice.status != VoiceCallStatus.disconnected &&
        voice.status != VoiceCallStatus.failed) {
      _showMessage(
        AppLocalizations.of(context).text(
          'Leave your current voice session before starting a call.',
          'Opuść bieżącą rozmowę głosową, zanim rozpoczniesz połączenie.',
        ),
      );
      return;
    }
    setState(() => _startingCall = true);
    String? callId;
    var effectiveMediaType = mediaType;
    try {
      final permissionSnapshot = await voice
          .prepareMediaPermissionsFromUserGesture(
            includeCamera: mediaType == DirectCallMediaType.video,
          );
      if (!mounted) return;
      if (!permissionSnapshot[AppPermissionKind.microphone].isUsable) {
        _showMessage(
          AppLocalizations.of(context).text(
            'Allow microphone access in system settings before starting a call.',
            'Zezwól na dostęp do mikrofonu w ustawieniach systemowych, zanim rozpoczniesz połączenie.',
          ),
        );
        return;
      }
      if (mediaType == DirectCallMediaType.video &&
          !permissionSnapshot[AppPermissionKind.camera].isUsable) {
        effectiveMediaType = DirectCallMediaType.audio;
        _showMessage(
          AppLocalizations.of(context).text(
            'Camera access is off. The call will start with audio only.',
            'Dostęp do aparatu jest wyłączony. Połączenie rozpocznie się tylko z dźwiękiem.',
          ),
        );
      }
      callId = await _calls.startCall(
        calleeId: widget.otherUserId,
        conversationId: widget.conversationId,
        mediaType: effectiveMediaType,
      );
      if (!mounted) {
        await _calls.cancel(callId);
        return;
      }
      // A mounted chat hidden under the fullscreen call is not active. Leave
      // the foreground-notification registry for the route lifetime so a DM
      // received during the call still banners/sounds.
      ActiveConversationRegistry.instance.leave(_registeredConversationId);
      try {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => DirectCallScreen(
              callId: callId!,
              callService: _calls,
              currentUserId: _currentUserId,
              participantName:
                  _auth.currentUser?.displayName ??
                  _auth.currentUser?.email ??
                  AppLocalizations.of(
                    context,
                  ).text('YO Voice user', 'Użytkownik YO Voice'),
            ),
          ),
        );
      } finally {
        if (mounted) {
          ActiveConversationRegistry.instance.enter(_registeredConversationId);
        }
      }
    } on DirectVideoCompatibilityException {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(
            copy.text(
              'This person needs a newer YO Voice version for video. You can call with audio now.',
              'Ta osoba potrzebuje nowszej wersji YO Voice do wideo. Możesz teraz zadzwonić głosowo.',
            ),
          ),
          action: SnackBarAction(
            label: copy.text('Start audio', 'Zadzwoń głosowo'),
            onPressed: () => unawaited(
              _startDirectCall(mediaType: DirectCallMediaType.audio),
            ),
          ),
        ),
      );
    } on DirectCallFriendshipException {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      _showMessage(
        copy.text(
          'Calls are temporarily unavailable while this friendship is verified. Try again shortly.',
          'Połączenia są chwilowo niedostępne, dopóki ta znajomość nie zostanie zweryfikowana. Spróbuj ponownie za chwilę.',
        ),
      );
    } on DirectCallConversationException {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      _showMessage(
        copy.text(
          'This chat is no longer ready for calls. Return to Chats and reopen the conversation.',
          'Ten czat nie jest już gotowy do połączeń. Wróć do Czatów i ponownie otwórz rozmowę.',
        ),
      );
    } on DirectCallEmailVerificationException {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      _showMessage(
        copy.text(
          'Verify your email before calling. Use the verification banner on Home.',
          'Zweryfikuj adres e-mail przed połączeniem. Użyj banera weryfikacji na stronie głównej.',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      _showMessage(
        friendlyErrorMessage(
          error,
          fallback: effectiveMediaType == DirectCallMediaType.video
              ? copy.text(
                  'Could not start this private video call.',
                  'Nie udało się rozpocząć prywatnego połączenia wideo.',
                )
              : copy.text(
                  'Could not start this private voice call.',
                  'Nie udało się rozpocząć prywatnego połączenia głosowego.',
                ),
        ),
      );
    } finally {
      if (mounted) setState(() => _startingCall = false);
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
    final shouldClearTyping = _typingAnnounced;
    _typingAnnounced = false;
    _lastTypingHeartbeat = null;
    if (shouldClearTyping) {
      unawaited(_queueTypingUpdate(false));
    }
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

  Future<void> _retryQueuedAttachment(DirectAttachmentOutboxEntry entry) async {
    try {
      await _service.retryFailedAttachment(entry.id);
    } catch (error) {
      if (mounted) _showMessage(intentionalOrFriendly(error));
    }
  }

  Future<void> _discardQueuedAttachment(
    DirectAttachmentOutboxEntry entry,
  ) async {
    try {
      await _service.discardQueuedAttachment(entry.id);
    } catch (error) {
      if (mounted) _showMessage(intentionalOrFriendly(error));
    }
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

  List<DirectAttachmentOutboxEntry> _visibleMediaOutboxEntries() {
    final visible =
        _mediaOutboxEntries
            .where((entry) => !_matchesCommittedMedia(entry))
            .toList(growable: false)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
    final copy = AppLocalizations.of(context);
    await reportContent(
      context: context,
      service: widget.contentReportService,
      content: ReportedContent.directMessage(
        conversationId: widget.conversationId,
        messageId: message.id,
      ),
      title: copy.text('Report this message', 'Zgłoś tę wiadomość'),
      subtitle: copy.template(
        'Your report goes to the YO Voice moderation team with this message attached. {displayName} is not told who reported it.',
        'Zgłoszenie wraz z tą wiadomością trafi do zespołu moderacji YO Voice. {displayName} nie dowie się, kto wysłał zgłoszenie.',
        values: {'displayName': _otherDisplayName},
      ),
    );
  }

  Future<void> _editMessage(Message message) async {
    final editController = TextEditingController(text: message.content);
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            copy.text('Edit message', 'Edytuj wiadomość'),
            style: TextStyle(color: palette.textPrimary),
          ),
          content: TextField(
            controller: editController,
            autofocus: true,
            maxLines: 5,
            minLines: 1,
            style: TextStyle(color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: copy.text('Message', 'Wiadomość'),
              hintStyle: TextStyle(color: palette.textTertiary),
              filled: true,
              fillColor: palette.surfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: palette.border),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, editController.text),
              child: Text(copy.text('Save', 'Zapisz')),
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            copy.text('Delete message?', 'Usunąć wiadomość?'),
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            copy.text(
              'The message will be replaced with “Message deleted”.',
              'Wiadomość zostanie zastąpiona tekstem „Wiadomość usunięta”.',
            ),
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                copy.text('Delete', 'Usuń'),
                style: TextStyle(color: colors.onErrorContainer),
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

  Future<void> _openProfilePreview() async {
    if (_profilePreviewOpen) return;
    _profilePreviewOpen = true;
    try {
      final action = widget.profilePreviewAction;
      if (action != null) {
        await action();
      } else {
        await showProfilePreview(
          context,
          userId: widget.otherUserId,
          displayName: _otherDisplayName,
          photoUrl: _otherPhotoUrl,
          firestore: _firestore,
          auth: _auth,
          messageService: _service,
          profileMediaService: _profileMediaService,
        );
      }
    } finally {
      _profilePreviewOpen = false;
    }
  }

  Future<void> _openSharedMedia() async {
    if (_sharedMediaOpen || !mounted) return;
    _sharedMediaOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => SharedMediaScreen(
            conversationId: widget.conversationId,
            messageService: _service,
          ),
        ),
      );
    } finally {
      _sharedMediaOpen = false;
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
        final copy = AppLocalizations.of(context);
        _showMessage(
          _isMuted
              ? copy.text(
                  'Conversation muted.',
                  'Powiadomienia dla rozmowy zostały wyciszone.',
                )
              : copy.text(
                  'Notifications turned on.',
                  'Powiadomienia zostały włączone.',
                ),
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          AppLocalizations.of(context).text(
            'Could not update notifications.',
            'Nie udało się zmienić ustawień powiadomień.',
          ),
        );
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
        _showMessage(
          AppLocalizations.of(context).text(
            'Could not archive this conversation.',
            'Nie udało się zarchiwizować tej rozmowy.',
          ),
        );
      }
    }
  }

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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
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
    if (_sendingMedia || _mediaPickerOpen) return;
    _mediaPickerOpen = true;
    DirectMessageMediaPickAction? action;
    try {
      action = await _chooseMediaAction();
    } finally {
      _mediaPickerOpen = false;
    }
    if (action == null || !mounted) return;
    switch (action) {
      case DirectMessageMediaPickAction.takePhoto:
        return _pickPhoto(ImageSource.camera);
      case DirectMessageMediaPickAction.photoLibrary:
        return _pickPhoto(ImageSource.gallery);
      case DirectMessageMediaPickAction.recordVideo:
        return _pickVideo(ImageSource.camera);
      case DirectMessageMediaPickAction.videoLibrary:
        return _pickVideo(ImageSource.gallery);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_sendingMedia) return;
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
    setState(() => _sendingMedia = true);
    try {
      await _service.sendImageMessage(
        conversationId: widget.conversationId,
        image: image,
      );
    } catch (error) {
      if (mounted) {
        final copy = AppLocalizations.of(context);
        _showMessage(
          error is VoiceRecordingException
              ? [error.message, error.action].whereType<String>().join(' ')
              : intentionalOrFriendly(
                  error,
                  fallback: copy.text(
                    'Your photo could not be sent. Try again.',
                    'Nie udało się wysłać zdjęcia. Spróbuj ponownie.',
                  ),
                ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    if (_sendingMedia) return;
    try {
      final picker = widget.videoPicker;
      final video = picker != null
          ? await picker(source)
          : await ImagePicker().pickVideo(
              source: source,
              maxDuration: const Duration(seconds: 60),
            );
      if (video == null || !mounted) return;
      setState(() => _sendingMedia = true);
      final duration =
          await (widget.videoInspector ?? inspectPickedDirectVideo)(video);
      final durationSeconds = (duration.inMilliseconds + 999) ~/ 1000;
      await _service.sendVideoMessage(
        conversationId: widget.conversationId,
        video: video,
        durationSeconds: durationSeconds,
      );
    } catch (error) {
      if (mounted) {
        final copy = AppLocalizations.of(context);
        _showMessage(
          intentionalOrFriendly(
            error,
            fallback: copy.text(
              'Your video could not be sent. Choose a video up to 60 seconds and try again.',
              'Nie udało się wysłać filmu. Wybierz film do 60 sekund i spróbuj ponownie.',
            ),
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
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final copy = AppLocalizations.of(context);

    return Scaffold(
      key: const ValueKey('chat-screen'),
      backgroundColor: palette.background,
      body: YoPageBackground(
        section: YoPageSection.chats,
        key: const ValueKey('chat-screen-background'),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.75, -1),
            radius: 1.2,
            colors: [
              Color.lerp(
                palette.backgroundTop,
                colors.primary,
                isDark ? .18 : .055,
              )!,
              palette.backgroundTop,
              palette.background,
            ],
            stops: const [0, .35, 1],
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
                  displayName: _otherDisplayName,
                  photoUrl: _otherPhotoUrl,
                  mediaRevision: _otherProfileUpdatedAt,
                  profileMediaService: _profileMediaService,
                  presenceStream: _presence,
                  muted: _isMuted,
                  callBusy: _startingCall,
                  onBack: () => Navigator.pop(context),
                  onMute: _toggleMute,
                  onArchive: _archiveConversation,
                  onSharedMedia: _openSharedMedia,
                  onProfileTap: _openProfilePreview,
                  onCall: () => _startDirectCall(),
                  onVideoCall: () =>
                      _startDirectCall(mediaType: DirectCallMediaType.video),
                ),
                Expanded(
                  child: StreamBuilder<List<Message>>(
                    stream: _messages,
                    builder: (context, snapshot) {
                      final queuedMessages = _visibleOutboxEntries();
                      final queuedMedia = _visibleMediaOutboxEntries();
                      final hasHistoryError = snapshot.hasError;
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData &&
                          queuedMessages.isEmpty &&
                          queuedMedia.isEmpty) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: colors.primary,
                            strokeWidth: 2.5,
                          ),
                        );
                      }

                      if (hasHistoryError &&
                          queuedMessages.isEmpty &&
                          queuedMedia.isEmpty) {
                        return Center(
                          child: Text(
                            copy.text(
                              'Could not load this conversation.',
                              'Nie udało się wczytać tej rozmowy.',
                            ),
                            style: TextStyle(color: palette.textSecondary),
                          ),
                        );
                      }

                      final messages = snapshot.data ?? const <Message>[];

                      if (messages.isEmpty &&
                          queuedMessages.isEmpty &&
                          queuedMedia.isEmpty) {
                        return _EmptyConversation(
                          userId: widget.otherUserId,
                          name: _otherDisplayName,
                          photoUrl: _otherPhotoUrl,
                          mediaRevision: _otherProfileUpdatedAt,
                          profileMediaService: _profileMediaService,
                        );
                      }

                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                        itemCount:
                            queuedMedia.length +
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
                          if (contentIndex < queuedMedia.length) {
                            final entry = queuedMedia[contentIndex];
                            return _QueuedMediaMessageCard(
                              key: ValueKey('queued-media-${entry.id}'),
                              entry: entry,
                              onRetry: () =>
                                  unawaited(_retryQueuedAttachment(entry)),
                              onDiscard: () =>
                                  unawaited(_discardQueuedAttachment(entry)),
                            );
                          }

                          final textIndex = contentIndex - queuedMedia.length;
                          if (textIndex < queuedMessages.length) {
                            final entry = queuedMessages[textIndex];
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
                              textIndex - queuedMessages.length;
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
                  onPhoto: _pickAttachment,
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
    required this.mediaRevision,
    this.profileMediaService,
    required this.presenceStream,
    required this.muted,
    required this.callBusy,
    required this.onBack,
    required this.onMute,
    required this.onArchive,
    required this.onSharedMedia,
    required this.onProfileTap,
    required this.onCall,
    required this.onVideoCall,
  });

  final String userId;
  final String displayName;
  final String photoUrl;
  final Object? mediaRevision;
  final ProfileMediaService? profileMediaService;
  final Stream<ChatPresence> presenceStream;
  final bool muted;
  final bool callBusy;
  final VoidCallback onBack;
  final VoidCallback onMute;
  final VoidCallback onArchive;
  final VoidCallback onSharedMedia;

  /// No dead avatars: tapping the person you're talking to opens their
  /// profile preview.
  final VoidCallback onProfileTap;
  final VoidCallback onCall;
  final VoidCallback onVideoCall;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);

    return Container(
      key: const ValueKey('chat-header'),
      padding: const EdgeInsets.fromLTRB(7, 8, 8, 8),
      decoration: BoxDecoration(
        color: palette.navigationSurface.withValues(alpha: .96),
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: copy.text('Back to chats', 'Wróć do czatów'),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: palette.textPrimary,
              size: 20,
            ),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: copy.template(
                'Open {displayName} profile',
                'Otwórz profil: {displayName}',
                values: {'displayName': displayName},
              ),
              child: InkWell(
                onTap: onProfileTap,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      _Avatar(
                        userId: userId,
                        name: displayName,
                        url: photoUrl,
                        mediaRevision: mediaRevision,
                        profileMediaService: profileMediaService,
                        radius: 20,
                      ),
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
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    UserIdentityBadges(uid: userId),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _presenceText(
                                    presence,
                                    AppLocalizations.of(context),
                                  ),
                                  style: TextStyle(
                                    color: presence?.isOnline == true
                                        ? const Color(0xFF50DF86)
                                        : palette.textSecondary,
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
          IconButton(
            onPressed: callBusy ? null : onCall,
            tooltip: callBusy
                ? copy.text(
                    'Starting voice call',
                    'Rozpoczynanie połączenia głosowego',
                  )
                : copy.text(
                    'Start voice call',
                    'Rozpocznij połączenie głosowe',
                  ),
            icon: callBusy
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  )
                : Icon(Icons.call_rounded, color: palette.textPrimary),
          ),
          IconButton(
            onPressed: callBusy ? null : onVideoCall,
            tooltip: callBusy
                ? copy.text('Starting call', 'Rozpoczynanie połączenia')
                : copy.text('Start video call', 'Rozpocznij połączenie wideo'),
            icon: Icon(
              Icons.videocam_rounded,
              color: callBusy ? palette.textTertiary : palette.textPrimary,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: copy.text('Conversation options', 'Opcje rozmowy'),
            color: palette.surfaceRaised,
            icon: Icon(Icons.more_horiz_rounded, color: palette.textPrimary),
            onSelected: (value) {
              if (value == 'mute') {
                onMute();
              } else if (value == 'archive') {
                onArchive();
              } else if (value == 'shared-media') {
                onSharedMedia();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'shared-media',
                child: Row(
                  children: [
                    Icon(Icons.perm_media_outlined, color: palette.textPrimary),
                    const SizedBox(width: 12),
                    Text(
                      copy.text('Shared media', 'Udostępnione multimedia'),
                      style: TextStyle(color: palette.textPrimary),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'mute',
                child: Row(
                  children: [
                    Icon(
                      muted
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      color: palette.textPrimary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      muted
                          ? copy.text('Unmute', 'Włącz powiadomienia')
                          : copy.text('Mute', 'Wycisz'),
                      style: TextStyle(color: palette.textPrimary),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'archive',
                child: Row(
                  children: [
                    Icon(Icons.archive_outlined, color: palette.textPrimary),
                    const SizedBox(width: 12),
                    Text(
                      copy.text('Archive', 'Archiwizuj'),
                      style: TextStyle(color: palette.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _presenceText(ChatPresence? presence, AppLocalizations copy) {
    if (presence?.isOnline == true) {
      return copy.text('Active now', 'Aktywny teraz');
    }

    final lastSeen = presence?.lastSeen;

    if (lastSeen == null) {
      return copy.text('Offline', 'Nieaktywny');
    }
    return copy.activeTime(lastSeen);
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({
    required this.userId,
    required this.name,
    required this.photoUrl,
    required this.mediaRevision,
    this.profileMediaService,
  });

  final String userId;
  final String name;
  final String photoUrl;
  final Object? mediaRevision;
  final ProfileMediaService? profileMediaService;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);

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
                  _Avatar(
                    userId: userId,
                    name: name,
                    url: photoUrl,
                    mediaRevision: mediaRevision,
                    profileMediaService: profileMediaService,
                    radius: 43,
                  ),
                  const SizedBox(height: 17),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    copy.text(
                      'You are friends on YO Voice',
                      'Jesteście znajomymi w YO Voice',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    copy.text('Say hello 👋', 'Przywitaj się 👋'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.focus,
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
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final label = _sameDate(date, now)
        ? copy.today
        : _sameDate(date, yesterday)
        ? copy.yesterday
        : copy.calendarDate(date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        label,
        style: TextStyle(
          color: palette.textSecondary,
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
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.border),
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
          Text(
            copy.text('typing…', 'pisze…'),
            style: TextStyle(color: palette.textSecondary, fontSize: 11),
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
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        border: Border(top: BorderSide(color: palette.border)),
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
                Text(
                  copy.text('Replying to message', 'Odpowiadasz na wiadomość'),
                  style: TextStyle(
                    color: palette.focus,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _localizedMessagePreview(message, copy),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: copy.text('Close reply', 'Anuluj odpowiedź'),
            icon: Icon(Icons.close_rounded, color: palette.textSecondary),
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

  String _status(AppLocalizations copy) {
    if (accepted) return copy.text('Sent', 'Wysłano');
    return switch (entry.state) {
      OutboxState.pending => copy.text('Sending…', 'Wysyłanie…'),
      OutboxState.retrying => copy.text(
        'Waiting for connection',
        'Oczekiwanie na połączenie',
      ),
      OutboxState.failed => copy.text('Not sent', 'Nie wysłano'),
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

  String _failureGuidance(AppLocalizations copy) {
    final error = (entry.lastError ?? '').trim().toLowerCase();
    bool containsAny(Iterable<String> fragments) =>
        fragments.any(error.contains);

    if (containsAny(const ['unauthenticated', 'signed in', 'session'])) {
      return copy.text(
        'Your session needs to be refreshed. Sign in again, then retry.',
        'Sesja wymaga odświeżenia. Zaloguj się ponownie i spróbuj jeszcze raz.',
      );
    }
    if (containsAny(const [
      'resource-exhausted',
      'rate limit',
      'too many',
      'quota',
    ])) {
      return copy.text(
        'Too many messages were sent at once. Wait a moment, then retry.',
        'Wysłano zbyt wiele wiadomości naraz. Odczekaj chwilę i spróbuj ponownie.',
      );
    }
    if (containsAny(const [
      'not-found',
      'conversation does not exist',
      'conversation is missing',
      'recipient does not exist',
    ])) {
      return copy.text(
        'This conversation is no longer available. Return to Chats and start a new one.',
        'Ta rozmowa nie jest już dostępna. Wróć do czatów i rozpocznij nową.',
      );
    }
    if (containsAny(const [
      'invalid-argument',
      'message cannot be empty',
      'message is too long',
      'malformed',
    ])) {
      return copy.text(
        "This message can't be sent as written. Copy it, remove it, then send a shorter message.",
        'Nie można wysłać tej wiadomości w tej formie. Skopiuj ją, usuń i wyślij krótszą wersję.',
      );
    }
    if (containsAny(const [
      'permission-denied',
      'permission denied',
      'failed-precondition',
      'blocked',
      'privacy',
      'restricted',
      'not friends',
    ])) {
      return copy.text(
        "Messaging isn't available for this conversation. Check the person's profile or remove this message.",
        'W tej rozmowie wiadomości są niedostępne. Sprawdź profil tej osoby lub usuń wiadomość.',
      );
    }
    if (containsAny(const [
      'unavailable',
      'deadline-exceeded',
      'timeout',
      'timed out',
      'connection',
      'network',
      'offline',
      'socket',
      'dns',
      'internal',
      'aborted',
      'cancelled',
    ])) {
      return copy.text(
        "YO Voice couldn't reach the messaging service. Check your connection, then retry.",
        'YO Voice nie może teraz połączyć się z usługą wiadomości. Sprawdź internet i spróbuj ponownie.',
      );
    }
    return copy.text(
      "YO Voice couldn't send this message. Check your connection, then retry or remove it.",
      'YO Voice nie może wysłać tej wiadomości. Sprawdź internet, a następnie spróbuj ponownie lub ją usuń.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final failed = !accepted && entry.state == OutboxState.failed;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final status = _status(copy);
    final failureGuidance = failed ? _failureGuidance(copy) : null;
    final statusColor = failed ? colors.onErrorContainer : palette.focus;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: copy.template(
        'Your message: {message}.',
        'Twoja wiadomość: {message}.',
        values: {'message': entry.text},
      ),
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
                label: copy.template(
                  'Message status: {status}',
                  'Status wiadomości: {status}',
                  values: {'status': status},
                ),
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
                        style: TextStyle(
                          color: palette.textTertiary,
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
                              status,
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
                const SizedBox(height: 6),
                Semantics(
                  liveRegion: true,
                  label: copy.template(
                    'Why it was not sent: {guidance}',
                    'Dlaczego nie wysłano: {guidance}',
                    values: {'guidance': failureGuidance!},
                  ),
                  child: ExcludeSemantics(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 310),
                      child: Text(
                        failureGuidance,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    TextButton(
                      onPressed: onDiscard,
                      style: TextButton.styleFrom(
                        foregroundColor: palette.textSecondary,
                        minimumSize: const Size(64, 44),
                      ),
                      child: Text(copy.text('Remove', 'Usuń')),
                    ),
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        foregroundColor: palette.focus,
                        minimumSize: const Size(64, 44),
                      ),
                      child: Text(copy.text('Retry', 'Spróbuj ponownie')),
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

class _QueuedMediaMessageCard extends StatelessWidget {
  const _QueuedMediaMessageCard({
    required this.entry,
    required this.onRetry,
    required this.onDiscard,
    super.key,
  });

  final DirectAttachmentOutboxEntry entry;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  String _kind(AppLocalizations copy) => switch (entry.type) {
    MessageType.voice => copy.text('Voice message', 'Wiadomość głosowa'),
    MessageType.video => copy.text('Video', 'Film'),
    MessageType.image => copy.text('Photo', 'Zdjęcie'),
    MessageType.text => copy.text('Message', 'Wiadomość'),
  };

  String _status(AppLocalizations copy) => switch (entry.status) {
    DirectAttachmentOutboxStatus.queued => copy.text('Sending…', 'Wysyłanie…'),
    DirectAttachmentOutboxStatus.retrying => copy.text(
      'Waiting for connection',
      'Oczekiwanie na połączenie',
    ),
    DirectAttachmentOutboxStatus.failed => copy.text('Not sent', 'Nie wysłano'),
  };

  IconData get _kindIcon => switch (entry.type) {
    MessageType.voice => Icons.graphic_eq_rounded,
    MessageType.video => Icons.video_file_outlined,
    MessageType.image => Icons.image_outlined,
    MessageType.text => Icons.chat_bubble_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final failed = entry.status == DirectAttachmentOutboxStatus.failed;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final kind = _kind(copy);
    final status = _status(copy);
    final semanticSubject = switch (entry.type) {
      MessageType.voice => copy.text(
        'Your voice message',
        'Twoja wiadomość głosowa',
      ),
      MessageType.video => copy.text('Your video', 'Twój film'),
      MessageType.image => copy.text('Your photo', 'Twoje zdjęcie'),
      MessageType.text => copy.text('Your message', 'Twoja wiadomość'),
    };
    final statusColor = failed ? colors.onErrorContainer : palette.focus;
    final maxWidth = (MediaQuery.sizeOf(context).width * 0.82).clamp(
      220.0,
      380.0,
    );

    return Semantics(
      container: true,
      label: copy.template(
        '{subject}. Status: {status}.',
        '{subject}. Status: {status}.',
        values: {'subject': semanticSubject, 'status': status},
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          margin: const EdgeInsets.only(left: 24, bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
          decoration: BoxDecoration(
            color: palette.surfaceMuted,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(5),
            ),
            border: Border.all(
              color: failed ? colors.onErrorContainer : palette.borderStrong,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(_kindIcon, color: colors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          kind,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (failed) ...[
                    TextButton(
                      key: ValueKey('discard-media-${entry.id}'),
                      onPressed: onDiscard,
                      style: TextButton.styleFrom(
                        foregroundColor: palette.textSecondary,
                        minimumSize: const Size(84, 44),
                      ),
                      child: Text(copy.text('Discard', 'Odrzuć')),
                    ),
                    FilledButton(
                      key: ValueKey('retry-media-${entry.id}'),
                      onPressed: onRetry,
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        minimumSize: const Size(84, 44),
                      ),
                      child: Text(copy.text('Retry', 'Spróbuj ponownie')),
                    ),
                  ],
                ],
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);

    return Container(
      key: const ValueKey('chat-composer'),
      padding: EdgeInsets.fromLTRB(
        10,
        9,
        10,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: palette.navigationSurface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            onPressed: sendingMedia ? null : onPhoto,
            tooltip: sendingMedia
                ? copy.text('Sending attachment', 'Wysyłanie załącznika')
                : copy.text('Add photo or video', 'Dodaj zdjęcie lub film'),
            style: IconButton.styleFrom(
              backgroundColor: palette.surfaceMuted,
              foregroundColor: palette.textPrimary,
            ),
            icon: sendingMedia
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  )
                : const Icon(Icons.camera_alt_outlined),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: palette.borderStrong),
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
                      style: TextStyle(color: palette.textPrimary),
                      decoration: InputDecoration(
                        hintText: copy.text('Message…', 'Wiadomość…'),
                        hintStyle: TextStyle(color: palette.textTertiary),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(
                          15,
                          12,
                          8,
                          12,
                        ),
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
                                tooltip: copy.text(
                                  'Saving message',
                                  'Zapisywanie wiadomości',
                                ),
                                icon: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.primary,
                                  ),
                                ),
                              )
                            : hasText
                            ? IconButton(
                                key: const ValueKey('send'),
                                onPressed: onSend,
                                tooltip: copy.text('Send', 'Wyślij'),
                                icon: Icon(
                                  Icons.send_rounded,
                                  color: colors.primary,
                                ),
                              )
                            : IconButton(
                                key: const ValueKey('voice'),
                                onPressed: sendingMedia ? null : onVoice,
                                tooltip: copy.text(
                                  'Record voice message',
                                  'Nagraj wiadomość głosową',
                                ),
                                icon: Icon(
                                  Icons.mic_none_rounded,
                                  color: palette.textPrimary,
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
    final copy = AppLocalizations.of(context);
    final label = copy.text(
      'Could not load this conversation. Your unsent messages are still shown.',
      'Nie udało się wczytać tej rozmowy. Niewysłane wiadomości są nadal widoczne.',
    );
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.onErrorContainer),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 20,
                color: colors.onErrorContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.text(
                        'Could not load this conversation.',
                        'Nie udało się wczytać tej rozmowy.',
                      ),
                      style: TextStyle(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      copy.text(
                        'Your unsent messages are still shown.',
                        'Niewysłane wiadomości są nadal widoczne.',
                      ),
                      style: TextStyle(color: colors.onErrorContainer),
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
  AudioPlayer? _previewPlayer;
  StreamSubscription<PlayerState>? _previewStateSubscription;
  PlayerState _previewState = PlayerState.stopped;
  int _durationSeconds = 0;
  bool _recording = false;
  bool _publishing = false;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_previewStateSubscription?.cancel());
    unawaited(_previewPlayer?.dispose());
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
    await _stopPreview();
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
        setState(
          () => _error = AppLocalizations.of(context).text(
            'Recording could not be started. Try again.',
            'Nie udało się rozpocząć nagrywania. Spróbuj ponownie.',
          ),
        );
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

  AudioPlayer _ensurePreviewPlayer() {
    final existing = _previewPlayer;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _previewPlayer = player;
    _previewStateSubscription = player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _previewState = state);
    });
    return player;
  }

  Future<void> _stopPreview() async {
    final player = _previewPlayer;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {
      // Recording/replacing must remain available even if audio teardown on
      // one platform fails. The player is disposed with the sheet as well.
    }
    if (mounted) setState(() => _previewState = PlayerState.stopped);
  }

  Future<void> _togglePreview() async {
    final audio = _audio;
    if (audio == null || _publishing) return;
    try {
      final player = _ensurePreviewPlayer();
      if (_previewState == PlayerState.playing) {
        await player.pause();
      } else if (_previewState == PlayerState.paused) {
        await player.resume();
      } else {
        await player.play(audio.playbackSource);
      }
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).text(
            'This recording could not be previewed. Record it again.',
            'Nie udało się odtworzyć nagrania. Nagraj je ponownie.',
          );
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
      await _stopPreview();
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
        final copy = AppLocalizations.of(context);
        setState(() {
          _publishing = false;
          _error = intentionalOrFriendly(
            error,
            fallback: copy.text(
              'Your voice message could not be sent. Try again.',
              'Nie udało się wysłać wiadomości głosowej. Spróbuj ponownie.',
            ),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTake = _audio != null;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Semantics(
      namesRoute: true,
      label: copy.text(
        'Voice message recorder',
        'Nagrywanie wiadomości głosowej',
      ),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          22,
          14,
          22,
          22 + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              YoModalSheetChrome(
                sheetLabel: copy.text(
                  'voice message recorder',
                  'nagrywanie wiadomości głosowej',
                ),
                surfaceColor: palette.surfaceRaised,
              ),
              const SizedBox(height: 4),
              Text(
                _recording
                    ? copy.text(
                        'Recording voice message…',
                        'Nagrywanie wiadomości głosowej…',
                      )
                    : hasTake
                    ? copy.text(
                        'Voice message ready',
                        'Wiadomość głosowa jest gotowa',
                      )
                    : copy.text(
                        'Record a voice message',
                        'Nagraj wiadomość głosową',
                      ),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_durationSeconds ~/ 60}:${(_durationSeconds % 60).toString().padLeft(2, '0')} / 1:00',
                style: TextStyle(
                  color: palette.textSecondary,
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
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Semantics(
                button: true,
                label: _recording
                    ? copy.text('Stop recording', 'Zatrzymaj nagrywanie')
                    : hasTake
                    ? copy.text('Record again', 'Nagraj ponownie')
                    : copy.text('Start recording', 'Rozpocznij nagrywanie'),
                child: IconButton.filled(
                  onPressed: _publishing ? null : _toggleRecording,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(72),
                    backgroundColor: _recording
                        ? const Color(0xFFFF4F78)
                        : colors.primary,
                    foregroundColor: _recording
                        ? AppColors.contrastInk
                        : colors.onPrimary,
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
                  child: OutlinedButton.icon(
                    onPressed: _publishing ? null : _togglePreview,
                    icon: Icon(
                      _previewState == PlayerState.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(
                      _previewState == PlayerState.playing
                          ? copy.text('Pause preview', 'Wstrzymaj odsłuch')
                          : _previewState == PlayerState.paused
                          ? copy.text('Resume preview', 'Wznów odsłuch')
                          : copy.text(
                              'Preview voice message',
                              'Odsłuchaj wiadomość głosową',
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _publishing ? null : _send,
                    icon: _publishing
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.onPrimary,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _publishing
                          ? copy.text('Sending…', 'Wysyłanie…')
                          : copy.text(
                              'Send voice message',
                              'Wyślij wiadomość głosową',
                            ),
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final warning = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFFB547)
        : const Color(0xFF754A00);

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        18 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
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
            YoModalSheetChrome(
              sheetLabel: copy.text('message actions', 'opcje wiadomości'),
              surfaceColor: palette.surfaceRaised,
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
            Divider(color: palette.border),
            ListTile(
              onTap: onReply,
              leading: Icon(Icons.reply_rounded, color: palette.textPrimary),
              title: Text(
                copy.text('Reply', 'Odpowiedz'),
                style: TextStyle(color: palette.textPrimary),
              ),
            ),
            if (isMine)
              ListTile(
                onTap: onEdit,
                leading: Icon(Icons.edit_outlined, color: palette.textPrimary),
                title: Text(
                  copy.text('Edit', 'Edytuj'),
                  style: TextStyle(color: palette.textPrimary),
                ),
              ),
            if (isMine)
              ListTile(
                onTap: onDelete,
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: colors.onErrorContainer,
                ),
                title: Text(
                  copy.text('Delete', 'Usuń'),
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
            // Not offered on your own message. Reporting yourself is not
            // a real intent, and every such report is a row a moderator
            // has to open before discovering there is nothing to do.
            if (!isMine)
              ListTile(
                key: const ValueKey('report-message'),
                onTap: onReport,
                leading: Icon(Icons.flag_outlined, color: warning),
                title: Text(
                  copy.text('Report message', 'Zgłoś wiadomość'),
                  style: TextStyle(color: warning),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.userId,
    required this.name,
    required this.url,
    required this.mediaRevision,
    this.profileMediaService,
    required this.radius,
  });

  final String userId;
  final String name;
  final String url;
  final Object? mediaRevision;
  final ProfileMediaService? profileMediaService;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return UserAvatar(
      radius: radius,
      userId: userId,
      backgroundColor: const Color(0xFF7B25E8),
      photoUrl: url,
      mediaRevision: mediaRevision,
      mediaService: profileMediaService,
      displayName: name,
    );
  }
}

String _localizedMessagePreview(Message message, AppLocalizations copy) {
  if (message.isDeleted) {
    return copy.text('Message deleted', 'Wiadomość usunięta');
  }
  return switch (message.type) {
    MessageType.voice => copy.text('Voice message', 'Wiadomość głosowa'),
    MessageType.image => copy.text('Photo', 'Zdjęcie'),
    MessageType.video => copy.text('Video', 'Film'),
    MessageType.text => message.content,
  };
}
