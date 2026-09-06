import 'package:yovoice/core/localization/app_localizations.dart';

/// Localized copy for a failed friend-request mutation.
///
/// Every surface that sends, cancels or accepts a friend request reads its
/// failure through here — the Add friends screen and the Friends screen's
/// "People you may know" rail — so the two name the same failure with the
/// same words, and neither can leak a raw exception string into a snackbar.
///
/// The matches are substring checks on purpose: the message may arrive as a
/// `StateError` raised locally by FriendService or as a
/// `FirebaseFunctionsException` from the callable, and both spell these
/// causes the same way.
String friendRequestErrorMessage(AppLocalizations copy, Object error) {
  final message = error.toString();

  if (message.contains('cannot add yourself')) {
    return copy.text(
      'You cannot add yourself.',
      'Nie możesz dodać siebie do znajomych.',
    );
  }
  if (message.contains('already friends')) {
    return copy.text('You are already friends.', 'Jesteście już znajomymi.');
  }
  if (message.contains('already sent')) {
    return copy.text(
      'Friend request already sent.',
      'To zaproszenie zostało już wysłane.',
    );
  }
  if (message.contains('no longer exists')) {
    return copy.text(
      'This user no longer exists.',
      'To konto już nie istnieje.',
    );
  }
  if (message.contains('not signed in')) {
    return copy.text('You must be signed in.', 'Musisz się zalogować.');
  }
  if (message.contains('permission-denied')) {
    return copy.text(
      'You do not have permission to do that.',
      'Nie masz uprawnień do wykonania tej czynności.',
    );
  }
  if (message.contains('unavailable')) {
    return copy.text(
      'Service is temporarily unavailable. Check your connection.',
      'Usługa jest chwilowo niedostępna. Sprawdź połączenie.',
    );
  }

  return copy.text(
    'Something went wrong. Please try again.',
    'Coś poszło nie tak. Spróbuj ponownie.',
  );
}
