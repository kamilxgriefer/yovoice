import 'dart:convert';
import 'dart:io';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/widgets/my_link_sheet.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';

/// "Mój link" (ADR-238): the sheet / dialog with the account's own profile
/// link as a QR code, Copy and Share.

const _uid = 'Zx8qT1mVbN4kLp0sWe7uYh2RcA93';
const _link = 'https://app.yovoice.app/?user=$_uid';

class _Harness {
  _Harness({bool signedIn = true})
    : auth = MockFirebaseAuth(
        signedIn: signedIn,
        mockUser: MockUser(
          uid: _uid,
          email: 'kamil@example.com',
          displayName: 'Kamil',
          isEmailVerified: true,
        ),
      );

  final MockFirebaseAuth auth;
  final FakeFirebaseFirestore db = FakeFirebaseFirestore();
  final List<String> copied = <String>[];
  final List<ShareParams> shared = <ShareParams>[];
  Object? copyError;
  Object? shareError;
  ShareResultStatus shareStatus = ShareResultStatus.success;
  bool runsPage = false;

  /// The account's stored `profileVisibility`; null leaves the field absent
  /// (the historical public default).
  String? profileVisibility;

  late final ProfileMediaService media = ProfileMediaService(
    auth: auth,
    invoker: (_, _) async => <Object?, Object?>{
      'schemaVersion': 1,
      'available': false,
      'expiresAtMillis': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch,
    },
  );

  Future<void> seed() => db.doc('users/$_uid').set(<String, dynamic>{
    'uid': _uid,
    'displayName': 'Kamil',
    'username': 'kamil',
    'profileVisibility': ?profileVisibility,
  });

  Future<void> open(BuildContext context) => showMyLink(
    context,
    auth: auth,
    profileService: ProfileService(firestore: db, auth: auth),
    mediaService: media,
    clipboardWriter: (text) async {
      final error = copyError;
      if (error != null) throw error;
      copied.add(text);
    },
    shareInvoker: (params) async {
      final error = shareError;
      if (error != null) throw error;
      shared.add(params);
      return ShareResult('raw', shareStatus);
    },
    runsPage: (_) async => runsPage,
  );
}

Future<_Harness> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  Locale locale = const Locale('pl'),
  ThemeData? theme,
  _Harness? harness,
  bool open = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = harness ?? _Harness();
  await h.seed();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? AppTheme.darkTheme,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              key: const ValueKey('open'),
              onPressed: () => h.open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  if (open) {
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
  }
  return h;
}

/// What the QR code on screen encodes.
String _qrData(WidgetTester tester) =>
    utf8.decode(tester.widget<BarcodeWidget>(find.byType(BarcodeWidget)).data);

/// The link printed under the code, without its invisible break point.
String _linkText(WidgetTester tester) {
  final text = tester.widget<Text>(find.byKey(const ValueKey('my-link-text')));
  expect(text.semanticsLabel, text.data!.replaceAll('\u200B', ''));
  return text.semanticsLabel!;
}

final _panel = find.byKey(const ValueKey('my-link-panel'));
final _copy = find.byKey(const ValueKey('my-link-copy'));
final _share = find.byKey(const ValueKey('my-link-share'));
final _feedback = find.byKey(const ValueKey('my-link-feedback'));

