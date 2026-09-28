import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';

import 'support/likers_fixtures.dart';

Future<void> settleAll(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pumpAndSettle();
}

void main() {
  test('size and gap follow the owner-chosen formula', () {
    expect(YoVipRosette.diameterFor(15), closeTo(13.8, .001));
    expect(YoVipRosette.diameterFor(8), 12);
    expect(YoVipRosette.diameterFor(40), 24);
    expect(YoVipRosette.gapFor(10), 3);
    expect(YoVipRosette.gapFor(20), closeTo(3.6, .001));
  });

  test('fills derive from the brand primary (no new literal)', () {
    expect(YoVipRosette.fillFor(Brightness.light), AppColors.primary);
    expect(
      YoVipRosette.fillFor(Brightness.dark).toARGB32(),
      0xFF8B48F8,
      reason: 'Dark is the primary lifted 12 % toward white (tick variant B).',
    );
  });

  testWidgets('NameWithVipMark shows the rosette only for VIP accounts', (
    tester,
  ) async {
    final repository = identityRepository(vip: {'marta'});
    await tester.pumpWidget(
      likersHost(
        Scaffold(
          body: Column(
            children: [
              NameWithVipMark(
                uid: 'marta',
                name: 'Marta',
                style: const TextStyle(fontSize: 15),
                repository: repository,
              ),
              NameWithVipMark(
                uid: 'julia',
                name: 'Julia',
                style: const TextStyle(fontSize: 15),
                repository: repository,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(YoVipRosette), findsNothing);
    await settleAll(tester);
    expect(find.byType(YoVipRosette), findsOneWidget);
    expect(find.bySemanticsLabel('VIP'), findsOneWidget);
    final name = tester.getRect(find.text('Marta'));
    final mark = tester.getRect(find.byType(YoVipRosette));
    expect(mark.left, greaterThanOrEqualTo(name.right));
    expect(mark.left - name.right, lessThan(6));
  });

  testWidgets('one line: a long name ellipsizes and the mark stays visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      likersHost(
        Scaffold(
          body: SizedBox(
            width: 160,
            child: NameWithVipMark(
              uid: 'x',
              name: 'Aleksandra Konstantynopolitańczykiewicz',
              style: const TextStyle(fontSize: 15),
              isVip: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final mark = tester.getRect(find.byType(YoVipRosette));
    expect(mark.right, lessThanOrEqualTo(160));
    expect(mark.width, greaterThan(12));
  });

  testWidgets('multi-line: truncation keeps the mark after "…"', (
    tester,
  ) async {
    await tester.pumpWidget(
      likersHost(
        Scaffold(
          body: SizedBox(
            width: 140,
            child: NameWithVipMark(
              uid: 'x',
              name:
                  'Aleksandra Konstantynopolitańczykiewicz Wielkopolska '
                  'Zachodniopomorska',
              style: const TextStyle(fontSize: 15),
              maxLines: 2,
              isVip: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(YoVipRosette), findsOneWidget);
    final rich = tester.widget<RichText>(
      find
          .descendant(
            of: find.byType(NameWithVipMark),
            matching: find.byType(RichText),
          )
          .first,
    );
    expect(rich.text.toPlainText(), contains('…'));
  });

  testWidgets('semanticsLabel replaces the name, VIP stays its own node', (
    tester,
  ) async {
    await tester.pumpWidget(
      likersHost(
        Scaffold(
          body: NameWithVipMark(
            uid: 'x',
            name: 'Ola',
            semanticsLabel: 'Ola, reacted 👍',
            style: const TextStyle(fontSize: 15),
            isVip: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Ola, reacted 👍'), findsOneWidget);
    expect(find.bySemanticsLabel('VIP'), findsOneWidget);
  });
}
