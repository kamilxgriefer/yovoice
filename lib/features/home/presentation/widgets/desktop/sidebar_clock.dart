import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';

/// Where a clock's idea of "now" and "which zone" comes from.
///
/// Injectable for one reason: a test that reads the machine's real clock
/// asserts nothing repeatable. Production passes nothing and gets the
/// device.
class ClockSource {
  const ClockSource({this.now, this.zoneLabel});

  final DateTime Function()? now;

  /// Overrides the resolved zone label. Production leaves this null.
  final String Function()? zoneLabel;

  DateTime read() => (now ?? DateTime.now)();

  /// Resolution order, and why each step exists:
  ///
  ///  1. an injected label (tests, and the seam a stored per-user
  ///     timezone would later plug into — `UserProfile` has no such
  ///     field today, so there is nothing to read);
  ///  2. the device/browser zone abbreviation, which on web comes from
  ///     the browser's own IANA zone;
  ///  3. a UTC offset, for platforms that report an empty or numeric
  ///     abbreviation.
  ///
  /// No city, country or zone is hard-coded anywhere in this file.
  String label() {
    if (zoneLabel != null) return zoneLabel!();
    final now = read();
    final abbreviation = now.timeZoneName.trim();
    final looksLikeAName =
        abbreviation.isNotEmpty && !RegExp(r'^[+-]?\d').hasMatch(abbreviation);
    if (looksLikeAName) return abbreviation;
    return utcOffsetLabel(now.timeZoneOffset);
  }

  static String utcOffsetLabel(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final absolute = offset.abs();
    final hours = absolute.inHours.toString().padLeft(2, '0');
    final minutes = (absolute.inMinutes % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }
}

/// The sidebar's quiet local clock.
///
/// Ticks on the MINUTE BOUNDARY rather than every second: the display has
/// no seconds, so a per-second timer would rebuild sixty times for
/// fifty-nine identical frames. The first timer is short (the remainder
/// of the current minute) and every one after it is a minute long, which
/// also keeps it aligned when the app is resumed after a long sleep.
class SidebarClock extends StatefulWidget {
  const SidebarClock({this.source = const ClockSource(), super.key});

  final ClockSource source;

  @override
  State<SidebarClock> createState() => SidebarClockState();
}

@visibleForTesting
class SidebarClockState extends State<SidebarClock>
    with WidgetsBindingObserver {
  Timer? _timer;
  late DateTime _now;

  /// Exposed so a test can assert the timer is really gone after dispose
  /// rather than trusting that dispose was written correctly.
  @visibleForTesting
  bool get hasActiveTimer => _timer?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = widget.source.read();
    _scheduleNextTick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A resumed tab may have been asleep across a minute, an hour, or a
    // daylight-saving change. Re-read rather than waiting for the next
    // tick, and re-align the schedule to the new boundary.
    if (state == AppLifecycleState.resumed) {
      _tick();
    }
  }

