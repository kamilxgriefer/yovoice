import 'package:flutter/widgets.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';

/// Which engagement operation a message is explaining.
///
/// The recoverable refusals (signed out, unverified, unavailable, offline)
/// read the same whichever operation hit them, because the next step is the
/// same. The rate limit and the residual "it failed" case name the operation,
/// so a viewer is never told "something went wrong" without learning *what*
/// went wrong — and so somebody who has just been harassed is never answered
/// with copy written for somebody tapping Like too fast.
enum ReelEngagementAction {
  like,
  comment,
  deleteComment,
  loadComments,

  /// Filing a safety report against somebody else's comment.
  reportComment,

  /// A Reel's author clearing somebody else's comment off their own thread.
  removeComment,
}

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
    ReelEngagementFailure.signedOut => switch (action) {
      ReelEngagementAction.reportComment => copy.text(
        'Sign in again to report this comment.',
        'Zaloguj się ponownie, aby zgłosić ten komentarz.',
      ),
      ReelEngagementAction.removeComment => copy.text(
        'Sign in again to remove this comment.',
        'Zaloguj się ponownie, aby usunąć ten komentarz.',
      ),
      _ => copy.text(
        'Sign in again to like or comment.',
        'Zaloguj się ponownie, aby polubić lub skomentować.',
      ),
    },
    ReelEngagementFailure.emailUnverified => reelVerificationNotice(context),
    // `createReelCommentReport` has exactly one source for this code, and
    // the client already hides Report on your own comment — so reaching it
    // means the two disagreed, and the server is the one that is right.
    ReelEngagementFailure.ownComment => copy.text(
      'You cannot report your own comment.',
      'Nie możesz zgłosić własnego komentarza.',
    ),
    // The report budget is 10 per 10 minutes and it is charged BEFORE the
    // target is read, so a reporter can meet it honestly. Answering them
    // with "you are doing that too often" would read as an accusation on
    // the one path where that is least acceptable.
    ReelEngagementFailure.rateLimited => switch (action) {
      ReelEngagementAction.reportComment => copy.text(
        'You have sent several reports recently. '
            'Try this one again in a few minutes.',
        'Wysłano ostatnio kilka zgłoszeń. '
            'Spróbuj ponownie za kilka minut.',
      ),
      ReelEngagementAction.removeComment => copy.text(
        'You have removed several comments recently. '
            'Try again in a few minutes.',
        'Usunięto ostatnio kilka komentarzy. '
            'Spróbuj ponownie za kilka minut.',
      ),
      _ => copy.text(
        'You are doing that too often. Try again shortly.',
        'Robisz to zbyt często. Spróbuj ponownie za chwilę.',
      ),
    },
    // The backend answers one refusal for every reason a Reel may be
    // out of reach — a block, a suspension, moderation, expiry. Naming a
    // reason here would rebuild exactly the oracle it refuses to be. On the
    // two comment-moderation paths the same envelope also covers a comment
    // that is simply gone, which is why it names the comment, not the Reel.
    ReelEngagementFailure.unavailable => switch (action) {
      ReelEngagementAction.reportComment ||
      ReelEngagementAction.removeComment => copy.text(
        'That comment is no longer available.',
        'Ten komentarz jest już niedostępny.',
      ),
      _ => copy.text(
        'This Reel is unavailable right now.',
        'Ten Reel jest teraz niedostępny.',
      ),
    },
    ReelEngagementFailure.offline => copy.text(
      'Check your connection and try again.',
      'Sprawdź połączenie z internetem i spróbuj ponownie.',
    ),
    // A conflict on the report path means this request id was already spent
    // against this same comment under a different reason or note — so the
    // reporter has provably already reported it, and saying so is a fact
    // rather than a guess. The earlier report is the one that stands.
    ReelEngagementFailure.conflict
        when action == ReelEngagementAction.reportComment =>
      copy.text(
        'You have already reported this comment. It is with our team.',
        'Ten komentarz został już przez Ciebie zgłoszony. '
            'Zajmuje się nim nasz zespół.',
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
      ReelEngagementAction.reportComment => copy.text(
        'The report could not be sent. Try again.',
        'Nie udało się wysłać zgłoszenia. Spróbuj ponownie.',
      ),
      ReelEngagementAction.removeComment => copy.text(
        'The comment could not be removed. Try again.',
        'Nie udało się usunąć komentarza. Spróbuj ponownie.',
      ),
    },
  };
}

/// The one sentence an unverified account sees instead of a dead control.
///
/// `setReelLike` and `createReelComment` are gated on a verified email;
/// reading the thread, removing your own comment, reporting somebody else's
/// and clearing your own thread are not. Saying so up front is the difference
/// between a disabled button and an explanation.
String reelVerificationNotice(BuildContext context) =>
    AppLocalizations.of(context).text(
      'Verify your email to like or comment.',
      'Zweryfikuj adres e-mail, aby polubić lub komentować.',
    );
