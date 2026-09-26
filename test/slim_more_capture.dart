// Developer-only VISUAL harness for Slim phase 6: the "More" family.
//
// Renders the REAL production widgets — the More sheet (mobile) and the
// desktop More popover, Settings, Friends, the Notifications inbox and the
// notification preferences — with fixtures injected through their
// constructor seams, at exact viewports, with real Inter + MaterialIcons
// glyphs (and the macOS colour-emoji font when the host has it, so an emoji
// never draws as a tofu box), locale `pl`, in Dark and Pearl, and writes one
// PNG per frame:
//
//   <screen>_<width>_<dark|pearl>_pl_<text>_populated[-hc].png
//
// The default matrix is 390 (2x), 768 (2x) and 1440 (1x) wide, at 100 % and
// 200 % text, plus a high-contrast frame (`-hc`, 100 % text, the app's
// high-contrast theme twins) of every screen and width. At 1440 the screens
// render without the app shell (the rail), as they always have here.
//
// It is NOT a test and deliberately does not end in `_test.dart`, so the
// regular suite never writes evidence. Run it explicitly:
//
//   flutter test --reporter compact test/slim_more_capture.dart
//
// Options (all `--dart-define`):
//   SLIM_OUT=<dir>                 output folder (below is the default)
//   SLIM_WIDTHS=390,768,1440       any of 390, 768, 1440
//   SLIM_TEXT=100,200              text scales, in percent
//   SLIM_HC=true|false             the high-contrast frames
//   SLIM_SCREENS=settings,friends  a subset of: more, settings, friends,
//                                  notifications, notification-prefs

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/marketing/data/services/public_showcase_consent_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/screens/notification_preferences_screen.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/settings/data/services/message_privacy_service.dart';
import 'package:yovoice/features/settings/presentation/screens/settings_screen.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/services/firestore_service.dart';

const String _outDir = String.fromEnvironment(
  'SLIM_OUT',
  defaultValue:
      r'C:\Users\mfvon\Documents\GitHub\yovoice-evidence\2026-09-19\slim-p6-frames\after',
);

const String _widthsDefine = String.fromEnvironment(
  'SLIM_WIDTHS',
  defaultValue: '390,768,1440',
);
const String _textDefine = String.fromEnvironment(
  'SLIM_TEXT',
  defaultValue: '100,200',
);
const bool _hcFrames = bool.fromEnvironment('SLIM_HC', defaultValue: true);
const String _screensDefine = String.fromEnvironment('SLIM_SCREENS');

List<String> _list(String define) => [
  for (final part in define.split(','))
    if (part.trim().isNotEmpty) part.trim(),
];

const String _me = 'kamil';

final _captureKey = GlobalKey();
const _moreTriggerKey = ValueKey('slim-capture-more-trigger');

// ---------------------------------------------------------------------------
// Fonts
// ---------------------------------------------------------------------------

String _resolveMaterialFontRoot() {
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null) {
    final configured = '$configuredRoot/bin/cache/artifacts/material_fonts';
    if (File('$configured/MaterialIcons-Regular.otf').existsSync()) {
      return configured;
    }
  }

  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final candidate = '${directory.path}/bin/cache/artifacts/material_fonts';
    if (File('$candidate/MaterialIcons-Regular.otf').existsSync()) {
      return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate Flutter material fonts.');
}

Future<ByteData> _read(String path) async {
  final bytes = Uint8List.fromList(File(path).readAsBytesSync());
  return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
}

