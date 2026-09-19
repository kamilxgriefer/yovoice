import 'dart:async';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/media/data/services/giphy_pingbacks.dart';

typedef GifMessageInvoker =
    Future<Object?> Function(String callable, Map<String, Object?> payload);

enum GifSendFailure { unavailable, refused, retryable }

/// A single explicit GIF send intent. It retains its exact request and account
/// on failure; retrying a lost acknowledgement cannot send a duplicate. Text
/// drafts and the private attachment upload pipeline remain separate owners.
class GifMessageController extends ChangeNotifier {
  GifMessageController({
    required this.callable,
    required Map<String, String> target,
    required String? Function() currentUserId,
    GifMessageInvoker? invoke,
    GiphyPingbacks? giphyPingbacks,
  }) : _target = Map.unmodifiable(target),
       _currentUserId = currentUserId,
       _invoke = invoke ?? _call,
       _giphyPingbacks = giphyPingbacks;

  final String callable;
  final Map<String, String> _target;
  final String? Function() _currentUserId;
  final GifMessageInvoker _invoke;

  /// GIPHY `onsent` (ADR-210). Fires only for a choice the picker armed with
  /// `onclick` while "Load GIFs automatically" was on; null or unarmed is a
  /// no-op, which is every Originals send and every build without a key.
  final GiphyPingbacks? _giphyPingbacks;
  GiphyPingbacks? get _pingbacks =>
      _giphyPingbacks ?? GiphyPingbackRegistry.instance;
  GifAsset? _asset;
  GifAsset? get asset => _owner == _currentUserId() ? _asset : null;
  String? _owner;
  Map<String, Object?>? _payload;
  bool sending = false;
  GifSendFailure? failure;
  bool _disposed = false;
  bool get canSelect => asset == null && !sending;
  bool get canRetry => failure == GifSendFailure.retryable && !sending;

  static Future<Object?> _call(String name, Map<String, Object?> data) async {
    final response = await FirebaseFunctions.instanceFor(
      region: 'europe-west1',
    ).httpsCallable(name).call<Object?>(data);
    return response.data;
  }

  Future<void> send(GifAsset asset, {String? replyToMessageId}) async {
    if (!canSelect || !asset.hasPinnedUrl) return;
    final owner = _currentUserId();
    if (owner == null || owner.isEmpty) return;
    _owner = owner;
    _asset = asset;
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _payload = Map.unmodifiable(<String, Object?>{
      ..._target,
      'requestId': 'gif-$id',
      'gif': asset.toMessageReference(),
      'replyToMessageId': ?replyToMessageId,
    });
    await _attempt();
  }

  Future<void> retry() async {
    if (canRetry) await _attempt();
  }

  Future<void> _attempt() async {
    final payload = _payload;
    if (_disposed || sending || payload == null) return;
    if (_owner != _currentUserId()) {
      discard();
      return;
    }
    sending = true;
    failure = null;
    notifyListeners();
    try {
      final result = await _invoke(
        callable,
        payload,
      ).timeout(const Duration(seconds: 20));
      if (result is! Map ||
          result['messageId'] is! String ||
          (result['messageId'] as String).isEmpty ||
          _target.entries.any((e) => result[e.key] != e.value)) {
        throw const FormatException('Malformed GIF acknowledgement.');
      }
      final committed = _asset;
      if (committed != null && committed.provider == 'giphy') {
        unawaited(_pingbacks?.sent(committed.id));
      }
      _asset = null;
      _payload = null;
    } catch (error) {
      failure = switch (error) {
        FirebaseFunctionsException(
          code: 'invalid-argument' ||
              'not-found' ||
              'unimplemented' ||
              'failed-precondition',
        ) =>
          GifSendFailure.unavailable,
        FirebaseFunctionsException(
          code: 'permission-denied' || 'unauthenticated',
        ) =>
          GifSendFailure.refused,
        _ => GifSendFailure.retryable,
      };
    } finally {
      sending = false;
      if (_owner != _currentUserId()) {
        _asset = null;
        _payload = null;
      }
      if (!_disposed) notifyListeners();
    }
  }

  void discard() {
    if (sending || _disposed) return;
    _asset = null;
    _payload = null;
    failure = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
