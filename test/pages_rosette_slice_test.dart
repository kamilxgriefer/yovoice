// Premium Pages C0 (spec premium-pages §4.6): the rosette slice. The header
// rosette's 44×44 target and the "VIP doesn't mean verified" sheet (R14),
// `PublicIdentity.pageKind` from `publicBadges.page`, and `PageFace`.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_pages.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/identity/vip_meaning_sheet.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';

import 'support/likers_fixtures.dart';

const _explainKey = ValueKey<String>('vip-mark-explain');

Future<void> _setView(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _header({
  required String name,
  bool vip = true,
  int? maxLines = 1,
  double width = 360,
  bool explain = true,
}) => Scaffold(
  body: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: width,
          child: NameWithVipMark(
            uid: 'page',
            name: name,
            isVip: vip,
            maxLines: maxLines,
            explainOnTap: explain,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        const Text('Business · 1.2K followers'),
      ],
    ),
  ),
);

ProfileMediaService _noPhoto() => ProfileMediaService(
  auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
  invoker: (_, _) async => {
    'schemaVersion': 1,
    'available': false,
    'expiresAtMillis': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch,
  },
);

void main() {
  group('PublicIdentity.pageKind', () {
    test('parses publicBadges.page and fails safe', () {
      PageKind? kind(Map<String, dynamic> wire) =>
          PublicIdentity.fromWire(wire).pageKind;
      expect(kind({'page': 'business'}), PageKind.business);
      expect(kind({'page': 'community'}), PageKind.community);
      expect(kind({'page': null}), isNull);
      expect(kind(const {}), isNull, reason: 'absent means null');
      expect(kind({'page': 'podcast'}), isNull, reason: 'unknown kind');
      expect(kind({'page': 1}), isNull);
      expect(PublicIdentity.fallback.pageKind, isNull);
      expect(PublicIdentity.fallback.isPage, isFalse);
    });

    test('unknown keys are ignored and the page kind joins equality', () {
      final a = PublicIdentity.fromWire({
        'staffRole': 'user',
        'isVip': true,
        'page': 'community',
        'someFutureKey': {'x': 1},
      });
      expect(a.isVip, isTrue);
      expect(a.isPage, isTrue);
      const b = PublicIdentity(
        role: OfficialRole.user,
        isVip: true,
        pageKind: PageKind.community,
      );
      const c = PublicIdentity(role: OfficialRole.user, isVip: true);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('the repository carries the page kind from getPublicBadges', () async {
      final repository = PublicIdentityRepository(
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
        fetchOverride: (uids) async => {
          'cafe': {'staffRole': 'user', 'isVip': true, 'page': 'business'},
          'ola': {'staffRole': 'user', 'isVip': false},
        },
        flushDelay: const Duration(milliseconds: 1),
      );
      expect((await repository.resolve('cafe')).pageKind, PageKind.business);
      expect((await repository.resolve('ola')).pageKind, isNull);
    });
  });

  group('header rosette target (R14)', () {
    testWidgets('one line: a 44×44 VIP button that does not move the mark', (
      tester,
    ) async {
      await tester.pumpWidget(likersHost(_header(name: 'Kawiarnia Ziarno')));
      await tester.pumpAndSettle();

      final target = tester.getRect(find.byKey(_explainKey));
      expect(target.width, greaterThanOrEqualTo(44));
      expect(target.height, greaterThanOrEqualTo(44));
      final mark = tester.getRect(find.byType(YoVipRosette));
      expect(target.contains(mark.center), isTrue);
      final name = tester.getRect(find.text('Kawiarnia Ziarno'));
      expect(mark.left - name.right, inInclusiveRange(0, 6));
      expect((mark.center.dy - name.center.dy).abs(), lessThan(2));

      final semantics = tester.getSemantics(find.byKey(_explainKey));
      expect(semantics.label, 'VIP');
      expect(semantics.hint, 'Shows what VIP means');
      expect(semantics.flagsCollection.isButton, isTrue);
      // The painted mark adds no second "VIP".
      expect(find.bySemanticsLabel('VIP'), findsOneWidget);
    });

    testWidgets('tapping the mark opens the VIP sheet; Got it closes it', (
      tester,
    ) async {
      await tester.pumpWidget(likersHost(_header(name: 'Kawiarnia Ziarno')));
      await tester.pumpAndSettle();
      // The edge of the target, away from the painted mark, still opens it.
      final target = tester.getRect(find.byKey(_explainKey));
      await tester.tapAt(target.bottomRight - const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byKey(VipMeaningSheet.surfaceKey), findsOneWidget);
      expect(find.text("VIP doesn't mean verified"), findsOneWidget);
      expect(find.text('YO Voice membership'), findsOneWidget);
      expect(find.text('Official'), findsOneWidget);
      expect(find.text('Account run by the YO Voice team'), findsOneWidget);
      expect(find.textContaining('verified'), findsWidgets);

      await tester.tap(find.byKey(VipMeaningSheet.closeKey));
      await tester.pumpAndSettle();
      expect(find.byKey(VipMeaningSheet.surfaceKey), findsNothing);
    });

    testWidgets('from a nested tab navigator the sheet opens on the root one', (
      tester,
    ) async {
      // Treści hosts Page profiles on its own Navigator above the dock; the
      // sheet must cover the dock rather than stop above it.
      const dockKey = ValueKey<String>('dock');
      await tester.pumpWidget(
        likersHost(
          Scaffold(
            body: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => _header(name: 'Kawiarnia Ziarno'),
              ),
            ),
            bottomNavigationBar: const SizedBox(key: dockKey, height: 72),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_explainKey));
      await tester.pumpAndSettle();

      final sheet = find.byKey(VipMeaningSheet.surfaceKey);
      expect(sheet, findsOneWidget);
      final navigators = find.ancestor(
        of: sheet,
        matching: find.byType(Navigator),
      );
      expect(
        navigators,
        findsOneWidget,
        reason: 'only the root navigator sits above the sheet',
      );
      expect(
        tester.getRect(sheet).bottom,
        greaterThan(tester.getRect(find.byKey(dockKey)).top),
      );
    });

    testWidgets('multi-line: the button sits over the inline mark', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        likersHost(
          Scaffold(
            body: SizedBox(
              width: 200,
              child: NameWithVipMark(
                uid: 'page',
                name: 'Stowarzyszenie Miłośników Kawy',
                isVip: true,
                maxLines: 2,
                explainOnTap: true,
                onExplain: () => opened++,
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final target = tester.getRect(find.byKey(_explainKey));
      expect(target.size, const Size.square(44));
      final mark = tester.getRect(find.byType(YoVipRosette));
      expect(target.contains(mark.center), isTrue);
      expect((target.center - mark.center).distance, lessThan(1.5));
      await tester.tapAt(target.topLeft + const Offset(2, 2));
      expect(opened, 1);
    });

    testWidgets('multi-line RTL keeps the target over the mark', (
      tester,
    ) async {
      await tester.pumpWidget(
        likersHost(
          Scaffold(
            body: SizedBox(
              width: 220,
              child: NameWithVipMark(
                uid: 'page',
                name: 'مقهى الحبة الذهبية للقهوة المختصة',
                isVip: true,
                maxLines: 2,
                explainOnTap: true,
                onExplain: () {},
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          locale: const Locale('ar'),
          direction: TextDirection.rtl,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final target = tester.getRect(find.byKey(_explainKey));
      final mark = tester.getRect(find.byType(YoVipRosette));
      expect(target.contains(mark.center), isTrue);
    });

    testWidgets('multi-line at 200 %: the inline mark keeps its size and '
        'survives truncation', (tester) async {
      for (final name in [
        'Kawiarnia Ziarno',
        'Stowarzyszenie Miłośników Kawy Speciality Wrocław',
      ]) {
        await tester.pumpWidget(
          likersHost(
            Scaffold(
              body: SizedBox(
                width: 288,
                child: NameWithVipMark(
                  uid: 'page',
                  name: name,
                  isVip: true,
                  maxLines: 2,
                  explainOnTap: true,
                  onExplain: () {},
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
            textScale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final mark = tester.getRect(find.byType(YoVipRosette));
        // 0.92 × 44 clamps to 24: the WidgetSpan's own 2× scale must not
        // double it.
        expect(mark.width, closeTo(24, .01), reason: name);
        final paragraph = tester.getRect(
          find
              .descendant(
                of: find.byType(NameWithVipMark),
                matching: find.byType(RichText),
              )
              .first,
        );
        expect(mark.right, lessThanOrEqualTo(paragraph.right + .01));
        expect(mark.bottom, lessThanOrEqualTo(paragraph.bottom + .01));
        final target = tester.getRect(find.byKey(_explainKey));
        expect(target.contains(mark.center), isTrue, reason: name);
      }
    });

    testWidgets('RTL: a short name is not pushed onto a second line', (
      tester,
    ) async {
      await tester.pumpWidget(
        likersHost(
          const Scaffold(
            body: SizedBox(
              // Wide enough for name + mark on one line (test font).
              width: 420,
              child: NameWithVipMark(
                uid: 'page',
                name: 'Kawiarnia Ziarno',
                isVip: true,
                maxLines: 2,
                style: TextStyle(fontSize: 22),
              ),
            ),
          ),
          locale: const Locale('ar'),
          direction: TextDirection.rtl,
        ),
      );
      await tester.pumpAndSettle();
      final rich = tester.widget<RichText>(
        find
            .descendant(
              of: find.byType(NameWithVipMark),
              matching: find.byType(RichText),
            )
            .first,
      );
      expect(rich.text.toPlainText(), isNot(contains('\n')));
    });

    testWidgets('lists and non-VIP names get no button', (tester) async {
      await tester.pumpWidget(
        likersHost(
          const Scaffold(
            body: Column(
              children: [
                NameWithVipMark(
                  uid: 'ola',
                  name: 'Ola',
                  isVip: false,
                  explainOnTap: true,
                  style: TextStyle(fontSize: 22),
                ),
                NameWithVipMark(
                  uid: 'marta',
                  name: 'Marta',
                  isVip: true,
                  style: TextStyle(fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_explainKey), findsNothing);
      expect(find.byType(YoVipRosette), findsOneWidget);
      expect(find.bySemanticsLabel('VIP'), findsOneWidget);
    });

    testWidgets('multi-line: the full name and VIP are read, never the cut', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      const long = 'Pracownia Ceramiki Artystycznej Glina z Oliwy i Sopotu';
      Widget name({required bool vip, String? label}) => SizedBox(
        width: 120,
        child: NameWithVipMark(
          uid: vip ? 'vip' : 'plain',
          name: long,
          isVip: vip,
          maxLines: 2,
          semanticsLabel: label,
          style: const TextStyle(fontSize: 15),
        ),
      );
      await tester.pumpWidget(
        likersHost(
          Scaffold(
            body: Column(
              children: [
                MergeSemantics(child: name(vip: true)),
                MergeSemantics(
                  child: name(vip: true, label: '$long, Firma, 18 min'),
                ),
                MergeSemantics(child: name(vip: false)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('$long, VIP'), findsOneWidget);
      expect(
        find.bySemanticsLabel('$long, Firma, 18 min, VIP'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(long), findsOneWidget, reason: 'non-VIP');
      expect(find.bySemanticsLabel(RegExp('…|\u2060')), findsNothing);
      handle.dispose();
    });

    testWidgets('keyboard focus draws the ring and Enter opens the sheet', (
      tester,
    ) async {
      await tester.pumpWidget(likersHost(_header(name: 'Kawiarnia Ziarno')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vip-mark-focus-ring')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vip-mark-focus-ring')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(VipMeaningSheet.surfaceKey), findsOneWidget);
    });
  });

  group('VIP meaning sheet', () {
    testWidgets('Polish copy matches the approved render', (tester) async {
      await tester.pumpWidget(
        likersHost(
          const Scaffold(body: VipMeaningSheet()),
          locale: const Locale('pl'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('VIP nie oznacza weryfikacji'), findsOneWidget);
      expect(
        find.text(
          'VIP to członkostwo YO Voice. Nie oznacza, że konto jest '
          'zweryfikowane. YO Voice nie sprawdza tożsamości ani danych firm.',
        ),
        findsOneWidget,
      );
      expect(find.text('Członkostwo YO Voice'), findsOneWidget);
      expect(find.text('Oficjalne'), findsOneWidget);
      expect(
        find.text('Konto prowadzone przez zespół YO Voice'),
        findsOneWidget,
      );
      expect(find.text('Rozumiem'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(VipMeaningSheet.closeKey)).height,
        greaterThanOrEqualTo(48),
      );
    });

    for (final (label, size, scale) in <(String, Size, double)>[
      ('320 px at 200 %', const Size(320, 640), 2.0),
      ('390 px', const Size(390, 844), 1.0),
      ('tablet', const Size(820, 1180), 1.0),
      ('desktop', const Size(1440, 900), 1.0),
    ]) {
      testWidgets('opens without overflow: $label', (tester) async {
        await _setView(tester, size);
        await tester.pumpWidget(
          likersHost(
            Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showVipMeaningSheet(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
            textScale: scale,
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final sheet = tester.getRect(find.byKey(VipMeaningSheet.surfaceKey));
        if (size.width >= 600) {
          expect(sheet.width, lessThanOrEqualTo(kVipMeaningSheetMaxWidth));
        } else {
          expect(sheet.width, size.width);
        }
        await tester.ensureVisible(find.byKey(VipMeaningSheet.closeKey));
        await tester.tap(find.byKey(VipMeaningSheet.closeKey));
        await tester.pumpAndSettle();
        expect(find.byKey(VipMeaningSheet.surfaceKey), findsNothing);
      });
    }

    test('every translated locale carries the C0 copy', () {
      for (final entry in appTranslations.entries) {
        for (final key in pagesTranslationKeys) {
          final value = entry.value[key];
          expect(value, isNotNull, reason: '${entry.key} misses "$key"');
          expect(value!.trim(), isNotEmpty);
          if (key.contains('YO Voice')) {
            expect(value, contains('YO Voice'), reason: '${entry.key} $key');
          }
          if (key.startsWith('VIP')) {
            expect(value, contains('VIP'), reason: '${entry.key} $key');
          }
        }
      }
    });
  });

  group('PageFace', () {
    testWidgets('letter fallback in the 14 px squircle, no semantics', (
      tester,
    ) async {
      await tester.pumpWidget(
        likersHost(
          Scaffold(
            body: Center(
              child: PageFace(
                pageId: 'cafe',
                name: ' kawiarnia Ziarno',
                size: 40,
                mediaService: _noPhoto(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(PageFace)), const Size.square(40));
      expect(find.byKey(const ValueKey('page-face-letter')), findsOneWidget);
      expect(find.text('K'), findsOneWidget);
      final clip = tester.widget<ClipRRect>(
        find.descendant(
          of: find.byType(PageFace),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(clip.borderRadius, AppRadius.md);
      expect(find.bySemanticsLabel('K'), findsNothing);
    });

    testWidgets('the ring grows the face by its width on every side', (
      tester,
    ) async {
      await tester.pumpWidget(
        likersHost(
          Scaffold(
            body: Center(
              child: PageFace(
                pageId: 'cafe',
                name: '☕ Ziarno',
                size: 80,
                ring: 3,
                mediaService: _noPhoto(),
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(PageFace)), const Size.square(86));
      expect(find.text('☕'), findsOneWidget, reason: 'first grapheme');
      final letter = tester.widget<Text>(find.text('☕'));
      expect(letter.textScaler, TextScaler.noScaling);
      expect(PageFace.initialFor('   '), '?');
    });
  });
}