Future<void> _loadFonts() async {
  // Without real fonts every glyph renders as a filled box and the
  // "look at it" step proves nothing.
  final inter = FontLoader('Inter')
    ..addFont(_read('assets/fonts/InterVariable.ttf'))
    ..addFont(_read('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();

  final icons = FontLoader('MaterialIcons')
    ..addFont(_read('${_resolveMaterialFontRoot()}/MaterialIcons-Regular.otf'));
  await icons.load();

  // Colour emoji (the Inter fallback chain ends in the platform emoji font).
  const emojiFont = '/System/Library/Fonts/Apple Color Emoji.ttc';
  if (File(emojiFont).existsSync()) {
    final emoji = FontLoader('Apple Color Emoji')..addFont(_read(emojiFont));
    await emoji.load();
    // ignore: avoid_print
    print('emoji font registered: $emojiFont');
  } else {
    // ignore: avoid_print
    print('emoji font NOT available on this host');
  }
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _NoStaffCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

/// "People you may know" is a callable; a capture has no Functions backend.
class _StubGraph extends SocialGraphService {
  @override
  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) async =>
      const [
        SuggestedFriend(
          uid: 'szymon',
          displayName: 'Szymon Kamiński',
          photoUrl: null,
          mutualCount: 3,
        ),
        SuggestedFriend(
          uid: 'julia',
          displayName: 'Julia Dąbrowska',
          photoUrl: null,
          mutualCount: 1,
        ),
        SuggestedFriend(
          uid: 'adam',
          displayName: 'Adam Grabowski',
          photoUrl: null,
          mutualCount: 2,
        ),
      ];
}

class _MemoryPreferencesStore implements AppPreferencesStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

Future<Map<String, dynamic>> _noMutation(
  String name,
  Map<String, dynamic> data,
) async => const <String, dynamic>{'changed': false};

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

class _Fixture {
  _Fixture._(this.db, this.auth);

  final FakeFirebaseFirestore db;
  final MockFirebaseAuth auth;

  static Future<_Fixture> seed({bool withPreferences = false}) async {
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: _me,
        email: 'kamil@yovoice.app',
        displayName: 'Kamil Jaguszewski',
        isEmailVerified: true,
      ),
    );
    final now = DateTime.now();
    Timestamp ago(Duration duration) =>
        Timestamp.fromDate(now.subtract(duration));

    await db.collection('users').doc(_me).set(<String, dynamic>{
      'uid': _me,
      'displayName': 'Kamil Jaguszewski',
      'username': 'kamil',
      'email': 'kamil@yovoice.app',
      'createdAt': Timestamp.fromDate(DateTime(2025, 3, 14, 12)),
      'accountType': 'creator',
      'availability': 'available',
      'isOnline': true,
      'statusMessage': 'Wieczorne rozmowy i dobra muzyka',
      'friendCount': 5,
      // Two switches off, so both switch states are in the frame.
      if (withPreferences)
        'notificationPreferences': <String, bool>{
          'follow': false,
          'missedCall': false,
        },
    });

    // Friends: a legacy mirror row, the public projection and the
    // separately authorised presence projection — the three reads
    // FriendService.watchFriends() joins.
    const friends =
        <
          ({
            String id,
            String name,
            String handle,
            bool online,
            String availability,
            Duration lastSeen,
            bool premium,
          })
        >[
          (
            id: 'ola',
            name: 'Ola Nowak',
            handle: 'olanowak',
            online: true,
            availability: 'available',
            lastSeen: Duration(minutes: 1),
            premium: true,
          ),
          (
            id: 'kuba',
            name: 'Kuba Wiśniewski',
            handle: 'kubaw',
            online: true,
            availability: 'busy',
            lastSeen: Duration(minutes: 2),
            premium: false,
          ),
          (
            id: 'marta',
            name: 'Marta Zielińska',
            handle: 'martaz',
            online: true,
            availability: 'away',
            lastSeen: Duration(minutes: 9),
            premium: false,
          ),
          (
            id: 'piotr',
            name: 'Piotr Kowalczyk',
            handle: 'piotrk',
            online: false,
            availability: 'offline',
            lastSeen: Duration(hours: 2),
            premium: false,
          ),
          (
            id: 'zuzanna',
            name: 'Zuzanna Lewandowska',
            handle: 'zuzal',
            online: false,
            availability: 'offline',
            lastSeen: Duration(days: 1, hours: 3),
            premium: false,
          ),
        ];
    for (final friend in friends) {
      await db
          .collection('users')
          .doc(_me)
          .collection('friends')
          .doc(friend.id)
          .set(<String, dynamic>{
            'displayName': friend.name,
            'createdAt': ago(const Duration(days: 40)),
          });
      await db
          .collection('publicProfiles')
          .doc(friend.id)
          .set(<String, dynamic>{
            'uid': friend.id,
            'displayName': friend.name,
            'username': friend.handle,
            'premiumIdentity': friend.premium,
          });
      await db
          .collection('socialPresence')
          .doc(friend.id)
          .set(<String, dynamic>{
            'isOnline': friend.online,
            'availability': friend.availability,
            'lastSeen': ago(friend.lastSeen),
          });
    }

    // Incoming friend requests, so the Requests entry carries a count.
    for (final (id, name, age) in const <(String, String, Duration)>[
      ('natalia', 'Natalia Wójcik', Duration(minutes: 18)),
      ('bartek', 'Bartek Mazur', Duration(hours: 5)),
    ]) {
      await db
          .collection('users')
          .doc(_me)
          .collection('friendRequests')
          .doc(id)
          .set(<String, dynamic>{
            'senderId': id,
            'senderName': name,
            'senderPhotoUrl': null,
            'createdAt': ago(age),
          });
    }

    // Activity feed: mixed kinds, some unread, spread across today,
    // yesterday and earlier so every date group renders.
    final startOfToday = DateTime(now.year, now.month, now.day);
    DateTime today(Duration duration) {
      final candidate = now.subtract(duration);
      final floor = startOfToday.add(const Duration(minutes: 1));
      return candidate.isBefore(floor) ? floor : candidate;
    }

    final yesterdayEvening = DateTime(now.year, now.month, now.day - 1, 18, 30);
    final yesterdayMorning = DateTime(now.year, now.month, now.day - 1, 9, 10);
    final fourDaysAgo = DateTime(now.year, now.month, now.day - 4, 20, 5);
    final sixDaysAgo = DateTime(now.year, now.month, now.day - 6, 14, 40);

    final notifications =
        <
          ({
            String id,
            String type,
            String actorId,
            String actorName,
            String? targetLabel,
            bool isRead,
            DateTime createdAt,
          })
        >[
          (
            id: 'follow_ola',
            type: 'follow',
            actorId: 'ola',
            actorName: 'Ola Nowak',
            targetLabel: null,
            isRead: false,
            createdAt: today(const Duration(minutes: 4)),
          ),
          (
            id: 'roomInvite_kuba',
            type: 'roomInvite',
            actorId: 'kuba',
            actorName: 'Kuba Wiśniewski',
            targetLabel: 'Wieczorne rozmowy',
            isRead: false,
            createdAt: today(const Duration(minutes: 47)),
          ),
          (
            id: 'friendAccepted_marta',
            type: 'friendAccepted',
            actorId: 'marta',
            actorName: 'Marta Zielińska',
            targetLabel: null,
            isRead: false,
            createdAt: today(const Duration(hours: 2, minutes: 10)),
          ),
          (
            id: 'mention_piotr',
            type: 'mention',
            actorId: 'piotr',
            actorName: 'Piotr Kowalczyk',
            targetLabel: 'Klub książki',
            isRead: true,
            createdAt: yesterdayEvening,
          ),
          (
            id: 'liveStarted_zuzanna',
            type: 'liveStarted',
            actorId: 'zuzanna',
            actorName: 'Zuzanna Lewandowska',
            targetLabel: 'Poranna kawa',
            isRead: true,
            createdAt: yesterdayMorning,
          ),
          (
            id: 'achievement_first_week',
            type: 'achievementUnlocked',
            actorId: '',
            actorName: 'YO Voice',
            targetLabel: 'Pierwszy tydzień',
            isRead: true,
            createdAt: fourDaysAgo,
          ),
          (
            id: 'clubInviteAccepted_bartek',
            type: 'clubInviteAccepted',
            actorId: 'bartek',
            actorName: 'Bartek Mazur',
            targetLabel: 'Polski Podcast',
            isRead: true,
            createdAt: sixDaysAgo,
          ),
        ];
    for (final notification in notifications) {
      await db
          .collection('users')
          .doc(_me)
          .collection('notifications')
          .doc(notification.id)
          .set(<String, dynamic>{
            'type': notification.type,
            'actorId': notification.actorId,
            'actorName': notification.actorName,
            'actorPhotoUrl': null,
            'targetId': null,
            'targetLabel': notification.targetLabel,
            'isRead': notification.isRead,
            'createdAt': Timestamp.fromDate(notification.createdAt),
            'dedupeKey': notification.id,
            'bellSuppressed': false,
          });
    }

    return _Fixture._(db, auth);
  }
}

