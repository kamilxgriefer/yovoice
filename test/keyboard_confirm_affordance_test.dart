import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_settings_screen.dart';
import 'package:yovoice/features/clubs/presentation/screens/create_club_screen.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/models/room_metadata.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/sheets/settings_sheet.dart';
import 'package:yovoice/features/rooms/presentation/screens/create_room_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_settings_screen.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/screens/staff_center_screen.dart';
import 'package:yovoice/shared/widgets/inputs/yo_keyboard_done_bar.dart';

import 'voice_moment_test_doubles.dart';

/// `ClubSettingsScreen` resolves its own services, which reach for
/// `Firebase.app()` while the State is constructed. The delegates below are
/// created lazily and never called by these tests, so a bare platform fake is
/// all that is needed — the same approach as test/auth_link_tap_target_test.
class _NoStaffCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

class _FakeFirebaseApp extends FirebaseAppPlatform {
  _FakeFirebaseApp()
    : super(
        defaultFirebaseAppName,
        const FirebaseOptions(
          apiKey: 'test-api-key',
          appId: 'test-app-id',
          messagingSenderId: 'test-sender-id',
          projectId: 'test-project-id',
          // ClubSettingsScreen resolves its own ClubService, which asks for
          // FirebaseStorage.instance; that refuses an app with no bucket.
          storageBucket: 'test-bucket',
        ),
      );
}

class _FakeFirebasePlatform extends FirebasePlatform {
  final _app = _FakeFirebaseApp();

  @override
  List<FirebaseAppPlatform> get apps => [_app];

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _app;

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async => _app;
}

