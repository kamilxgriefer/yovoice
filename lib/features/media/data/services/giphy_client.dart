import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:yovoice/features/media/data/models/gif_asset.dart';

/// The GIPHY search client, running in the app (ADR-214, option B).
///
/// GIPHY's API terms require Search and Trending to be requested from the
/// client and forbid proxying them, so this class talks to `api.giphy.com`
/// directly. The server stays the send-time authority: a chosen result crosses
/// to YO Voice only as `{provider: 'giphy', id}`, and `resolveGif` re-fetches
/// that id with the server's own key before any message can carry it.
///
/// ## The key
///
/// The key is a compile-time define, [apiKeyDefine]
/// (`--dart-define=YOVOICE_GIPHY_API_KEY=...`), and nothing else. It is never
/// logged, never stored, never sent to YO Voice, and never part of an error
/// message: [GiphyClientException] carries a status code only. With no define
/// [GiphyClient.fromEnvironment] returns null and the picker is exactly the
/// Originals-only picker that shipped before GIPHY.
///
/// ## What is pinned here, not trusted from a response
///
///  * `rating=g` is a constant on every request, and every result is
///    re-filtered to rating `g` after parsing.
///  * The message URL is DERIVED from the id with the same template as the
///    server (`gif_ref.js`), and results whose id falls outside the shared
///    grammar are dropped.
///  * Preview and analytics URLs must be `https` on a `giphy.com` host.
///  * Queries pass the same short denylist the server applies to titles, so a
///    blocked term never reaches GIPHY from this app either.
class GiphyClient {
  GiphyClient({
    required String apiKey,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 6),
  }) : _apiKey = apiKey.trim(),
       _http = httpClient ?? http.Client(),
       _timeout = timeout;

  /// The build define that carries the client key.
  static const apiKeyDefine = 'YOVOICE_GIPHY_API_KEY';

  static const String _definedKey = String.fromEnvironment(apiKeyDefine);

  /// True when this build was compiled with a GIPHY key.
  static bool get isConfiguredInBuild => _definedKey.trim().isNotEmpty;

  /// The client for this build, or null when no key was compiled in.
  static GiphyClient? fromEnvironment({http.Client? httpClient}) =>
      isConfiguredInBuild
      ? GiphyClient(apiKey: _definedKey, httpClient: httpClient)
      : null;

  static const String provider = 'giphy';
  static const String rating = 'g';
  static const int maxQueryLength = 50;
  static const int maxSearchOffset = 4999;
  static const int maxTrendingOffset = 499;

  final String _apiKey;
  final http.Client _http;
  final Duration _timeout;

  static final Uri _root = Uri.parse('https://api.giphy.com/v1/');

  Future<GiphyPage> trending({
    required int limit,
    int offset = 0,
    String? customerId,
  }) {
    return _page('gifs/trending', <String, String>{
      'limit': '${_clampLimit(limit)}',
      'offset': '${offset.clamp(0, maxTrendingOffset)}',
      'bundle': 'messaging_non_clips',
      'customer_id': ?customerId,
    }, maximumOffset: maxTrendingOffset);
  }

  Future<GiphyPage> search({
    required String query,
    required int limit,
    String? language,
    int offset = 0,
    String? customerId,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty || isDeniedGifQuery(trimmed)) {
      // Neutral and empty, never an error: naming the term that tripped the
      // filter would be a map of the filter.
      return Future<GiphyPage>.value(GiphyPage.empty);
    }
    final clipped = String.fromCharCodes(trimmed.runes.take(maxQueryLength));
    return _page('gifs/search', <String, String>{
      'q': clipped,
      'limit': '${_clampLimit(limit)}',
      'offset': '${offset.clamp(0, maxSearchOffset)}',
      'lang': ?_language(language),
      'bundle': 'messaging_non_clips',
      'customer_id': ?customerId,
    }, maximumOffset: maxSearchOffset);
  }

  /// A GIPHY random id for Action Register pingbacks (`/v1/randomid`).
  /// Returns null on any failure; pingbacks are then simply not sent.
  Future<String?> randomId() async {
    try {
      final payload = await _get('randomid', const <String, String>{});
      final data = payload['data'];
      final value = data is Map ? data['random_id'] : null;
      return value is String && _randomIdPattern.hasMatch(value) ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// Fires one Action Register pingback. Best-effort by design: a failed
  /// analytics beacon must never surface to the person using the picker.
  Future<void> ping(Uri url) async {
    if (!GiphyAnalytics.isAllowedUrl(url)) return;
    try {
      await _http.get(url).timeout(_timeout);
    } catch (_) {
      // Deliberately silent.
    }
  }

  void close() => _http.close();

  Future<GiphyPage> _page(
    String path,
    Map<String, String> params, {
    required int maximumOffset,
  }) async {
    final payload = await _get(path, params);
    final raw = payload['data'];
    final results = <GiphyResult>[];
    if (raw is List) {
      for (final entry in raw) {
        final result = GiphyResult.fromJson(entry);
        if (result != null) results.add(result);
      }
    }
    final pagination = payload['pagination'];
    int? integer(String key) {
      final value = pagination is Map ? pagination[key] : null;
      return value is int ? value : null;
    }

    final offset = integer('offset') ?? 0;
    final count = raw is List ? raw.length : 0;
    final total = integer('total_count');
    final consumed = offset + count;
    final hasMore =
        count > 0 &&
        consumed <= maximumOffset &&
        (total == null || consumed < total);
    return GiphyPage(
      results: List<GiphyResult>.unmodifiable(results),
      nextOffset: hasMore ? consumed : null,
    );
  }

  Future<Map<String, Object?>> _get(
    String path,
    Map<String, String> params,
  ) async {
    if (_apiKey.isEmpty) {
      throw const GiphyClientException(0);
    }
    final uri = _root
        .resolve(path)
        .replace(
          queryParameters: <String, String>{
            'api_key': _apiKey,
            // RATING IS SET HERE AND NOWHERE ELSE.
            'rating': rating,
            ...params,
          },
        );
    final http.Response response;
    try {
      response = await _http
          .get(uri, headers: const {'accept': 'application/json'})
          .timeout(_timeout);
    } catch (_) {
      throw const GiphyClientException(0);
    }
    if (response.statusCode != 200) {
      throw GiphyClientException(response.statusCode);
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, Object?>) return decoded;
    } catch (_) {
      // Fall through.
    }
    throw GiphyClientException(response.statusCode);
  }

  static int _clampLimit(int limit) => limit.clamp(1, 30);

  static String? _language(String? value) {
    final lowered = (value ?? '').trim().toLowerCase();
    return RegExp(r'^[a-z]{2}$').hasMatch(lowered) ? lowered : null;
  }

  static final RegExp _randomIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
}