// ---------------------------------------------------------------------------
// Frames
// ---------------------------------------------------------------------------

enum _Look {
  dark('dark', AppThemePreference.dark),
  pearl('pearl', AppThemePreference.light);

  const _Look(this.label, this.preference);

  final String label;
  final AppThemePreference preference;

  /// The app's theme, or its high-contrast twin (what `MaterialApp` picks
  /// under the platform's high-contrast setting).
  ThemeData theme({bool highContrast = false}) =>
      switch ((this, highContrast)) {
        (_Look.dark, false) => AppTheme.darkTheme,
        (_Look.dark, true) => AppTheme.darkHighContrastTheme,
        (_Look.pearl, false) => AppTheme.lightTheme,
        (_Look.pearl, true) => AppTheme.lightHighContrastTheme,
      };
}

enum _Screen {
  more('more'),
  settings('settings'),
  friends('friends'),
  notifications('notifications'),
  notificationPrefs('notification-prefs');

  const _Screen(this.label);

  final String label;
}

class _Viewport {
  const _Viewport(this.size, this.pixelRatio);

  final Size size;
  final double pixelRatio;

  int get width => size.width.toInt();
  bool get isDesktop => size.width >= 980;
}

const _allViewports = <_Viewport>[
  _Viewport(Size(390, 844), 2),
  _Viewport(Size(768, 1024), 2),
  _Viewport(Size(1440, 900), 1),
];

