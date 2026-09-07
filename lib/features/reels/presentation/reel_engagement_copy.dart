import 'package:flutter/widgets.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';

/// Which engagement operation a message is explaining.
///
/// The recoverable refusals (signed out, unverified, rate limited,
/// unavailable, offline) read the same whichever operation hit them, because
/// the next step is the same. Only the residual "it failed" case names the
/// operation, so a viewer is never told "something went wrong" without
/// learning *what* went wrong.
enum ReelEngagementAction { like, comment, deleteComment, loadComments }

/// Turns a refused engagement call into copy a viewer can act on.
///
/// Anything that is not a [ReelEngagementException] — an identity-lease
/// [StateError], a malformed response — falls through to the same
/// per-operation message rather than leaking an exception string into the UI.
String reelEngagementMessage(
  BuildContext context,
  Object error, {
  required ReelEngagementAction action,
}) {
  final copy = AppLocalizations.of(context);
  final reason = error is ReelEngagementException
      ? error.reason
      : ReelEngagementFailure.unknown;
  return switch (reason) {
    ReelEngagementFailure.signedOut => copy.text(
      'Sign in again to like or comment.',
      'Zaloguj się ponownie, aby polubić lub skomentować.',
    ),
    ReelEngagementFailure.emailUnverified => reelVerificationNotice(context),
    ReelEngagementFailure.rateLimited => copy.text(
      'You are doing that too often. Try again shortly.',
      'Robisz to zbyt często. Spróbuj ponownie za chwilę.',
    ),
    // The backend answers one refusal for every reason a Reel may be
    // out of reach — a block, a suspension, moderation, expiry. Naming a
    // reason here would rebuild exactly the oracle it refuses to be.
    ReelEngagementFailure.unavailable => copy.text(
      'This Reel is unavailable right now.',
      'Ten Reel jest teraz niedostępny.',
    ),
    ReelEngagementFailure.offline => copy.text(
      'Check your connection and try again.',
      'Sprawdź połączenie z internetem i spróbuj ponownie.',
    ),
    ReelEngagementFailure.conflict ||
    ReelEngagementFailure.invalid ||
    ReelEngagementFailure.unknown => switch (action) {
      ReelEngagementAction.like => copy.text(
        'The like could not be saved. Try again.',
        'Nie udało się zapisać polubienia. Spróbuj ponownie.',
      ),
      ReelEngagementAction.comment => copy.text(
        'The comment could not be posted. Try again.',
        'Nie udało się opublikować komentarza. Spróbuj ponownie.',
      ),
      ReelEngagementAction.deleteComment => copy.text(
        'The comment could not be deleted. Try again.',
        'Nie udało się usunąć komentarza. Spróbuj ponownie.',
      ),
      ReelEngagementAction.loadComments => copy.text(
        'Comments could not be loaded.',
        'Nie udało się wczytać komentarzy.',
      ),
    },
  };
}

/// The one sentence an unverified account sees instead of a dead control.
///
/// `setReelLike` and `createReelComment` are gated on a verified email;
/// reading the thread and removing your own comment are not. Saying so up
/// front is the difference between a disabled button and an explanation.
String reelVerificationNotice(BuildContext context) =>
    AppLocalizations.of(context).text(
      'Verify your email to like or comment.',
      'Zweryfikuj adres e-mail, aby polubić lub komentować.',
    );
