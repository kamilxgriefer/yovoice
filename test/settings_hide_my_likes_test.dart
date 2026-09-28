import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/marketing/data/services/public_showcase_consent_service.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/services/likes_visibility_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/settings/data/services/message_privacy_service.dart';
import 'package:yovoice/features/settings/presentation/screens/settings_screen.dart';
import 'package:yovoice/services/firestore_service.dart';

const _me = 'me';
const _row = ValueKey<String>('settings-hide-my-likes');
const _switch = ValueKey<String>('settings-hide-my-likes-switch');
const _subtitleEn =
    'You won\'t appear in YO Voice\'s lists of who liked or reacted. Counts don\'t change. Server members still receive your reactions in channels you share.';
const _subtitlePl =
    'Nie pojawisz się na listach YO Voice pokazujących, kto polubił lub zareagował. Liczniki się nie zmieniają. Członkowie serwerów nadal otrzymują Twoje reakcje na wspólnych kanałach.';

class _MemoryPreferencesStore implements AppPreferencesStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

/// A scripted `setMyLikesHiddenV1`: each call waits for [next] (when set)
/// and answers like the server, or throws.
class _Callable {
  final List<Map<String, dynamic>> calls = [];
  Completer<void>? next;
  bool fail = false;

  Future<Map<String, dynamic>> call(Map<String, dynamic> data) async {
    calls.add(data);
    final gate = next;
    if (gate != null) await gate.future;
    if (fail) throw StateError('offline');
    return {'hidden': data['hidden'], 'changed': true};
  }
}

Future<Map<String, dynamic>> _noMutation(
  String name,
  Map<String, dynamic> data,
) async => const <String, dynamic>{'changed': false};