void main() {
  // The action row decides between one line and a stack by MEASURING its
  // labels, so the suite runs with the app's real typeface rather than the
  // test font's 1 em glyphs.
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(
        Future<ByteData>.value(
          ByteData.sublistView(
            File('assets/fonts/InterVariable.ttf').readAsBytesSync(),
          ),
        ),
      );
    await inter.load();
  });
  setUp(ProfileService.resetCurrentProfileCache);

  testWidgets('phone: a bottom sheet with the identity, the code, the link '
      'and the two actions', (tester) async {
    await _pump(tester);

    expect(_panel, findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.getSize(_panel).width, 390);
    expect(
      find.byKey(const ValueKey('modal-sheet-drag-handle')),
      findsOneWidget,
    );
    expect(find.text('Mój link'), findsOneWidget);
    expect(
      find.text(
        'Kto go otworzy albo zeskanuje kod, zobaczy Twój profil i będzie '
        'mógł dodać Cię do znajomych.',
      ),
      findsOneWidget,
    );
    expect(find.text('Kamil'), findsOneWidget);
    expect(find.text('@kamil'), findsOneWidget);

    // The code encodes exactly the link printed under it.
    expect(_qrData(tester), _link);
    expect(_linkText(tester), 'app.yovoice.app/?user=$_uid');
    final tile = tester.getSize(find.byKey(const ValueKey('my-link-qr')));
    expect(tile, const Size(220, 220));
    final box = tester.widget<Container>(
      find.byKey(const ValueKey('my-link-qr')),
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.borderRadius, BorderRadius.circular(16));

    // "Kopiuj link" (tonal) beside "Udostępnij" (the gradient CTA), 48 px.
    expect(find.text('Kopiuj link'), findsOneWidget);
    expect(find.text('Udostępnij'), findsOneWidget);
    expect(find.byType(YoGradientFilledButton), findsOneWidget);
    final copy = tester.getRect(_copy);
    final share = tester.getRect(_share);
    expect(copy.height, 48);
    expect(share.height, 48);
    expect(copy.center.dy, share.center.dy);
    expect(copy.right, lessThan(share.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the link never contains the e-mail address or the name', (
    tester,
  ) async {
    await _pump(tester);
    final data = _qrData(tester);
    expect(data, isNot(contains('kamil')));
    expect(data, isNot(contains('@')));
    expect(Uri.parse(data).queryParameters.keys, ['user']);
  });

  testWidgets('Copy writes the whole link and says so', (tester) async {
    final h = await _pump(tester);
    await tester.tap(_copy);
    await tester.pumpAndSettle();
    expect(h.copied, [_link]);
    expect(tester.widget<Text>(_feedback).data, 'Link skopiowany.');
  });

  testWidgets('a failed copy is reported, not hidden', (tester) async {
    final h = _Harness()..copyError = StateError('denied');
    await _pump(tester, harness: h);
    await tester.tap(_copy);
    await tester.pumpAndSettle();
    expect(h.copied, isEmpty);
    expect(
      tester.widget<Text>(_feedback).data,
      'Nie udało się skopiować linku. Spróbuj ponownie.',
    );
  });

  testWidgets('Share hands the sentence with the link to the system sheet', (
    tester,
  ) async {
    final h = await _pump(tester);
    await tester.tap(_share);
    await tester.pumpAndSettle();
    expect(h.shared.single.text, 'Znajdź mnie w YO Voice: $_link');
    expect(h.shared.single.uri, isNull);
    expect(h.shared.single.sharePositionOrigin, isNotNull);
    // A nominal success claims nothing.
    expect(_feedback, findsNothing);
  });

  testWidgets('an unavailable or failing share offers the copy fallback', (
    tester,
  ) async {
    final h = _Harness()..shareStatus = ShareResultStatus.unavailable;
    await _pump(tester, harness: h);
    await tester.tap(_share);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(_feedback).data,
      'Nie można potwierdzić udostępnienia. Możesz skopiować link.',
    );

    h.shareError = StateError('no share target');
    await tester.tap(_share);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(_feedback).data,
      'Udostępnianie jest tutaj niedostępne. Skopiuj link.',
    );
    expect(h.copied, isEmpty, reason: 'the clipboard is never overwritten');
  });

  testWidgets('an account that runs a Page reads the Page sentence', (
    tester,
  ) async {
    final h = _Harness()..runsPage = true;
    await _pump(tester, harness: h);
    expect(
      find.text(
        'Kto go otworzy albo zeskanuje kod, zobaczy Twoją Stronę i będzie '
        'mógł Cię obserwować.',
      ),
      findsOneWidget,
    );
  });

  // The sentence promises what the link does for whoever opens it. A profile
  // that is "Friends only" or "Only me" is not shown to the people that
  // setting excludes (they read "Ten profil jest niedostępny." and cannot
  // add the person), so the sheet must not promise otherwise.
  const notPublic =
      'Twój profil nie jest publiczny, więc ten link nie otworzy go każdemu. '
      'Aby każdy mógł Cię dodać, zmień Widoczność profilu w Ustawieniach.';
  for (final visibility in const <String>['friends', 'private']) {
    testWidgets('a "$visibility" profile is told the link will not open it '
        'for everyone', (tester) async {
      final h = _Harness()..profileVisibility = visibility;
      await _pump(tester, harness: h);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('my-link-body'))).data,
        notPublic,
      );
      // The link is still the account's own and both actions still work.
      expect(_qrData(tester), _link);
      expect(_linkText(tester), 'app.yovoice.app/?user=$_uid');
      await tester.tap(_copy);
      await tester.pumpAndSettle();
      expect(h.copied, [_link]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a public profile keeps the approved sentence', (tester) async {
    final h = _Harness()..profileVisibility = 'public';
    await _pump(tester, harness: h);
    expect(find.text(notPublic), findsNothing);
    expect(
      find.text(
        'Kto go otworzy albo zeskanuje kod, zobaczy Twój profil i będzie '
        'mógł dodać Cię do znajomych.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a Page account whose profile is not public reads the honest '
      'sentence, not the Page one', (tester) async {
    final h = _Harness()
      ..runsPage = true
      ..profileVisibility = 'friends';
    await _pump(tester, harness: h);
    expect(find.text(notPublic), findsOneWidget);
  });

  testWidgets('the not-public sentence fits 320 px at 200 % text', (
    tester,
  ) async {
    final h = _Harness()..profileVisibility = 'private';
    await _pump(tester, harness: h, size: const Size(320, 690), textScale: 2);
    expect(find.text(notPublic), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet: the sheet is a centred 520 px column', (tester) async {
    await _pump(tester, size: const Size(768, 1024));
    expect(find.byType(Dialog), findsNothing);
    final rect = tester.getRect(_panel);
    expect(rect.width, 520);
    expect(rect.center.dx, 384);
    expect(rect.bottom, 1024);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop: a centred 420 px dialog without a drag handle', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1440, 900));
    expect(find.byType(Dialog), findsOneWidget);
    final rect = tester.getRect(_panel);
    expect(rect.width, 420);
    expect(rect.center.dx, 720);
    expect(rect.center.dy, closeTo(450, 1));
    expect(find.byKey(const ValueKey('modal-sheet-drag-handle')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('my-link-qr'))),
      const Size(220, 220),
    );
    expect(tester.takeException(), isNull);

    // The close control dismisses it.
    await tester.tap(find.byTooltip('Zamknij: Mój link'));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
  });

  testWidgets('one at a time: a second tap opens no second sheet', (
    tester,
  ) async {
    final h = await _pump(tester, open: false);
    final context = tester.element(find.byKey(const ValueKey('open')));
    final first = h.open(context);
    final second = h.open(context);
    expect(identical(first, second), isTrue);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
  });

  testWidgets('320 px at 200 % text: stacked actions, nothing overflows', (
    tester,
  ) async {
    await _pump(tester, size: const Size(320, 690), textScale: 2);
    expect(tester.takeException(), isNull);
    final copy = tester.getRect(_copy);
    final share = tester.getRect(_share);
    expect(share.bottom, lessThanOrEqualTo(copy.top));
    expect(copy.width, share.width);
    // The link is printed whole, never elided.
    final link = tester.widget<Text>(
      find.byKey(const ValueKey('my-link-text')),
    );
    expect(link.overflow, isNull);
    expect(link.maxLines, isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('my-link-qr'))).width,
      lessThanOrEqualTo(220),
    );
  });

  testWidgets('a long language stacks the actions instead of cutting them', (
    tester,
  ) async {
    await _pump(tester, locale: const Locale('el'));
    expect(tester.takeException(), isNull);
    expect(find.text('Αντιγραφή συνδέσμου'), findsOneWidget);
    final copy = tester.getRect(_copy);
    final share = tester.getRect(_share);
    expect(share.bottom, lessThanOrEqualTo(copy.top));
    expect(copy.width, 350);
  });

  testWidgets('RTL: the sheet mirrors, the link stays left-to-right', (
    tester,
  ) async {
    await _pump(tester, locale: const Locale('ar'));
    expect(tester.takeException(), isNull);
    expect(find.text('رابطي'), findsOneWidget);
    final link = tester.widget<Text>(
      find.byKey(const ValueKey('my-link-text')),
    );
    expect(link.textDirection, TextDirection.ltr);
    expect(_linkText(tester), 'app.yovoice.app/?user=$_uid');
  });

  testWidgets('Pearl renders the same structure', (tester) async {
    await _pump(tester, theme: AppTheme.lightTheme);
    expect(tester.takeException(), isNull);
    expect(find.byType(BarcodeWidget), findsOneWidget);
    expect(find.text('Kopiuj link'), findsOneWidget);
  });

  testWidgets('without a session there is no code and no link', (tester) async {
    await _pump(tester, harness: _Harness(signedIn: false));
    expect(_panel, findsOneWidget);
    expect(find.text('Twój link jest teraz niedostępny.'), findsOneWidget);
    expect(find.byType(BarcodeWidget), findsNothing);
    expect(_copy, findsNothing);
    expect(_share, findsNothing);
  });

  group('shareMyLink (every "invite friends" action)', () {
    testWidgets('shares the own profile link, never a download page', (
      tester,
    ) async {
      final h = await _pump(tester, open: false);
      final context = tester.element(find.byKey(const ValueKey('open')));
      final ok = await shareMyLink(
        context,
        userId: _uid,
        shareInvoker: (params) async {
          h.shared.add(params);
          return const ShareResult('raw', ShareResultStatus.success);
        },
      );
      expect(ok, isTrue);
      expect(h.shared.single.text, 'Znajdź mnie w YO Voice: $_link');
      expect(h.shared.single.text, isNot(contains('/download')));
    });

    testWidgets('says so when there is no link to share', (tester) async {
      await _pump(tester, open: false);
      final context = tester.element(find.byKey(const ValueKey('open')));
      var calls = 0;
      final ok = await shareMyLink(
        context,
        userId: 'not a/valid id',
        shareInvoker: (params) async {
          calls++;
          return const ShareResult('raw', ShareResultStatus.success);
        },
      );
      await tester.pump();
      expect(ok, isFalse);
      expect(calls, 0);
      expect(find.text('Twój link jest teraz niedostępny.'), findsOneWidget);
    });
  });
}
