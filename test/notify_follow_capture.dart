// ignore_for_file: avoid_print
// Developer-only capture harness for "notifications that follow what you
// follow" (ADR-237): the bell row of a followed Page's post, the achievement
// row that now opens Awards, the "Following" group of notification settings,
// and the lock-screen push in the recipient's language. Not a *_test.dart
// file, so the regular suite ignores it; run it explicitly:
//
//   flutter test test/notify_follow_capture.dart --concurrency=1 \
//     --dart-define=NOTIFY_FOLLOW_OUT=<dir> [--dart-define=ONLY=a,b]
//
// Real screens and widgets over a fake Firestore, the real Inter and Material
// Icons fonts, device pixel ratio 2. Frames: 390 (phone), 768 (tablet) and
// 1440 (desktop shell slot), Dark and Pearl, 200 % text, Arabic (RTL) and
// German (long words).
//
// The push frame is a drawing of a lock screen, not a device screenshot: no
// test can show the operating system's own notification. What it proves is
// the TEXT — title and body come from functions/notifications/push_copy.json
// (the file the server reads), filled the way push_locale.js fills them.
import 'dart:convert';
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

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/notification_router.dart';
import 'package:yovoice/features/notifications/presentation/screens/notification_preferences_screen.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';

import 'support/material_icons_font.dart';

const _out = String.fromEnvironment(
  'NOTIFY_FOLLOW_OUT',
  defaultValue:
      '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-10-03/w42/notify',
);
const _only = String.fromEnvironment('ONLY');
const double _dpr = 2;

const _phone = Size(390, 844);
const _tablet = Size(768, 1024);
const _desktopSize = Size(1440, 900);

final _capture = GlobalKey();
final List<String> _log = <String>[];

const _me = 'me';
const _page = 'glina';
final _postId = 'pp_${'a' * 40}';

// ------------------------------------------------------------------ fonts

Future<void> _fonts() async {
  final inter = FontLoader('Inter')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('assets/fonts/InterVariable.ttf').readAsBytesSync(),
        ),
      ),
    )
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('assets/fonts/InterVariable-Italic.ttf').readAsBytesSync(),
        ),
      ),
    );
  await inter.load();
  await loadMaterialIconsFont();
  // Inter has no Arabic. The app falls back to the device's own Arabic face
  // (AppTypography.fontFamilyFallback); a test has no device fonts, so the
  // host's Arabic font is registered under the first fallback name. Without
  // it the RTL frames still prove the mirroring, with boxes for letters.
  final arabic = File('/System/Library/Fonts/SFArabic.ttf');
  if (arabic.existsSync()) {
    await (FontLoader(AppTypography.fontFamilyFallback.first)..addFont(
          Future.value(ByteData.sublistView(arabic.readAsBytesSync())),
        ))
        .load();
    print('arabic font registered');
  } else {
    print('arabic font NOT available on this host');
  }
}

// ---------------------------------------------------------------- fixtures

class _Fixture {
  final db = FakeFirebaseFirestore();
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: _me, isEmailVerified: true),
  );

  NotificationService get notifications =>
      NotificationService(firestore: db, auth: auth);

  Future<void> seed({bool rows = true}) async {
    await db.doc('users/$_me').set(<String, Object?>{
      'uid': _me,
      'displayName': 'Kasia',
      'username': 'kasia',
      'availability': 'available',
      'notificationPreferences': <String, bool>{},
    });
    if (!rows) return;
    final now = DateTime.now();
    final inbox = db.collection('users/$_me/notifications');
    // Exactly what functions/notifications/page_posts.js writes.
    await inbox.doc('pagePost_$_postId').set(<String, Object?>{
      'type': 'pagePostPublished',
      'actorId': _page,
      'actorName': 'Pracownia Glina',
      'actorPhotoUrl': null,
      'targetId': _postId,
      'targetLabel': 'New post from a Page you follow: Pracownia Glina',
      'postPreview': 'Nowe kubki już w pracowni',
      'pageKind': 'business',
      'sourcePath': 'pagePosts/$_postId',
      'sourceGeneration': '1759485600:0',
      'isRead': false,
      'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 2))),
      'dedupeKey': 'pagePost_$_postId',
      'bellSuppressed': false,
    });
    // Exactly what functions/achievements/engine.js writes.
    await inbox.doc('achievementUnlocked_moments_1').set(<String, Object?>{
      'type': 'achievementUnlocked',
      'actorId': 'yovoice-system',
      'actorName': 'YO Voice',
      'actorPhotoUrl': null,
      'targetId': 'moments_1',
      'targetLabel': 'First Moment',
      'isRead': true,
      'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 4))),
      'dedupeKey': 'achievementUnlocked_moments_1',
      'bellSuppressed': false,
    });
    await inbox.doc('follow_ola').set(<String, Object?>{
      'type': 'follow',
      'actorId': 'qa-ola',
      'actorName': 'Ola Nowak',
      'actorPhotoUrl': null,
      'targetId': null,
      'targetLabel': null,
      'isRead': true,
      'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 9))),
      'dedupeKey': 'follow_ola',
      'bellSuppressed': false,
    });
  }

  Widget bell({bool root = false}) => NotificationsScreen(
    isRootTab: root,
    friendService: FriendService(firestore: db, auth: auth),
    messageService: MessageService(
      firestore: db,
      auth: auth,
      notificationService: notifications,
    ),
    notificationService: notifications,
    currentUserId: _me,
    firestore: db,
    auth: auth,
    acknowledgeOnVisible: false,
    openNotification: (_) async {},
  );

  Widget preferences({bool root = false}) => NotificationPreferencesScreen(
    isRootTab: root,
    notificationService: notifications,
    auth: auth,
    creatorAudienceVisibleStream: Stream<bool>.value(false),
  );

  /// The desktop shell's frame: the real sidebar beside the content slot.
  Widget desktop(Widget slot) => Scaffold(
    body: Row(
      children: [
        DesktopSidebar(
          active: DesktopNavItem.notifications,
          showContent: true,
          unreadConversationCount: 0,
          unreadNotificationCount: 1,
          onSelect: (_) {},
          onCreateRoom: () {},
          onCreateMoment: () {},
          onOpenProfile: () {},
          onOpenProfileSettings: () {},
          profileService: ProfileService(firestore: db, auth: auth),
        ),
        Expanded(child: slot),
      ],
    ),
  );
}

