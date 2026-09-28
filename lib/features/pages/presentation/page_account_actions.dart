import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/calls/data/models/direct_call.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/calls/presentation/direct_call_launcher.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/widgets/invite_person_to_server_sheet.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

/// What the Page profile can do with the ACCOUNT behind a Page (spec
/// premium-pages §4.3, R10): message, call, invite, remove a friend, block
/// and the personal-profile fallback. "Zgłoś stronę" is not here: it files
/// a Page report (`createPageReportV1 {targetType:'page'}`, §2.10) through
/// `PagesService`, so it reaches Page moderation with its snapshot. Every action goes through the
/// app's existing path for accounts (the same services the friend profile
/// uses), so a Page never carries a second, weaker copy of a safety action.
abstract interface class PageAccountActions {
  /// The viewer's relation to [uid]; null when unknown.
  Future<FriendRelationshipStatus?> relationship(String uid);

  Future<void> openChat(
    BuildContext context, {
    required String uid,
    required String name,
    bool recordVoice = false,
  });

  Future<void> call(
    BuildContext context, {
    required String uid,
    required String name,
  });

  Future<void> inviteToServer(
    BuildContext context, {
    required String uid,
    required String name,
  });

  /// Throws on failure.
  Future<void> removeFriend(String uid);

  /// Throws on failure.
  Future<void> block(String uid);

  /// The §4.3 fallback: the ordinary personal profile, which keeps call,
  /// remove-friend, Block and Report.
  Future<void> openPersonalProfile(
    BuildContext context, {
    required String uid,
    String? name,
  });
}

/// The production [PageAccountActions].
class AppPageAccountActions implements PageAccountActions {
  const AppPageAccountActions();

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  @override
  Future<FriendRelationshipStatus?> relationship(String uid) async {
    try {
      return await FriendService().getRelationshipStatus(uid);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> openChat(
    BuildContext context, {
    required String uid,
    required String name,
    bool recordVoice = false,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failure = PagesCopy(AppLocalizations.of(context)).chatFailed;
    try {
      final conversationId = await MessageService.live.openOrCreateConversation(
        otherUserId: uid,
        otherDisplayName: name,
        otherEmail: '',
        otherPhotoUrl: '',
      );
      if (!navigator.mounted) return;
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            otherUserId: uid,
            otherDisplayName: name,
            otherEmail: '',
            otherPhotoUrl: '',
            initialAction: recordVoice
                ? ChatLaunchAction.recordVoice
                : ChatLaunchAction.none,
          ),
        ),
      );
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  @override
  Future<void> call(
    BuildContext context, {
    required String uid,
    required String name,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final copy = AppLocalizations.of(context);
    void show(String message) =>
        messenger?.showSnackBar(SnackBar(content: Text(message)));
    await launchDirectCall(
      context,
      calls: DirectCallService(),
      voice: VoiceCallService.instance,
      calleeId: uid,
      resolveConversationId: () => MessageService.live.openOrCreateConversation(
        otherUserId: uid,
        otherDisplayName: name,
        otherEmail: '',
        otherPhotoUrl: '',
      ),
      currentUserId: _auth.currentUser?.uid ?? '',
      participantName: () =>
          _auth.currentUser?.displayName ??
          copy.text('YO Voice user', 'Użytkownik YO Voice'),
      showMessage: show,
      onBusyChanged: (_) {},
      onStartAudioInstead: () {},
      mediaType: DirectCallMediaType.audio,
    );
  }

  @override
  Future<void> inviteToServer(
    BuildContext context, {
    required String uid,
    required String name,
  }) => showInvitePersonToServerSheet(
    context,
    inviteeId: uid,
    inviteeName: name,
    repository: ServerService(),
  );

  @override
  Future<void> removeFriend(String uid) => FriendService().removeFriend(uid);

  @override
  Future<void> block(String uid) => FriendService().blockUser(uid);

  @override
  Future<void> openPersonalProfile(
    BuildContext context, {
    required String uid,
    String? name,
  }) => showProfilePreview(
    context,
    userId: uid,
    displayName: name,
    resolvePages: false,
  );
}
