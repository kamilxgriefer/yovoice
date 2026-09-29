import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// What fills the bands around a contained (non-portrait) Yeel video.
enum ReelVideoBackdrop {
  /// A blurred cover copy of the same picture under a 40% black scrim — the
  /// designer's finish (blur 18 on a 390-wide frame).
  blurred,

  /// Plain black: the safety net where a second draw of the video texture
  /// is not affordable or not possible.
  black,
}

/// Total RAM at or below which an Android device gets [ReelVideoBackdrop.black].
///
/// Android reports `MemoryInfo.totalMem`, a little under the nominal size
/// (a "4 GB" phone reports roughly 3.5–3.9 GB), so this cut-off keeps every
/// nominal 4 GB phone — where entry GPUs (PowerVR, small Mali) are common and
/// a full-frame blur of live video is least affordable — on black. There is
/// no remote switch for this, so it errs on the safe side until frame times
/// have been measured on such a device.
const int reelBlurredBackdropMinimumRamMb = 4096;

/// Reads the two Android facts the policy needs. Injectable for tests.
typedef ReelAndroidMemoryProbe =
    Future<({bool isLowRamDevice, int physicalRamMb})> Function();

/// Resolves, once per process, whether contained videos get the blurred or
/// the black backdrop (ADR-235).
///
/// * iOS and macOS: blurred. The blurred copy is a second `VideoPlayer` on
///   the SAME controller — the same texture id — so there is no second
///   decoder and no second download; the engine caches the external-texture
///   image once per frame, so both draws show the same frame. The added cost
///   is one texture draw plus one downsampled Gaussian pass, paid only by
///   non-portrait clips.
/// * Android: blurred, except on a device with at most
///   [reelBlurredBackdropMinimumRamMb] of RAM or one that reports memory
///   pressure when the policy resolves (device_info_plus's `isLowRamDevice`
///   is `MemoryInfo.lowMemory`, a snapshot, not the static low-RAM flag).
///   Until the probe answers (milliseconds) the value is black, so a weak
///   device never pays for it — and the feed and the composer start the
///   probe as they open ([ensureResolved]), long before a video decoder is
///   ready, so a landscape Yeel does not switch from black to blur on
///   screen.
/// * Web: black. video_player_web draws one `<video>` element per player
///   through an HtmlElementView whose factory returns the same element for
///   every view id; Flutter can neither duplicate nor filter it. A canvas
///   mirror via requestVideoFrameCallback would couple to plugin internals,
///   so it is deferred.
///
/// A poster or snapshot frame was rejected: there is no thumbnail pipeline,
/// a poster asset would need a new media field (exact-shape readers refuse
/// it), `toImage` on external textures is unreliable across Impeller, Skia
/// and web platform views, and a frozen frame behind moving video reads as a
/// glitch.
class ReelVideoBackdropPolicy extends ValueNotifier<ReelVideoBackdrop> {
  ReelVideoBackdropPolicy._() : super(_initialValue());

  static final ReelVideoBackdropPolicy instance = ReelVideoBackdropPolicy._();

  /// Test seam: when set, every contained video uses this backdrop.
  @visibleForTesting
  static ReelVideoBackdrop? debugOverride;

  /// Test seam for the Android memory facts.
  @visibleForTesting
  static ReelAndroidMemoryProbe? debugAndroidMemoryProbe;

  /// Test seam: the platform the policy resolves for.
  @visibleForTesting
  static bool? debugIsWeb;

  bool _resolving = false;
  bool _resolved = false;

  static bool get _isWeb => debugIsWeb ?? kIsWeb;

  static ReelVideoBackdrop _initialValue() {
    if (_isWeb) return ReelVideoBackdrop.black;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => ReelVideoBackdrop.blurred,
      TargetPlatform.android => ReelVideoBackdrop.black,
      _ => ReelVideoBackdrop.blurred,
    };
  }

  /// The backdrop to draw now; [debugOverride] wins.
  ReelVideoBackdrop get effective => debugOverride ?? value;

  /// Starts the one-time resolution. Idempotent and cheap to call from build.
  void ensureResolved() {
    if (_resolved || _resolving) return;
    if (_isWeb || defaultTargetPlatform != TargetPlatform.android) {
      _resolved = true;
      value = _initialValue();
      return;
    }
    _resolving = true;
    unawaited(_resolveAndroid());
  }

  Future<void> _resolveAndroid() async {
    var next = ReelVideoBackdrop.black;
    try {
      final probe = debugAndroidMemoryProbe ?? _deviceMemory;
      final memory = await probe();
      next =
          memory.isLowRamDevice ||
              memory.physicalRamMb <= reelBlurredBackdropMinimumRamMb
          ? ReelVideoBackdrop.black
          : ReelVideoBackdrop.blurred;
    } catch (_) {
      // Unknown hardware keeps the safe backdrop.
      next = ReelVideoBackdrop.black;
    } finally {
      _resolving = false;
      _resolved = true;
    }
    value = next;
  }

  static Future<({bool isLowRamDevice, int physicalRamMb})>
  _deviceMemory() async {
    final info = await DeviceInfoPlugin().androidInfo;
    return (
      isLowRamDevice: info.isLowRamDevice,
      physicalRamMb: info.physicalRamSize,
    );
  }

  /// Forgets the resolution (tests only).
  @visibleForTesting
  void debugReset() {
    _resolving = false;
    _resolved = false;
    value = _initialValue();
  }
}
