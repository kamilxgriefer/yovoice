import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/account/data/account_deletion_service.dart';
import 'package:yovoice/features/auth/data/reauthentication_service.dart';
import 'package:yovoice/features/settings/presentation/screens/delete_account_screen.dart';

class _FakeReauthentication implements ReauthenticationClient {
  _FakeReauthentication({this.providers = const ['password'], this.fail});

  final List<String> providers;
  final Object? fail;
  final passwords = <String>[];
  int googleCalls = 0;
  int appleCalls = 0;

  @override
  List<String> get providerIds => providers;

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    passwords.add(password);
    if (fail != null) throw fail!;
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    googleCalls++;
    if (fail != null) throw fail!;
  }

  @override
  Future<void> reauthenticateWithApple() async {
    appleCalls++;
    if (fail != null) throw fail!;
  }
}

class _FakeDeletion implements AccountDeletionClient {
  _FakeDeletion({this.failure, this.events});

  final AccountDeletionFailure? failure;

  /// A shared, ordered log. Counters prove that two things happened; only an
  /// order proves the request is accepted BEFORE the session is dropped, and
  /// that the session is still open while the pending panel is readable.
  final List<String>? events;
  int calls = 0;

  @override
  Future<AccountDeletionReceipt> requestDeletion() async {
    calls++;
    events?.add('callable');
    final failed = failure;
    if (failed != null) throw failed;
    return const AccountDeletionReceipt(state: AccountDeletionState.pending);
  }
}

