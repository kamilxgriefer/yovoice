import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/moment_links.dart';
import 'package:yovoice/features/profile/presentation/my_link_copy.dart';

typedef VoiceMomentShareInvoker =
    Future<ShareResult> Function(ShareParams params);

/// What sharing [moment] hands to the system share sheet: one sentence and
/// the Moment's public link on `app.yovoice.app` (ADR-238). Null for an
/// identifier the link contract cannot carry — nothing is shared then, so a
/// link that cannot open is never handed out.
String? voiceMomentShareText(AppLocalizations copy, VoiceMoment moment) {
  if (!isSafeMomentLinkId(moment.id)) return null;
  return MyLinkCopy(copy).momentShareText(
    authorName: moment.authorName,
    link: buildMomentLink(moment.id),
  );
}

/// The ONE way a Voice Moment is shared (the feed, the detail page and Home's
/// rail). The destination performs its own identity and availability checks;
/// no media URL, grant or author id is shared.
Future<void> shareVoiceMoment(
  AppLocalizations copy,
  VoiceMoment moment, {
  VoiceMomentShareInvoker? shareInvoker,
}) async {
  final text = voiceMomentShareText(copy, moment);
  if (text == null) return;
  await (shareInvoker ?? SharePlus.instance.share)(ShareParams(text: text));
}
