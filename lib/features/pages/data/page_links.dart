/// Canonical public links to a Premium Page and to one of its posts:
/// `https://app.yovoice.app/?page=<uid>[&post=<id>]`.
///
/// Spec premium-pages §4.7 named the apex `yovoice.app`, but the apex is the
/// Next.js marketing site, which has no `?page=` handling: a shared link
/// would land on the homepage and never reach the app. Links are therefore
/// emitted on `app.yovoice.app`, the same contract as Server
/// (`server_links.dart`) and Yeel links. The parser still accepts the apex
/// and `www.` so any link built to the spec's shape keeps opening.
library;

const pageLinkHost = 'app.yovoice.app';

/// Every host a Page link may arrive on. Nothing else is accepted.
const Set<String> _pageLinkHosts = <String>{
  pageLinkHost,
  'yovoice.app',
  'www.yovoice.app',
};

/// A Page id is its owner's uid (`pages/{uid}`).
final RegExp _pageLinkId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Post ids are allocated by the server (spec §1.1).
final RegExp _pagePostLinkId = RegExp(r'^pp_[a-f0-9]{40}$');

bool isSafePageLinkId(String value) => _pageLinkId.hasMatch(value);
bool isSafePagePostLinkId(String value) => _pagePostLinkId.hasMatch(value);

class PageLinkTarget {
  const PageLinkTarget({
    required this.pageId,
    this.postId,
    this.fromLink = true,
  });

  final String pageId;
  final String? postId;

  /// True for a `?page=` link (an unavailable Page shows E7); false when the
  /// app itself opens an account's Page (the resolver falls back to the
  /// personal profile instead).
  final bool fromLink;

  @override
  bool operator ==(Object other) =>
      other is PageLinkTarget &&
      other.pageId == pageId &&
      other.postId == postId &&
      other.fromLink == fromLink;

  @override
  int get hashCode => Object.hash(pageId, postId, fromLink);

  @override
  String toString() => 'PageLinkTarget($pageId, $postId)';
}

/// Builds the only Page link shape the application emits.
Uri buildPageLink(String pageId, {String? postId}) {
  if (!isSafePageLinkId(pageId)) {
    throw ArgumentError.value(pageId, 'pageId', 'Invalid Page identifier.');
  }
  if (postId != null && !isSafePagePostLinkId(postId)) {
    throw ArgumentError.value(postId, 'postId', 'Invalid Page post id.');
  }
  return Uri.https(pageLinkHost, '/', <String, String>{
    'page': pageId,
    'post': ?postId,
  });
}

/// Parses exactly the public Page link contract, modelled on
/// `parseServerLink`: credentials, ports, fragments, a path, duplicate
/// values, unknown parameters and malformed ids all fail closed, so a Page
/// link can never smuggle in a Server, Club or Room destination.
PageLinkTarget? parsePageLink(Uri uri) {
  if (uri.scheme != 'https' ||
      !_pageLinkHosts.contains(uri.host.toLowerCase()) ||
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
  if (parameters.isEmpty || parameters.length > 2) return null;
  if (parameters.keys.any((key) => key != 'page' && key != 'post')) {
    return null;
  }

  final pageIds = parameters['page'];
  if (pageIds == null ||
      pageIds.length != 1 ||
      !isSafePageLinkId(pageIds.single)) {
    return null;
  }
  final postIds = parameters['post'];
  if (postIds != null &&
      (postIds.length != 1 || !isSafePagePostLinkId(postIds.single))) {
    return null;
  }
  return PageLinkTarget(pageId: pageIds.single, postId: postIds?.single);
}

/// True when [uri] carries any Page link parameter, valid or not. The shell
/// uses it to fail closed: an altered Page link must not fall through into
/// another link contract.
bool carriesPageLinkParameters(Uri uri) {
  try {
    final keys = uri.queryParametersAll.keys;
    return keys.contains('page') || keys.contains('post');
  } on FormatException {
    return false;
  }
}