/// A GIPHY request failed. Carries the HTTP status (0 for a network failure or
/// a missing key) and never the request URL, which contains the key.
@immutable
class GiphyClientException implements Exception {
  const GiphyClientException(this.status);

  final int status;

  bool get isRateLimited => status == 429;
  bool get isUnauthorized => status == 401 || status == 403;

  @override
  String toString() => 'GiphyClientException($status)';
}

@immutable
class GiphyPage {
  const GiphyPage({required this.results, required this.nextOffset});

  static const empty = GiphyPage(results: <GiphyResult>[], nextOffset: null);

  final List<GiphyResult> results;
  final int? nextOffset;
}

/// One GIPHY search result: the canonical asset plus its Action Register URLs.
@immutable
class GiphyResult {
  const GiphyResult({required this.asset, required this.analytics});

  final GifAsset asset;
  final GiphyAnalytics analytics;

  static final RegExp _idPattern = RegExp(
    r'^(?!\.{1,2}$)(?!__.*__$)[A-Za-z0-9._-]{1,128}$',
  );

  static GiphyResult? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = value.cast<Object?, Object?>();
    final id = map['id'];
    if (id is! String || !_idPattern.hasMatch(id)) return null;
    final rawRating = map['rating'];
    if (rawRating is! String || rawRating.trim().toLowerCase() != 'g') {
      return null;
    }
    final images = map['images'];
    Map<Object?, Object?>? rendition(String name) {
      if (images is! Map) return null;
      final entry = images[name];
      return entry is Map ? entry.cast<Object?, Object?>() : null;
    }

    int dimension(Map<Object?, Object?>? source, String key, int fallback) {
      final raw = source?[key];
      final parsed = raw is int
          ? raw
          : raw is String
          ? int.tryParse(raw)
          : null;
      if (parsed == null || parsed < 1 || parsed > 4096) return fallback;
      return parsed;
    }

    final fixed = rendition('fixed_height') ?? rendition('original');
    final height = dimension(fixed, 'height', 200);
    final width = dimension(fixed, 'width', height);
    final url = 'https://media.giphy.com/media/$id/200h.gif';
    String preview = url;
    for (final name in const [
      'fixed_height_small',
      'fixed_height_downsampled',
      'fixed_height',
    ]) {
      final candidate = rendition(name)?['url'];
      if (candidate is String && _isGiphyMediaUrl(candidate)) {
        preview = candidate;
        break;
      }
    }
    final asset = GifAsset(
      provider: GiphyClient.provider,
      id: id,
      title: sanitizeGiphyTitle(map['title']),
      rating: 'g',
      previewUrl: preview,
      url: url,
      width: width,
      height: height,
    );
    if (!asset.hasPinnedUrl) return null;
    return GiphyResult(
      asset: asset,
      analytics: GiphyAnalytics.fromJson(map['analytics']),
    );
  }

  static bool _isGiphyMediaUrl(String value) {
    return RegExp(
      r'^https://(?:media[0-9]*|i)\.giphy\.com/[A-Za-z0-9/._~%-]{1,300}$',
    ).hasMatch(value);
  }
}

