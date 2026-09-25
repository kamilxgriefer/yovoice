import 'package:cloud_functions/cloud_functions.dart';
import 'package:yovoice/core/localization/app_localizations.dart';

import '../../data/models/server_session_hand.dart';
import '../../data/services/server_session_controller.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';

/// Where this person's own request to speak stands in the generation they are
/// in, for the listener's side of a stage.
///
/// The lasting truth is their own participant document
/// ([ServerSessionController.ownParticipant]): raised, or lowered with the
/// answer it received. The callable receipt of their own press is used only
/// until a document snapshot newer than that press arrives, so the control
/// answers the press at once and then follows the backend — including an
/// answer given on another device, a decline, or a hand the backend lowered
/// when they were disconnected. A repository without the own-document read
/// keeps the receipt alone, which is what the stage always did.
({bool up, ServerHandDecision? decision}) serverOwnHand({
  required ServerSessionController session,
  required String? sessionId,
  required bool receiptRaised,
  required String? receiptSessionId,
  required int? receiptVersion,
}) {
  if (sessionId == null) return (up: false, decision: null);
  final receiptUp = receiptRaised && receiptSessionId == sessionId;
  final own = session.ownParticipant;
  if (own == null || own.sessionId != sessionId) {
    return (up: receiptUp, decision: null);
  }
  final documentIsNewer =
      receiptVersion == null || session.ownParticipantVersion > receiptVersion;
  if (!documentIsNewer) return (up: receiptUp, decision: null);
  return (
    up: own.isHandRaised,
    decision: own.isHandRaised ? null : own.handDecision,
  );
}

/// The one line under a listener's hand control, or null when there is
/// nothing true to say. Never claims a host has seen the request.
String? serverOwnHandMessage(
  AppLocalizations copy, {
  required bool up,
  required ServerHandDecision? decision,
}) {
  if (up) return copy.serverHandRaised;
  return switch (decision) {
    ServerHandDecision.declined => copy.serverHandDeclined,
    ServerHandDecision.lowered => copy.serverHandLowered,
    ServerHandDecision.approved || null => null,
  };
}

/// The `details.reason` `setServerSessionHandV1` attaches when it refuses a
/// raise straight after a decline (`functions/servers/session_participation.js`
/// HAND_COOLDOWN_REASON).
const serverHandCooldownReason = 'hand-decline-cooldown';

/// The one sentence for a hand press that did not go through: "wait a minute"
/// for the decline cooldown, otherwise the shared action-failure copy.
String serverHandFailureCopy(Object error, AppLocalizations copy) {
  if (error is FirebaseFunctionsException &&
      error.code == 'failed-precondition') {
    final details = error.details;
    if (details is Map && details['reason'] == serverHandCooldownReason) {
      return copy.serverHandCooldown;
    }
  }
  return serverActionFailureCopy(error, copy, fallback: copy.serverHandFailed);
}
