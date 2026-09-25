import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

import '../../data/models/server_session_hand.dart';
import '../../data/services/server_session_controller.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import 'server_waiting_dot.dart';

/// The raised hands of the joined generation, for its host and moderators.
///
/// Everything here is read from the session: the queue is the rules-admitted
/// query of raised hands (`canListServerSessionHands`), limited to people the
/// provider still reports in the generation, oldest first. Each row names the
/// person, says how long they have been waiting from the backend's own
/// instant, and offers the two answers: Approve (the reviewed promotion, after
/// which the person's device re-mints onto the stage by itself) and Decline
/// (`answerServerSessionHandV1`). Nothing is drawn for anybody who may not
/// answer, and no count is ever invented. A request this viewer does not
/// outrank (a moderator looking at an admin's hand) is listed with a line
/// saying somebody with a higher role will answer it, and does not light the
/// waiting dot.
///
/// [showEmpty] decides whether an empty queue says so (the sheet, which the
/// person opened on purpose) or draws nothing (inline in the studio).
class ServerStageRequests extends StatelessWidget {
  const ServerStageRequests({
    required this.session,
    this.showEmpty = false,
    super.key,
  });

  final ServerSessionController session;
  final bool showEmpty;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      if (!session.canAnswerHands) return const SizedBox.shrink();
      final hands = session.raisedHands;
      if (hands.isEmpty && !showEmpty) return const SizedBox.shrink();
      final answerable = session.answerableHandCount;
      final copy = AppLocalizations.of(context);
      final palette = context.appPalette;
      final error = session.handAnswerError;
      return Semantics(
        container: true,
        explicitChildNodes: true,
        child: Column(
          key: const ValueKey('server-stage-requests'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              liveRegion: true,
              child: Row(
                children: [
                  ServerWaitingDot.on(
                    waiting: answerable > 0,
                    semanticLabel: copy.serverHandWaitingLabel(answerable),
                    child: Icon(
                      Icons.back_hand_outlined,
                      size: 18,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppRhythm.tight),
                  Flexible(
                    child: Text(
                      hands.isEmpty
                          ? copy.serverHandQueueTitle
                          : copy.serverHandQueueCount(hands.length),
                      key: const ValueKey('server-stage-requests-title'),
                      style: AppTypography.eyebrow.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppRhythm.tight),
            if (hands.isEmpty)
              Text(
                copy.serverHandQueueEmpty,
                key: const ValueKey('server-stage-requests-empty'),
                style: AppTypography.bodyMedium.copyWith(
                  color: palette.textSecondary,
                ),
              )
            else
              for (var index = 0; index < hands.length; index++) ...[
                if (index > 0) const SizedBox(height: AppRhythm.tight),
                _RequestRow(
                  key: ValueKey('server-stage-request-${hands[index].userId}'),
                  hand: hands[index],
                  canAnswer: session.canAnswerHand(hands[index]),
                  busy: session.isAnsweringHand(hands[index].userId),
                  onApprove: () => session.approveHand(hands[index]),
                  onDecline: () => session.declineHand(hands[index]),
                ),
              ],
            if (error != null) ...[
              const SizedBox(height: AppRhythm.tight),
              Semantics(
                liveRegion: true,
                child: Text(
                  serverActionFailureCopy(
                    error,
                    copy,
                    fallback: copy.serverHandAnswerFailed,
                  ),
                  key: const ValueKey('server-stage-requests-error'),
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.dangerForeground,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Opens the queue as a sheet — the dock's way in from anywhere inside the
/// server, whichever channel is on screen.
Future<void> showServerStageRequestsSheet(
  BuildContext context,
  ServerSessionController session,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
  builder: (sheetContext) => AnimatedBuilder(
    animation: session,
    builder: (sheetContext, _) {
      // The sheet belongs to the generation it was opened for: leaving, a
      // failure or losing the standing closes it instead of leaving a queue
      // that can no longer be answered.
      if (!session.canAnswerHands) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final navigator = Navigator.of(sheetContext);
          if (sheetContext.mounted && navigator.canPop()) navigator.pop();
        });
      }
      return SingleChildScrollView(
        key: const ValueKey('server-stage-requests-sheet'),
        padding: const EdgeInsets.fromLTRB(
          AppRhythm.title,
          0,
          AppRhythm.title,
          AppRhythm.section,
        ),
        child: ServerStageRequests(session: session, showEmpty: true),
      );
    },
  ),
);

class _RequestRow extends StatefulWidget {
  const _RequestRow({
    required this.hand,
    required this.canAnswer,
    required this.busy,
    required this.onApprove,
    required this.onDecline,
    super.key,
  });

  final ServerSessionHand hand;

  /// False when the callables would refuse this viewer's answer: the row
  /// then says so instead of offering two buttons that always fail.
  final bool canAnswer;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  /// Below this width, or at a large text setting, the two answers move under
  /// the name instead of squeezing it to an ellipsis.
  static const double sideBySideWidth = 420;

  @override
  State<_RequestRow> createState() => _RequestRowState();
}

class _RequestRowState extends State<_RequestRow> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Minutes are all the row says, so it repaints twice a minute and only
    // while it is on screen.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final hand = widget.hand;
    final raisedAt = hand.raisedAt;
    final waited = raisedAt == null
        ? null
        : copy.serverHandWaited(
            DateTime.now().difference(raisedAt).isNegative
                ? Duration.zero
                : DateTime.now().difference(raisedAt),
          );
    final identity = Semantics(
      container: true,
      label: [hand.displayName, ?waited].join(', '),
      excludeSemantics: true,
      child: Row(
        children: [
          UserAvatar(
            radius: 18,
            userId: hand.userId,
            displayName: hand.displayName,
            backgroundColor: palette.surfaceRaised,
          ),
          const SizedBox(width: AppRhythm.item),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hand.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                if (waited != null)
                  Text(
                    waited,
                    key: ValueKey('server-stage-request-waited-${hand.userId}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    final approve = Semantics(
      button: true,
      label: copy.serverHandApproveLabel(hand.displayName),
      excludeSemantics: true,
      onTap: widget.busy ? null : widget.onApprove,
      child: FilledButton(
        key: ValueKey('server-stage-request-approve-${hand.userId}'),
        onPressed: widget.busy ? null : widget.onApprove,
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
        child: widget.busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : Text(copy.serverHandApprove),
      ),
    );
    final decline = Semantics(
      button: true,
      label: copy.serverHandDeclineLabel(hand.displayName),
      excludeSemantics: true,
      onTap: widget.busy ? null : widget.onDecline,
      child: OutlinedButton(
        key: ValueKey('server-stage-request-decline-${hand.userId}'),
        onPressed: widget.busy ? null : widget.onDecline,
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
        child: Text(copy.serverHandDecline),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(AppRhythm.item),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: AppRadius.md,
        border: Border.all(color: palette.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!widget.canAnswer) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                identity,
                const SizedBox(height: AppRhythm.tight),
                Text(
                  copy.serverHandHigherRoleAnswers,
                  key: ValueKey(
                    'server-stage-request-unanswerable-${hand.userId}',
                  ),
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            );
          }
          final stacked =
              constraints.maxWidth < _RequestRow.sideBySideWidth ||
              MediaQuery.textScalerOf(context).scale(16) > 22;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                identity,
                const SizedBox(height: AppRhythm.tight),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppRhythm.tight,
                  runSpacing: AppRhythm.tight,
                  children: [decline, approve],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: AppRhythm.tight),
              decline,
              const SizedBox(width: AppRhythm.tight),
              approve,
            ],
          );
        },
      ),
    );
  }
}