/// Bounded settle: `pumpAndSettle` when the screen goes quiet, otherwise a
/// fixed series of frames so a perpetual animation or stream cannot hang
/// the harness.
Future<void> _settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 8),
    );
  } on FlutterError catch (error) {
    // ignore: avoid_print
    print('pumpAndSettle did not settle (${error.message}); bounded pumps.');
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }
}

Future<void> _capturePng(
  WidgetTester tester,
  String filename,
  double pixelRatio,
) async {
  await tester.runAsync(() async {
    final boundary =
        _captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;

    // Prime the font and icon atlases. Without this first raster pass a
    // headless engine can intermittently omit one glyph from the evidence.
    final warmup = await boundary.toImage(pixelRatio: pixelRatio);
    warmup.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 16));

    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir${Platform.pathSeparator}$filename');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path} (${image.width}x${image.height})');
    } finally {
      image.dispose();
    }
  });
}

Widget _app({
  required _Look look,
  required AppPreferencesController preferences,
  required Widget home,
  double textScale = 1,
  bool highContrast = false,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: look.theme(highContrast: highContrast),
    locale: const Locale('pl'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    // The boundary sits ABOVE the Navigator so modal sheets and popovers,
    // which live in the Navigator's overlay, are part of the captured layer.
    builder: (context, child) => AppPreferencesScope(
      controller: preferences,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: textScale == 1
              ? TextScaler.noScaling
              : TextScaler.linear(textScale),
          highContrast: highContrast,
        ),
        child: RepaintBoundary(key: _captureKey, child: child!),
      ),
    ),
    home: home,
  );
}

/// The screen a More launcher is opened from. The trigger sits where the
/// real control sits (the dock's centre on mobile, the rail row on
/// desktop) but paints nothing, so no harness chrome leaks into the frame;
/// a tester tap still lands on it and opens the real sheet or popover.
Widget _moreHost(_Viewport viewport, _Fixture fixture) {
  return Builder(
    builder: (context) {
      final palette = context.appPalette;
      final trigger = TextButton(
        key: _moreTriggerKey,
        onPressed: () {
          if (viewport.isDesktop) {
            unawaited(
              showDesktopMoreMenu(context, anchor: const Offset(264, 520)),
            );
          } else {
            unawaited(
              showMoreSheet(
                context,
                capabilityService: _NoStaffCapabilities(),
                currentUid: _me,
                // The real account doc, so the availability chip renders.
                profileService: ProfileService(
                  firestore: fixture.db,
                  auth: fixture.auth,
                ),
              ),
            );
          }
        },
        child: const SizedBox(width: 96, height: 44),
      );
      return Scaffold(
        backgroundColor: palette.background,
        body: Stack(
          children: [
            if (viewport.isDesktop)
              Positioned(left: 24, top: 500, child: trigger)
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: 18,
                child: Center(child: trigger),
              ),
          ],
        ),
      );
    },
  );
}

