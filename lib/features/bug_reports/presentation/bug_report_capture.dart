import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

/// The one boundary a bug-report screenshot is taken from: the app's
/// navigator (every route and modal), and nothing painted above it — not the
/// top notification banners, which can show other people's message previews,
/// and not the floating "Bug" button itself.
final GlobalKey bugReportCaptureKey = GlobalKey(
  debugLabel: 'bug-report-capture',
);

class BugReportCaptureBoundary extends StatelessWidget {
  const BugReportCaptureBoundary({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: bugReportCaptureKey, child: child);
}

/// Marks a screen whose pixels must never leave the device in a bug report —
/// today the two-factor setup screen, which shows a TOTP secret and QR code.
/// While any guard is mounted, [captureBugReportScreenshot] returns null and
/// the reporter says screenshots are off on this screen.
class BugReportCaptureGuard extends StatefulWidget {
  const BugReportCaptureGuard({required this.child, super.key});

  final Widget child;

  static int _active = 0;

  static bool get isActive => _active > 0;

  @override
  State<BugReportCaptureGuard> createState() => _BugReportCaptureGuardState();
}

class _BugReportCaptureGuardState extends State<BugReportCaptureGuard> {
  @override
  void initState() {
    super.initState();
    BugReportCaptureGuard._active += 1;
  }

  @override
  void dispose() {
    BugReportCaptureGuard._active -= 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

const int bugReportScreenshotMaxBytes = 1500000;
const int _longEdge = 1280;

/// Captures the current screen as a JPEG (long edge <= 1280 px, <= 1.5 MB),
/// or null when capture is blocked or unavailable. Nothing is uploaded here:
/// the reporter decides, after seeing a preview, whether to attach it.
Future<Uint8List?> captureBugReportScreenshot({GlobalKey? key}) async {
  if (BugReportCaptureGuard.isActive) return null;
  try {
    final renderObject = (key ?? bugReportCaptureKey).currentContext
        ?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary || !renderObject.hasSize) {
      return null;
    }
    final size = renderObject.size;
    final longest = math.max(size.width, size.height);
    if (longest <= 0) return null;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final dpr = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    final ratio = math.min(math.min(dpr, 2.0), _longEdge / longest);
    final image = await renderObject.toImage(pixelRatio: ratio);
    try {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) return null;
      final encoded = await compute(
        _encodeJpeg,
        _RawFrame(image.width, image.height, rgba.buffer.asUint8List()),
      );
      return encoded;
    } finally {
      image.dispose();
    }
  } catch (_) {
    return null;
  }
}

class _RawFrame {
  const _RawFrame(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;
}

Uint8List? _encodeJpeg(_RawFrame frame) {
  final raw = img.Image.fromBytes(
    width: frame.width,
    height: frame.height,
    bytes: frame.rgba.buffer,
    numChannels: 4,
  );
  for (final quality in const [70, 50, 35]) {
    final bytes = Uint8List.fromList(img.encodeJpg(raw, quality: quality));
    if (bytes.length <= bugReportScreenshotMaxBytes) return bytes;
  }
  return null;
}
