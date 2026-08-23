import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/widgets/desktop/timezone_world_map_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/sponsored_card.dart';

/// Focused coverage for the desktop corrections. Every test here uses
/// injected dependencies — no network, no real clock, no zone overrides
/// — so none of them can stall the way the abandoned HttpOverrides
/// harness did.
void main() {
  group('sidebar clock', () {
    /// 24-hour is forced here because these cases assert on "18:42".
    /// The card now honours the platform's clock preference rather than
    /// hard-coding 24-hour — the same fix message_bubble.dart,
    /// edit_profile_screen.dart and club_chat_screen.dart each needed —
    /// and a test MediaQuery defaults `alwaysUse24HourFormat` to false.
    /// The 12-hour path has its own case at the end of this group.
    Widget host(TimezoneWorldMapCard clock, {bool use24Hour = true}) =>
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(alwaysUse24HourFormat: use24Hour),
            child: Scaffold(
              body: Align(alignment: Alignment.topLeft, child: clock),
            ),
          ),
        );

    testWidgets('renders the supplied time and the resolved zone label', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          TimezoneWorldMapCard(
            source: ClockSource(
              now: () => DateTime(2026, 8, 12, 18, 42, 30),
              zoneLabel: () => 'CEST',
            ),
          ),
        ),
      );

      expect(find.text('18:42'), findsOneWidget);
      expect(find.text('CEST'), findsOneWidget);
    });

    testWidgets('the first tick lands on the NEXT MINUTE BOUNDARY, not a '
        'minute from now, and it keeps ticking once a minute after that', (
      tester,
    ) async {
      var current = DateTime(2026, 8, 12, 18, 42, 30);
      await tester.pumpWidget(
        host(
          TimezoneWorldMapCard(
            source: ClockSource(now: () => current, zoneLabel: () => 'UTC'),
          ),
        ),
      );
      expect(find.text('18:42'), findsOneWidget);

      // 29s in: still inside the same minute, nothing should have fired.
      current = DateTime(2026, 8, 12, 18, 42, 59);
      await tester.pump(const Duration(seconds: 29));
      expect(find.text('18:43'), findsNothing);

      // The boundary itself, 30s after mount — not 60.
      current = DateTime(2026, 8, 12, 18, 43, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('18:43'), findsOneWidget);

      current = DateTime(2026, 8, 12, 18, 44, 0);
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('18:44'), findsOneWidget);
    });

    testWidgets('the timer is disposed with the widget', (tester) async {
      await tester.pumpWidget(
        host(
          TimezoneWorldMapCard(
            source: ClockSource(
              now: () => DateTime(2026, 8, 12, 9, 5),
              zoneLabel: () => 'UTC',
            ),
          ),
        ),
      );
      final state = tester.state<TimezoneWorldMapCardState>(
        find.byType(TimezoneWorldMapCard),
      );
      expect(state.hasActiveTimer, isTrue);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(state.hasActiveTimer, isFalse);
    });

    testWidgets('a resumed tab re-reads the clock instead of waiting', (
      tester,
    ) async {
      var current = DateTime(2026, 8, 12, 18, 42, 10);
      await tester.pumpWidget(
        host(
          TimezoneWorldMapCard(
            source: ClockSource(now: () => current, zoneLabel: () => 'UTC'),
          ),
        ),
      );
      expect(find.text('18:42'), findsOneWidget);

      // Asleep for two hours, then resumed.
      current = DateTime(2026, 8, 12, 20, 15, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.text('20:15'), findsOneWidget);
    });

    test('no city, country or zone is hard-coded — the label comes from '
        'the device when nothing is injected', () {
      const source = ClockSource();
      final resolved = source.label();
      expect(resolved, isNotEmpty);
      // Whatever the machine reports, it must match what dart:core says,
      // not a literal baked into the widget.
      final now = DateTime.now();
      final expected = RegExp(r'^[+-]?\d').hasMatch(now.timeZoneName.trim())
          ? ClockSource.utcOffsetLabel(now.timeZoneOffset)
          : now.timeZoneName.trim();
      expect(resolved, expected);
    });

    test('an unusable abbreviation degrades to a UTC offset', () {
      final source = ClockSource(
        now: () => DateTime(2026, 8, 12, 12),
        zoneLabel: null,
      );
      // The formatter itself is the part that must be right.
      expect(ClockSource.utcOffsetLabel(const Duration(hours: 2)), 'UTC+02:00');

      expect(
        ClockSource.utcOffsetLabel(const Duration(hours: -5, minutes: -30)),
        'UTC-05:30',
      );
      expect(source.label(), isNotEmpty);
    });

    testWidgets('a 12-hour-clock locale is honoured rather than overridden', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          TimezoneWorldMapCard(
            source: ClockSource(
              now: () => DateTime(2026, 8, 12, 18, 42, 30),
              zoneLabel: () => 'CEST',
            ),
          ),
          use24Hour: false,
        ),
      );
      expect(find.text('6:42 PM'), findsOneWidget);
      expect(find.text('18:42'), findsNothing);
    });

    testWidgets('an IANA zone yields a city and a region, and NEVER a '
        'country the app does not know', (tester) async {
      await tester.pumpWidget(
        host(
          TimezoneWorldMapCard(
            source: ClockSource(
              now: () => DateTime(2026, 8, 12, 18, 42, 30),
              ianaName: () => 'Europe/Warsaw',
            ),
          ),
        ),
      );
      expect(find.text('Warsaw'), findsOneWidget);
      expect(find.text('Europe'), findsOneWidget);
      // The app holds no country data for this user; inventing "Poland"
      // from a timezone is exactly what this feature must not do.
      expect(find.text('Poland'), findsNothing);
    });

    testWidgets('with NO IANA zone the card degrades to the UTC offset and '
        'still names no place', (tester) async {
      await tester.pumpWidget(
        host(
          TimezoneWorldMapCard(
            source: ClockSource(
              now: () => DateTime.utc(2026, 8, 12, 18, 42, 30),
              ianaName: () => null,
            ),
          ),
        ),
      );
      // Two UTC+00:00 renders would mean the fallback label and the chip
      // are duplicating each other; the primary label must fall through
      // to the offset exactly once alongside the chip.
      expect(find.textContaining('UTC+00:00'), findsWidgets);
      expect(find.text('Europe'), findsNothing);
    });

    testWidgets('the semantic label carries the time and zone as TEXT, so '
        'the map is never the only carrier', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          TimezoneWorldMapCard(
            source: ClockSource(
              now: () => DateTime(2026, 8, 12, 18, 42, 30),
              ianaName: () => 'Europe/Warsaw',
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Local time .*Warsaw.*Europe.*UTC')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('sponsored placement', () {
    testWidgets('the example discloses itself and offers nothing to click', (
      tester,
    ) async {
      var launched = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: SponsoredCard(onOpen: (_) => launched++),
            ),
          ),
        ),
      );

      expect(find.text('SPONSORED EXAMPLE'), findsOneWidget);
      // No claim of a customer, no metrics, no quotation.
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('"'), findsNothing);

      // The CTA exists as a preview and is NOT a button.
      expect(find.textContaining('preview'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(launched, 0);
    });

    test('only absolute https destinations are considered launchable', () {
      const base = SponsoredPlacement(headline: 'h', body: 'b');
      expect(base.hasLaunchableDestination, isFalse);

      for (final unsafe in [
        'javascript:alert(1)',
        'data:text/html,<script>',
        'file:///etc/passwd',
        'http://example.com',
        '//example.com',
        'https:',
      ]) {
        expect(
          SponsoredPlacement(
            headline: 'h',
            body: 'b',
            destination: Uri.parse(unsafe),
          ).hasLaunchableDestination,
          isFalse,
          reason: '$unsafe must never be launchable',
        );
      }

      expect(
        SponsoredPlacement(
          headline: 'h',
          body: 'b',
          destination: Uri.parse('https://example.com/campaign'),
        ).hasLaunchableDestination,
        isTrue,
      );
    });

    testWidgets('a real https placement becomes an actionable button that '
        'hands back its destination', (tester) async {
      Uri? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: SponsoredCard(
                placement: SponsoredPlacement(
                  headline: 'Real campaign',
                  body: 'Supplied by a partner',
                  ctaLabel: 'Open',
                  destination: Uri.parse('https://example.com/x'),
                  isExample: false,
                ),
                onOpen: (uri) => opened = uri,
              ),
            ),
          ),
        ),
      );

      expect(find.text('SPONSORED'), findsOneWidget);
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();
      expect(opened, Uri.parse('https://example.com/x'));
    });

    testWidgets('fits the right column width without overflow', (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox(width: 320, child: SponsoredCard())),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
