/// Public links carry an opaque identifier, never a media URL or authority.
///
/// The marketing domain does not serve the Flutter application. This HTTPS
/// link opens its web destination; native association is a separate release
/// requirement and is deliberately not implied by this builder.
const reelLinkHost = 'app.yovoice.app';

final _reelLinkId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

bool isSafeReelLinkId(String value) => _reelLinkId.hasMatch(value);

Uri buildReelLink(String reelId) {
  if (!isSafeReelLinkId(reelId)) {
    throw ArgumentError.value(reelId, 'reelId', 'Invalid Reel identifier.');
  }
  return Uri.https(reelLinkHost, '/', <String, String>{'reel': reelId});
}

/// Accepts exactly the public contract, not a return URL or a generic router.
/// Extra parameters, fragments, credentials and duplicate ids fail closed.
String? parseReelLink(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host != reelLinkHost ||
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
  final ids = parameters['reel'];
  if (ids == null || ids.length != 1 || !isSafeReelLinkId(ids.single)) {
    return null;
  }
  return ids.single;
}