/// GIPHY's Action Register URLs for one result.
@immutable
class GiphyAnalytics {
  const GiphyAnalytics({this.onLoad, this.onClick, this.onSent});

  static const none = GiphyAnalytics();

  final Uri? onLoad;
  final Uri? onClick;
  final Uri? onSent;

  static GiphyAnalytics fromJson(Object? value) {
    if (value is! Map) return none;
    Uri? read(String name) {
      final entry = value[name];
      final raw = entry is Map ? entry['url'] : null;
      if (raw is! String) return null;
      final uri = Uri.tryParse(raw);
      return uri != null && isAllowedUrl(uri) ? uri : null;
    }

    return GiphyAnalytics(
      onLoad: read('onload'),
      onClick: read('onclick'),
      onSent: read('onsent'),
    );
  }

  /// An analytics URL is a beacon we fire from the device, so it is held to a
  /// host allowlist: `https` on `giphy.com` or one of its subdomains, and
  /// nothing that could carry credentials.
  static bool isAllowedUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        !uri.hasPort &&
        (host == 'giphy.com' || host.endsWith('.giphy.com'));
  }
}

/// GIPHY titles routinely end in " GIF" or " GIF by `brand`". Mirrors
/// `sanitizeTitle` in functions/media/gif/normalize.js closely enough for the
/// picker's labels; the server re-derives the stored title at send time.
String sanitizeGiphyTitle(Object? value) {
  if (value is! String) return 'GIF';
  final stripped = value
      .replaceAll(
        RegExp(
          r'[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u2028\u2029'
          r'\u202A-\u202E\u2066-\u2069\uFEFF]',
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final trimmed = stripped
      .replaceFirst(RegExp(r'\s+GIF(\s+by\s+.+)?$', caseSensitive: false), '')
      .trim();
  final chosen = trimmed.isNotEmpty ? trimmed : stripped;
  if (chosen.isEmpty) return 'GIF';
  return chosen.length > 100 ? chosen.substring(0, 100).trim() : chosen;
}

/// The client mirror of functions/media/gif/denylist.js. Keep the two lists
/// identical; the server list is the reviewed source of truth.
const Set<String> _deniedTerms = <String>{
  'porn', 'porno', 'pornhub', 'xxx', 'nsfw', 'nude', 'nudes', 'naked', //
  'nago', 'nagie', 'sex', 'seks', 'sexy', 'seksowne', 'hentai', 'boobs', //
  'cycki', 'tits', 'penis', 'dick', 'cock', 'pussy', 'cipka', 'anal', //
  'blowjob', 'orgasm', 'orgazm', 'masturbation', 'masturbacja', 'escort', //
  'onlyfans', 'camgirl', 'fetish', 'fetysz', 'bdsm', 'rape', 'gwalt', //
  'incest', 'kazirodztwo', 'loli', 'shota', 'cp', 'underage', 'nieletnie', //
  'nieletni', 'gore', 'beheading', 'suicide', 'samobojstwo', 'selfharm', //
};

const List<String> _deniedPhrases = <String>[
  'child porn',
  'teen porn',
  'kill yourself',
  'how to die',
];

const Map<String, String> _foldedLetters = <String, String>{
  'ą': 'a', 'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
  'ć': 'c', 'ç': 'c', 'č': 'c', 'ę': 'e', 'è': 'e', 'é': 'e', 'ê': 'e', //
  'ë': 'e', 'ě': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ł': 'l', //
  'ń': 'n', 'ñ': 'n', 'ň': 'n', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', //
  'ö': 'o', 'ø': 'o', 'ś': 's', 'š': 's', 'ß': 'ss', 'ù': 'u', 'ú': 'u', //
  'û': 'u', 'ü': 'u', 'ů': 'u', 'ý': 'y', 'ÿ': 'y', 'ź': 'z', 'ż': 'z', //
  'ž': 'z', 'đ': 'd', 'ď': 'd', 'ř': 'r', 'ť': 't', 'æ': 'ae', 'œ': 'oe', //
};

String _foldQuery(String query) {
  final buffer = StringBuffer();
  for (final rune in query.toLowerCase().runes) {
    final letter = String.fromCharCode(rune);
    buffer.write(_foldedLetters[letter] ?? letter);
  }
  return buffer
      .toString()
      .replaceAll(RegExp('[^a-z0-9 ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// True when [query] must not reach GIPHY. Whole-token matching, so
/// "assassin" does not trip "ass" and "Scunthorpe" is fine.
bool isDeniedGifQuery(String query) {
  final folded = _foldQuery(query);
  if (folded.isEmpty) return false;
  for (final phrase in _deniedPhrases) {
    if (folded.contains(phrase)) return true;
  }
  return folded.split(' ').any(_deniedTerms.contains);
}
