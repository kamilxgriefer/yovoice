import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/presentation/widgets/yo_top_notification_host.dart';

void main() {
  for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
    for (final width in [320.0, 390.0, 768.0, 1440.0]) {
      testWidgets('top notification ${theme.brightness.name} $width at 200%', (
        tester,
      ) async {
        final size = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final controller = YoTopNotificationController();
        var opened = 0;
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
                padding: const EdgeInsets.only(top: 47),
                viewPadding: const EdgeInsets.only(top: 47),
                textScaler: const TextScaler.linear(2),
              ),
              child: YoTopNotificationHost(
                controller: controller,
                child: child!,
              ),
            ),
            home: const Scaffold(body: SizedBox.expand()),
          ),
        );
        expect(
          controller.show(
            YoTopNotification(
              title:
                  'Aleksandra przesłała Ci wiadomość z bardzo długim tytułem',
              body:
                  'Otwórz rozmowę, aby zobaczyć całą wiadomość i odpowiedzieć. '
                  'Ta treść powinna pozostać czytelna przy powiększeniu tekstu.',
              type: NotificationType.directMessage,
              onOpen: () => opened++,
            ),
          ),
          isTrue,
        );
        await tester.pumpAndSettle();
        final card = find.byKey(const ValueKey('yo-top-notification-card'));
        final rect = tester.getRect(card);
        expect(rect.top, 57);
        expect(rect.left, greaterThanOrEqualTo(16));
        expect(rect.right, lessThanOrEqualTo(width - 16));
        expect(rect.width, lessThanOrEqualTo(520));
        expect(rect.height, lessThanOrEqualTo(360));
        final palette = theme.brightness == Brightness.dark
            ? AppPalette.dark
            : AppPalette.light;
        expect(tester.widget<Material>(card).color, palette.surfaceRaised);
        expect(find.text('Otwórz'), findsOneWidget);
        expect(find.byTooltip('Zamknij'), findsOneWidget);
        for (final key in [
          'yo-top-notification-open',
          'yo-top-notification-close',
        ]) {
          final size = tester.getSize(find.byKey(ValueKey(key)));
          expect(size.width, greaterThanOrEqualTo(44));
          expect(size.height, greaterThanOrEqualTo(44));
        }
        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('yo-top-notification-scroll')),
            matching: find.byType(Text),
          ),
        )) {
          expect(text.maxLines, isNull);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
        }
        await tester.tap(
          find.byKey(const ValueKey('yo-top-notification-open')),
        );
        await tester.pump();
        expect(opened, 1);
        expect(card, findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      });
    }
  }
  testWidgets('achievement uses title-only trophy and two-second lifetime', (
    tester,
  ) async {
    final controller = YoTopNotificationController();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            YoTopNotificationHost(controller: controller, child: child!),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    controller.show(
      YoTopNotification(
        title: 'Achievement unlocked: First Word',
        body: 'Unused duplicate body',
        type: NotificationType.achievementUnlocked,
        onOpen: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
    expect(find.text('Unused duplicate body'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('yo-top-notification-card')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
