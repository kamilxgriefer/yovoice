import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_social_button.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

const _polishCopy = AppLocalizations(Locale('pl'));

Widget _polishHost(Widget child) {
  return MaterialApp(
    locale: const Locale('pl'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.darkTheme,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('shared Polish presentation copy', () {
    testWidgets(
      'official roles localize without changing the wire vocabulary',
      (tester) async {
        expect(OfficialRole.ownerSuperAdmin.label, 'OWNER · SUPER ADMIN');
        expect(
          OfficialRole.ownerSuperAdmin.localizedLabel(_polishCopy),
          'WŁAŚCICIEL · SUPERADMIN',
        );

        await tester.pumpWidget(
          _polishHost(
            const Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                OfficialRoleBadge(role: OfficialRole.user),
                OfficialRoleBadge(role: OfficialRole.guideMaster),
                OfficialRoleBadge(role: OfficialRole.support),
                OfficialRoleBadge(role: OfficialRole.auditor),
                OfficialRoleBadge(role: OfficialRole.ownerSuperAdmin),
              ],
            ),
          ),
        );

        expect(find.text('UŻYTKOWNIK'), findsOneWidget);
        expect(find.text('GŁÓWNY PRZEWODNIK'), findsOneWidget);
        expect(find.text('WSPARCIE'), findsOneWidget);
        expect(find.text('AUDYTOR'), findsOneWidget);
        expect(find.text('WŁAŚCICIEL · SUPERADMIN'), findsOneWidget);
        expect(find.text('OWNER · SUPER ADMIN'), findsNothing);
      },
    );

    testWidgets('modal close action includes its localized sheet name', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _polishHost(
          const Material(
            color: Color(0xFF120D1A),
            child: YoModalSheetChrome(
              sheetLabel: 'Ustawienia konta',
              surfaceColor: Color(0xFF120D1A),
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('Zamknij: Ustawienia konta'),
        findsOneWidget,
      );
      final button = tester.widget<YoIconButton>(
        find.byKey(const ValueKey<String>('modal-sheet-close')),
      );
      expect(button.tooltip, 'Zamknij: Ustawienia konta');
      semantics.dispose();
    });

    testWidgets('icon controls infer Polish labels and loading semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _polishHost(
          Wrap(
            children: <Widget>[
              YoIconButton(icon: Icons.arrow_back_rounded, onPressed: () {}),
              YoIconButton(icon: Icons.close_rounded, onPressed: () {}),
              YoIconButton(icon: Icons.settings_rounded, onPressed: () {}),
              YoIconButton(icon: Icons.search_rounded, onPressed: () {}),
              YoIconButton(icon: Icons.add_rounded, onPressed: () {}),
              YoIconButton(icon: Icons.more_horiz_rounded, onPressed: () {}),
              YoIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onPressed: () {},
                isLoading: true,
              ),
            ],
          ),
        ),
      );

      for (final label in <String>[
        'Wstecz',
        'Zamknij',
        'Ustawienia',
        'Szukaj',
        'Dodaj',
        'Więcej opcji',
        'Wstecz, trwa ładowanie',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      semantics.dispose();
    });

    testWidgets('button loading copy preserves caller labels and brands', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _polishHost(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              YoButton(label: 'Zapisz', onPressed: () {}, isLoading: true),
              YoSocialButton(
                label: 'Kontynuuj z Google',
                icon: Icons.login_rounded,
                onPressed: () {},
                isLoading: true,
              ),
            ],
          ),
        ),
      );

      expect(find.bySemanticsLabel('Zapisz, trwa ładowanie'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Kontynuuj z Google, trwa ładowanie'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('people status is localized in text and semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _polishHost(
          PeopleStatusAvatar(
            displayName: 'Ada Lovelace',
            status: PeopleStatus.inRoom,
            onTap: () {},
          ),
        ),
      );

      expect(find.text('W pokoju'), findsOneWidget);
      final data = tester
          .getSemantics(find.byType(PeopleStatusAvatar))
          .getSemanticsData();
      expect(data.label, 'Ada Lovelace');
      expect(data.value, 'W pokoju');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
      semantics.dispose();
    });

    testWidgets('YoErrorState localizes built-in body, heading and retry', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _polishHost(
          YoErrorState(
            error: Exception('SocketException: connection failed'),
            onRetry: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Coś poszło nie tak'), findsOneWidget);
      expect(
        find.text('Sprawdź połączenie z internetem i spróbuj ponownie.'),
        findsOneWidget,
      );
      expect(find.text('Spróbuj ponownie'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Coś poszło nie tak. Sprawdź połączenie z internetem i spróbuj ponownie.',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('Polish safe error mapping', () {
    test(
      'localizes every built-in error category without exposing internals',
      () {
        final cases = <(Object, String)>[
          (
            Exception('permission-denied private rule path'),
            'Nie masz uprawnień, aby to zrobić.',
          ),
          (
            Exception('not-found internal document id'),
            'Nie udało się tego znaleźć — element mógł zostać usunięty.',
          ),
          (
            Exception('deadline-exceeded internal timeout'),
            'To trwa dłużej, niż oczekiwano. Spróbuj ponownie.',
          ),
          (
            Exception('failed host lookup private endpoint'),
            'Sprawdź połączenie z internetem i spróbuj ponownie.',
          ),
          (
            Exception('unauthenticated private token'),
            'Zaloguj się ponownie, aby kontynuować.',
          ),
          (Exception('already-exists private id'), 'To już istnieje.'),
          (
            Exception('resource-exhausted private quota'),
            'Usługa jest teraz przeciążona — spróbuj ponownie za chwilę.',
          ),
          (Exception('cancelled private operation'), 'Anulowano.'),
          (
            Exception('NoSuchMethodError private stack'),
            'Coś poszło nie tak. Spróbuj ponownie.',
          ),
        ];

        for (final (error, expected) in cases) {
          final message = friendlyErrorMessage(error, copy: _polishCopy);
          expect(message, expected);
          expect(message, isNot(contains('private')));
        }
      },
    );

    test('localizes privileged authentication guidance', () {
      expect(
        friendlyErrorMessage(
          FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'private backend detail',
            details: const <String, Object?>{
              'reason': 'recent-authentication-required',
            },
          ),
          copy: _polishCopy,
        ),
        'Ze względów bezpieczeństwa zaloguj się ponownie przed wykonaniem tej chronionej operacji.',
      );
      expect(
        friendlyErrorMessage(
          FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'private backend detail',
            details: const <String, Object?>{
              'reason': 'multi-factor-authentication-required',
            },
          ),
          copy: _polishCopy,
        ),
        'Zaloguj się z użyciem uwierzytelniania dwuskładnikowego przed wykonaniem tej chronionej operacji.',
      );
    });

    test('keeps deliberate caller copy and explicit localized fallback', () {
      expect(
        intentionalOrFriendly(
          StateError('Własny komunikat procesu.'),
          copy: _polishCopy,
        ),
        'Własny komunikat procesu.',
      );
      expect(
        friendlyErrorMessage(
          Exception('unknown private error'),
          fallback: 'Nie udało się otworzyć widoku.',
          copy: _polishCopy,
        ),
        'Nie udało się otworzyć widoku.',
      );
    });
  });
}
