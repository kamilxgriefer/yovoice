import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/time/timezone_label.dart';
import 'package:yovoice/core/time/timezone_platform.dart';

/// Where a clock's idea of "now" and "which zone" comes from.
///
/// Injectable for one reason: a test that reads the machine's real clock
/// asserts nothing repeatable. Production passes nothing and gets the
/// device.
class ClockSource {
  const ClockSource({this.now, this.zoneLabel, this.ianaName});

  final DateTime Function()? now;

  /// Overrides the resolved zone label. Production leaves this null.
  final String Function()? zoneLabel;

  /// Overrides the IANA lookup. Production leaves this null and gets the
  /// browser's `Intl.DateTimeFormat().resolvedOptions().timeZone` on web,
  /// null on native.
  final String? Function()? ianaName;

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

  /// Everything the card needs, resolved once per tick.
  ///
  /// An injected [zoneLabel] still wins outright — it is the test seam AND
  /// the seam a user-selected timezone would plug into. `UserProfile` has
  /// no timezone field today (its `country` is free text typed into a bare
  /// text box, so it cannot be mapped to a zone), which is why this reads
  /// the platform rather than the profile.
  TimezoneReading reading() {
    final now = read();
    if (zoneLabel != null) {
      return TimezoneReading(
        offset: now.timeZoneOffset,
        platformLabel: zoneLabel!(),
      );
    }
    final abbreviation = now.timeZoneName.trim();
    return TimezoneReading(
      offset: now.timeZoneOffset,
      ianaName: (ianaName ?? readPlatformIanaTimezone)(),
      platformLabel: abbreviation.isEmpty ? null : abbreviation,
    );
  }

  /// Kept as the public entry point six existing tests already call;
  /// the implementation is the shared one in `core/time` so the card and
  /// the service can never disagree about the format.
  static String utcOffsetLabel(Duration offset) =>
      TimezoneReading.utcOffsetLabel(offset);
}

/// The sidebar's quiet local clock.
///
/// Ticks on the MINUTE BOUNDARY rather than every second: the display has
/// no seconds, so a per-second timer would rebuild sixty times for
/// fifty-nine identical frames. The first timer is short (the remainder
/// of the current minute) and every one after it is a minute long, which
/// also keeps it aligned when the app is resumed after a long sleep.
class TimezoneWorldMapCard extends StatefulWidget {
  const TimezoneWorldMapCard({
    this.source = const ClockSource(),
    this.railHeight,
    super.key,
  });

  final ClockSource source;

  /// The RAIL's available height, measured by the rail itself.
  ///
  /// Passed in rather than read from a `LayoutBuilder` here, because
  /// this card is a non-flex child of a `Column`: its own vertical
  /// constraint is `Infinity`, so a `LayoutBuilder` in this file would
  /// measure nothing and the compact tier would never engage. Verified
  /// rather than assumed — a probe returned `Infinity`.
  ///
  /// Null means "unmeasured", which renders the full card; that is the
  /// right default for the preview harnesses and the existing tests
  /// that construct this widget directly.
  final double? railHeight;

  @override
  State<TimezoneWorldMapCard> createState() => TimezoneWorldMapCardState();
}

