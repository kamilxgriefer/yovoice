import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/discover/presentation/screens/discover_screen.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

class _RoomsService extends RoomService {
  _RoomsService(this.stream)
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true),
      );

  final Stream<List<VoiceRoom>> stream;

  @override
  Stream<List<VoiceRoom>> watchLivePublicRooms() => stream;
}

void main() {
  test('mobile roots retain content IDs and use the new visual order', () {
    const visualOrder = [0, 3, 1, 5];
    expect(visualOrder.map(MainShell.mobileIndexFor), visualOrder);
    expect(visualOrder.map(MainShell.mobileNavigationOrder), [0, 1, 2, 3]);
    expect(MainShell.mobileIndexFor(2), 2, reason: 'Friends stays reachable');
    for (final desktopOnly in [4, 6, 7, 8, 9, 10, 11, 12]) {
      expect(MainShell.mobileIndexFor(desktopOnly), 0);
    }
  });

  for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
    for (final phase in ['loading', 'empty', 'error']) {
      testWidgets(
        'Rooms Create CTA works during $phase, ${theme.brightness}, 320px/200%',
        (tester) async {
          tester.view.physicalSize = const Size(320, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final rooms = StreamController<List<VoiceRoom>>();
          addTearDown(rooms.close);
          final createKey = GlobalKey();
          var creates = 0;

          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              locale: const Locale('pl'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: DiscoverScreen(
                isRootTab: true,
                asRoomsDestination: true,
                onCreateRoom: () => creates++,
                createRoomKey: createKey,
                roomService: _RoomsService(rooms.stream),
              ),
            ),
          );
          if (phase == 'empty') rooms.add([]);
          if (phase == 'error') rooms.addError(StateError('offline'));
          await tester.pump();
          await tester.pump();

          expect(find.text('Pokoje'), findsOneWidget);
          expect(find.text('Utwórz pokój'), findsOneWidget);
          expect(find.byKey(createKey), findsOneWidget);
          expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
          expect(
            tester.getSize(find.byKey(createKey)).height,
            greaterThanOrEqualTo(48),
          );
          await tester.ensureVisible(find.byKey(createKey));
          await tester.tap(find.byKey(createKey));
          expect(creates, 1);
          if (phase == 'error') {
            // At 200% the header intentionally occupies the first viewport;
            // the error sliver is built only when the user scrolls to it.
            await tester.drag(
              find.byType(CustomScrollView),
              const Offset(0, -450),
            );
            await tester.pump();
            expect(find.text('Nie udało się wczytać pokojów'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'desktop discovery keeps its name and does not add duplicate Create',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: DiscoverScreen(
            isRootTab: true,
            roomService: _RoomsService(Stream.value([])),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('Create room'), findsNothing);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
