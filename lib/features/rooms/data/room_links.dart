/// The canonical room deep link and its parser.
///
/// One place decides what a room link looks like, for the same reason
/// `ClubService.createInviteLink` owns `?club=` and Moments own `?moment=`:
/// the app's only room deep-link handler (`MainShell._openInitialRoomLink`)
/// reads `Uri.base.queryParameters['room']`, so a link in any other shape
/// is a link the app cannot open. The Broadcast share sheet used to build
/// `https://yovoice.app/rooms/{id}` — a PATH nobody handled.
library;

/// The same guard `MainShell.isSafeInitialRoomLinkId` applies before a
/// deep-linked id is allowed anywhere near a Firestore document path.
final RegExp _roomIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Hosts that serve the YO Voice web app. `app.yovoice.app` is the
/// production app host in progress (Roadmap); `www.` is a common paste.
const Set<String> _roomLinkHosts = <String>{
  'yovoice.app',
  'www.yovoice.app',
  'app.yovoice.app',
};

/// A very loose URL sniffer for free text. Every candidate is re-validated
/// by [tryParseRoomLink], so this only has to be generous, never precise.
final RegExp _urlCandidate = RegExp(r'''https?://[^\s<>"']+''');

/// Characters a sentence commonly hangs off the end of a pasted link.
const String _trailingPunctuation = '.,;:!?)]}>\'"';

bool isSafeRoomLinkId(String value) => _roomIdPattern.hasMatch(value);

/// The canonical shareable link for [roomId].
///
/// Throws [ArgumentError] for an id the deep-link guard would refuse, so a
/// malformed id never becomes a link that silently does nothing.
String roomShareLink(String roomId) {
  if (!isSafeRoomLinkId(roomId)) {
    throw ArgumentError.value(roomId, 'roomId', 'Not a safe room id.');
  }
  return 'https://yovoice.app/?room=$roomId';
}

/// Returns the room id carried by [value] when it is a YO Voice room link,
/// or null for anything else — a foreign host, a non-https scheme, a
/// missing or malformed id, or plain text.
///
/// Accepts the canonical `https://yovoice.app/?room=<id>` form and, for
/// messages sent before the share sheet was fixed, the legacy
/// `https://yovoice.app/rooms/<id>` path. Both resolve to the same in-app
/// destination; only the canonical form is ever generated.
String? tryParseRoomLink(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > 2048) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme != 'https') return null;
  if (!_roomLinkHosts.contains(uri.host.toLowerCase())) return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  String? candidate;
  if (segments.isEmpty) {
    candidate = uri.queryParameters['room'];
  } else if (segments.length == 2 && segments.first == 'rooms') {
    candidate = segments[1];
  }
  if (candidate == null) return null;
  final id = candidate.trim();
  return isSafeRoomLinkId(id) ? id : null;
}

/// The first room id linked anywhere inside [text], or null when the text
/// carries no YO Voice room link. Used by the chat bubble to decide whether
/// a plain text message deserves a room card underneath it.
String? findRoomLinkId(String text) {
  if (!text.contains('yovoice.app')) return null;
  for (final match in _urlCandidate.allMatches(text)) {
    var candidate = match.group(0)!;
    while (candidate.isNotEmpty &&
        _trailingPunctuation.contains(candidate[candidate.length - 1])) {
      candidate = candidate.substring(0, candidate.length - 1);
    }
    final id = tryParseRoomLink(candidate);
    if (id != null) return id;
  }
  return null;
}
