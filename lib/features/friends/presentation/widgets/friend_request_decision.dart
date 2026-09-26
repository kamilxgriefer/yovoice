import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The one Accept / Decline pair every incoming-request surface uses.
///
/// Accepting a friend request is a consent decision (ADR "friend requests are
/// an explicit consent decision"), so both choices are always visible, always
/// carry a text label and are equally easy to reach. No surface may offer an
/// icon-only check, a lone Accept, or accept on a tap of its body.
///
/// [busyAccept] / [busyDecline] show progress on the pressed button and
/// disable both while either call is in flight. The pair stacks when the
/// available width or the text scale would squeeze the labels.
class FriendRequestDecisionButtons extends StatelessWidget {
  const FriendRequestDecisionButtons({
    required this.onAccept,
    required this.onDecline,
    this.busyAccept = false,
    this.busyDecline = false,
    this.acceptKey,
    this.declineKey,
    this.name,
    this.dense = false,
    super.key,
  });

  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final bool busyAccept;
  final bool busyDecline;
  final Key? acceptKey;
  final Key? declineKey;

  /// The requester's name, for the buttons' spoken labels only.
  final String? name;

  /// 44 px buttons instead of 48 px, for compact surfaces (the top banner).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final busy = busyAccept || busyDecline;
    final height = dense ? 44.0 : 48.0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final who = name?.trim();
    final named = who != null && who.isNotEmpty;
    Widget progress(Color color) => SizedBox(
      width: 15,
      height: 15,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );

