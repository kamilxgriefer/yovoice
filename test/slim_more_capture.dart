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
//   <screen>_<width>_<dark|pearl>_pl_<text>_<state>[-hc].png
//
// Refine-look B9 adds states beyond `populated`: Settings scrolled to the
// "O aplikacji" group (`about`, the logo on the Wersja row), Friends with
// the Online chip selected (`online`), and Find creators with results
// (`populated`) and the Verified chip selected (`verified`). The activity
// fixture carries a YO Voice system notice (type `system`, no actor), so
// every Notifications frame shows the system sender's logo.
//
// The B9 review round adds: More for a staff account (`staff`) and, at
// 1440, the popover opened from the REAL desktop rail (`rail`); keyboard
// focus on a Settings row and a Friends row (`focus`); the Friends
// requests view (`requests`) and a suggestion just sent (`sent`); the
// loading, empty and error states of Friends, Notifications and Find
// creators; and three more screens with brand avatars — Add friend,
// Blocked users and the follow list (`populated`); and Settings scrolled
// to the Appearance / Language drop-in groups (`appearance`).
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
//                                  notifications, notification-prefs,
//                                  find-creators, add-friend, blocked,
//                                  follow-list
//   SLIM_STATES=populated,online   a subset of the states above

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
import 'package:yovoice/features/creator/data/services/creator_directory_service.dart';
import 'package:yovoice/features/creator/presentation/screens/find_creators_screen.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/presentation/screens/add_friend_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/blocked_users_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/marketing/data/services/public_showcase_consent_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/screens/notification_preferences_screen.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/follow_list_screen.dart';
import 'package:yovoice/features/settings/data/services/message_privacy_service.dart';
import 'package:yovoice/features/settings/presentation/screens/settings_screen.dart';
import 'package:yovoice/features/settings/presentation/widgets/appearance_language_settings_section.dart';
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
const String _statesDefine = String.fromEnvironment('SLIM_STATES');

List<String> _list(String define) => [
  for (final part in define.split(','))
    if (part.trim().isNotEmpty) part.trim(),
];

const String _me = 'kamil';

final _captureKey = GlobalKey();
const _moreTriggerKey = ValueKey('slim-capture-more-trigger');
final _railMoreKey = GlobalKey(debugLabel: 'slim-capture-rail-more');

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
  // The test renderer has no system fallback, so the host's colour-emoji
  // font is registered under its own name and under the generic
  // 'sans-serif' family that closes `AppTypography.fontFamilyFallback`, as
  // the Start harness does.
  // macOS first, then the Linux host's Noto Color Emoji.
  final emojiFont = const [
    '/System/Library/Fonts/Apple Color Emoji.ttc',
    '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
  ].firstWhere((path) => File(path).existsSync(), orElse: () => '');
  if (emojiFont.isNotEmpty) {
    for (final family in const ['Apple Color Emoji', 'sans-serif']) {
      final emoji = FontLoader(family)..addFont(_read(emojiFont));
      await emoji.load();
    }
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

/// Answers the first load; every later (background) reload stays open.
class _HeldReloadGraph extends _StubGraph {
  int _calls = 0;

  @override
  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) {
    _calls++;
    if (_calls == 1) return super.getFriendSuggestions(limit: limit);
    return Completer<List<SuggestedFriend>>().future;
  }
}

/// A moderator who also manages roles: every staff row of the More sheet.
class _StaffCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      const StaffCapabilities(
        staffRole: 'moderator',
        handleAssignedReports: true,
        manageRoles: true,
      );
}

/// A stream that never answers: the screen stays on its loading state.
Stream<T> _pending<T>() => Stream<T>.multi((_) {});

/// What a dropped connection looks like to a Firestore listener.
FirebaseException _unavailable() => FirebaseException(
  plugin: 'cloud_firestore',
  code: 'unavailable',
  message: 'The service is currently unavailable.',
);

/// Friends whose list never loads (`loading`) or fails (`error`).
class _FriendsVariant extends FriendService {
  _FriendsVariant({
    required super.firestore,
    required super.auth,
    required this.fail,
  }) : super(mutationInvoker: _noMutation);

  final bool fail;

  @override
  Stream<List<FriendUser>> watchFriends() => fail
      ? Stream<List<FriendUser>>.error(_unavailable())
      : _pending<List<FriendUser>>();
}

