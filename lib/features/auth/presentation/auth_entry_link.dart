import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/moments/data/moment_links.dart';
import 'package:yovoice/features/profile/data/user_links.dart';
import 'package:yovoice/features/profile/presentation/my_link_copy.dart';

/// What the browser entry URL points at, for a visitor who is not signed in
/// (ADR-238). A profile link or a Voice Moment link opens only after sign-in,
/// so the supporting line of the sign-in form — and of the create-account
/// form, which is the one a newly invited person uses — says what it opens
/// instead of the generic copy. The headlines and the forms are unchanged.
///
/// The line never names the person or the Moment: a signed-out visitor
/// cannot read either (public profiles and Moments are readable by signed-in
/// accounts only), and nothing in the link is trusted as display copy.
enum AuthEntryLink { profile, voiceMoment }

/// The kind of [uri], or null when it is not exactly a profile or a Voice
/// Moment link. Uses the same fail-closed parsers as the shell.
AuthEntryLink? authEntryLinkOf(Uri uri) {
  if (parseUserLink(uri) != null) return AuthEntryLink.profile;
  if (parseMomentLink(uri) != null) return AuthEntryLink.voiceMoment;
  return null;
}

/// The sign-in form's supporting line for [link].
String authEntryLinkLine(AppLocalizations copy, AuthEntryLink link) {
  final myLink = MyLinkCopy(copy);
  return switch (link) {
    AuthEntryLink.profile => myLink.signInForProfile,
    AuthEntryLink.voiceMoment => myLink.signInForMoment,
  };
}

/// The create-account form's supporting line for [link]. Someone who follows
/// an invitation usually has no account yet; the link opens after
/// registration exactly as it does after sign-in, so this form says so too.
String authEntryLinkRegisterLine(AppLocalizations copy, AuthEntryLink link) {
  final myLink = MyLinkCopy(copy);
  return switch (link) {
    AuthEntryLink.profile => myLink.createAccountForProfile,
    AuthEntryLink.voiceMoment => myLink.createAccountForMoment,
  };
}
