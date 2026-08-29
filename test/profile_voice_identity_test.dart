import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';

UserProfile _profile({
  String vibe = '',
  String bio = '',
  String website = '',
  String country = '',
  String nativeLanguage = '',
  List<String> spokenLanguages = const [],
  List<String> learningLanguages = const [],
}) => UserProfile(
  uid: 'profile-vibe-test',
  email: 'vibe@yovoice.app',
  displayName: 'Vibe Tester',
  username: 'vibetester',
  statusMessage: vibe,
  bio: bio,
  country: country,
  nativeLanguage: nativeLanguage,
  spokenLanguages: spokenLanguages,
  learningLanguages: learningLanguages,
  photoUrl: null,
  bannerUrl: null,
  website: website,
  accountType: AccountType.personal,
  friendCount: 0,
  followerCount: 0,
  followingCount: 0,
  roomCount: 0,
  communityCount: 0,
  voiceMinutes: 0,
  messageCount: 0,
  activeDays: 0,
  momentCount: 0,
  reactionCount: 0,
  hostMinutes: 0,
  selectedTitleId: null,
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: DateTime(2026),
);

Future<void> _pumpCard(
  WidgetTester tester,
  UserProfile profile, {
  double width = 390,
  double textScale = 1,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = Size(width, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: ProfileVoiceIdentityCard(profile: profile),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _contrastRatio(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first.computeLuminance()
      : second.computeLuminance();
  final darker = first.computeLuminance() > second.computeLuminance()
      ? second.computeLuminance()
      : first.computeLuminance();
  return (lighter + .05) / (darker + .05);
}

void main() {
  testWidgets('renders a saved vibe as its own profile section', (
    tester,
  ) async {
    const vibe = 'Linkin Park · In the End · on repeat tonight';
    await _pumpCard(tester, _profile(vibe: vibe, bio: 'CEO.'));

    expect(find.byKey(const ValueKey('profile-vibe')), findsOneWidget);
    expect(find.text('VIBE'), findsOneWidget);
    expect(find.text(vibe), findsOneWidget);
    expect(find.text('CEO.'), findsOneWidget);
    expect(
      find.text('Add your vibe, bio or languages so people know you.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('vibe alone is a complete identity and remains visible at 200%', (
    tester,
  ) async {
    const longVibe =
        'Linkin Park - In the End https://youtu.be/eVTXPUF4Oz4 playing on repeat tonight!';
    expect(longVibe.length, 80, reason: 'exercise the editor field limit');
    await _pumpCard(tester, _profile(vibe: longVibe), width: 320, textScale: 2);

    expect(
      find.text('Linkin Park - In the End playing on repeat tonight!'),
      findsOneWidget,
    );
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('youtu.be'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-vibe')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long website alone stays bounded at 320px and 200%', (
    tester,
  ) async {
    const website =
        'https://yovoice.app/creators/a-very-long-profile-address-that-must-not-overflow';
    await _pumpCard(
      tester,
      _profile(website: website),
      width: 320,
      textScale: 2,
    );

    expect(find.text(website), findsOneWidget);
    expect(
      find.text('Add your vibe, bio or languages so people know you.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final entry in <(String, ThemeData)>[
    ('Dark', AppTheme.darkTheme),
    ('Pearl', AppTheme.lightTheme),
  ]) {
    testWidgets(
      '${entry.$1} gives Vibe and identity icons accessible contrast',
      (tester) async {
        const uri = 'https://youtu.be/eVTXPUF4Oz4';
        await _pumpCard(
          tester,
          _profile(
            vibe: 'Linkin Park - In the End $uri',
            bio: 'CEO.',
            country: 'Poland',
            website: 'yovoice.app',
            nativeLanguage: 'Polish',
            spokenLanguages: const ['English'],
            learningLanguages: const ['Japanese'],
          ),
          theme: entry.$2,
        );

        final vibeSurface = tester
            .widget<Material>(
              find.byKey(const ValueKey('profile-vibe-surface')),
            )
            .color!;
        final vibeLabel = tester
            .widget<Text>(find.byKey(const ValueKey('profile-vibe-label')))
            .style!
            .color!;
        final vibeIcon = tester
            .widget<Icon>(
              find.byKey(const ValueKey('profile-vibe-accent-icon')),
            )
            .color!;
        expect(
          _contrastRatio(vibeLabel, vibeSurface),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.$1} VIBE is small text, not decorative ink',
        );
        expect(_contrastRatio(vibeIcon, vibeSurface), greaterThanOrEqualTo(3));

        final linkSurface = tester
            .widget<Material>(
              find.byKey(const ValueKey('profile-vibe-link-surface-$uri')),
            )
            .color!;
        for (final key in const [
          'profile-vibe-link-leading-$uri',
          'profile-vibe-link-trailing-$uri',
        ]) {
          final icon = tester.widget<Icon>(find.byKey(ValueKey(key))).color!;
          expect(
            _contrastRatio(icon, linkSurface),
            greaterThanOrEqualTo(3),
            reason: '${entry.$1} link action icon $key',
          );
        }

        final iconColors = <Color>[];
        for (final label in const [
          'Poland',
          'yovoice.app',
          'Native: Polish',
          'English',
          'Learning Japanese',
        ]) {
          final container = tester.widget<Container>(
            find.byKey(ValueKey('profile-identity-chip-$label')),
          );
          final surface = (container.decoration! as BoxDecoration).color!;
          final icon = tester
              .widget<Icon>(
                find.byKey(ValueKey('profile-identity-chip-icon-$label')),
              )
              .color!;
          final text = tester.widget<Text>(find.text(label)).style!.color!;
          iconColors.add(icon);
          expect(
            _contrastRatio(icon, surface),
            greaterThanOrEqualTo(3),
            reason: '${entry.$1} $label icon',
          );
          expect(
            _contrastRatio(text, surface),
            greaterThanOrEqualTo(4.5),
            reason: '${entry.$1} $label text',
          );
        }
        expect(iconColors.toSet(), hasLength(3));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('${entry.$1} full identity stays complete at 320px and 200%', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _profile(
          vibe:
              'Linkin Park - In the End https://youtu.be/eVTXPUF4Oz4 playing tonight!',
          bio: 'CEO and independent voice creator.',
          country: 'Poland',
          website: 'yovoice.app',
          nativeLanguage: 'Polish',
          spokenLanguages: const ['English'],
          learningLanguages: const ['Japanese'],
        ),
        width: 320,
        textScale: 2,
        theme: entry.$2,
      );

      for (final label in const [
        'VIBE',
        'YouTube',
        'CEO and independent voice creator.',
        'Poland',
        'yovoice.app',
        'Native: Polish',
        'English',
        'Learning Japanese',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '${entry.$1}: $label');
      }
      final learning = tester.widget<Text>(find.text('Learning Japanese'));
      expect(learning.maxLines, 2);
      expect(learning.overflow, TextOverflow.visible);
      expect(tester.takeException(), isNull);
    });
  }
}