/// An activity feed that never loads (`loading`) or fails (`error`).
class _NotificationsVariant extends NotificationService {
  _NotificationsVariant({
    required super.firestore,
    required super.auth,
    required this.fail,
  });

  final bool fail;

  @override
  Stream<List<AppNotification>> watchNotifications({int limit = 50}) => fail
      ? Stream<List<AppNotification>>.error(_unavailable())
      : _pending<List<AppNotification>>();
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

  static Future<_Fixture> seed({
    bool withPreferences = false,
    bool empty = false,
    bool withBlocked = false,
    bool withFollowers = false,
  }) async {
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

    // A brand-new account: the profile and nothing else.
    if (empty) return _Fixture._(db, auth);

    // Blocked users (only for the Blocked users screen, so the Settings
    // frames keep "Brak zablokowanych osób" as before).
    if (withBlocked) {
      for (final (id, name) in const [
        ('tomasz', 'Tomasz Wrona'),
        ('ewelina', 'Ewelina Krawczyk-Sobczak'),
      ]) {
        await db.collection('users').doc(_me).collection('blocked').doc(id).set(
          <String, dynamic>{'blockedAt': ago(const Duration(days: 3))},
        );
        await db.collection('publicProfiles').doc(id).set(<String, dynamic>{
          'uid': id,
          'displayName': name,
          'username': id,
        });
      }
    }

    // Followers (only for the follow list).
    if (withFollowers) {
      for (final (index, (id, name)) in const [
        ('ola', 'Ola Nowak'),
        ('kuba', 'Kuba Wiśniewski'),
        ('glos.miasta', 'Głos Miasta'),
        ('natalia', 'Natalia Wójcik'),
      ].indexed) {
        await db
            .collection('users')
            .doc(_me)
            .collection('followers')
            .doc(id)
            .set(<String, dynamic>{
              'uid': id,
              'followedAt': ago(Duration(hours: index * 5 + 1)),
            });
        await db.collection('publicProfiles').doc(id).set(<String, dynamic>{
          'uid': id,
          'displayName': name,
          'username': id,
        });
      }
    }

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
          // A notice YO Voice itself sent: no actor, so the row shows the
          // real logo as its sender.
          (
            id: 'system_community_guidelines',
            type: 'system',
            actorId: '',
            actorName: '',
            targetLabel: 'Zaktualizowaliśmy zasady społeczności',
            isRead: false,
            createdAt: today(const Duration(minutes: 1)),
          ),
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
  notificationPrefs('notification-prefs'),
  findCreators('find-creators'),
  addFriend('add-friend'),
  blocked('blocked'),
  followList('follow-list');

  const _Screen(this.label);

  final String label;
}

/// One captured state of a screen: what is done after the first settle.
class _Shot {
  const _Shot(
    this.screen,
    this.state, [
    this.prepare,
    this.desktopOnly = false,
  ]);

  final _Screen screen;
  final String state;
  final Future<void> Function(WidgetTester tester)? prepare;

  /// Only the desktop viewport (the rail exists only there).
  final bool desktopOnly;
}

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.byKey(_moreTriggerKey));
  await _settle(tester);
}

/// Settings scrolled so the "O aplikacji" group (the Wersja row's logo)
/// sits mid-screen.
Future<void> _scrollSettingsToAbout(WidgetTester tester) async {
  final version = find.byKey(const ValueKey('settings-version'));
  await tester.scrollUntilVisible(
    version,
    400,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump();
  await Scrollable.ensureVisible(tester.element(version), alignment: .45);
  await _settle(tester);
}

/// Settings scrolled to the Appearance / Language drop-in groups, which sit
/// between the Settings groups (and are owned outside this batch).
Future<void> _scrollSettingsToAppearance(WidgetTester tester) async {
  final section = find.byType(AppearanceLanguageSettingsSection);
  await tester.scrollUntilVisible(
    section,
    400,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump();
  await Scrollable.ensureVisible(tester.element(section), alignment: .3);
  await _settle(tester);
}

Future<void> _selectFriendsOnline(WidgetTester tester) async {
  await tester.tap(find.text('Online'));
  await _settle(tester);
}

Future<void> _searchCreators(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('find-creators-search')),
    'voice',
  );
  await tester.pump(const Duration(milliseconds: 500));
  // No caret in the evidence: the field keeps its text, not its focus.
  FocusManager.instance.primaryFocus?.unfocus();
  await _settle(tester);
}

