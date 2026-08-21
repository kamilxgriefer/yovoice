import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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

    return Semantics(
      // One label, not a live region: the sidebar should not announce
      // itself every minute while someone is reading something else.
      label: 'Local time $time, $zone',
      excludeSemantics: true,
      // Compact block: one big time line, one small zone line — nothing
      // else, so the pinned bottom of the rail stays short even on a
      // height-constrained window.
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
                color: Color(0xFF6E6683),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: .4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
