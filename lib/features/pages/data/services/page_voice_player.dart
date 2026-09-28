import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:yovoice/core/security/ephemeral_media_access_registry.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_voice_playback_source.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';

/// Where a voice post is in its playback.
enum PageVoicePhase { idle, loading, playing, paused, failed }

/// Downloads one granted clip. Throws [PageVoiceDownloadException] with the
/// HTTP status on a refusal, so a 403 (an expired 90 s URL) can be retried.
typedef PageVoiceDownloader = Future<Uint8List> Function(Uri url);

class PageVoiceDownloadException implements Exception {
  const PageVoiceDownloadException(this.statusCode);

  final int? statusCode;

  bool get expired => statusCode == 403 || statusCode == 401;

  @override
  String toString() => 'PageVoiceDownloadException($statusCode)';
}

/// The slice of an audio player the voice posts use, so the flow is
/// testable without a platform channel.
abstract interface class PageVoiceAudio {
  Stream<Duration> get positions;
  Stream<void> get completions;
  Future<void> play(Source source);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> dispose();
}

class _AudioPlayersVoiceAudio implements PageVoiceAudio {
  _AudioPlayersVoiceAudio() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<Duration> get positions => _player.onPositionChanged;

  @override
  Stream<void> get completions => _player.onPlayerComplete;

  @override
  Future<void> play(Source source) => _player.play(source);

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Voice posts on Treści (spec premium-pages §4.5, D8, ADR-184).
///
/// * **Full download first.** The clip (≤ 4 MB, ≤ 60 s) is fetched whole
///   through its 90 s grant into memory (a temporary file on Apple
///   platforms, where `audioplayers` has no byte source) before playback
///   starts; the signed URL is never streamed, so its expiry cannot cut a
///   clip mid-play. A 403 drops the grant, asks for one new grant and
///   retries once.
/// * **One clip at a time.** One player serves every card, the profile and
///   the post detail; [activePostId] is the one id that may sound (the
///   ADR-184 rule: arbitrate by a value). Starting another clip stops it.
class PageVoicePlayer extends ChangeNotifier {
  PageVoicePlayer({
    PagesService? service,
    PageVoiceDownloader? downloader,
    PageVoiceAudio Function()? audioFactory,
    Future<PreparedDirectVoiceSource> Function(Uint8List bytes, String id)?
    prepareSource,
  }) : _service = service ?? PagesService.instance,
       _download = downloader ?? downloadPageVoiceClip,
       _audioFactory = audioFactory ?? _AudioPlayersVoiceAudio.new,
       _prepare = prepareSource ?? prepareDirectVoiceSource;

  /// The app-wide player. Its downloaded clips are private media, so
  /// sign-out stops playback and drops them with every other media cache.
  static final PageVoicePlayer instance = () {
    final player = PageVoicePlayer();
    _shared = player;
    EphemeralMediaAccessRegistry.register('pagesVoice', () {
      player.clearCache();
      unawaited(player.stop());
    });
    return player;
  }();

  static PageVoicePlayer? _shared;

  /// Silences the app-wide clip when [owns] claims it: a Page profile or a
  /// post detail that is closing (opened from a chat, a notification or a
  /// room, outside Treści's own visibility hook) never leaves its clip
  /// sounding after Back. Never creates the player when nothing has played.
  static void silenceSharedIf(bool Function(String postId) owns) {
    final player = _shared;
    final active = player?._activePostId;
    if (player == null || active == null || !owns(active)) return;
    if (player._phase == PageVoicePhase.loading) {
      // Still downloading: a pause would not stop it from starting.
      unawaited(player.stop());
    } else {
      unawaited(player.pause());
    }
  }

  /// §1.1: a clip is at most 4 MB.
  static const int maxBytes = 4 * 1024 * 1024;
  static const int _cacheSize = 3;

  final PagesService _service;
  final PageVoiceDownloader _download;
  final PageVoiceAudio Function() _audioFactory;
  final Future<PreparedDirectVoiceSource> Function(Uint8List, String) _prepare;

  PageVoiceAudio? _audio;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _completeSub;
  Future<void> Function()? _releaseSource;
  final LinkedHashMap<String, Uint8List> _clips =
      LinkedHashMap<String, Uint8List>();

  String? _activePostId;
  PageVoicePhase _phase = PageVoicePhase.idle;
  Duration _position = Duration.zero;
  int _generation = 0;
  bool _disposed = false;

  String? get activePostId => _activePostId;
  PageVoicePhase get phase => _phase;
  Duration get position => _position;

  /// The phase of [postId]: idle unless it is the active clip.
  PageVoicePhase phaseOf(String postId) =>
      postId == _activePostId ? _phase : PageVoicePhase.idle;