Future<void> _pumps(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late _Callable callable;

  setUp(() async {
    FriendService.clearSharedReadCaches();
    ProfileService.resetCurrentProfileCache();
    EntitlementService.resetCache();
    PackageInfo.setMockInitialValues(
      appName: 'YO Voice',
      packageName: 'app.yovoice',
      version: '3.4.0',
      buildNumber: '39',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => call.method == 'checkPermissionStatus' ? 1 : null,
        );
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _me, email: 'me@yovoice.app'),
    );
    callable = _Callable();
  });

  tearDown(() {
    FriendService.clearSharedReadCaches();
    ProfileService.resetCurrentProfileCache();
    EntitlementService.resetCache();
  });

  Future<void> seed({Object? likesHidden}) =>
      db.collection('users').doc(_me).set(<String, dynamic>{
        'uid': _me,
        'displayName': 'Kamil',
        'username': 'kamil',
        'email': 'me@yovoice.app',
        'createdAt': Timestamp.fromDate(DateTime(2025, 3, 14)),
        'likesHidden': ?likesHidden,
      });

  Future<void> pumpSettings(
    WidgetTester tester, {
    Size size = const Size(390, 6000),
    Locale locale = const Locale('en'),
    bool isRootTab = true,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final preferences = AppPreferencesController(
      store: _MemoryPreferencesStore(),
    );
    addTearDown(preferences.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => AppPreferencesScope(
          controller: preferences,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
        home: SettingsScreen(
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
          messagePrivacyService: MessagePrivacyService(
            firestore: db,
            auth: auth,
          ),
          likesVisibilityService: LikesVisibilityService(
            mutationInvoker: callable.call,
          ),
        ),
      ),
    );
    await _pumps(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Switch switchOf(WidgetTester tester) =>
      tester.widget<Switch>(find.byKey(_switch));

  testWidgets('the switch reflects profile.likesHidden and sits in Privacy '
      'right after Profile visibility', (tester) async {
    await seed(likesHidden: true);
    await pumpSettings(tester);
    expect(find.byKey(_row), findsOneWidget);
    expect(switchOf(tester).value, isTrue);
    final visibility = tester.getTopLeft(find.text('Profile visibility')).dy;
    final hide = tester.getTopLeft(find.text('Hide my likes')).dy;
    final website = tester
        .getTopLeft(find.text('Appear on the YO Voice website'))
        .dy;
    expect(hide, greaterThan(visibility));
    expect(hide, lessThan(website));
    await unmount(tester);
  });

  testWidgets('the disclosure subtitle is shown whole, never ellipsized', (
    tester,
  ) async {
    await seed();
    await pumpSettings(tester);
    final text = tester.widget<Text>(find.text(_subtitleEn));
    expect(text.maxLines, isNull);
    expect(text.overflow, TextOverflow.visible);
    await unmount(tester);
  });

  testWidgets('optimistic on, disabled while saving, then the server-written '
      'field takes over', (tester) async {
    await seed();
    await pumpSettings(tester);
    expect(switchOf(tester).value, isFalse);

    callable.next = Completer<void>();
    await tester.tap(find.byKey(_switch));
    await tester.pump();
    expect(callable.calls, [
      {'hidden': true},
    ]);
    expect(switchOf(tester).value, isTrue, reason: 'optimistic flip');
    expect(switchOf(tester).onChanged, isNull, reason: 'disabled while busy');

    callable.next!.complete();
    await _pumps(tester, 3);
    expect(switchOf(tester).value, isTrue);
    expect(switchOf(tester).onChanged, isNotNull);

    // The server writes the field; the stream agrees.
    await db.collection('users').doc(_me).update({'likesHidden': true});
    await _pumps(tester, 3);
    expect(switchOf(tester).value, isTrue);

    // Changed later from another device: the stream is the truth again.
    await db.collection('users').doc(_me).update({'likesHidden': false});
    await _pumps(tester, 3);
    expect(switchOf(tester).value, isFalse);
    await unmount(tester);
  });

  testWidgets('a failure reverts the switch and says so', (tester) async {
    await seed(likesHidden: true);
    await pumpSettings(tester);
    callable.fail = true;
    await tester.tap(find.byKey(_switch));
    await _pumps(tester, 3);
    expect(callable.calls, [
      {'hidden': false},
    ]);
    expect(switchOf(tester).value, isTrue);
    expect(
      find.text('Couldn\'t update this setting. Try again.'),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('Polish copy', (tester) async {
    await seed();
    await pumpSettings(tester, locale: const Locale('pl'));
    expect(find.text('Ukryj moje polubienia'), findsOneWidget);
    expect(find.text(_subtitlePl), findsOneWidget);
    callable.fail = true;
    await tester.tap(find.byKey(_switch));
    await _pumps(tester, 3);
    expect(
      find.text('Nie udało się zmienić tego ustawienia. Spróbuj ponownie.'),
      findsOneWidget,
    );
    await unmount(tester);
  });

  for (final (label, size, rootTab, scale) in const [
    ('phone route, 200 % text', Size(390, 844), false, 2.0),
    ('tablet', Size(800, 1024), false, 1.0),
    ('desktop content slot', Size(1280, 800), true, 1.0),
  ]) {
    testWidgets('$label: the row is reachable and lays out cleanly', (
      tester,
    ) async {
      await seed();
      await pumpSettings(
        tester,
        size: size,
        isRootTab: rootTab,
        textScale: scale,
      );
      await tester.scrollUntilVisible(
        find.byKey(_switch),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text(_subtitleEn), findsOneWidget);
      final row = tester.getRect(find.byKey(_row));
      expect(row.width, lessThanOrEqualTo(size.width));
      final toggle = tester.getRect(find.byKey(_switch));
      expect(row.contains(toggle.center), isTrue);
      expect(find.byTooltip('Back'), rootTab ? findsNothing : findsWidgets);
      await tester.tap(find.byKey(_switch));
      await _pumps(tester, 3);
      expect(callable.calls, [
        {'hidden': true},
      ]);
      await unmount(tester);
    });
  }
}