/// One contract, checked on every screen that owns a text field: while the
/// keyboard is up there is always a visible way to finish typing, and the
/// screen's primary action is never stranded behind the keyboard.
///
/// The maintainer's report was about the Voice Moment caption — Return only
/// added a line break, Publish fell off the bottom of the screen, and the
/// only escape was an undiscoverable drag. These tests pin the fix and the
/// same guarantee on every sibling form.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Use the shipped typeface for responsive measurements; Ahem's square
    // glyphs can invent width failures that the actual interface does not have.
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    FirebasePlatform.instance = _FakeFirebasePlatform();
    await Firebase.initializeApp();
  });

  const phone = Size(390, 844);
  const small = Size(320, 568);

  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host(
    Widget child, {
    double textScale = 1,
    EdgeInsets viewInsets = EdgeInsets.zero,
    ThemeData? theme,
    Locale locale = const Locale('en'),
  }) {
    return MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: viewInsets,
        ),
        child: inner!,
      ),
      home: child,
    );
  }

  final doneBar = find.byKey(const ValueKey('yo-keyboard-done-bar'));
  final doneButton = find.byKey(const ValueKey('yo-keyboard-done'));

  bool focusIsEditable() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  // ------------------------------------------------------ Record a Moment

  ({FakeStopwatch clock, StubMomentService service, Widget screen}) recorder() {
    final backend = FakeRecorderBackend();
    final capture = FakeAudioCapture()..result = FakeRecordedAudio();
    final service = StubMomentService();
    final clock = FakeStopwatch();
    final preview = FakePreviewAudioPlayer();
    return (
      clock: clock,
      service: service,
      screen: RecordVoiceMomentScreen(
        recorder: VoiceMomentRecorder(
          backend: backend,
          capture: capture,
          clock: clock,
        ),
        momentService: service,
        previewPlayerFactory: () => preview,
      ),
    );
  }

  Future<void> recordFor(WidgetTester tester, FakeStopwatch clock) async {
    final microphone = find.byIcon(Icons.mic_rounded);
    await tester.ensureVisible(microphone);
    await tester.pump();
    await tester.tap(microphone);
    await tester.pump();
    await tester.pump();
    clock.value = const Duration(seconds: 6);
    await tester.pump(const Duration(milliseconds: 200));
    final stop = find.byIcon(Icons.stop_rounded);
    await tester.ensureVisible(stop);
    await tester.pump();
    await tester.tap(stop);
    await tester.pump();
    await tester.pump();
  }

  group('Record a Voice Moment — the reported screen', () {
    for (final (label, size, inset) in <(String, Size, double)>[
      ('390x844', phone, 336),
      ('320x568', small, 300),
    ]) {
      testWidgets('$label: Done and Publish both ride above the keyboard, and '
          'Done restores the pinned footer', (tester) async {
        useSurface(tester, size);
        final harness = recorder();
        await tester.pumpWidget(host(harness.screen));
        await tester.pumpAndSettle();
        await recordFor(tester, harness.clock);

        // At rest the footer is pinned, as it always was.
        expect(
          find.byKey(const ValueKey('voice-moment-review-action-bar')),
          findsOneWidget,
        );
        expect(doneBar, findsNothing);

        final caption = find.byKey(const ValueKey('voice-moment-caption'));
        await tester.ensureVisible(caption);
        await tester.pumpAndSettle();
        await tester.tap(caption);
        await tester.enterText(caption, 'halooo');
        await tester.pumpWidget(
          host(harness.screen, viewInsets: EdgeInsets.only(bottom: inset)),
        );
        await tester.pumpAndSettle();

        // The confirm affordance is visible…
        expect(doneBar, findsOneWidget);
        expect(find.text('Done'), findsOneWidget);
        // …and so is the screen's primary action, docked next to it. The
        // in-body copy is gone, so a screen reader meets Publish once.
        final docked = find.byKey(
          const ValueKey('voice-moment-docked-publish'),
        );
        expect(docked, findsOneWidget);
        expect(find.text('Publish'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('voice-moment-review-action-bar')),
          findsNothing,
        );
        // Both sit above the keyboard, not behind it.
        final keyboardTop = size.height - inset;
        expect(tester.getRect(doneBar).bottom, lessThanOrEqualTo(keyboardTop));
        expect(tester.getRect(docked).bottom, lessThanOrEqualTo(keyboardTop));
        expect(
          tester.getSize(docked).height,
          greaterThanOrEqualTo(44),
          reason: 'docs/UI.md sets a 44 px floor',
        );

        // Finishing keeps what was typed and brings the footer back.
        await tester.tap(doneButton);
        await tester.pump();
        expect(focusIsEditable(), isFalse);
        await tester.pumpWidget(host(harness.screen));
        await tester.pumpAndSettle();
        expect(find.text('halooo'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('voice-moment-review-action-bar')),
          findsOneWidget,
        );
        expect(doneBar, findsNothing);
        expect(harness.service.publishCalls, 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Return confirms the caption instead of adding a line break', (
      tester,
    ) async {
      useSurface(tester, phone);
      final harness = recorder();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock);

      final caption = find.byKey(const ValueKey('voice-moment-caption'));
      final field = tester.widget<TextField>(caption);
      // A 140-character caption is a label, not prose: the platform must
      // draw a confirm key rather than a newline arrow.
      expect(field.textInputAction, TextInputAction.done);
      expect(field.keyboardType, TextInputType.text);

      await tester.ensureVisible(caption);
      await tester.pumpAndSettle();
      await tester.tap(caption);
      await tester.enterText(caption, 'halooo');
      await tester.pump();
      expect(focusIsEditable(), isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(focusIsEditable(), isFalse);
      final editable = tester.widget<EditableText>(
        find.descendant(of: caption, matching: find.byType(EditableText)),
      );
      expect(editable.controller.text, 'halooo');
      expect(editable.controller.text.contains('\n'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 200% text the bar stays Done-only and the actions stay in '
        'the scroll', (tester) async {
      useSurface(tester, small);
      final harness = recorder();
      await tester.pumpWidget(host(harness.screen, textScale: 2));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock);

      final caption = find.byKey(const ValueKey('voice-moment-caption'));
      await tester.ensureVisible(caption);
      await tester.pumpAndSettle();
      await tester.tap(caption);
      await tester.pumpWidget(
        host(
          harness.screen,
          textScale: 2,
          viewInsets: const EdgeInsets.only(bottom: 300),
        ),
      );
      await tester.pumpAndSettle();

      expect(doneBar, findsOneWidget);
      // Enlarged text needs the whole row for Done; Publish keeps its full
      // label in the scroll rather than being squeezed onto the bar.
      expect(
        find.byKey(const ValueKey('voice-moment-docked-publish')),
        findsNothing,
      );
      expect(find.text('Publish'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a hardware keyboard reports no inset, so no bar appears', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 900));
      final harness = recorder();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock);

      final caption = find.byKey(const ValueKey('voice-moment-caption'));
      await tester.ensureVisible(caption);
      await tester.pumpAndSettle();
      await tester.tap(caption);
      await tester.pumpAndSettle();

      // Focused, no software keyboard: the screen's own resting chrome is
      // already visible, so nothing is added.
      expect(doneBar, findsNothing);
      expect(
        find.byKey(const ValueKey('voice-moment-review-action-bar')),
        findsOneWidget,
      );
      // The desk keyboard's Return still confirms the caption.
      await tester.enterText(caption, 'typed on a desk keyboard');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(focusIsEditable(), isFalse);
      expect(find.text('typed on a desk keyboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------------ Create room

  group('Create room', () {
    testWidgets('the description keeps line breaks, and Continue stays above '
        'the keyboard with Done', (tester) async {
      useSurface(tester, phone);
      await tester.pumpWidget(host(const CreateRoomScreen()));
      await tester.pumpAndSettle();

      final description = find.byType(TextFormField).at(1);
      final field = tester.widget<EditableText>(
        find.descendant(of: description, matching: find.byType(EditableText)),
      );
      // Prose field: Return is deliberately still a line break.
      expect(field.maxLines, 3);
      expect(field.textInputAction, isNull);

      await tester.ensureVisible(description);
      await tester.pumpAndSettle();
      await tester.tap(description);
      await tester.enterText(description, 'Line one\nLine two');
      await tester.pumpWidget(
        host(
          const CreateRoomScreen(),
          viewInsets: const EdgeInsets.only(bottom: 336),
        ),
      );
      await tester.pumpAndSettle();

      expect(doneBar, findsOneWidget);
      // The step's primary action is pinned in the same bottom slot, so it
      // is never behind the keyboard.
      expect(find.text('Continue'), findsOneWidget);
      expect(
        tester.getRect(find.text('Continue')).bottom,
        lessThanOrEqualTo(phone.height - 336),
      );

      await tester.tap(doneButton);
      await tester.pump();
      expect(focusIsEditable(), isFalse);
      expect(find.text('Line one\nLine two'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the room name declares a next key so Return walks the form', (
      tester,
    ) async {
      useSurface(tester, phone);
      await tester.pumpWidget(host(const CreateRoomScreen()));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byType(TextFormField).first,
                matching: find.byType(EditableText),
              ),
            )
            .textInputAction,
        TextInputAction.next,
      );
    });
  });

  // ---------------------------------------------------------- Room settings

  group('Room settings', () {
    const room = VoiceRoom(
      id: 'room-1',
      hostId: 'host',
      hostName: 'Host',
      hostPhotoUrl: null,
      name: 'Community room',
      description: 'Room description',
      category: 'talk',
      visibility: 'public',
      language: 'English',
      maxParticipants: 25,
      participantCount: 1,
      memberCount: 1,
      isLive: false,
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

    testWidgets('SAVE stays in the app bar while the description is edited', (
      tester,
    ) async {
      useSurface(tester, phone);
      await tester.pumpWidget(host(RoomSettingsScreen(room: room)));
      await tester.pumpAndSettle();

      final description = find.widgetWithText(TextFormField, 'Description');
      await tester.ensureVisible(description);
      await tester.pumpAndSettle();
      await tester.tap(description);
      await tester.enterText(description, 'A room\nwith two lines');
      await tester.pumpWidget(
        host(
          RoomSettingsScreen(room: room),
          viewInsets: const EdgeInsets.only(bottom: 336),
        ),
      );
      await tester.pumpAndSettle();

      expect(doneBar, findsOneWidget);
      // The primary action is an app-bar action: above the keyboard by
      // construction, and above the field being edited.
      expect(find.text('SAVE'), findsOneWidget);
      expect(tester.getRect(find.text('SAVE')).bottom, lessThan(120));

      await tester.tap(doneButton);
      await tester.pump();
      expect(focusIsEditable(), isFalse);
      expect(find.text('A room\nwith two lines'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ----------------------------------------------------------- Edit profile

  group('Edit profile', () {
    UserProfile seed() => UserProfile(
      uid: 'me',
      email: 'me@yovoice.app',
      displayName: 'Tester',
      username: 'tester',
      bio: 'old bio',
      country: '',
      nativeLanguage: '',
      spokenLanguages: const [],
      learningLanguages: const [],
      photoUrl: null,
      bannerUrl: null,
      website: '',
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

    Widget screen() {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'me'),
      );
      return EditProfileScreen(
        profile: seed(),
        service: ProfileService(
          firestore: db,
          auth: auth,
          storage: MockFirebaseStorage(),
        ),
        entitlements: EntitlementService(firestore: db, auth: auth),
      );
    }

    testWidgets('the bio keeps line breaks; Save stays in the app bar and '
        'Done sits on the keyboard', (tester) async {
      useSurface(tester, phone);
      await tester.pumpWidget(host(screen()));
      await tester.pumpAndSettle();

      final bio = find.widgetWithText(TextFormField, 'Bio');
      await tester.ensureVisible(bio);
      await tester.pumpAndSettle();
      await tester.tap(bio);
      await tester.enterText(bio, 'First line\nSecond line');
      await tester.pumpWidget(
        host(screen(), viewInsets: const EdgeInsets.only(bottom: 336)),
      );
      await tester.pumpAndSettle();
      final field = find.widgetWithText(
        TextFormField,
        'First line\nSecond line',
      );
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();

      expect(doneBar, findsOneWidget);
      expect(
        tester.getRect(doneBar).bottom,
        lessThanOrEqualTo(phone.height - 336),
      );
      expect(find.text('Save'), findsOneWidget);
      expect(tester.getRect(find.text('Save')).bottom, lessThan(120));

      await tester.tap(doneButton);
      await tester.pump();
      expect(focusIsEditable(), isFalse);
      expect(find.text('First line\nSecond line'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('single-line identity fields declare a next key', (
      tester,
    ) async {
      useSurface(tester, phone);
      await tester.pumpWidget(host(screen()));
      await tester.pumpAndSettle();
      final displayName = find.widgetWithText(TextFormField, 'Display name');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: displayName,
                matching: find.byType(EditableText),
              ),
            )
            .textInputAction,
        TextInputAction.next,
      );
      // The bio deliberately keeps the newline action.
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.widgetWithText(TextFormField, 'Bio'),
                matching: find.byType(EditableText),
              ),
            )
            .textInputAction,
        isNull,
      );
    });
  });

  // ------------------------------------------------------------ Create club

  group('Create club', () {
    Widget screen() => CreateClubScreen(
      clubService: ClubService(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
        storage: MockFirebaseStorage(),
      ),
    );

    for (final size in [small, phone]) {
      for (final locale in [const Locale('en'), const Locale('pl')]) {
        testWidgets(
          'media cards grow with 200% text at ${size.width} $locale',
          (tester) async {
            useSurface(tester, size);
            await tester.pumpWidget(
              host(screen(), textScale: 2, locale: locale),
            );
            await tester.pumpAndSettle();
            final copy = AppLocalizations(locale);
            final avatar = find.text(copy.text('Club avatar', 'Avatar klubu'));
            await tester.scrollUntilVisible(avatar, 180);
            await tester.pumpAndSettle();
            for (final label in [
              avatar,
              find.text(copy.text('Club banner', 'Baner klubu')),
            ]) {
              final card = find.ancestor(
                of: label,
                matching: find.byType(InkWell),
              );
              final helper = find.descendant(
                of: card,
                matching: find.text(
                  copy.text('Choose image', 'Wybierz zdjęcie'),
                ),
              );
              expect(tester.getRect(card).height, greaterThanOrEqualTo(150));
              expect(
                tester.getRect(helper).bottom,
                lessThanOrEqualTo(tester.getRect(card).bottom),
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('Create Club stays above the keyboard while the description '
        'is written', (tester) async {
      useSurface(tester, phone);
      await tester.pumpWidget(host(screen()));
      await tester.pumpAndSettle();

      final description = find.widgetWithText(TextFormField, 'Description');
      await tester.ensureVisible(description);
      await tester.pumpAndSettle();
      await tester.tap(description);
      await tester.enterText(description, 'Two\nlines');
      await tester.pumpWidget(
        host(screen(), viewInsets: const EdgeInsets.only(bottom: 336)),
      );
      await tester.pumpAndSettle();

      expect(doneBar, findsOneWidget);
      final cta = find.byKey(const ValueKey('space-identity-create-cta'));
      expect(cta, findsOneWidget);
      expect(
        tester.getRect(cta).bottom,
        lessThanOrEqualTo(phone.height - 336),
        reason: 'the create action must not sit behind the keyboard',
      );
      expect(
        tester.getRect(doneBar).bottom,
        lessThanOrEqualTo(phone.height - 336),
      );

      await tester.tap(doneButton);
      await tester.pump();
      expect(focusIsEditable(), isFalse);
      expect(find.text('Two\nlines'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // --------------------------------------------------- Podcast settings sheet

  group('Podcast settings sheet', () {
    const room = VoiceRoom(
      id: 'podcast-1',
      hostId: 'host',
      hostName: 'Host',
      hostPhotoUrl: null,
      name: 'The Show',
      description: 'An episode',
      category: 'talk',
      visibility: 'public',
      language: 'English',
      maxParticipants: 50,
      participantCount: 1,
      memberCount: 1,
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

    for (final size in [small, phone]) {
      for (final locale in [const Locale('en'), const Locale('pl')]) {
        testWidgets('format choices fit 200% text at ${size.width} $locale', (
          tester,
        ) async {
          useSurface(tester, size);
          final service = RoomService(
            firestore: FakeFirebaseFirestore(),
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'host'),
            ),
          );
          await tester.pumpWidget(
            host(
              Scaffold(
                body: BroadcastSettingsSheet(room: room, service: service),
              ),
              textScale: 2,
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          final format = find.byType(DropdownButtonFormField<ShowFormat>);
          await tester.ensureVisible(format);
          await tester.pumpAndSettle();
          final dropdown = tester.widget<DropdownButtonFormField<ShowFormat>>(
            format,
          );
          // Exercise every long choice in the actual bounded field, not
          // only the short initial "Solo" label.
          for (final value in ShowFormat.values) {
            dropdown.onChanged!(value);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$locale $value');
          }
          await tester.tap(format);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'expanded menu $locale',
          );
        });
      }
    }

    testWidgets('Update podcast is pinned under the Done bar instead of '
        'sitting at the end of the scroll', (tester) async {
      useSurface(tester, phone);
      final service = RoomService(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'host')),
      );
      final opener = Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) =>
                    BroadcastSettingsSheet(room: room, service: service),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(opener));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final update = find.byKey(const ValueKey('podcast-settings-update'));
      expect(update, findsOneWidget);

      final description = find.widgetWithText(TextField, 'Episode description');
      await tester.ensureVisible(description);
      await tester.pumpAndSettle();
      await tester.tap(description);
      await tester.enterText(description, 'Episode\nnotes');
      // The sheet lives in its own route and pads itself by the keyboard
      // inset; the route keeps its state across this rebuild.
      await tester.pumpWidget(
        host(opener, viewInsets: const EdgeInsets.only(bottom: 336)),
      );
      await tester.pumpAndSettle();

      expect(doneBar, findsOneWidget);
      expect(
        tester.getRect(doneBar).bottom,
        lessThanOrEqualTo(phone.height - 336),
      );
      expect(
        tester.getRect(update).bottom,
        lessThanOrEqualTo(phone.height - 336),
        reason: 'Update must stay above the keyboard, not below the scroll',
      );

      await tester.tap(doneButton);
      await tester.pump();
      expect(focusIsEditable(), isFalse);
      expect(find.text('Episode\nnotes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------- Moderation Center

  group('Moderation Center', () {
    for (final size in [small, phone]) {
      for (final textScale in [1.0, 2.0]) {
        testWidgets('the internal note stays visible at ${size.width} x$textScale', (
          tester,
        ) async {
          useSurface(tester, size);
          final keyboardHeight = size == small ? 300.0 : 336.0;
          final db = FakeFirebaseFirestore();
          await db.collection('users').doc('mod').set(<String, dynamic>{
            'uid': 'mod',
            'displayName': 'Mod',
            'role': 'moderator',
          });
          await db.collection('reports').doc('r1').set(<String, dynamic>{
            'reporterId': 'reporter',
            'targetType': 'globalMessage',
            'targetId': 'msg-1',
            'reportedUserId': 'author',
            'contextPath': 'globalChat/main/messages/msg-1',
            'reason': 'harassment',
            'note': '',
            'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
            'status': 'open',
          });
          final service = ModerationService(
            firestore: db,
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(
                uid: 'mod',
                email: 'mod@yovoice.app',
                displayName: 'Mod',
                customClaim: const {'role': 'moderator'},
              ),
            ),
          );

          final screen = ModerationCenterScreen(moderationService: service);
          await tester.pumpWidget(host(screen, textScale: textScale));
          // The queue's avatars keep an indeterminate placeholder animating, so
          // this screen never "settles"; bounded pumps are what its own suite
          // uses too.
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 120));
          }

          // Open the report so its detail — and the internal note — is on screen.
          await tester.tap(find.text('Harassment or bullying').last);
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 120));
          }

          final note = find.widgetWithText(
            TextField,
            'Internal note (optional)',
          );
          await tester.scrollUntilVisible(
            note,
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump();
          await tester.tap(note);
          await tester.enterText(note, 'Checked the thread');
          await tester.pumpWidget(
            host(
              screen,
              textScale: textScale,
              viewInsets: EdgeInsets.only(bottom: keyboardHeight),
            ),
          );
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 120));
          }

          expect(doneBar, findsOneWidget);
          expect(
            tester.getRect(doneBar).bottom,
            lessThanOrEqualTo(size.height - keyboardHeight),
          );
          final editor = find.descendant(
            of: note,
            matching: find.byType(EditableText),
          );
          expect(tester.getRect(editor).top, greaterThanOrEqualTo(56));
          expect(
            tester.getRect(editor).bottom,
            lessThanOrEqualTo(tester.getRect(doneBar).top),
            reason:
                'the focused editor, not only Done, must stay above the keyboard',
          );
          expect(tester.takeException(), isNull);

          await tester.tap(doneButton);
          await tester.pump();
          expect(focusIsEditable(), isFalse);
          expect(find.text('Checked the thread'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(host(screen, textScale: textScale));
          await tester.pump(const Duration(milliseconds: 200));
          final back = find.byTooltip('Back to the queue');
          await tester.scrollUntilVisible(
            back,
            -180,
            scrollable: find.byType(Scrollable).first,
          );
          // End the drag's ballistic phase before tapping the queue action.
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
          expect(back.hitTestable(), findsOneWidget);
          await tester.tap(back);
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
          expect(find.byTooltip('Back to the queue'), findsNothing);
          expect(find.text('Harassment or bullying'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  // ----------------------------------------------------------- Club settings

  group('Club settings', () {
    final club = Club(
      id: 'club-1',
      name: 'Founders',
      description: 'A club',
      ownerId: 'someone-else',
      ownerName: 'Owner',
      avatarUrl: null,
      bannerUrl: null,
      privacy: ClubPrivacy.public,
      defaultLanguage: 'English',
      memberCount: 3,
      onlineCount: 1,
      defaultChatChannelId: 'chat',
      defaultVoiceChannelId: 'voice',
      announcementChannelId: 'news',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    testWidgets('SAVE moved into the app bar, where the keyboard cannot '
        'bury it', (tester) async {
      useSurface(tester, phone);
      await tester.pumpWidget(host(ClubSettingsScreen(club: club)));
      await tester.pumpAndSettle();

      final description = find.widgetWithText(TextField, 'Description');
      await tester.ensureVisible(description);
      await tester.pumpAndSettle();
      await tester.tap(description);
      await tester.enterText(description, 'Club\nrules');
      await tester.pumpWidget(
        host(
          ClubSettingsScreen(club: club),
          viewInsets: const EdgeInsets.only(bottom: 336),
        ),
      );
      await tester.pumpAndSettle();

      expect(doneBar, findsOneWidget);
      expect(
        tester.getRect(doneBar).bottom,
        lessThanOrEqualTo(phone.height - 336),
      );
      final save = find.byKey(const ValueKey('club-settings-appbar-save'));
      expect(save, findsOneWidget);
      expect(tester.getRect(save).bottom, lessThan(120));

      await tester.tap(doneButton);
      await tester.pump();
      expect(focusIsEditable(), isFalse);
      expect(find.text('Club\nrules'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------- widths and text scales

  group('the contract holds at every width and text scale', () {
    for (final (label, size, scale) in <(String, Size, double)>[
      ('320 at 100%', Size(320, 568), 1.0),
      ('320 at 200%', Size(320, 568), 2.0),
      ('390 at 100%', Size(390, 844), 1.0),
      ('390 at 200%', Size(390, 844), 2.0),
      ('430 at 100%', Size(430, 932), 1.0),
      ('768 at 100%', Size(768, 1024), 1.0),
      ('768 at 200%', Size(768, 1024), 2.0),
      ('1440 at 100%', Size(1440, 900), 1.0),
    ]) {
      testWidgets('$label: Create room keeps Continue and Done above the '
          'keyboard', (tester) async {
        useSurface(tester, size);
        final inset = size.height * .4;
        await tester.pumpWidget(
          host(const CreateRoomScreen(), textScale: scale),
        );
        await tester.pumpAndSettle();

        final description = find.byType(TextFormField).at(1);
        await tester.ensureVisible(description);
        await tester.pumpAndSettle();
        await tester.tap(description);
        await tester.pumpWidget(
          host(
            const CreateRoomScreen(),
            textScale: scale,
            viewInsets: EdgeInsets.only(bottom: inset),
          ),
        );
        await tester.pumpAndSettle();

        final keyboardTop = size.height - inset;
        expect(doneBar, findsOneWidget);
        expect(tester.getRect(doneBar).bottom, lessThanOrEqualTo(keyboardTop));
        expect(
          tester.getRect(find.text('Continue')).bottom,
          lessThanOrEqualTo(keyboardTop),
        );
        expect(
          tester.getSize(doneButton).height,
          greaterThanOrEqualTo(44),
          reason: 'docs/UI.md sets a 44 px floor',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ------------------------------------------------------------ the wiring

  group('every form with a long-form field carries the bar', () {
    testWidgets('Create room, Room settings', (tester) async {
      useSurface(tester, phone);
      await tester.pumpWidget(host(const CreateRoomScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(YoKeyboardDoneBar), findsOneWidget);

      await tester.pumpWidget(
        host(
          RoomSettingsScreen(
            room: VoiceRoom(
              id: 'r',
              hostId: 'h',
              hostName: 'H',
              hostPhotoUrl: null,
              name: 'R',
              description: '',
              category: 'talk',
              visibility: 'public',
              language: 'English',
              maxParticipants: 25,
              participantCount: 1,
              memberCount: 1,
              isLive: false,
              roomType: RoomType.community,
              status: RoomStatus.active,
              imageUrl: null,
              approvalRequired: false,
              slowModeSeconds: 0,
              autoMuteNewUsers: false,
              membersCanStartVoice: true,
              createdAt: null,
              updatedAt: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(YoKeyboardDoneBar), findsOneWidget);
    });

    testWidgets('Staff Center, which hosts the embedded Moderation Center', (
      tester,
    ) async {
      useSurface(tester, phone);
      await tester.pumpWidget(
        host(
          StaffCenterScreen(
            capabilityService: _NoStaffCapabilities(),
            currentUid: 'member',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(YoKeyboardDoneBar), findsOneWidget);
      expect(find.byType(YoKeyboardSafeBottomBar), findsOneWidget);
    });
  });
}