  Duration positionOf(String postId) =>
      postId == _activePostId ? _position : Duration.zero;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Play, pause or resume the clip of [post].
  Future<void> toggle(PagePostView post) async {
    final voice = post.voice;
    if (voice == null) return;
    if (post.postId == _activePostId) {
      switch (_phase) {
        case PageVoicePhase.playing:
          _phase = PageVoicePhase.paused;
          _notify();
          await _audio?.pause();
          return;
        case PageVoicePhase.paused:
          _phase = PageVoicePhase.playing;
          _notify();
          await _audio?.resume();
          return;
        case PageVoicePhase.loading:
          return;
        case PageVoicePhase.idle:
        case PageVoicePhase.failed:
          break;
      }
    }
    await _start(post, voice);
  }

  Future<void> _start(PagePostView post, PageMediaView voice) async {
    final generation = ++_generation;
    await _stopAudio();
    _activePostId = post.postId;
    _phase = PageVoicePhase.loading;
    _position = Duration.zero;
    _notify();
    try {
      final bytes = await _clipBytes(post.postId, voice.mediaId);
      if (generation != _generation || _disposed) return;
      final prepared = await _prepare(bytes, voice.mediaId);
      if (generation != _generation || _disposed) {
        await prepared.dispose();
        return;
      }
      _releaseSource = prepared.dispose;
      final audio = _audio ??= _audioFactory();
      _positionSub ??= audio.positions.listen(_onPosition);
      _completeSub ??= audio.completions.listen((_) => _onComplete());
      _phase = PageVoicePhase.playing;
      _notify();
      await audio.play(prepared.source);
    } catch (_) {
      if (generation != _generation || _disposed) return;
      _phase = PageVoicePhase.failed;
      _notify();
    }
  }

  Future<Uint8List> _clipBytes(String postId, String mediaId) async {
    final key = '$postId/$mediaId';
    final cached = _clips.remove(key);
    if (cached != null) {
      _clips[key] = cached;
      return cached;
    }
    Future<Uint8List> attempt() async {
      final grants = await _service.mediaAccess(postId, [mediaId]);
      final grant = grants[mediaId];
      if (grant == null) {
        throw const PagesException(PagesFailure.unavailable, 'grant');
      }
      return _download(grant.url);
    }

    Uint8List bytes;
    try {
      bytes = await attempt();
    } on PageVoiceDownloadException catch (error) {
      if (!error.expired) rethrow;
      // The 90 s URL lapsed between grant and download: one new grant.
      _service.forgetMediaGrant(postId, mediaId);
      bytes = await attempt();
    }
    _clips[key] = bytes;
    while (_clips.length > _cacheSize) {
      _clips.remove(_clips.keys.first);
    }
    return bytes;
  }

  void _onPosition(Duration position) {
    if (_phase != PageVoicePhase.playing) return;
    _position = position;
    _notify();
  }

  void _onComplete() {
    _phase = PageVoicePhase.idle;
    _position = Duration.zero;
    _activePostId = null;
    unawaited(_release());
    _notify();
  }

  /// Stops whatever is sounding (the Treści tab was left, sign-out).
  Future<void> stop() async {
    _generation++;
    await _stopAudio();
    if (_activePostId == null && _phase == PageVoicePhase.idle) return;
    _activePostId = null;
    _phase = PageVoicePhase.idle;
    _position = Duration.zero;
    _notify();
  }

  /// Pauses the sounding clip, keeping its place.
  Future<void> pause() async {
    if (_phase != PageVoicePhase.playing) return;
    _phase = PageVoicePhase.paused;
    _notify();
    await _audio?.pause();
  }

  Future<void> _stopAudio() async {
    try {
      await _audio?.stop();
    } catch (_) {
      // A player that already stopped is fine.
    }
    await _release();
  }

  Future<void> _release() async {
    final release = _releaseSource;
    _releaseSource = null;
    if (release != null) {
      try {
        await release();
      } catch (_) {}
    }
  }

  /// Drops the downloaded clips (sign-out).
  void clearCache() => _clips.clear();

  @override
  void dispose() {
    _disposed = true;
    unawaited(_positionSub?.cancel());
    unawaited(_completeSub?.cancel());
    unawaited(_release());
    unawaited(_audio?.dispose());
    super.dispose();
  }
}

/// The production download: the whole clip, bounded to 4 MB and 25 s.
Future<Uint8List> downloadPageVoiceClip(Uri url) async {
  final client = http.Client();
  try {
    final response = await client
        .send(http.Request('GET', url))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PageVoiceDownloadException(response.statusCode);
    }
    final declared = response.contentLength;
    if (declared != null && declared > PageVoicePlayer.maxBytes) {
      throw const PageVoiceDownloadException(null);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 25),
    )) {
      builder.add(chunk);
      if (builder.length > PageVoicePlayer.maxBytes) {
        throw const PageVoiceDownloadException(null);
      }
    }
    return builder.takeBytes();
  } finally {
    client.close();
  }
}
