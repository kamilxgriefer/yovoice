import 'package:yovoice/core/localization/app_localizations.dart';

import '../../data/models/server_session_hand.dart';
import '../../data/services/server_session_controller.dart';
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