    final accept = Semantics(
      button: true,
      // Always labelled and always replacing the button's own node, named or
      // not: a wrapper that declares a tap without excluding the child's
      // node would leave two tap targets for one button.
      label: named
          ? copy.template(
              'Accept friend request from {name}',
              'Akceptuj zaproszenie od {name}',
              values: <String, Object>{'name': who},
            )
          : copy.text('Accept friend request', 'Akceptuj zaproszenie'),
      // The spoken label replaces the button's own node, so this node must
      // carry the tap action and the enabled state itself (as the Yeel chip
      // does); otherwise a busy button is announced as active.
      enabled: !busy,
      onTap: busy ? null : onAccept,
      excludeSemantics: true,
      child: FilledButton.icon(
        key: acceptKey,
        onPressed: busy ? null : onAccept,
        style: FilledButton.styleFrom(
          minimumSize: Size.fromHeight(height),
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          shape: shape,
        ),
        icon: busyAccept
            ? progress(colors.onPrimary)
            : const Icon(Icons.check_rounded, size: 18),
        label: Text(
          copy.text('Accept', 'Akceptuj'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    final decline = Semantics(
      button: true,
      label: named
          ? copy.template(
              'Decline friend request from {name}',
              'Odrzuć zaproszenie od {name}',
              values: <String, Object>{'name': who},
            )
          : copy.text('Decline friend request', 'Odrzuć zaproszenie'),
      enabled: !busy,
      onTap: busy ? null : onDecline,
      excludeSemantics: true,
      child: OutlinedButton.icon(
        key: declineKey,
        onPressed: busy ? null : onDecline,
        style: OutlinedButton.styleFrom(
          minimumSize: Size.fromHeight(height),
          foregroundColor: palette.textPrimary,
          side: BorderSide(color: palette.borderStrong),
          shape: shape,
        ),
        icon: busyDecline
            ? progress(palette.textPrimary)
            : const Icon(Icons.close_rounded, size: 18),
        label: Text(
          copy.text('Decline', 'Odrzuć'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stack =
            // Below ~300 px "Akceptuj" and "Odrzuć" would ellipsize side by
            // side; stacked, both labels always read in full.
            constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.4;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              accept,
              const SizedBox(height: AppRhythm.tight),
              decline,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: accept),
            const SizedBox(width: AppRhythm.tight),
            Expanded(child: decline),
          ],
        );
      },
    );
  }
}

/// The feedback line for a finished Accept / Decline.
String friendRequestResponseMessage(
  AppLocalizations copy,
  FriendRequestResponseOutcome outcome, {
  String? name,
}) {
  final who = name?.trim();
  final named = who != null && who.isNotEmpty;
  return switch (outcome) {
    FriendRequestResponseOutcome.accepted =>
      named
          ? copy.template(
              'You and {name} are now friends.',
              'Ty i {name} jesteście teraz znajomymi.',
              values: <String, Object>{'name': who},
            )
          : copy.text(
              'Friend request accepted.',
              'Zaproszenie zostało przyjęte.',
            ),
    FriendRequestResponseOutcome.declined => copy.text(
      'Friend request declined.',
      'Zaproszenie zostało odrzucone.',
    ),
    FriendRequestResponseOutcome.alreadyFriends =>
      named
          ? copy.template(
              'You and {name} are already friends.',
              'Ty i {name} już jesteście znajomymi.',
              values: <String, Object>{'name': who},
            )
          : copy.text('You are already friends.', 'Jesteście już znajomymi.'),
    FriendRequestResponseOutcome.alreadyResolved => copy.text(
      'This request was already answered.',
      'To zaproszenie ma już odpowiedź.',
    ),
    FriendRequestResponseOutcome.noLongerAvailable => copy.text(
      'This request is no longer available.',
      'To zaproszenie nie jest już dostępne.',
    ),
    FriendRequestResponseOutcome.unavailable => copy.text(
      'This request is unavailable.',
      'To zaproszenie jest niedostępne.',
    ),
  };
}

/// The relationship to show after an explicit Accept / Decline.
///
/// A fresh answer is definitive. A stale one is not: the server answers
/// `alreadyResolved` to a Decline on a request that was already accepted on
/// another device (the friendship stays), and a request that is "no longer
/// available" may have been accepted, cancelled or sent again. Those re-read
/// the relationship instead of assuming "not friends", so no surface offers
/// "Add friend" to a friend or disables calls between friends. A failed
/// re-read falls back to [FriendRelationshipStatus.none], the answer the
/// user asked for.
///
/// [reread] is the surface's own relationship read (normally
/// `friendService.getRelationshipStatus(senderId)`); it only runs for the
/// stale outcomes.
Future<FriendRelationshipStatus> friendRelationshipAfterResponse(
  FriendRequestResponseOutcome outcome, {
  required Future<FriendRelationshipStatus> Function() reread,
}) async {
  switch (outcome) {
    case FriendRequestResponseOutcome.accepted:
    case FriendRequestResponseOutcome.alreadyFriends:
      return FriendRelationshipStatus.friends;
    case FriendRequestResponseOutcome.declined:
    case FriendRequestResponseOutcome.unavailable:
      return FriendRelationshipStatus.none;
    case FriendRequestResponseOutcome.alreadyResolved:
    case FriendRequestResponseOutcome.noLongerAvailable:
      try {
        return await reread();
      } catch (_) {
        return FriendRelationshipStatus.none;
      }
  }
}

/// The copy an "Add friend" tap shows when an older Functions deployment
/// turned the send into an acceptance. It is the truth — they are friends —
/// said as what happened, with the way back.
String friendRequestAcceptedWithoutPromptMessage(
  AppLocalizations copy, {
  required String name,
}) => copy.template(
  '{name} had already sent you a request, so you are now friends. '
      'You can remove them from their profile.',
  '{name} już wcześniej wysłał(a) Ci zaproszenie, więc jesteście teraz '
      'znajomymi. Możesz to cofnąć w profilu tej osoby.',
  values: <String, Object>{'name': name},
);

/// An honest line in place of the buttons once a request is no longer
/// pending, so nothing on screen offers a choice that would fail.
class FriendRequestResolvedNotice extends StatelessWidget {
  const FriendRequestResolvedNotice({
    required this.outcome,
    this.name,
    super.key,
  });

  final FriendRequestResponseOutcome outcome;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final (icon, ink) = switch (outcome) {
      FriendRequestResponseOutcome.accepted ||
      FriendRequestResponseOutcome.alreadyFriends => (
        Icons.people_alt_rounded,
        palette.successForeground,
      ),
      FriendRequestResponseOutcome.declined ||
      FriendRequestResponseOutcome.alreadyResolved => (
        Icons.do_not_disturb_on_outlined,
        palette.textSecondary,
      ),
      FriendRequestResponseOutcome.noLongerAvailable ||
      FriendRequestResponseOutcome.unavailable => (
        Icons.info_outline_rounded,
        palette.textSecondary,
      ),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: ExcludeSemantics(child: Icon(icon, size: 18, color: ink)),
          ),
          const SizedBox(width: AppRhythm.tight),
          Expanded(
            child: Text(
              friendRequestResponseMessage(copy, outcome, name: name),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A self-contained response block: who is asking, then Accept / Decline,
/// then the result in place of the buttons.
///
/// Used where a surface has no request list of its own to drive the call —
/// a full profile, the profile preview, and the prompt shown when "Add
/// friend" discovers the other person already asked. It owns the call so
/// every one of them handles busy, stale and failed states the same way.
class FriendRequestResponsePanel extends StatefulWidget {
  const FriendRequestResponsePanel({
    required this.senderId,
    required this.senderName,
    required this.friendService,
    this.onResolved,
    this.showIdentity = true,
    this.profileMediaService,
    this.keyPrefix = 'friend-request-panel',
    super.key,
  });

  final String senderId;
  final String senderName;
  final FriendService friendService;

  /// Called once with the server's answer, after the panel updated itself.
  final ValueChanged<FriendRequestResponseOutcome>? onResolved;

  /// Avatar + "{name} sent you a friend request". A full profile already
  /// shows the person above, so it passes false and keeps only the line.
  final bool showIdentity;
  final ProfileMediaService? profileMediaService;
  final String keyPrefix;

  @override
  State<FriendRequestResponsePanel> createState() =>
      _FriendRequestResponsePanelState();
}

class _FriendRequestResponsePanelState
    extends State<FriendRequestResponsePanel> {
  bool? _pendingAccept;
  FriendRequestResponseOutcome? _outcome;
  String? _error;

  Future<void> _respond({required bool accept}) async {
    if (_pendingAccept != null || _outcome != null) return;
    setState(() {
      _pendingAccept = accept;
      _error = null;
    });
    try {
      final outcome = await widget.friendService.respondToFriendRequest(
        widget.senderId,
        accept: accept,
      );
      if (!mounted) return;
      setState(() => _outcome = outcome);
      widget.onResolved?.call(outcome);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).text(
          'Could not answer this request. Try again.',
          'Nie udało się odpowiedzieć na zaproszenie. Spróbuj ponownie.',
        );
      });
    } finally {
      if (mounted) setState(() => _pendingAccept = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final name = widget.senderName.trim().isEmpty
        ? copy.text('YO Voice user', 'Użytkownik YO Voice')
        : widget.senderName.trim();
    final outcome = _outcome;
    final prompt = Text(
      copy.template(
        '{name} sent you a friend request',
        '{name} wysyła Ci zaproszenie do znajomych',
        values: <String, Object>{'name': name},
      ),
      style: TextStyle(
        color: palette.textPrimary,
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
    );

    return Container(
      key: ValueKey('${widget.keyPrefix}-${widget.senderId}'),
      padding: const EdgeInsets.all(AppRhythm.item),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showIdentity)
            Row(
              children: [
                ExcludeSemantics(
                  child: UserAvatar(
                    radius: 20,
                    userId: widget.senderId,
                    displayName: name,
                    mediaService: widget.profileMediaService,
                    backgroundColor: palette.surfaceSunken,
                  ),
                ),
                const SizedBox(width: AppRhythm.item),
                Expanded(child: prompt),
              ],
            )
          else
            prompt,
          const SizedBox(height: AppRhythm.item),
          if (outcome != null)
            FriendRequestResolvedNotice(outcome: outcome, name: name)
          else ...[
            // A button pair, not a bar: capped so a desktop-wide panel keeps
            // the same two targets a phone shows.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: FriendRequestDecisionButtons(
                  acceptKey: ValueKey('${widget.keyPrefix}-accept'),
                  declineKey: ValueKey('${widget.keyPrefix}-decline'),
                  name: name,
                  busyAccept: _pendingAccept == true,
                  busyDecline: _pendingAccept == false,
                  onAccept: () => unawaited(_respond(accept: true)),
                  onDecline: () => unawaited(_respond(accept: false)),
                ),
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: AppRhythm.tight),
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(
                    color: palette.dangerForeground,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The explicit prompt an "Add friend" tap opens when the other person had
/// already sent a request (`incomingPending`). Nothing was changed by the
/// tap; this sheet is where the user decides. Returns the answer, or null
/// when the sheet was closed without one.
///
/// The answer is returned however the sheet closes — "Done", a swipe down,
/// the barrier or Back — so a caller never keeps a stale "request received"
/// state for a request that was just answered.
Future<FriendRequestResponseOutcome?> showFriendRequestPrompt(
  BuildContext context, {
  required String senderId,
  required String senderName,
  required FriendService friendService,
  ProfileMediaService? profileMediaService,
}) async {
  final palette = context.appPalette;
  FriendRequestResponseOutcome? answered;
  final popped = await showModalBottomSheet<FriendRequestResponseOutcome>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: palette.surfaceRaised,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(
      context,
      maxWidth: 480,
    ),
    builder: (sheetContext) => _FriendRequestPromptSheet(
      senderId: senderId,
      senderName: senderName,
      friendService: friendService,
      profileMediaService: profileMediaService,
      onResolved: (outcome) => answered = outcome,
    ),
  );
  return popped ?? answered;
}

class _FriendRequestPromptSheet extends StatefulWidget {
  const _FriendRequestPromptSheet({
    required this.senderId,
    required this.senderName,
    required this.friendService,
    required this.onResolved,
    this.profileMediaService,
  });

  final String senderId;
  final String senderName;
  final FriendService friendService;
  final ProfileMediaService? profileMediaService;

  /// Records the answer for [showFriendRequestPrompt] the moment it arrives,
  /// independent of how the sheet is later closed.
  final ValueChanged<FriendRequestResponseOutcome> onResolved;

  @override
  State<_FriendRequestPromptSheet> createState() =>
      _FriendRequestPromptSheetState();
}

class _FriendRequestPromptSheetState extends State<_FriendRequestPromptSheet> {
  FriendRequestResponseOutcome? _outcome;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final name = widget.senderName.trim().isEmpty
        ? copy.text('YO Voice user', 'Użytkownik YO Voice')
        : widget.senderName.trim();
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppRhythm.title,
          0,
          AppRhythm.title,
          AppRhythm.title,
        ),
        child: Column(
          key: const ValueKey('friend-request-prompt'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              copy.template(
                '{name} already asked to be your friend',
                '{name} już zaprasza Cię do znajomych',
                values: <String, Object>{'name': name},
              ),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 17,
                height: 1.3,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppRhythm.hairline),
            Text(
              copy.text(
                'Nothing has changed yet. Choose whether to accept.',
                'Nic się jeszcze nie zmieniło. Zdecyduj, czy chcesz przyjąć.',
              ),
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: AppRhythm.item),
            FriendRequestResponsePanel(
              senderId: widget.senderId,
              senderName: name,
              friendService: widget.friendService,
              profileMediaService: widget.profileMediaService,
              keyPrefix: 'friend-request-prompt',
              onResolved: (outcome) {
                widget.onResolved(outcome);
                setState(() => _outcome = outcome);
              },
            ),
            const SizedBox(height: AppRhythm.tight),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const ValueKey('friend-request-prompt-close'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => Navigator.of(context).pop(_outcome),
                child: Text(
                  _outcome == null
                      ? copy.text('Not now', 'Nie teraz')
                      : copy.text('Done', 'Gotowe'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
