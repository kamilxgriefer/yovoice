/// One public HTTPS destination extracted from free-form Vibe text.
class ProfileVibeLink {
  const ProfileVibeLink({
    required this.uri,
    required this.start,
    required this.end,
    required this.provider,
  });

  final Uri uri;
  final int start;
  final int end;
  final String? provider;

  String get hostLabel {
    final host = uri.host.toLowerCase();
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  String get actionLabel => provider == null ? 'External link' : provider!;

  String get semanticLabel => provider == null
      ? 'Open external link, $hostLabel'
      : 'Open in $provider, $hostLabel';

  static final RegExp _candidates = RegExp(
    r'''https://[^\s<>"\u0000-\u001F]+''',
    caseSensitive: false,
  );

  /// Extracts every safe link in source order.
  ///
  /// The parser accepts only public absolute HTTPS URLs. Vibe is user input,
  /// so credentials, local/private-style hosts, IP literals and custom ports
  /// are refused before anything is handed to the platform launcher.
  static List<ProfileVibeLink> fromText(String text) {
    final links = <ProfileVibeLink>[];
    for (final match in _candidates.allMatches(text)) {
      final raw = match.group(0) ?? '';
      final candidate = _stripTrailingSentencePunctuation(raw);
      if (candidate.isEmpty) continue;

      final uri = Uri.tryParse(candidate);
      if (uri == null || !_isSafePublicHttpsUri(uri, candidate)) continue;

      links.add(
        ProfileVibeLink(
          uri: uri,
          start: match.start,
          end: match.start + candidate.length,
          provider: _providerForHost(uri.host.toLowerCase()),
        ),
      );
    }
    return List.unmodifiable(links);
  }

  static bool _isSafePublicHttpsUri(Uri uri, String source) {
    if (uri.scheme.toLowerCase() != 'https') return false;
    if (uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasPort) {
      return false;
    }

    final authorityStart = source.indexOf('://') + 3;
    final authorityEnd = _firstIndexOfAny(source, const [
      '/',
      '?',
      '#',
    ], start: authorityStart);
    final authority = source.substring(authorityStart, authorityEnd);
    if (!RegExp(r'^[\x21-\x7E]+$').hasMatch(authority)) return false;

    var host = uri.host.toLowerCase();
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    if (host.isEmpty || !host.contains('.')) return false;
    if (host.contains(':') || _looksLikeIpv4(host)) return false;
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal')) {
      return false;
    }

    final labels = host.split('.');
    final safeLabel = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
    return labels.every(safeLabel.hasMatch);
  }

  static int _firstIndexOfAny(
    String value,
    List<String> characters, {
    required int start,
  }) {
    var result = value.length;
    for (final character in characters) {
      final index = value.indexOf(character, start);
      if (index >= 0 && index < result) result = index;
    }
    return result;
  }

  static bool _looksLikeIpv4(String host) {
    final labels = host.split('.');
    if (labels.length < 2 || labels.any((label) => label.isEmpty)) {
      return false;
    }
    return labels.every((label) => int.tryParse(label) != null);
  }

  static String _stripTrailingSentencePunctuation(String token) {
    var result = token;
    const punctuation = ".,!?;:'\u2019\u201D\u00BB\u2026";
    while (result.isNotEmpty &&
        punctuation.contains(result[result.length - 1])) {
      result = result.substring(0, result.length - 1);
    }

    const pairs = <String, String>{')': '(', ']': '[', '}': '{'};
    var removed = true;
    while (result.isNotEmpty && removed) {
      removed = false;
      final closing = result[result.length - 1];
      final opening = pairs[closing];
      if (opening == null) continue;
      if (closing.allMatches(result).length >
          opening.allMatches(result).length) {
        result = result.substring(0, result.length - 1);
        removed = true;
      }
    }
    return result;
  }

  static String? _providerForHost(String host) {
    final normalized = host.startsWith('www.') ? host.substring(4) : host;
    if (_isDomain(normalized, 'youtu.be') ||
        _isDomain(normalized, 'youtube.com') ||
        _isDomain(normalized, 'youtube-nocookie.com')) {
      return 'YouTube';
    }
    if (_isDomain(normalized, 'spotify.com') ||
        _isDomain(normalized, 'spotify.link')) {
      return 'Spotify';
    }
    if (_isDomain(normalized, 'music.apple.com') ||
        _isDomain(normalized, 'itunes.apple.com')) {
      return 'Apple Music';
    }
    if (_isDomain(normalized, 'soundcloud.com')) return 'SoundCloud';
    if (_isDomain(normalized, 'tidal.com')) return 'TIDAL';
    if (_isDomain(normalized, 'deezer.com')) return 'Deezer';
    if (_isDomain(normalized, 'bandcamp.com')) return 'Bandcamp';
    if (_amazonMusicHosts.contains(normalized)) return 'Amazon Music';
    if (_isDomain(normalized, 'audiomack.com')) return 'Audiomack';
    if (_isDomain(normalized, 'pandora.com')) return 'Pandora';
    if (_isDomain(normalized, 'mixcloud.com')) return 'Mixcloud';
    if (_isDomain(normalized, 'qobuz.com')) return 'Qobuz';
    if (_isDomain(normalized, 'napster.com')) return 'Napster';
    return null;
  }

  static bool _isDomain(String host, String domain) =>
      host == domain || host.endsWith('.$domain');

  static const _amazonMusicHosts = <String>{
    'music.amazon.com',
    'music.amazon.ca',
    'music.amazon.com.au',
    'music.amazon.com.br',
    'music.amazon.com.mx',
    'music.amazon.co.jp',
    'music.amazon.co.uk',
    'music.amazon.de',
    'music.amazon.es',
    'music.amazon.fr',
    'music.amazon.in',
    'music.amazon.it',
  };
}

String profileVibeDescription(String text, List<ProfileVibeLink> links) {
  if (links.isEmpty) return text.trim();
  final buffer = StringBuffer();
  var cursor = 0;
  for (final link in links) {
    buffer.write(text.substring(cursor, link.start));
    cursor = link.end;
  }
  buffer.write(text.substring(cursor));
  return buffer
      .toString()
      .replaceAll(RegExp(r'\(\s*\)|\[\s*\]|\{\s*\}'), '')
      .replaceAll("''", '')
      .replaceAll('""', '')
      .replaceAll(RegExp(r'‘\s*’|“\s*”'), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAllMapped(
        RegExp(r'\s+([.,!?;:\u2026])'),
        (match) => match.group(1)!,
      )
      .trim();
}
