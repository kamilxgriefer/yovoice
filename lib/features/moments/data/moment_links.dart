/// Canonical public link to one Voice Moment (ADR-238):
/// `https://app.yovoice.app/?moment=<id>`.
///
/// Until build 42 every Voice share built `https://yovoice.app/?moment=<id>`.
/// The apex is the Next.js marketing site, which has no `?moment=` handling,
/// and the app had no handler either, so those links opened nothing. Links
/// are now emitted on `app.yovoice.app` — the same contract as Server, Page
/// and Yeel links — and the shell opens the Voice. The parser still accepts
/// the apex and `www.`, so a link shared by an older build opens as soon as
/// it reaches the app.
///
/// The link carries an opaque identifier only: never a media URL, a grant or
/// the author. Opening it grants nothing; the destination loads the Moment
/// through the same privacy-filtered callable as every other surface.
library;

const momentLinkHost = 'app.yovoice.app';

/// Every host a Voice Moment link may arrive on. Nothing else is accepted.
const Set<String> _momentLinkHosts = <String>{
  momentLinkHost,
  'yovoice.app',
  'www.yovoice.app',
};

final RegExp _momentLinkId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

bool isSafeMomentLinkId(String value) => _momentLinkId.hasMatch(value);

/// Builds the only Voice Moment link shape the application emits.
Uri buildMomentLink(String momentId) {
  if (!isSafeMomentLinkId(momentId)) {
    throw ArgumentError.value(
      momentId,
      'momentId',
      'Invalid Voice Moment identifier.',
    );
  }
  return Uri.https(momentLinkHost, '/', <String, String>{'moment': momentId});
}

/// Parses exactly the public Voice Moment link contract, modelled on
/// `parseReelLink`: another host, credentials, a port, a path, a fragment,
/// duplicate values, any other parameter and a malformed id all fail closed.
String? parseMomentLink(Uri uri) {
  if (uri.scheme != 'https' ||
      !_momentLinkHosts.contains(uri.host.toLowerCase()) ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.path != '/' ||
      uri.hasFragment ||
      uri.toString().length > 512) {
    return null;
  }
  Map<String, List<String>> parameters;
  try {
    parameters = uri.queryParametersAll;
  } on FormatException {
    return null;
  }
  if (parameters.length != 1) return null;
  final ids = parameters['moment'];
  if (ids == null || ids.length != 1 || !isSafeMomentLinkId(ids.single)) {
    return null;
  }
  return ids.single;
}

/// True when [uri] carries the Voice Moment link parameter, valid or not.
/// The shell uses it to fail closed: an altered Moment link must not fall
/// through into another link contract.
bool carriesMomentLinkParameters(Uri uri) {
  try {
    return uri.queryParametersAll.containsKey('moment');
  } on FormatException {
    return false;
  }
}
