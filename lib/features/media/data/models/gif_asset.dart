import 'package:flutter/foundation.dart';

/// One GIF, as the composer knows it.
///
/// The client mirror of `GifAsset` in `functions/media/gif/normalize.js`. It is
/// deliberately small and inert: no bytes, no provider knowledge, no HTTP. A
/// GIF in YO Voice is a provider id, a human label and a URL that points at the
/// provider's own CDN — never something we host, because GIPHY's terms require
/// hotlinking and forbid rehosting.
///
/// ## Why the title is not decoration
///
/// [title] is stored with every sent GIF, and it is what makes the feature
/// degrade honestly rather than silently:
///
///  * a dead CDN URL renders a same-height placeholder carrying the title, so
///    the message keeps its meaning;
///  * an app install that predates GIF support ignores unknown Firestore
///    fields and falls back to a plain text bubble reading the title;
///  * a moderator reading a report sees it, because staff cannot read the
///    server's asset records.
///
/// So an empty title is never acceptable, and the server guarantees one.
@immutable
class GifAsset {
  const GifAsset({
    required this.provider,
    required this.id,
    required this.title,
    required this.rating,
    required this.previewUrl,
    required this.url,
    required this.width,
    required this.height,
  });

  /// `giphy`, or `fake` in the emulator and in tests. The client never
  /// branches on this for behaviour — it is carried so a report and a send can
  /// name the asset unambiguously across providers.
  final String provider;

  final String id;

  /// Sanitized server-side: bounded to 100 characters, stripped of control
  /// characters and bidi overrides, never empty.
  final String title;

  /// Always `g`. Carried rather than assumed so a client can assert it in a
  /// test and so the value shown to a person is the value the server used.
  final String rating;

  /// The grid thumbnail. May be the same as [url].
  final String previewUrl;

  /// The fixed-height rendition, on the provider's CDN.
  ///
  /// Fixed height is the whole reason a chat list does not reflow when the
  /// image lands: the bubble's height is known before a byte is fetched.
  final String url;

  final int width;
  final int height;

  /// Width for a given rendered height, from the intrinsic ratio.
  ///
  /// Computed rather than measured, because measuring means waiting for the
  /// image — which is exactly the reflow this design exists to avoid.
  double widthForHeight(double renderedHeight) {
    if (height <= 0) return renderedHeight;
    return renderedHeight * (width / height);
  }

  /// `<provider>:<id>` — the form a report names, matching `gifTargetId` in
  /// `functions/media/gif/gif_ref.js`.
  String get targetId => '$provider:$id';

  Map<String, String> toMessageReference() => {'provider': provider, 'id': id};

  /// Message media must match the server's canonical template byte for byte.
  /// Unknown or malformed records retain their text fallback without causing
  /// a request to an arbitrary remote host.
  static GifAsset? fromMessage(Object? value) {
    final asset = fromWire(value);
    if (asset == null ||
        !asset.hasPinnedUrl ||
        asset.rating != 'g' ||
        asset.width < 1 ||
        asset.width > 4096 ||
        asset.height < 1 ||
        asset.height > 4096) {
      return null;
    }
    return asset;
  }

  bool get hasPinnedUrl {
    if (!RegExp(
      r'^(?!\.{1,2}$)(?!__.*__$)[A-Za-z0-9._-]{1,128}$',
    ).hasMatch(id)) {
      return false;
    }
    final prefix = switch (provider) {
      'giphy' => 'https://media.giphy.com/media/',
      'fake' => 'https://fake.invalid/gif/',
      _ => null,
    };
    return prefix != null && url == '$prefix$id/200h.gif';
  }

  /// Parses one wire item, returning `null` for anything malformed.
  ///
  /// Null rather than a throw: one bad item in a page of twenty-four must cost
  /// that item, not the page.
  static GifAsset? fromWire(Object? value) {
    if (value is! Map) return null;
    final map = value.cast<Object?, Object?>();
    String? string(String key) {
      final raw = map[key];
      return raw is String && raw.isNotEmpty ? raw : null;
    }

    int integer(String key, int fallback) {
      final raw = map[key];
      if (raw is int) return raw;
      if (raw is num && raw.isFinite) return raw.round();
      return fallback;
    }

    final provider = string('provider');
    final id = string('id');
    final url = string('url');
    if (provider == null || id == null || url == null) return null;
    for (final key in ['width', 'height']) {
      final dimension = map[key];
      if (dimension is num && !dimension.isFinite) return null;
    }
    final height = integer('height', 200);
    return GifAsset(
      provider: provider,
      id: id,
      title: string('title') ?? 'GIF',
      rating: string('rating') ?? 'g',
      previewUrl: string('previewUrl') ?? url,
      url: url,
      width: integer('width', height),
      height: height,
    );
  }

  Map<String, Object?> toWire() => <String, Object?>{
    'provider': provider,
    'id': id,
    'title': title,
    'rating': rating,
    'previewUrl': previewUrl,
    'url': url,
    'width': width,
    'height': height,
  };

  @override
  bool operator ==(Object other) =>
      other is GifAsset && other.provider == provider && other.id == id;

  @override
  int get hashCode => Object.hash(provider, id);
}

