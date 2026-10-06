/// Canonical public link to a person's profile ("Mój link", ADR-238):
/// `https://app.yovoice.app/?user=<uid>`.
///
/// The identifier is the account's public id — the document id of
/// `publicProfiles/{uid}`, the same one a Page link carries (`?page=`). It is
/// never an e-mail address, a phone number or a username, and the link holds
/// nothing else: no name, no photo, no token. Opening it grants nothing — the
/// profile is read through the same rules as from anywhere else in the app.
///
/// Links are emitted on `app.yovoice.app` (the web app), the same contract as
/// Server, Page and Yeel links: the apex is the marketing site and has no
/// `?user=` handling. Native link claiming (Associated Domains / Android
/// intent filters) is not configured, so on a phone the link opens the web
/// app.
library;

const userLinkHost = 'app.yovoice.app';

final RegExp _userLinkId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

bool isSafeUserLinkId(String value) => _userLinkId.hasMatch(value);

/// Builds the only profile link shape the application emits.
Uri buildUserLink(String userId) {
  if (!isSafeUserLinkId(userId)) {
    throw ArgumentError.value(userId, 'userId', 'Invalid account identifier.');
  }
  return Uri.https(userLinkHost, '/', <String, String>{'user': userId});
}

/// [buildUserLink], or null for an identifier the contract cannot carry.
Uri? tryBuildUserLink(String? userId) =>
    userId != null && isSafeUserLinkId(userId) ? buildUserLink(userId) : null;

/// The link as people read it: without the scheme
/// (`app.yovoice.app/?user=<uid>`).
String displayUserLink(Uri link) => '${link.host}${link.path}?${link.query}';

/// [displayUserLink] with one invisible break opportunity (U+200B) before
/// the identifier, so a slot too narrow for the whole link wraps it as
/// address / identifier instead of cutting the identifier mid-way. For
/// painting only: copy, share and the QR code use the link itself.
String displayUserLinkBreakable(Uri link) {
  final shown = displayUserLink(link);
  final split = shown.indexOf('=') + 1;
  return split <= 0
      ? shown
      : '${shown.substring(0, split)}\u200B${shown.substring(split)}';
}

/// Parses exactly the public profile link contract, modelled on
/// `parseReelLink`: another host, credentials, a port, a path, a fragment,
/// duplicate values, any other parameter and a malformed id all fail closed,
/// so a profile link can never smuggle in a Server, Page, Club or Room
/// destination.
String? parseUserLink(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host.toLowerCase() != userLinkHost ||
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
  final ids = parameters['user'];
  if (ids == null || ids.length != 1 || !isSafeUserLinkId(ids.single)) {
    return null;
  }
  return ids.single;
}

/// True when [uri] carries the profile link parameter, valid or not. The
/// shell uses it to fail closed: an altered profile link must not fall
/// through into another link contract.
bool carriesUserLinkParameters(Uri uri) {
  try {
    return uri.queryParametersAll.containsKey('user');
  } on FormatException {
    return false;
  }
}
