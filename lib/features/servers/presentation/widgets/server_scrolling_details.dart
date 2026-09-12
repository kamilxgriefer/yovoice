import 'package:flutter/material.dart';

/// A phone-sized scrolling remainder with an honest bottom edge.
///
/// On a phone the template scenes pin what matters — the picture or the
/// studio, the channel's name, the tab strip and the one action that changes
/// what this person is doing — and let the rest share whatever is left. When
/// that remainder does not fit it has to scroll, and without a visible edge
/// the cut slices a card or a chip in half and reads as a broken layout. The
/// fade says "there is more below", and it appears only while there actually
/// is: a surface that holds all of its content is not faded.
///
/// Extracted from board 02's stage, where the defect was first found in a
/// rendered frame, so board 05 and every later template share one behaviour
/// instead of each re-deriving it.
class ServerScrollingDetails extends StatefulWidget {
  const ServerScrollingDetails({
    required this.child,
    this.fadeKey,
    this.padding,
    super.key,
  });

  final Widget child;

  /// Names the fade itself, so a template's own tests can address it.
  final Key? fadeKey;
  final EdgeInsetsGeometry? padding;

  @override
  State<ServerScrollingDetails> createState() => _ServerScrollingDetailsState();
}

class _ServerScrollingDetailsState extends State<ServerScrollingDetails> {
  bool _more = false;

  /// Metrics arrive during layout, so the flag is applied after the frame.
  bool _measure(ScrollMetrics metrics) {
    final more =
        metrics.hasContentDimensions &&
        metrics.maxScrollExtent - metrics.pixels > 1;
    if (more != _more) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && more != _more) setState(() => _more = more);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scroller = NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) => _measure(notification.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => _measure(notification.metrics),
        child: SingleChildScrollView(
          key: const ValueKey('server-channel-content-scroll'),
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
    if (!_more) return scroller;
    return ShaderMask(
      key: widget.fadeKey,
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, .86, 1],
      ).createShader(bounds),
      child: scroller,
    );
  }
}