Future<void> pumpDeleteAccount(
  WidgetTester tester, {
  required Size size,
  ReauthenticationClient? reauthentication,
  AccountDeletionClient? deletion,
  DeleteAccountSignOut? signOut,
  DeleteAccountUrlOpener? openUrl,
  bool isRootTab = false,
  double textScale = 1,
  Locale locale = const Locale('pl'),
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: AppTheme.darkTheme,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: DeleteAccountScreen(
        isRootTab: isRootTab,
        reauthentication: reauthentication ?? _FakeReauthentication(),
        deletionClient: deletion ?? _FakeDeletion(),
        signOut: signOut ?? () async {},
        openUrl: openUrl ?? (_) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Walks the flow to the confirmation dialog and types the word.
Future<void> reachConfirmation(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey('delete-account-primary')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('delete-account-primary')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('delete-account-password-field')),
    'hunter2',
  );
  await tester.tap(
    find.byKey(const ValueKey('delete-account-password-submit')),
  );
  await tester.pumpAndSettle();
}

void main() {
  const heading = 'Usunięcie konta jest nieodwracalne. Oto co się stanie.';
  const messageLine =
      'Wiadomości, które wysłałeś(-aś), pozostaną widoczne dla odbiorcy jako '
      'pochodzące z usuniętego konta. Wysłane pliki i notatki głosowe zostaną '
      'usunięte.';

  testWidgets('the consequences are stated at narrow, medium and wide', (
    tester,
  ) async {
    for (final size in [
      const Size(390, 900),
      const Size(820, 1000),
      const Size(1280, 900),
    ]) {
      await pumpDeleteAccount(tester, size: size);
      expect(find.text(heading), findsOneWidget, reason: '$size');
      // The six deletions are the promise the backend has to keep, so every
      // one of them is on the screen before the button is reachable.
      expect(
        find.byKey(const ValueKey('delete-account-consequences')),
        findsOneWidget,
        reason: '$size',
      );
      expect(find.text(messageLine), findsOneWidget, reason: '$size');
      expect(
        find.byKey(const ValueKey('delete-account-primary')),
        findsOneWidget,
        reason: '$size',
      );
      // Never remove existing functionality: the email route this screen
      // replaced is still here, demoted to a secondary action.
      expect(
        find.byKey(const ValueKey('delete-account-email-fallback')),
        findsOneWidget,
        reason: '$size',
      );
    }
  });

  testWidgets(
    'a pushed route carries a back affordance, a content slot does not',
    (tester) async {
      await pumpDeleteAccount(tester, size: const Size(390, 900));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byTooltip('Wstecz'), findsOneWidget);

      // Inside the desktop shell the shell owns navigation, so the screen draws
      // no app bar of its own.
      await pumpDeleteAccount(
        tester,
        size: const Size(1280, 900),
        isRootTab: true,
      );
      expect(find.byType(AppBar), findsNothing);
      expect(find.text(heading), findsOneWidget);
    },
  );

  testWidgets('the whole page still reads at 200 percent text scale', (
    tester,
  ) async {
    await pumpDeleteAccount(tester, size: const Size(390, 900), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text(heading), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('delete-account-primary')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('what we keep is named, with the reason for each item', (
    tester,
  ) async {
    await pumpDeleteAccount(tester, size: const Size(390, 1800));
    const banDigest =
        'Jeśli Twoje konto było zablokowane — jednokierunkowy skrót adresu '
        'e-mail, aby usunięcie konta nie znosiło blokady. Sam adres nie jest '
        'przechowywany.';
    expect(find.text(banDigest), findsNothing);
    await tester.tap(find.text('Co zachowujemy i dlaczego'));
    await tester.pumpAndSettle();
    expect(find.text(banDigest), findsOneWidget);
    expect(
      find.textContaining('Zgłoszenia, które wysłałeś(-aś)'),
      findsOneWidget,
    );
    // The export gap is still real and the screen keeps saying so.
    expect(find.textContaining('wyeksportować'), findsOneWidget);
  });

  testWidgets(
    'deletion proves identity, takes a typed word, then calls the callable',
    (tester) async {
      final events = <String>[];
      final reauth = _FakeReauthentication();
      final deletion = _FakeDeletion(events: events);
      var signedOut = 0;
      await pumpDeleteAccount(
        tester,
        size: const Size(390, 900),
        reauthentication: reauth,
        deletion: deletion,
        signOut: () async {
          signedOut++;
          events.add('signOut');
        },
      );

      await reachConfirmation(tester);
      expect(reauth.passwords, ['hunter2']);
      expect(
        find.byKey(const ValueKey('delete-account-confirm-dialog')),
        findsOneWidget,
      );

      // Nothing has been asked of the server yet, and the destructive control is
      // inert until the word is typed.
      expect(deletion.calls, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('delete-account-confirm-submit')),
            )
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(const ValueKey('delete-account-confirm-field')),
        'usuń',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('delete-account-confirm-submit')),
      );
      await tester.pumpAndSettle();

      expect(deletion.calls, 1);
      // The pipeline is asynchronous, so the screen says "being deleted" — never
      // "deleted".
      expect(
        find.byKey(const ValueKey('delete-account-pending')),
        findsOneWidget,
      );
      expect(find.text('Twoje konto jest usuwane'), findsOneWidget);
      // The panel may not claim a sign-out that has not happened. The sentence
      // it actually renders is asserted here, not paraphrased: at this point
      // the session is still open and Done is what ends it.
      expect(
        find.text(
          'Zwykle kończy się to w ciągu kilku minut. Naciśnij Gotowe, aby '
          'wylogować się na tym urządzeniu.',
        ),
        findsOneWidget,
      );
      expect(signedOut, 0);
      expect(events, ['callable']);

      await tester.tap(find.byKey(const ValueKey('delete-account-done')));
      await tester.pumpAndSettle();
      expect(signedOut, 1);
      // Order, not merely occurrence: the callable is asked first and the
      // session is dropped second, on the tap and never before it.
      expect(events, ['callable', 'signOut']);
    },
  );

  testWidgets(
    'the English pending panel promises the same sign-out, and only on Done',
    (tester) async {
      final events = <String>[];
      final deletion = _FakeDeletion(events: events);
      await pumpDeleteAccount(
        tester,
        size: const Size(390, 900),
        deletion: deletion,
        locale: const Locale('en'),
        signOut: () async => events.add('signOut'),
      );
      await reachConfirmation(tester);
      await tester.enterText(
        find.byKey(const ValueKey('delete-account-confirm-field')),
        'DELETE',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('delete-account-confirm-submit')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your account is being deleted'), findsOneWidget);
      expect(
        find.text(
          'This usually finishes within a few minutes. Tap Done to sign out '
          'on this device.',
        ),
        findsOneWidget,
      );
      expect(events, ['callable']);

      await tester.tap(find.byKey(const ValueKey('delete-account-done')));
      await tester.pumpAndSettle();
      expect(events, ['callable', 'signOut']);
    },
  );

  testWidgets('cancelling the confirmation asks the server for nothing', (
    tester,
  ) async {
    final deletion = _FakeDeletion();
    await pumpDeleteAccount(
      tester,
      size: const Size(390, 900),
      deletion: deletion,
    );
    await reachConfirmation(tester);
    await tester.tap(
      find.byKey(const ValueKey('delete-account-confirm-cancel')),
    );
    await tester.pumpAndSettle();
    expect(deletion.calls, 0);
    expect(find.byKey(const ValueKey('delete-account-pending')), findsNothing);
    expect(find.text(heading), findsOneWidget);
  });

  testWidgets('a wrong password stops the flow with a localized sentence', (
    tester,
  ) async {
    final deletion = _FakeDeletion();
    await pumpDeleteAccount(
      tester,
      size: const Size(390, 900),
      reauthentication: _FakeReauthentication(
        fail: FirebaseAuthException(code: 'wrong-password'),
      ),
      deletion: deletion,
    );
    await reachConfirmation(tester);
    expect(find.text('Nieprawidłowy adres e-mail lub hasło.'), findsOneWidget);
    // The confirmation is never reached, so the server is never asked.
    expect(
      find.byKey(const ValueKey('delete-account-confirm-dialog')),
      findsNothing,
    );
    expect(deletion.calls, 0);
  });

  // Two-factor authentication is a shipped feature, and an enrolled account is
  // exactly the account that CANNOT finish a re-authentication here: Firebase
  // answers `second-factor-required` (native) or `multi-factor-auth-required`
  // (web) and this screen has no second-factor step. Before this the user got a
  // generic auth error and a dead end — the users who followed our own security
  // advice locked out of the affordance Google Play requires.
  for (final code in const ['second-factor-required', 'multi-factor-auth-required']) {
    testWidgets('a 2FA account is sent to the route that works ($code)', (
      tester,
    ) async {
      final deletion = _FakeDeletion();
      await pumpDeleteAccount(
        tester,
        size: const Size(390, 900),
        reauthentication: _FakeReauthentication(
          fail: FirebaseAuthException(code: code),
        ),
        deletion: deletion,
      );
      await reachConfirmation(tester);

      expect(
        find.textContaining('weryfikacji dwuskładnikowej'),
        findsOneWidget,
      );
      // It names the button that is actually on this screen, so the sentence is
      // an instruction rather than an apology.
      expect(
        find.textContaining('„Poproś nas o to e-mailem”'),
        findsOneWidget,
      );
      expect(
        find.text('Poproś nas o to e-mailem'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('delete-account-confirm-dialog')),
        findsNothing,
      );
      expect(deletion.calls, 0);
    });
  }

  testWidgets('an account this app cannot re-challenge is told what to do', (
    tester,
  ) async {
    final deletion = _FakeDeletion();
    await pumpDeleteAccount(
      tester,
      size: const Size(390, 900),
      reauthentication: _FakeReauthentication(providers: const ['phone']),
      deletion: deletion,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('delete-account-primary')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-account-primary')));
    await tester.pumpAndSettle();
    expect(
      find.text('Wyloguj się i zaloguj ponownie przed usunięciem konta.'),
      findsOneWidget,
    );
    expect(deletion.calls, 0);
  });

  testWidgets('a federated account is re-challenged with its own provider', (
    tester,
  ) async {
    final reauth = _FakeReauthentication(providers: const ['google.com']);
    await pumpDeleteAccount(
      tester,
      size: const Size(390, 900),
      reauthentication: reauth,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('delete-account-primary')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-account-primary')));
    await tester.pumpAndSettle();
    expect(reauth.googleCalls, 1);
    expect(reauth.passwords, isEmpty);
    // No password dialog for an account that has no password.
    expect(
      find.byKey(const ValueKey('delete-account-password-dialog')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('delete-account-confirm-dialog')),
      findsOneWidget,
    );
  });

  testWidgets(
    'a callable that is not live yet says so and keeps the email route',
    (tester) async {
      final opened = <String>[];
      await pumpDeleteAccount(
        tester,
        size: const Size(390, 900),
        deletion: _FakeDeletion(
          failure: const AccountDeletionFailure(
            AccountDeletionFailureKind.unavailable,
            code: 'not-found',
          ),
        ),
        openUrl: (url) async => opened.add(url),
      );
      await reachConfirmation(tester);
      await tester.enterText(
        find.byKey(const ValueKey('delete-account-confirm-field')),
        'USUŃ',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('delete-account-confirm-submit')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('delete-account-error')),
        findsOneWidget,
      );
      expect(find.textContaining('nie jest jeszcze dostępne'), findsOneWidget);
      expect(find.textContaining('not-found'), findsNothing);
      expect(
        find.byKey(const ValueKey('delete-account-pending')),
        findsNothing,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('delete-account-email-fallback')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('delete-account-email-fallback')),
      );
      await tester.pumpAndSettle();
      expect(opened.single, startsWith('mailto:privacy@yovoice.app'));
    },
  );

  testWidgets('English carries the same promise, word for word', (
    tester,
  ) async {
    await pumpDeleteAccount(
      tester,
      size: const Size(390, 1000),
      locale: const Locale('en'),
    );
    expect(
      find.text('Deleting your account is permanent. This is what happens.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Your profile, and the photos, videos, voice recordings and files you '
        'uploaded to your own account, are deleted.',
      ),
      findsOneWidget,
    );
    // The Server line says what the pipeline does — anonymize the membership
    // and leave the Server running — not the closure it used to promise.
    expect(
      find.text(
        'Your name and photo are removed from every server you were in. '
        'Servers you own keep running under an anonymous owner until we '
        'transfer or close them.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('are closed'), findsNothing);
    expect(find.text('Delete my account permanently'), findsOneWidget);
    expect(find.text('What we keep, and why'), findsOneWidget);
  });
}