/// Why the GIF surface is unavailable, when it is.
///
/// A closed set rather than a free-text reason, because each value maps to a
/// different sentence a person reads — and because "unavailable" with no
/// explanation is exactly the broken-looking state CLAUDE.md forbids.
enum GifUnavailableReason {
  /// No provider is configured on the server. This is production today.
  notConfigured,

  /// A provider is named but its API key is missing or empty at runtime.
  providerNotConfigured,

  /// `appConfig/gif.enabled = false` — the operator's kill switch.
  disabled,

  /// The provider refused us (a revoked key, or a 429); the server's circuit
  /// breaker is open.
  providerUnavailable,

  /// This composer has no GIF send path yet, so offering a picker here would
  /// be offering something that cannot work.
  surfaceUnsupported,

  /// The catalog could not be fetched at all — offline, or the call failed.
  unreachable;

  static GifUnavailableReason fromServer(String? reason) {
    return switch (reason) {
      'disabled' => GifUnavailableReason.disabled,
      'provider_not_configured' => GifUnavailableReason.providerNotConfigured,
      'provider_unavailable' => GifUnavailableReason.providerUnavailable,
      _ => GifUnavailableReason.notConfigured,
    };
  }
}

/// What `getGifCatalog` answers.
@immutable
class GifCatalog {
  const GifCatalog({
    required this.available,
    required this.reason,
    required this.provider,
    required this.attribution,
    required this.categories,
    required this.pageSize,
    required this.minimumQueryLength,
    required this.ratingLabel,
  });

  /// The unavailable catalog used before the server has answered, and whenever
  /// it cannot be reached. Availability is never assumed optimistically: a
  /// picker that renders as working and then fails is worse than one that says
  /// up front that it is not ready.
  const GifCatalog.unavailable(this.reason)
    : available = false,
      provider = 'none',
      attribution = null,
      categories = const <String>[],
      pageSize = 24,
      minimumQueryLength = 2,
      ratingLabel = 'g';

  final bool available;
  final GifUnavailableReason? reason;
  final String provider;

  /// Contractual for GIPHY. When [GifAttribution.required] is true the picker
  /// must show its text wherever results are shown; there is no code path that
  /// hides it.
  final GifAttribution? attribution;

  /// Suggested-search KEYS, not words: the server has no locale authority, so
  /// the client owns the EN/PL copy and the key doubles as the query.
  final List<String> categories;

  final int pageSize;
  final int minimumQueryLength;
  final String ratingLabel;

  static GifCatalog fromWire(Object? value) {
    if (value is! Map) {
      return const GifCatalog.unavailable(GifUnavailableReason.unreachable);
    }
    final map = value.cast<Object?, Object?>();
    final available = map['available'] == true;
    if (!available) {
      return GifCatalog.unavailable(
        GifUnavailableReason.fromServer(map['reason'] as String?),
      );
    }
    final rawCategories = map['categories'];
    return GifCatalog(
      available: true,
      reason: null,
      provider: map['provider'] as String? ?? 'none',
      attribution: GifAttribution.fromWire(map['attribution']),
      categories: rawCategories is List
          ? List<String>.unmodifiable(rawCategories.whereType<String>())
          : const <String>[],
      pageSize: map['pageSize'] is int ? map['pageSize'] as int : 24,
      minimumQueryLength: map['minimumQueryLength'] is int
          ? map['minimumQueryLength'] as int
          : 2,
      ratingLabel: map['ratingLabel'] as String? ?? 'g',
    );
  }
}

@immutable
class GifAttribution {
  const GifAttribution({required this.text, required this.required});

  final String text;
  final bool required;

  static GifAttribution? fromWire(Object? value) {
    if (value is! Map) return null;
    final map = value.cast<Object?, Object?>();
    final text = map['text'];
    if (text is! String || text.isEmpty) return null;
    return GifAttribution(text: text, required: map['required'] == true);
  }
}

/// One page of results.
@immutable
class GifSearchPage {
  const GifSearchPage({
    required this.items,
    required this.nextCursor,
    required this.degraded,
    required this.cacheHit,
    this.attribution,
  });

  static const empty = GifSearchPage(
    items: <GifAsset>[],
    nextCursor: null,
    degraded: false,
    cacheHit: false,
  );

  final List<GifAsset> items;
  final String? nextCursor;

  /// True when the server served a stale or fallback page because the hour's
  /// provider budget was spent or the provider failed. The picker says so
  /// ("Showing popular GIFs") rather than pretending these are search results.
  final bool degraded;

  final bool cacheHit;
  final GifAttribution? attribution;

  static GifSearchPage fromWire(Object? value) {
    if (value is! Map) return empty;
    final map = value.cast<Object?, Object?>();
    final raw = map['items'];
    final items = <GifAsset>[];
    if (raw is List) {
      for (final entry in raw) {
        final asset = GifAsset.fromWire(entry);
        if (asset != null) items.add(asset);
      }
    }
    return GifSearchPage(
      items: List<GifAsset>.unmodifiable(items),
      nextCursor: map['nextCursor'] as String?,
      degraded: map['degraded'] == true,
      cacheHit: map['cacheHit'] == true,
      attribution: GifAttribution.fromWire(map['attribution']),
    );
  }
}
