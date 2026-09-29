import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:yovoice/features/reels/presentation/reel_media_fit.dart';
import 'package:yovoice/features/reels/presentation/reel_video_backdrop_policy.dart';

/// The ONE way a Yeel video is laid into its composition canvas — composer
/// preview and feed player alike — so the two can never disagree (ADR-235).
///
/// [size] is the decoder's display size (`controller.value.size`, which on
/// iOS, Android and web already includes the file's track matrix).
/// [quarterTurns] is the composer's pending "Obróć" rotation: the picture is
/// turned with a [RotatedBox] and the fit rule is evaluated on the turned
/// size, without touching the decoder.
///
/// Cover (every upright phone clip) builds exactly today's tree:
/// `FittedBox(cover, SizedBox(size, video))`. Contain draws, bottom to top:
/// black, a blurred cover copy of the same picture (a second view of the same
/// controller, so no second decoder), a 40% black scrim, and the whole video
/// contained and centred in the full canvas (scaled up as well as down). The
/// backdrop is decorative: excluded from semantics and hit testing. It sits inside the canvas's filter and zoom transform, so filters
/// and zoom apply to it as well; its σ 18 is in canvas design units (the
/// canvas is 390 wide by contract), so it scales with the canvas on every
/// screen exactly like the designer's "blur 18 on a 390-wide frame".
class ReelFittedVideo extends StatelessWidget {
  const ReelFittedVideo({
    required this.size,
    required this.video,
    this.quarterTurns = 0,
    this.backdrop,
    super.key,
  });

  final Size size;

  /// Builds one view of the video. Called once for cover and twice for a
  /// blurred contain (the backdrop and the foreground share its controller).
  final Widget Function() video;
  final int quarterTurns;

  /// Overrides [ReelVideoBackdropPolicy] for this video.
  final ReelVideoBackdrop? backdrop;

  /// Design-unit blur radius of the backdrop.
  static const double backdropSigma = 18;

  /// The scrim over the blurred copy: 40% black.
  static const Color backdropScrim = Color(0x66000000);

  @override
  Widget build(BuildContext context) {
    final turns = quarterTurns % 4;
    final display = reelDisplaySize(size, turns);
    Widget sized() => SizedBox(
      width: display.width,
      height: display.height,
      child: turns == 0
          ? video()
          : RotatedBox(quarterTurns: turns, child: video()),
    );
    if (reelVideoFit(display) == ReelMediaFit.cover) {
      return FittedBox(fit: BoxFit.cover, child: sized());
    }
    return _ContainedVideo(backdrop: backdrop, sized: sized);
  }
}

class _ContainedVideo extends StatefulWidget {
  const _ContainedVideo({required this.backdrop, required this.sized});

  final ReelVideoBackdrop? backdrop;
  final Widget Function() sized;

  @override
  State<_ContainedVideo> createState() => _ContainedVideoState();
}

class _ContainedVideoState extends State<_ContainedVideo> {
  final ReelVideoBackdropPolicy _policy = ReelVideoBackdropPolicy.instance;

  @override
  void initState() {
    super.initState();
    _policy.addListener(_policyChanged);
    _policy.ensureResolved();
  }

  @override
  void dispose() {
    _policy.removeListener(_policyChanged);
    super.dispose();
  }

  void _policyChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final backdrop = widget.backdrop ?? _policy.effective;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const ColoredBox(
          key: ValueKey<String>('reel-fitted-video-base'),
          color: Colors.black,
        ),
        if (backdrop == ReelVideoBackdrop.blurred) ...<Widget>[
          ExcludeSemantics(
            child: IgnorePointer(
              child: ClipRect(
                key: const ValueKey<String>('reel-fitted-video-backdrop'),
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: ReelFittedVideo.backdropSigma,
                    sigmaY: ReelFittedVideo.backdropSigma,
                    tileMode: TileMode.mirror,
                  ),
                  child: FittedBox(fit: BoxFit.cover, child: widget.sized()),
                ),
              ),
            ),
          ),
          const IgnorePointer(
            child: ColoredBox(
              key: ValueKey<String>('reel-fitted-video-scrim'),
              color: ReelFittedVideo.backdropScrim,
            ),
          ),
        ],
        // Tight, not Center's loose constraints: a loosely constrained
        // FittedBox takes a smaller child's own size and never scales it
        // UP, so a low-resolution clip (320×180, the 64×36 fixtures) would
        // sit small in the middle instead of spanning the frame.
        SizedBox.expand(
          key: const ValueKey<String>('reel-fitted-video-foreground'),
          child: FittedBox(fit: BoxFit.contain, child: widget.sized()),
        ),
      ],
    );
  }
}