  void _scheduleNextTick() {
    final now = widget.source.read();
    final untilNextMinute = Duration(
      seconds: 60 - now.second,
      milliseconds: -now.millisecond,
      microseconds: -now.microsecond,
    );
    _timer?.cancel();
    _timer = Timer(untilNextMinute, () {
      _tick();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    });
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _now = widget.source.read());
  }

  static String formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final time = formatTime(_now);
    final zone = widget.source.label();
    // The map is decoration and yields FIRST on a height-constrained
    // window: the block must stay compact enough that it never crowds
    // the pinned profile card below it.
    final showMap = MediaQuery.sizeOf(context).height >= 700;

    return Semantics(
      // One label, not a live region: the sidebar should not announce
      // itself every minute while someone is reading something else.
      label: 'Local time $time, $zone',
      excludeSemantics: true,
      // Compact block: one big time line, one small zone line, and — when
      // the window is tall enough — a quiet dotted world map whose glow
      // dot sits at the longitude of the device's real UTC offset.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              time,
              style: const TextStyle(
                color: Color(0xFFE8E2F2),
                fontSize: 21,
                height: 1.0,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
                fontFeatures: [ui.FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              zone,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                // Lifted from 0xFF6E6683 (3.34:1): the zone name is 10px text
                // and must clear 4.5:1.
                color: Color(0xFF9C93AB),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: .4,
              ),
            ),
            if (showMap) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 52,
                width: double.infinity,
                child: CustomPaint(
                  key: const ValueKey('sidebar-clock-map'),
                  painter: DottedWorldMapPainter(
                    utcOffset: _now.timeZoneOffset,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A coarse dotted world map, drawn procedurally — no asset, no network,
/// no geo lookup. The single glow dot is placed by the only geographic
/// fact this app actually holds: the device's UTC offset, mapped to a
/// longitude (`offset / 12h × 180°`) at a fixed mid-northern latitude.
/// That is an approximation of a meridian, not a location — which is why
/// the block deliberately names no city and no country: the app has no
/// geo data, and printing one would be an invention.
class DottedWorldMapPainter extends CustomPainter {
  DottedWorldMapPainter({required this.utcOffset});

  final Duration utcOffset;

  static const int columns = 44;
  static const int rows = 20;

  /// The latitude band the grid covers (equirectangular, cropped the way
  /// dotted maps usually are — no empty polar bands).
  static const double latTop = 75;
  static const double latBottom = -55;

  /// Where the glow dot sits vertically: a fixed mid-northern latitude.
  static const double dotLatitude = 45;

  /// Landmass as inclusive column ranges per row, row 0 at [latTop].
  /// Hand-encoded and deliberately coarse: it only has to read as "the
  /// world", not survive a geography exam.
  static const List<List<(int, int)>> landRanges = [
    [(1, 4), (6, 13), (15, 19), (24, 25), (27, 43)], // ~72N
    [(1, 3), (5, 13), (16, 18), (23, 42)], // ~65N
    [(1, 3), (6, 13), (17, 17), (23, 42)], // ~59N
    [(6, 13), (20, 20), (22, 42)], // ~52N
    [(6, 13), (21, 40)], // ~46N
    [(6, 12), (20, 27), (29, 38), (40, 40)], // ~39N
    [(6, 11), (20, 29), (33, 39)], // ~33N
    [(7, 9), (19, 29), (31, 37)], // ~26N
    [(8, 10), (19, 29), (31, 33), (34, 37)], // ~20N
    [(9, 11), (19, 27), (31, 32), (34, 38)], // ~13N
    [(11, 14), (20, 28), (34, 38)], // ~7N
    [(11, 16), (21, 27), (34, 39)], // ~0
    [(11, 17), (22, 26), (35, 41)], // ~6S
    [(12, 17), (22, 26), (37, 40)], // ~13S
    [(12, 16), (22, 25), (36, 40)], // ~19S
    [(12, 15), (22, 25), (36, 40)], // ~26S
    [(12, 14), (23, 24), (36, 40)], // ~32S
    [(12, 13), (38, 40), (42, 42)], // ~39S
    [(12, 13), (42, 42)], // ~45S
    [(12, 13)], // ~52S
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / columns;
    final cellHeight = size.height / rows;
    final dotRadius = math.min(cellWidth, cellHeight) * .28;

    final dotPaint = Paint()
      ..color = AppColors.textHint.withValues(alpha: .34);
    for (var row = 0; row < rows && row < landRanges.length; row++) {
      final y = (row + .5) * cellHeight;
      for (final (start, end) in landRanges[row]) {
        for (var column = start; column <= end && column < columns; column++) {
          canvas.drawCircle(
            Offset((column + .5) * cellWidth, y),
            dotRadius,
            dotPaint,
          );
        }
      }
    }

    // The "you are around here" glow: longitude from the real UTC
    // offset, latitude fixed.
    final offsetHours = utcOffset.inMinutes / 60.0;
    final longitude = (offsetHours / 12.0 * 180.0).clamp(-180.0, 180.0);
    final x = (longitude + 180.0) / 360.0 * size.width;
    final y = (latTop - dotLatitude) / (latTop - latBottom) * size.height;
    final center = Offset(x, y);

    canvas.drawCircle(
      center,
      dotRadius * 4.6,
      Paint()
        ..color = AppColors.primary.withValues(alpha: .5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      center,
      dotRadius * 1.7,
      Paint()..color = AppColors.secondary,
    );
    canvas.drawCircle(
      center,
      dotRadius * .8,
      Paint()..color = AppColors.textPrimary,
    );
  }

  @override
  bool shouldRepaint(DottedWorldMapPainter oldDelegate) =>
      oldDelegate.utcOffset != utcOffset;
}
