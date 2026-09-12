import 'package:cloud_functions/cloud_functions.dart';
import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';

import 'server_localized_copy.dart';

/// Product copy for a failed shell action (invite, channel creation, join).
///
/// A missing export (`not-found` / `unimplemented`) means the V1 callables
/// are held, which is the honest "still being prepared" state — not "we
/// couldn't find that", which is what the generic helper would say. Every
/// invitee-state refusal is one `permission-denied` by design, so it gets
/// the invite-specific sentence when [invite] is set.
String serverActionFailureCopy(
  Object error,
  AppLocalizations copy, {
  bool invite = false,
  String? fallback,
}) {
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'not-found':
      case 'unimplemented':
        return copy.serverActionUnavailable;
      case 'permission-denied':
        return invite ? copy.serverInviteRefused : copy.serverActionDenied;
      case 'failed-precondition':
        return fallback ?? copy.serverActionDenied;
    }
  }
  return friendlyErrorMessage(error, copy: copy, fallback: fallback);
}
