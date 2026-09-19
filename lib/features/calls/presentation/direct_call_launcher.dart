import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/calls/data/models/direct_call.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/calls/presentation/screens/direct_call_screen.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';

/// Starts a private 1:1 call from any surface that knows who to call.
///
/// This is the flow that used to live inside `ChatScreen._startDirectCall`,
/// moved verbatim so the chat header and the friend profile share one path,
/// one copy table and one exception mapping. The order is load-bearing:
///
/// 1. refuse while another voice session is live;
/// 2. ask for media permissions — the FIRST await after the tap, which keeps
///    the browser's user-gesture chain intact on web;
/// 3. resolve the conversation ([resolveConversationId]; the chat already
///    knows it, the profile opens it through `openDirectConversation`);
/// 4. `startDirectCall` on the backend, which re-proves friendship, blocks,
///    restrictions and the two-person conversation;
/// 5. push the fullscreen [DirectCallScreen].
///
/// The caller owns its busy flag through [onBusyChanged] (called with `true`
/// once the flow really starts and `false` when it ends while still
/// mounted), and its snackbar presentation through [showMessage].
/// [onCoveredStart] / [onCoveredEnd] bracket the fullscreen call route.
/// [describeError] lets a caller name a failure the shared table does not
/// know (it runs before the generic fallback and returns null to pass).
Future<void> launchDirectCall(
  BuildContext context, {
  required DirectCallGateway calls,
  required VoiceCallService voice,
  required String calleeId,
  required FutureOr<String> Function() resolveConversationId,
  required String currentUserId,
  required String Function() participantName,
  required void Function(String message) showMessage,
  required void Function(bool busy) onBusyChanged,
  required VoidCallback onStartAudioInstead,
  DirectCallMediaType mediaType = DirectCallMediaType.audio,
  VoidCallback? onCoveredStart,
  VoidCallback? onCoveredEnd,
  String? Function(Object error, AppLocalizations copy)? describeError,
}) async {
  if (voice.status != VoiceCallStatus.disconnected &&
      voice.status != VoiceCallStatus.failed) {
    showMessage(
      AppLocalizations.of(context).text(
        'Leave your current voice session before starting a call.',
        'Opuść bieżącą rozmowę głosową, zanim rozpoczniesz połączenie.',
      ),
    );
    return;
  }
  onBusyChanged(true);
  String? callId;
  var effectiveMediaType = mediaType;
  try {
    final permissionSnapshot = await voice
        .prepareMediaPermissionsFromUserGesture(
          includeCamera: mediaType == DirectCallMediaType.video,
        );
    if (!context.mounted) return;
    if (!permissionSnapshot[AppPermissionKind.microphone].isUsable) {
      showMessage(
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
      showMessage(
        AppLocalizations.of(context).text(
          'Camera access is off. The call will start with audio only.',
          'Dostęp do aparatu jest wyłączony. Połączenie rozpocznie się tylko z dźwiękiem.',
        ),
      );
    }
    // A caller that already knows the conversation answers synchronously, so
    // the chat path keeps exactly its previous microtask timing.
    final pendingConversation = resolveConversationId();
    final String conversationId;
    if (pendingConversation is Future<String>) {
      conversationId = await pendingConversation;
      if (!context.mounted) return;
    } else {
      conversationId = pendingConversation;
    }
    callId = await calls.startCall(
      calleeId: calleeId,
      conversationId: conversationId,
      mediaType: effectiveMediaType,
    );
    if (!context.mounted) {
      await calls.cancel(callId);
      return;
    }
    onCoveredStart?.call();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => DirectCallScreen(
            callId: callId!,
            callService: calls,
            currentUserId: currentUserId,
            participantName: participantName(),
          ),
        ),
      );
    } finally {
      if (context.mounted) onCoveredEnd?.call();
    }
  } on DirectVideoCompatibilityException {
    if (!context.mounted) return;
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
          onPressed: onStartAudioInstead,
        ),
      ),
    );
  } on DirectCallFriendshipException {
    if (!context.mounted) return;
    final copy = AppLocalizations.of(context);
    showMessage(
      copy.text(
        'Calls are temporarily unavailable while this friendship is verified. Try again shortly.',
        'Połączenia są chwilowo niedostępne, dopóki ta znajomość nie zostanie zweryfikowana. Spróbuj ponownie za chwilę.',
      ),
    );
  } on DirectCallConversationException {
    if (!context.mounted) return;
    final copy = AppLocalizations.of(context);
    showMessage(
      copy.text(
        'This chat is no longer ready for calls. Return to Chats and reopen the conversation.',
        'Ten czat nie jest już gotowy do połączeń. Wróć do Czatów i ponownie otwórz rozmowę.',
      ),
    );
  } on DirectCallEmailVerificationException {
    if (!context.mounted) return;
    final copy = AppLocalizations.of(context);
    showMessage(
      copy.text(
        'Verify your email before calling. Use the verification banner on Home.',
        'Zweryfikuj adres e-mail przed połączeniem. Użyj banera weryfikacji na stronie głównej.',
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    final copy = AppLocalizations.of(context);
    final described = describeError?.call(error, copy);
    showMessage(
      described ??
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
    if (context.mounted) onBusyChanged(false);
  }
}