Widget _screen(
  _Screen screen,
  _Viewport viewport,
  _Fixture fixture,
  List<Future<void> Function()> disposers,
) {
  final db = fixture.db;
  final auth = fixture.auth;
  final isRootTab = viewport.isDesktop;

  switch (screen) {
    case _Screen.more:
      return _moreHost(viewport, fixture);
    case _Screen.friends:
      final messages = MessageService(firestore: db, auth: auth);
      disposers.add(messages.dispose);
      return FriendsScreen(
        isRootTab: isRootTab,
        showRequestsInitially: false,
        friendService: FriendService(
          firestore: db,
          auth: auth,
          mutationInvoker: _noMutation,
        ),
        messageService: messages,
        socialGraphService: _StubGraph(),
        firestore: db,
        auth: auth,
      );
    case _Screen.notifications:
      final notifications = NotificationService(firestore: db, auth: auth);
      final messages = MessageService(
        firestore: db,
        auth: auth,
        notificationService: notifications,
      );
      disposers.add(messages.dispose);
      return NotificationsScreen(
        isRootTab: isRootTab,
        // Keep the unread styling: visiting would otherwise acknowledge
        // every unread row before the frame is captured.
        acknowledgeOnVisible: false,
        friendService: FriendService(
          firestore: db,
          auth: auth,
          mutationInvoker: _noMutation,
        ),
        messageService: messages,
        notificationService: notifications,
        currentUserId: _me,
        firestore: db,
        auth: auth,
      );
    case _Screen.notificationPrefs:
      return NotificationPreferencesScreen(
        isRootTab: isRootTab,
        notificationService: NotificationService(firestore: db, auth: auth),
        auth: auth,
        // A creator account, so the followers switch is part of the frame.
        creatorAudienceVisibleStream: Stream<bool>.value(true),
      );
    case _Screen.settings:
      return SettingsScreen(
        isRootTab: isRootTab,
        profileService: ProfileService(firestore: db, auth: auth),
        authService: AuthService(
          firebaseAuth: auth,
          firestoreService: FirestoreService(firestore: db),
        ),
        friendService: FriendService(
          firestore: db,
          auth: auth,
          mutationInvoker: _noMutation,
        ),
        entitlementService: EntitlementService(firestore: db, auth: auth),
        showcaseConsentService: PublicShowcaseConsentService(firestore: db),
        messagePrivacyService: MessagePrivacyService(firestore: db, auth: auth),
      );
  }
}

void _resetSharedCaches() {
  FriendService.clearSharedReadCaches();
  ProfileService.resetCurrentProfileCache();
  EntitlementService.resetCache();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
    PackageInfo.setMockInitialValues(
      appName: 'YO Voice',
      packageName: 'app.yovoice',
      version: '3.0.0',
      buildNumber: '34',
      buildSignature: '',
    );
  });

  setUp(() {
    _resetSharedCaches();
    // permission_handler: every permission reads as granted (index 1).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => call.method == 'checkPermissionStatus' ? 1 : null,
        );
  });

  tearDown(_resetSharedCaches);

  final widths = _list(_widthsDefine).map(int.parse).toSet();
  final viewports = [
    for (final viewport in _allViewports)
      if (widths.contains(viewport.width)) viewport,
  ];
  final textScales = _list(_textDefine).map(int.parse).toList();
  final screenNames = _list(_screensDefine).toSet();
  final screens = [
    for (final screen in _Screen.values)
      if (screenNames.isEmpty || screenNames.contains(screen.label)) screen,
  ];
  // (text %, high contrast): every text scale, then the -hc frame at 100 %.
  final modes = <(int, bool)>[
    for (final text in textScales) (text, false),
    if (_hcFrames) (100, true),
  ];

  for (final look in _Look.values) {
    for (final viewport in viewports) {
      for (final (text, highContrast) in modes) {
        for (final screen in screens) {
          final state = highContrast ? 'populated-hc' : 'populated';
          final filename =
              '${screen.label}_${viewport.width}_${look.label}_pl_${text}_'
              '$state.png';
          testWidgets(filename, (tester) async {
            tester.view.physicalSize = viewport.size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);

            final fixture = await _Fixture.seed(
              withPreferences: screen == _Screen.notificationPrefs,
            );
            final disposers = <Future<void> Function()>[];
            final preferences = AppPreferencesController(
              store: _MemoryPreferencesStore(),
              initialValue: AppPreferences(
                theme: look.preference,
                language: AppLanguagePreference.polish,
              ),
            );

            // flutter_test replaces every elevation and BoxShadow blur with a
            // hard, solid debug band. Evidence must show the real soft shadow,
            // so it is re-enabled for the render and restored before the
            // binding checks its invariants at the end of the test.
            debugDisableShadows = false;
            try {
              await tester.pumpWidget(
                _app(
                  look: look,
                  preferences: preferences,
                  textScale: text / 100,
                  highContrast: highContrast,
                  home: _screen(screen, viewport, fixture, disposers),
                ),
              );
              await _settle(tester);

              if (screen == _Screen.more) {
                await tester.tap(find.byKey(_moreTriggerKey));
                await _settle(tester);
              }

              await _capturePng(tester, filename, viewport.pixelRatio);

              final exception = tester.takeException();
              if (exception != null) {
                // ignore: avoid_print
                print('EXCEPTION while rendering $filename: $exception');
              }

              // Unmount inside the test so stream listeners and their timers
              // are released before the binding checks for pending work.
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump(const Duration(seconds: 1));
              for (final dispose in disposers) {
                await dispose();
              }
              preferences.dispose();
            } finally {
              debugDisableShadows = true;
            }
          });
        }
      }
    }
  }
}
