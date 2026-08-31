import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';

void main() {
  for (final theme in <ThemeData>[AppTheme.darkTheme, AppTheme.lightTheme]) {
    testWidgets(
      '${theme.brightness.name} Home gradient actions keep AA copy and focus',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  MobilePremiumCard(onCheckPlans: () {}),
                  const SizedBox(height: 16),
                  HomeRoomBanner(room: _room, compact: true, onJoin: (_) {}),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        final scheme = theme.colorScheme;
        final actions = <Finder>[
          find.byKey(const ValueKey('home-premium-check-plans')),
          find.byKey(const ValueKey('home-room-join')),
        ];

        for (final action in actions) {
          expect(action, findsOneWidget);
          expect(tester.widget<YoButton>(action).onPressed, isNotNull);
          final painted = find.descendant(
            of: action,
            matching: find.byType(AnimatedContainer),
          );
          final decoration =
              tester.widget<AnimatedContainer>(painted).decoration!
                  as BoxDecoration;
          expect(decoration.gradient!.colors, [
            scheme.primary,
            scheme.secondary,
          ]);
          final label = tester.widget<Text>(
            find.descendant(of: action, matching: find.byType(Text)),
          );
          expect(label.style!.color, scheme.onPrimary);
          for (final stop in decoration.gradient!.colors) {
            expect(
              _contrast(scheme.onPrimary, stop),
              greaterThanOrEqualTo(4.5),
            );
          }
        }

        for (final action in actions) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final painted = find.descendant(
            of: action,
            matching: find.byType(AnimatedContainer),
          );
          final decoration =
              tester.widget<AnimatedContainer>(painted).decoration!
                  as BoxDecoration;
          final border = decoration.border! as Border;
          expect(border.top.color, scheme.onPrimary);
          expect(border.top.width, 2);
          for (final stop in decoration.gradient!.colors) {
            expect(_contrast(border.top.color, stop), greaterThanOrEqualTo(3));
          }
        }

        expect(tester.takeException(), isNull);
      },
    );
  }
}

const _room = VoiceRoom(
  id: 'room-a11y',
  hostId: 'host',
  hostName: 'Host',
  hostPhotoUrl: null,
  name: 'Design review',
  description: 'A focused conversation.',
  category: 'talk',
  visibility: 'public',
  language: 'English',
  maxParticipants: null,
  participantCount: 3,
  memberCount: 3,
  isLive: true,
  roomType: RoomType.community,
  status: RoomStatus.active,
  imageUrl: null,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: false,
  membersCanStartVoice: true,
  createdAt: null,
  updatedAt: null,
);

double _contrast(Color first, Color second) {
  final light = first.computeLuminance() > second.computeLuminance()
      ? first
      : second;
  final dark = identical(light, first) ? second : first;
  return (light.computeLuminance() + .05) / (dark.computeLuminance() + .05);
}