Future<void> _selectVerifiedCreators(WidgetTester tester) async {
  await _searchCreators(tester);
  await tester.tap(find.byKey(const ValueKey('creator-filter-verified')));
  await _settle(tester);
}

/// Opens the popover the way the shell does: a tap on the rail's More row.
Future<void> _openRailMore(WidgetTester tester) async {
  await tester.tap(find.byKey(_railMoreKey));
  await _settle(tester);
}

/// Tab until [ring] (a row's keyboard focus ring) is on screen.
Future<void> Function(WidgetTester) _tabTo(String ring) => (tester) async {
  final finder = find.byKey(ValueKey(ring));
  for (var tab = 0; tab < 30 && finder.evaluate().isEmpty; tab++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  if (finder.evaluate().isEmpty) {
    // ignore: avoid_print
    print('FOCUS: $ring never appeared');
  }
  await tester.pump(const Duration(milliseconds: 300));
};

Future<void> _openFriendRequests(WidgetTester tester) async {
  await tester.tap(find.textContaining('Zaproszenia').first);
  await _settle(tester);
}

/// "Dodaj" on the first suggestion; the stubbed callable answers
/// `requested`, so the card turns into its "Wysłano" state. The screen then
/// reloads its suggestions in the background and drops the sent one; the
/// `sent` graph holds that reload open, so the frame shows the transient
/// "Wysłano" card a user sees until the reload lands.
Future<void> _sendFirstSuggestion(WidgetTester tester) async {
  final add = find.text('Dodaj').first;
  // At 200 % text the rail sits below the fold: scroll only as far as it
  // takes to bring the button in, so the card stays in the frame.
  await Scrollable.ensureVisible(
    tester.element(add),
    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
  );
  await tester.pump();
  await tester.tap(add);
  await _settle(tester);
}

const _shots = <_Shot>[
  _Shot(_Screen.more, 'populated', _openMore),
  _Shot(_Screen.settings, 'populated'),
  _Shot(_Screen.settings, 'about', _scrollSettingsToAbout),
  _Shot(_Screen.friends, 'populated'),
  _Shot(_Screen.friends, 'online', _selectFriendsOnline),
  _Shot(_Screen.notifications, 'populated'),
  _Shot(_Screen.notificationPrefs, 'populated'),
  _Shot(_Screen.findCreators, 'populated', _searchCreators),
  _Shot(_Screen.findCreators, 'verified', _selectVerifiedCreators),
  // Review round (B9): staff rows, the popover beside the real rail,
  // keyboard focus, the other Friends states and the three more screens
  // with brand avatars.
  _Shot(_Screen.more, 'staff', _openMore),
  _Shot(_Screen.more, 'rail', _openRailMore, true),
  _Shot(_Screen.settings, 'focus', _focusSettingsRow),
  _Shot(_Screen.settings, 'appearance', _scrollSettingsToAppearance),
  _Shot(_Screen.friends, 'focus', _focusFriendRow),
  _Shot(_Screen.friends, 'requests', _openFriendRequests),
  _Shot(_Screen.friends, 'sent', _sendFirstSuggestion),
  _Shot(_Screen.friends, 'loading'),
  _Shot(_Screen.friends, 'empty'),
  _Shot(_Screen.friends, 'error'),
  _Shot(_Screen.notifications, 'loading'),
  _Shot(_Screen.notifications, 'empty'),
  _Shot(_Screen.notifications, 'error'),
  _Shot(_Screen.findCreators, 'loading', _searchCreators),
  _Shot(_Screen.findCreators, 'empty', _searchCreators),
  _Shot(_Screen.findCreators, 'error', _searchCreators),
  _Shot(_Screen.addFriend, 'populated'),
  _Shot(_Screen.blocked, 'populated'),
  _Shot(_Screen.followList, 'populated'),
];

Future<void> _focusSettingsRow(WidgetTester tester) =>
    _tabTo('settings-row-focus-ring')(tester);

Future<void> _focusFriendRow(WidgetTester tester) =>
    _tabTo('friend-row-focus-ring')(tester);

Map<String, dynamic> _creator({
  required String uid,
  required String name,
  required String accountType,
  required String bio,
  required int followers,
}) => <String, dynamic>{
  'uid': uid,
  'displayName': name,
  'username': uid,
  'photoUrl': null,
  'bio': bio,
  'statusMessage': '',
  'accountType': accountType,
  'premiumIdentity': accountType == 'creator',
  'followerCount': followers,
  'creatorAudienceVisible': true,
};

/// "Find creators" is a callable; a capture has no Functions backend. The
/// stub answers every query with the same small directory, honouring the
/// account-type filter the screen sends.
Future<Map<String, dynamic>> _creatorSearch(
  Map<String, dynamic> payload,
) async {
  final types = (payload['accountTypes'] as List).cast<String>();
  return <String, dynamic>{
    'profiles': [
      for (final profile in [
        _creator(
          uid: 'glos.miasta',
          name: 'Głos Miasta',
          accountType: 'official',
          bio: 'Rozmowy o mieście, ludziach i dobrych miejscach.',
          followers: 1240,
        ),
        _creator(
          uid: 'ola.voice',
          name: 'Ola Nowak',
          accountType: 'creator',
          bio: 'Wieczorne rozmowy i dobra muzyka.',
          followers: 312,
        ),
        _creator(
          uid: 'kuba.podcast',
          name: 'Kuba Wiśniewski',
          accountType: 'creator',
          bio: 'Podcast o grach, technologii i kulturze.',
          followers: 87,
        ),
      ])
        if (types.contains(profile['accountType'])) profile,
    ],
  };
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

/// Decodes every on-screen `Image` in real async time before a capture.
/// The fake-async test clock never finishes an asset decode on its own, so
/// without this the first frame to show an image (the Wersja row's logo,
/// the system sender's logo) could capture an empty slot.
Future<void> _decodeImages(WidgetTester tester) async {
  final elements = find.byType(Image).evaluate().toList(growable: false);
  if (elements.isEmpty) return;
  await tester.runAsync(() async {
    for (final element in elements) {
      final image = element.widget as Image;
      await precacheImage(
        image.image,
        element,
        onError: (_, _) {},
      ).timeout(const Duration(seconds: 5), onTimeout: () {});
    }
  });
  await tester.pump();
  await tester.pump();
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
Widget _moreHost(_Viewport viewport, _Fixture fixture, {bool staff = false}) {
  return Builder(
    builder: (context) {
      final palette = context.appPalette;
      final trigger = TextButton(
        key: _moreTriggerKey,
        onPressed: () {
          if (viewport.isDesktop) {
            unawaited(
              showDesktopMoreMenu(
                context,
                anchor: const Offset(264, 520),
                isStaff: staff,
                isOwner: staff,
              ),
            );
          } else {
            unawaited(
              showMoreSheet(
                context,
                capabilityService: staff
                    ? _StaffCapabilities()
                    : _NoStaffCapabilities(),
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

/// The desktop rail exactly as the shell mounts it, beside an empty
/// content slot. Its More row opens the popover through the shell's own
/// anchor rule (the row's top edge, 8 px in from its end), so the frame
/// shows the popover where a user sees it: next to the rail.
Widget _railHost(_Fixture fixture) {
  return Builder(
    builder: (context) {
      final palette = context.appPalette;
      return Scaffold(
        backgroundColor: palette.background,
        body: Row(
          children: [
            DesktopSidebar(
              moreItemKey: _railMoreKey,
              active: DesktopNavItem.home,
              unreadConversationCount: 0,
              unreadNotificationCount: 0,
              onSelect: (item) {
                if (item != DesktopNavItem.more) return;
                final box =
                    _railMoreKey.currentContext?.findRenderObject()
                        as RenderBox?;
                final anchor = box == null
                    ? const Offset(16, 320)
                    : box.localToGlobal(Offset(box.size.width - 8, 0));
                unawaited(showDesktopMoreMenu(context, anchor: anchor));
              },
              onCreateRoom: () {},
              onCreateMoment: () {},
              onOpenProfile: () {},
              onOpenProfileSettings: () {},
              profileService: ProfileService(
                firestore: fixture.db,
                auth: fixture.auth,
              ),
            ),
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      );
    },
  );
}

Widget _screen(
  _Screen screen,
  String state,
  _Viewport viewport,
  _Fixture fixture,
  List<Future<void> Function()> disposers,
) {
  final db = fixture.db;
  final auth = fixture.auth;
  final isRootTab = viewport.isDesktop;
  final loading = state == 'loading';
  final failing = state == 'error';

  switch (screen) {
    case _Screen.more:
      if (state == 'rail') return _railHost(fixture);
      return _moreHost(viewport, fixture, staff: state == 'staff');
    case _Screen.findCreators:
      return FindCreatorsScreen(
        isRootTab: isRootTab,
        directoryService: CreatorDirectoryService(
          searchInvoker: loading
              ? (_) => Completer<Map<String, dynamic>>().future
              : failing
              ? (_) async => throw _unavailable()
              : state == 'empty'
              ? (_) async => const <String, dynamic>{'profiles': <Object>[]}
              : _creatorSearch,
        ),
        followService: FollowService(
          firestore: db,
          auth: auth,
          mutationInvoker: (_) async => const <String, dynamic>{},
        ),
      );
    case _Screen.friends:
      final messages = MessageService(firestore: db, auth: auth);
      disposers.add(messages.dispose);
      return FriendsScreen(
        isRootTab: isRootTab,
        showRequestsInitially: false,
        friendService: loading || failing
            ? _FriendsVariant(firestore: db, auth: auth, fail: failing)
            : FriendService(
                firestore: db,
                auth: auth,
                mutationInvoker: state == 'sent'
                    ? (_, _) async => const <String, dynamic>{
                        'outcome': 'requested',
                      }
                    : _noMutation,
              ),
        messageService: messages,
        socialGraphService: state == 'sent' ? _HeldReloadGraph() : _StubGraph(),
        firestore: db,
        auth: auth,
      );
    case _Screen.notifications:
      final notifications = loading || failing
          ? _NotificationsVariant(firestore: db, auth: auth, fail: failing)
          : NotificationService(firestore: db, auth: auth);
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
    case _Screen.addFriend:
      return AddFriendScreen(
        friendService: FriendService(
          firestore: db,
          auth: auth,
          mutationInvoker: _noMutation,
        ),
        socialGraphService: _StubGraph(),
      );
    case _Screen.blocked:
      return BlockedUsersScreen(
        friendService: FriendService(
          firestore: db,
          auth: auth,
          mutationInvoker: _noMutation,
        ),
      );
    case _Screen.followList:
      return FollowListScreen(
        userId: _me,
        type: FollowListType.followers,
        service: FollowService(
          firestore: db,
          auth: auth,
          mutationInvoker: (_) async => const <String, dynamic>{},
        ),
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
  final stateNames = _list(_statesDefine).toSet();
  final shots = [
    for (final shot in _shots)
      if ((screenNames.isEmpty || screenNames.contains(shot.screen.label)) &&
          (stateNames.isEmpty || stateNames.contains(shot.state)))
        shot,
  ];
  // (text %, high contrast): every text scale, then the -hc frame at 100 %.
  final modes = <(int, bool)>[
    for (final text in textScales) (text, false),
    if (_hcFrames) (100, true),
  ];

  for (final look in _Look.values) {
    for (final viewport in viewports) {
      for (final (text, highContrast) in modes) {
        for (final shot in shots) {
          if (shot.desktopOnly && !viewport.isDesktop) continue;
          final screen = shot.screen;
          final state = highContrast ? '${shot.state}-hc' : shot.state;
          final filename =
              '${screen.label}_${viewport.width}_${look.label}_pl_${text}_'
              '$state.png';
          testWidgets(filename, (tester) async {
            tester.view.physicalSize = viewport.size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);

            final fixture = await _Fixture.seed(
              withPreferences: screen == _Screen.notificationPrefs,
              empty: shot.state == 'empty',
              withBlocked: screen == _Screen.blocked,
              withFollowers: screen == _Screen.followList,
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
                  home: _screen(
                    screen,
                    shot.state,
                    viewport,
                    fixture,
                    disposers,
                  ),
                ),
              );
              await _settle(tester);

              final prepare = shot.prepare;
              if (prepare != null) await prepare(tester);
              await _decodeImages(tester);

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
