import 'dart:math' as math;
import 'dart:ui';

// How a Yeel's VIDEO sits in its frame — the one rule the composer preview,
// the feed player, the canvas pan, the crop gesture and the crop sliders all
// share, so the author and every viewer always see the same picture
// (ADR-235).
//
// Owner decision A (2026-09-29): keep today's cover fill whenever it still
// shows at least ~72% of the picture — every upright phone clip, on every
// host frame — otherwise show the WHOLE video (contain) over a blurred copy
// of itself. Photos never come through here: they keep `BoxFit.cover`.
//
// The decision is a function of the clip alone, measured against the
// canonical recipe frame ([reelRecipeAspect], i.e.
// `ReelCompositionFrame.designSize`), never the host viewport. A host-based
// rule would contain a 4:5 clip in the 9:16 composer but cover it in a
// 0.588 phone feed — composer and feed would disagree — and would flip 3:4
// clips to contain on fold cover screens.
//
// Imports no widgets, so the canvas can use it without an import cycle.

/// The recipe frame's aspect ratio (width / height).
const double reelRecipeAspect = 9 / 16;

/// Cover stays while it shows at least this fraction of the picture.
const double reelCoverMinimumVisibleFraction = .72;

enum ReelMediaFit { cover, contain }

bool _usable(Size size) =>
    size.width.isFinite &&
    size.height.isFinite &&
    size.width > 0 &&
    size.height > 0;

/// The fraction of [media] a cover fill of the 9:16 recipe frame shows along
/// the cropped axis: 1.0 for 9:16, 0.316 for 16:9. An unusable size is 1.0.
double reelCoverVisibleFraction(Size media) {
  if (!_usable(media)) return 1;
  final aspect = media.width / media.height;
  return math.min(aspect / reelRecipeAspect, reelRecipeAspect / aspect);
}

/// The fit for a video of display size [media] (already rotated by its
/// matrix, and by the composer's pending turns — see [reelDisplaySize]).
///
/// Null, zero or non-finite sizes keep today's cover. The boundary is
/// inclusive: exactly 72% visible is still cover.
ReelMediaFit reelVideoFit(Size? media) {
  if (media == null || !_usable(media)) return ReelMediaFit.cover;
  // A hair of tolerance so a clip that shows exactly 72% cannot flip on the
  // last bit of a division.
  return reelCoverVisibleFraction(media) >=
          reelCoverMinimumVisibleFraction - 1e-9
      ? ReelMediaFit.cover
      : ReelMediaFit.contain;
}

/// [size] after [quarterTurns] clockwise quarter turns: odd turns swap the
/// axes. The composer applies it to the decoder size for a pending rotation.
Size reelDisplaySize(Size size, int quarterTurns) =>
    quarterTurns.isOdd ? Size(size.height, size.width) : size;

/// `BoxFit.contain` of [media] inside [frame], centred.
Rect reelContainRect(Size frame, Size media) {
  if (!_usable(media) || frame.isEmpty) return Offset.zero & frame;
  final scale = math.min(
    frame.width / media.width,
    frame.height / media.height,
  );
  final fitted = Size(media.width * scale, media.height * scale);
  return Rect.fromLTWH(
    (frame.width - fitted.width) / 2,
    (frame.height - fitted.height) / 2,
    fitted.width,
    fitted.height,
  );
}

/// How far the zoomed media may pan along each axis, in [frame] units, at
/// crop [scale] (clamped to the recipe's 1–8).
///
/// Cover — and images, which pass no [mediaSize] — keep today's exact
/// `frame · (s − 1) / 2`: the media fills the frame, so that is its spare
/// zoom margin. A contained video pans only where the ZOOMED picture
/// overflows the frame, `max(0, (fitted · s − frame) / 2)`: a 16:9 clip in
/// the 9:16 frame pans horizontally exactly as before and vertically only
/// past 3.16×, growing continuously from 0. The blurred backdrop is a cover
/// fill scaled by the same s, so these limits keep it edge-to-edge too.
Offset reelCropPanLimits(Size frame, double scale, {Size? mediaSize}) {
  final s = scale.clamp(1.0, 8.0).toDouble();
  if (reelVideoFit(mediaSize) == ReelMediaFit.cover) {
    return Offset(
      math.max(0.0, frame.width * (s - 1) / 2),
      math.max(0.0, frame.height * (s - 1) / 2),
    );
  }
  final fitted = reelContainRect(frame, mediaSize!).size;
  return Offset(
    math.max(0.0, (fitted.width * s - frame.width) / 2),
    math.max(0.0, (fitted.height * s - frame.height) / 2),
  );
}