// ------------------------------------------------------------- the push

/// A push exactly as functions/notifications/push_locale.js composes it.
class _Push {
  _Push({
    required String locale,
    required String type,
    required String actor,
    String? postPreview,
  }) {
    final copy =
        jsonDecode(
              File('functions/notifications/push_copy.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final templates = copy['templates'] as Map<String, dynamic>;
    String text(String id) =>
        (templates[id] as Map<String, dynamic>)[locale] as String;
    title = text(type).replaceAll('{actor}', actor);
    body = postPreview ?? text('body.default');
  }

  late final String title;
  late final String body;
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({
    required this.date,
    required this.now,
    required this.push,
  });

  final String date;
  final String now;
  final _Push push;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Scaffold(
      backgroundColor: palette.background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(palette.background, AppColors.primary, .34)!,
              Color.lerp(palette.background, AppColors.secondary, .10)!,
              palette.background,
            ],
            stops: const [0, .55, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 26),
              Icon(
                Icons.lock_rounded,
                size: 22,
                color: AppColors.white.withValues(alpha: .86),
              ),
              const SizedBox(height: 14),
              Text(
                date,
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.white.withValues(alpha: .86),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Text(
                '14:20',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.white,
                  fontSize: 88,
                  height: 1.05,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -2,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 56),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised.withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppPalette.dark.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: palette.border),
                        ),
                        child: const Center(
                          child: YoBrandMark(
                            size: 30,
                            light: YoBrandLight.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'YO Voice',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: palette.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  now,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 1),
                            Text(
                              push.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.titleSmall.copyWith(
                                color: palette.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            Text(
                              push.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyMedium.copyWith(
                                color: palette.textPrimary.withValues(
                                  alpha: .86,
                                ),
                                fontSize: 14,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- harness

final _navigatorKey = GlobalKey<NavigatorState>();

Widget _app(
  Widget home, {
  Brightness brightness = Brightness.dark,
  Locale locale = const Locale('pl'),
  double textScale = 1,
}) => MaterialApp(
  navigatorKey: _navigatorKey,
  debugShowCheckedModeBanner: false,
  theme: brightness == Brightness.dark
      ? AppTheme.darkTheme
      : AppTheme.lightTheme,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: true,
      textScaler: TextScaler.linear(textScale),
    ),
    child: child!,
  ),
  home: home,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  for (var round = 0; round < 5; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    print('wrote $name ${image.width}x${image.height}');
  });
}

void _scene(
  String name,
  Size size,
  Widget Function(_Fixture fixture) build, {
  bool rows = true,
  Future<void> Function(WidgetTester tester)? then,
}) {
  if (_only.isNotEmpty && !_only.split(',').contains(name)) return;
  testWidgets(name, (tester) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) =>
        errors.add(details.exceptionAsString().split('\n').first);
    final fixture = _Fixture();
    try {
      debugDisableShadows = false;
      tester.view.physicalSize = size * _dpr;
      tester.view.devicePixelRatio = _dpr;
      if (size.width < 600) {
        tester.view.padding = const FakeViewPadding(
          top: 47 * _dpr,
          bottom: 34 * _dpr,
        );
        tester.view.viewPadding = const FakeViewPadding(
          top: 47 * _dpr,
          bottom: 34 * _dpr,
        );
      }
      await tester.runAsync(() => fixture.seed(rows: rows));
      await tester.pumpWidget(
        RepaintBoundary(key: _capture, child: build(fixture)),
      );
      await _settle(tester);
      if (then != null) {
        await then(tester);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      await _shoot(tester, name);
    } finally {
      FlutterError.onError = previous;
    }
    Object? exception;
    while ((exception = tester.takeException()) != null) {
      errors.add('$exception'.split('\n').first);
    }
    final line =
        '$name errors=${errors.length}'
        '${errors.isEmpty ? '' : ': ${errors.toSet().join(' | ')}'}';
    print('NOTE $line');
    _log.add(line);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    tester.view.reset();
    debugDisableShadows = true;
    expect(errors, isEmpty, reason: line);
  });
}

void main() {
  setUpAll(() async {
    await _fonts();
    Directory(_out).createSync(recursive: true);
  });
  tearDownAll(() {
    File(
      '$_out/_capture_log${_only.isEmpty ? '' : '_partial'}.txt',
    ).writeAsStringSync('${_log.join('\n')}\n');
  });
  setUp(() {
    EntitlementService.resetCache();
    ProfileService.resetCurrentProfileCache();
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      fetchOverride: (uids) async => {
        for (final uid in uids)
          uid: <String, Object?>{'staffRole': 'user', 'isVip': false},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  // ---- the chosen row: A1 bell, A2 settings, A3 push (390, Dark, Polish)
  _scene('a1_bell_390_dark_pl', _phone, (f) => _app(f.bell()));
  _scene('a2_prefs_390_dark_pl', _phone, (f) => _app(f.preferences()));
  _scene(
    'a3_push_390_dark_pl',
    _phone,
    (f) => _app(
      _LockScreen(
        date: 'sobota, 3 października',
        now: 'teraz',
        push: _Push(
          locale: 'pl',
          type: 'pagePostPublished',
          actor: 'Pracownia Glina',
          postPreview: 'Nowe kubki już w pracowni',
        ),
      ),
    ),
    rows: false,
  );
  // The same push for a German and a Japanese recipient, and a type that
  // carries no words of its own (the generic body, translated).
  _scene(
    'a3_push_390_dark_de',
    _phone,
    (f) => _app(
      _LockScreen(
        date: 'Samstag, 3. Oktober',
        now: 'jetzt',
        push: _Push(
          locale: 'de',
          type: 'pagePostPublished',
          actor: 'Pracownia Glina',
          postPreview: 'Nowe kubki już w pracowni',
        ),
      ),
      locale: const Locale('de'),
    ),
    rows: false,
  );
  _scene(
    'a3_push_390_dark_pl_friend_request',
    _phone,
    (f) => _app(
      _LockScreen(
        date: 'sobota, 3 października',
        now: 'teraz',
        push: _Push(locale: 'pl', type: 'friendRequest', actor: 'Ola Nowak'),
      ),
    ),
    rows: false,
  );

  // ---- the same two screens wider: tablet as a pushed route, desktop in
  // the shell's content slot (no app bar of its own)
  _scene('a_bell_768_dark_pl', _tablet, (f) => _app(f.bell()));
  _scene('a_prefs_768_dark_pl', _tablet, (f) => _app(f.preferences()));
  _scene(
    'a_bell_1440_dark_pl',
    _desktopSize,
    (f) => _app(f.desktop(f.bell(root: true))),
  );
  _scene(
    'a_prefs_1440_dark_pl',
    _desktopSize,
    (f) => _app(f.desktop(f.preferences(root: true))),
  );

  // ---- Pearl
  _scene(
    'a_bell_390_pearl_pl',
    _phone,
    (f) => _app(f.bell(), brightness: Brightness.light),
  );
  _scene(
    'a_prefs_390_pearl_pl',
    _phone,
    (f) => _app(f.preferences(), brightness: Brightness.light),
  );
  _scene(
    'a_bell_1440_pearl_pl',
    _desktopSize,
    (f) => _app(f.desktop(f.bell(root: true)), brightness: Brightness.light),
  );

  // ---- 200 % text
  _scene(
    'a_bell_390_dark_pl_text200',
    _phone,
    (f) => _app(f.bell(), textScale: 2),
  );
  _scene(
    'a_prefs_390_dark_pl_text200',
    _phone,
    (f) => _app(f.preferences(), textScale: 2),
  );

  // ---- RTL (Arabic) and a long-word language (German)
  _scene(
    'a_bell_390_dark_ar_rtl',
    _phone,
    (f) => _app(f.bell(), locale: const Locale('ar')),
  );
  _scene(
    'a_prefs_390_dark_ar_rtl',
    _phone,
    (f) => _app(f.preferences(), locale: const Locale('ar')),
  );
  _scene(
    'a_bell_390_dark_de',
    _phone,
    (f) => _app(f.bell(), locale: const Locale('de')),
  );
  _scene(
    'a_prefs_390_dark_de',
    _phone,
    (f) => _app(f.preferences(), locale: const Locale('de')),
  );

  // ---- a destination that is gone: the one honest line
  _scene(
    'a_unavailable_390_dark_pl',
    _phone,
    (f) => _app(f.bell()),
    then: (tester) async {
      NotificationRouter.announceUnavailable(_navigatorKey.currentState!);
    },
  );
}
