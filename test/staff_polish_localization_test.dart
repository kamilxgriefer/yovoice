import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/screens/staff_center_screen.dart';
import 'package:yovoice/features/staff/presentation/screens/user_management_screen.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_section_shared.dart';
import 'package:yovoice/features/staff/presentation/staff_localized_copy.dart';
import 'package:yovoice/features/staff/presentation/widgets/room_staff_menu.dart';
import 'package:yovoice/features/staff/presentation/widgets/user_actions_menu.dart';

const _ownerCapabilities = StaffCapabilities(
  staffRole: 'superAdmin',
  isOwner: true,
  manageRoles: true,
  warnUsers: true,
  suspendUsers: true,
  liftSuspensions: true,
  permanentBan: true,
);

const _room = VoiceRoom(
  id: 'staff-polish-room',
  hostId: 'host',
  hostName: 'Ola',
  hostPhotoUrl: null,
  name: 'Wieczorne rozmowy',
  description: 'Rozmowa społeczności.',
  category: 'talk',
  visibility: 'public',
  language: 'Polish',
  maxParticipants: 50,
  participantCount: 2,
  memberCount: 2,
  isLive: true,
  roomType: RoomType.community,
  status: RoomStatus.active,
  imageUrl: null,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: false,
  membersCanStartVoice: false,
  createdAt: null,
  updatedAt: null,
);

class _Capabilities extends StaffCapabilityService {
  _Capabilities(this.value);

  final StaffCapabilities value;

  @override
  Future<StaffCapabilities> load({bool refresh = false}) async => value;
}

class _Lookup implements StaffUserLookup {
  @override
  Future<ManagedUser?> lookup(String rawInput) async => const ManagedUser(
    uid: 'staff-polish-user',
    displayName: '',
    username: 'tester',
    role: 'user',
    banned: false,
    isVip: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _polishApp(Widget home) => MaterialApp(
  locale: const Locale('pl'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

void _useDesktopSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test('Staff count and identifier labels use Polish grammar', () {
    const copy = AppLocalizations(Locale('pl'));

    expect(localizedStaffParticipantCount(copy, 1), '1 osoba w pokoju');
    expect(localizedStaffParticipantCount(copy, 2), '2 osoby w pokoju');
    expect(localizedStaffParticipantCount(copy, 5), '5 osób w pokoju');
    expect(localizedStaffResultCount(copy, 12), '12 wyników');
    expect(
      localizedStaffResultCount(copy, 22, moreAvailable: true),
      '22 wyniki — dostępne są kolejne',
    );
    expect(localizedStaffRole(copy, 'superModerator'), 'Supermoderator');
    expect(localizedStaffStatus(copy, 'BANNED'), 'ZABLOKOWANE');
    expect(
      localizedStaffAuditAction(copy, 'force_end_room'),
      'Wymuszone zakończenie pokoju',
    );
  });

  testWidgets('shared Staff states expose Polish actions and status', (
    tester,
  ) async {
    await tester.pumpWidget(
      _polishApp(
        Scaffold(
          body: Column(
            children: [
              StaffErrorState(
                message: 'Błąd połączenia.',
                onRetry: () {},
                onClear: () {},
              ),
              const AccountStatusChip(status: 'BANNED'),
              const StaffOfficialRoleBadge(role: 'superAdmin'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Spróbuj ponownie'), findsOneWidget);
    expect(find.text('Wyczyść'), findsOneWidget);
    expect(find.text('ZABLOKOWANE'), findsOneWidget);
    expect(find.text('WŁAŚCICIEL · SUPERADMINISTRATOR'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('user and sanction actions are fully localized in Polish', (
    tester,
  ) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(
      _polishApp(
        const Scaffold(
          body: UserActionsMenu(
            targetUid: 'target',
            targetName: 'Ola',
            currentUid: 'owner',
            capabilities: _ownerCapabilities,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Zgłoś użytkownika'), findsOneWidget);
    expect(find.text('Zablokuj użytkownika'), findsOneWidget);
    expect(find.text('Wycisz dla mnie'), findsOneWidget);
    expect(find.text('Wycisz komunikację…'), findsOneWidget);
    expect(find.text('Zablokuj trwale…'), findsOneWidget);
    expect(find.text('Report user'), findsNothing);

    await tester.tap(find.text('Wycisz komunikację…'));
    await tester.pumpAndSettle();

    expect(find.text('Wycisz komunikację — Ola'), findsOneWidget);
    expect(find.text('Użytkownik: Ola'), findsOneWidget);
    expect(
      find.text('Zakres: komunikacja publiczna na całej platformie.'),
      findsOneWidget,
    );
    expect(find.text('Powód (wymagany)'), findsOneWidget);
    expect(find.text('Czas trwania'), findsOneWidget);
    expect(find.text('1 godzina'), findsOneWidget);
    expect(find.text('Apply mute'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('room Staff menu and confirmation are localized in Polish', (
    tester,
  ) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(
      _polishApp(
        const Scaffold(
          body: RoomStaffMenu(
            room: _room,
            capabilities: StaffCapabilities(
              staffRole: 'superAdmin',
              isOwner: true,
              endAnyRoom: true,
              quarantineSpaces: true,
              permanentDeleteSpaces: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Działania zespołu'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.shield_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Zakończ pokój…'), findsOneWidget);
    expect(find.text('Poddaj kwarantannie…'), findsOneWidget);
    expect(find.text('Usuń trwale…'), findsOneWidget);

    await tester.tap(find.text('Poddaj kwarantannie…'));
    await tester.pumpAndSettle();

    expect(
      find.text('Poddaj pokój „Wieczorne rozmowy” kwarantannie?'),
      findsOneWidget,
    );
    expect(find.text('Powód (wymagany)'), findsOneWidget);
    expect(find.text('Anuluj'), findsOneWidget);
    expect(find.text('Quarantine'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('User Management localizes fallback identity and role controls', (
    tester,
  ) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(
      _polishApp(
        UserManagementScreen(
          lookup: _Lookup(),
          capabilityService: _Capabilities(_ownerCapabilities),
          currentUid: 'owner',
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'tester');
    await tester.tap(find.text('Wyszukaj'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Zarządzanie użytkownikami'), findsOneWidget);
    expect(find.text('Użytkownik YO Voice'), findsOneWidget);
    expect(find.text('@tester'), findsOneWidget);
    expect(find.text('ROLA: UŻYTKOWNIK'), findsOneWidget);
    expect(find.text('Przypisz rolę'), findsOneWidget);
    expect(find.text('Użytkownik (bez roli zespołu)'), findsOneWidget);
    expect(find.text('Supermoderator'), findsOneWidget);
    expect(find.text('User Management'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied Staff Center explains access in Polish', (tester) async {
    await tester.pumpWidget(
      _polishApp(
        StaffCenterScreen(
          capabilityService: _Capabilities(StaffCapabilities.none),
          currentUid: 'ordinary-user',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Centrum zespołu'), findsWidgets);
    expect(
      find.textContaining(
        'Centrum zespołu jest dostępne wyłącznie dla właściciela aplikacji',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('reserved for the application owner'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