@visibleForTesting
class TimezoneWorldMapCardState extends State<TimezoneWorldMapCard>
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

  static String formatTime(DateTime time, {bool use24Hour = true}) {
    if (use24Hour) {
      final hour = time.hour.toString().padLeft(2, '0');
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    // 24-hour was hard-coded here until this card existed, the same bug
    // message_bubble.dart, edit_profile_screen.dart and club_chat_screen.dart
    // each had to fix: a 12-hour-clock locale heard "13:04".
    final raw = time.hour % 12;
    final hour = raw == 0 ? 12 : raw;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
  }

  /// The rail's real height, below which the map yields.
  ///
  /// MEASURED, not guessed. The rail's fixed chrome plus its nav column
  /// demand ~758 px; `maxScrollExtent` is 0 at 1440x768 and 40 at 720. A
  /// full card adds height to the pinned side of that budget, so it is
  /// spent only where it is genuinely free.
  ///
  /// The threshold reads `constraints.maxHeight` — the RAIL's height —
  /// rather than `MediaQuery.sizeOf(context).height`. The window is the
  /// wrong measurement: `RoomMiniBar` (~118 px with a live room) and the
  /// verification banner (~38 px) both shrink the rail without changing
  /// the window, which is exactly the state the old `>= 700` window gate
  /// got wrong — it kept the map on screen precisely when the rail was
  /// starving.
  static const double fullCardMinRailHeight = 800;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = context.appPalette;
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final time = formatTime(_now, use24Hour: use24Hour);
    final reading = widget.source.reading();
    final zone = reading.primaryLabel;
    final region = reading.regionLabel;
    final offsetLabel = TimezoneReading.utcOffsetLabel(reading.offset);

    final railHeight = widget.railHeight;
    final showMap = railHeight == null || railHeight >= fullCardMinRailHeight;
    return Builder(
      builder: (context) {
        return Semantics(
          // One label, not a live region: the sidebar should not announce
          // itself every minute while someone is reading something else.
          // The text is the ONLY carrier of the timezone — the highlighted
          // map region is decoration and is excluded below, so nothing here
          // is communicated by the map alone.
          label: _semanticLabel(time, zone, region, reading.offset),
          excludeSemantics: true,
          child: Container(
            key: const ValueKey('desktop-timezone-card'),
            // Lifted verbatim from _ProfileCard directly below it, so the
            // two read as one pinned pair rather than two loose blocks.
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: palette.surfaceRaised,
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            time,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 21,
                              height: 1.0,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .5,
                              // Load-bearing: without tabular figures the
                              // digits jitter on every minute tick.
                              fontFeatures: [ui.FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            zone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _OffsetChip(label: offsetLabel),
                  ],
                ),
                if (region != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    region,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textTertiary,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .5,
                    ),
                  ),
                ],
                if (showMap) ...[
                  const SizedBox(height: 8),
                  // The map carries no text and no independent meaning, so
                  // it contributes nothing to the accessibility tree.
                  ExcludeSemantics(
                    child: SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: CustomPaint(
                        key: const ValueKey('sidebar-clock-map'),
                        painter: DottedWorldMapPainter(
                          utcOffset: reading.offset,
                          localHour: _now.hour,
                          landColor: palette.textTertiary.withValues(
                            alpha: .42,
                          ),
                          daytimeMarkerColor: colors.secondary,
                          nighttimeMarkerColor: colors.primary,
                          markerCoreColor: colors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// "Local time 12:37, Central European Summer Time, UTC plus two."
  ///
  /// The offset is spelled out because a screen reader renders "UTC+02:00"
  /// as an unreadable run of characters.
  static String _semanticLabel(
    String time,
    String zone,
    String? region,
    Duration offset,
  ) {
    final hours = offset.inMinutes.abs() ~/ 60;
    final minutes = offset.inMinutes.abs() % 60;
    final direction = offset.isNegative ? 'minus' : 'plus';
    final spoken = minutes == 0
        ? 'UTC $direction $hours'
        : 'UTC $direction $hours $minutes';
    final place = region == null ? zone : '$zone, $region';
    return 'Local time $time, $place, $spoken';
  }
}

/// The UTC offset as a pill, matching the rail's active-nav wash and the
/// profile card's gear chip so it reads as native rather than as a badge
/// borrowed from somewhere else.
class _OffsetChip extends StatelessWidget {
  const _OffsetChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: colors.primaryContainer,
        border: Border.all(color: colors.primary.withValues(alpha: .45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: .3,
          fontFeatures: [ui.FontFeature.tabularFigures()],
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
  DottedWorldMapPainter({
    required this.utcOffset,
    required this.landColor,
    required this.daytimeMarkerColor,
    required this.nighttimeMarkerColor,
    required this.markerCoreColor,
    this.localHour,
  });

  final Duration utcOffset;
  final Color landColor;
  final Color daytimeMarkerColor;
  final Color nighttimeMarkerColor;
  final Color markerCoreColor;

  /// The user's local hour, 0-23, used only to warm or cool the glow.
  ///
  /// This is a DAY/NIGHT TINT, not astronomy: no solar declination, no
  /// terminator curve, no per-frame maths. It changes at most once an hour
  /// and is recomputed only when the minute-boundary timer rebuilds the
  /// card, which is why `shouldRepaint` compares it.
  final int? localHour;

  /// True between 06:00 and 17:59 local.
  bool get _isDaytime {
    final hour = localHour;
    if (hour == null) return true;
    return hour >= 6 && hour < 18;
  }

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

    final dotPaint = Paint()..color = landColor;
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

    // Warm violet by day, cooler by night. Both stay inside the brand
    // palette — this is a mood shift of a few percent, not a second theme.
    final halo = _isDaytime
        ? daytimeMarkerColor.withValues(alpha: .52)
        : nighttimeMarkerColor.withValues(alpha: .46);
    canvas.drawCircle(
      center,
      dotRadius * 4.6,
      Paint()
        ..color = halo
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      center,
      dotRadius * 1.7,
      Paint()..color = _isDaytime ? daytimeMarkerColor : nighttimeMarkerColor,
    );
    canvas.drawCircle(center, dotRadius * .8, Paint()..color = markerCoreColor);
  }

  @override
  bool shouldRepaint(DottedWorldMapPainter oldDelegate) =>
      oldDelegate.utcOffset != utcOffset ||
      oldDelegate._isDaytime != _isDaytime ||
      oldDelegate.landColor != landColor ||
      oldDelegate.daytimeMarkerColor != daytimeMarkerColor ||
      oldDelegate.nighttimeMarkerColor != nighttimeMarkerColor ||
      oldDelegate.markerCoreColor != markerCoreColor;
}
