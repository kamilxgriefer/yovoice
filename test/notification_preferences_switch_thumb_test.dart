import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/screens/notification_preferences_screen.dart';

/// R-06: every toggle on the notification preferences screen forced
/// `activeThumbColor: colorScheme.primary`, which is the exact colour the
/// theme already paints the *selected track* with — so an ON switch rendered
/// as a solid purple lozenge with no visible thumb.
///
/// The assertion is behavioural rather than a colour literal: whatever the
/// palette resolves to, the selected thumb has to be distinguishable from the
/// selected track.
Color? _resolveThumb(Switch toggle, ThemeData theme, Set<WidgetState> states) {
  final resolved = toggle.thumbColor?.resolve(states);
  if (resolved != null) return resolved;
  if (states.contains(WidgetState.selected) &&
      toggle.activeThumbColor != null) {
    return toggle.activeThumbColor;
  }
  return theme.switchTheme.thumbColor?.resolve(states);
}

Color? _resolveTrack(Switch toggle, ThemeData theme, Set<WidgetState> states) {
  final resolved = toggle.trackColor?.resolve(states);
  if (resolved != null) return resolved;
  if (states.contains(WidgetState.selected) &&
      toggle.activeTrackColor != null) {
    return toggle.activeTrackColor;
  }
  return theme.switchTheme.trackColor?.resolve(states);
}

Future<void> _pumpPreferences(WidgetTester tester, ThemeData theme) async {
  final firestore = FakeFirebaseFirestore();
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'switch-thumb-owner'),
  );
  await firestore.collection('users').doc('switch-thumb-owner').set({
    'uid': 'switch-thumb-owner',
    'notificationPreferences': <String, bool>{},
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: NotificationPreferencesScreen(
        isRootTab: true,
        notificationService: NotificationService(
          firestore: firestore,
          auth: auth,
        ),
        creatorAudienceVisibleStream: Stream.value(false),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, theme) in <(String, ThemeData)>[
    ('dark', AppTheme.darkTheme),
    ('light', AppTheme.lightTheme),
  ]) {
    testWidgets('an ON preference switch keeps a visible thumb ($name theme)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _pumpPreferences(tester, theme);

      final switches = tester.widgetList<Switch>(find.byType(Switch));
      expect(
        switches,
        isNotEmpty,
        reason: 'the preferences screen should render toggles',
      );

      const selected = <WidgetState>{WidgetState.selected};
      for (final toggle in switches) {
        final thumb = _resolveThumb(toggle, theme, selected);
        final track = _resolveTrack(toggle, theme, selected);
        expect(
          thumb,
          isNotNull,
          reason: 'the selected thumb needs a resolvable colour',
        );
        expect(
          thumb,
          isNot(track),
          reason:
              'an ON switch whose thumb matches its track reads as a solid '
              'lozenge with no thumb',
        );
      }
    });
  }
}
