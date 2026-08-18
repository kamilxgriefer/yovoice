import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('en'), Locale('pl')];

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('en'));
  }

  bool get isPolish => locale.languageCode == 'pl';

  String text(String english, String polish) => isPolish ? polish : english;

  String get settings => text('Settings', 'Ustawienia');
  String get appearance => text('Appearance', 'Wygląd');
  String get theme => text('Theme', 'Motyw');
  String get systemTheme =>
      text('Use device setting', 'Użyj ustawienia urządzenia');
  String get darkTheme => text('Dark', 'Ciemny');
  String get lightTheme => text('Light', 'Jasny');
  String get language => text('Language', 'Język');
  String get appLanguage => text('App language', 'Język aplikacji');
  String get systemLanguage =>
      text('Use device language', 'Użyj języka urządzenia');
  String get english => text('English', 'Angielski');
  String get polish => text('Polish', 'Polski');
  String get languagePreviewTitle =>
      text('Polish translation preview', 'Podgląd polskiego tłumaczenia');
  String get languagePreviewBody => text(
    'Navigation, authentication, Settings and system controls are being translated first. Some product screens still use English while the translation is completed.',
    'Najpierw tłumaczymy nawigację, logowanie, Ustawienia i kontrolki systemowe. Część ekranów produktu nadal używa języka angielskiego do czasu zakończenia tłumaczenia.',
  );
  String get savedOnDevice => text(
    'This preference is saved on this device.',
    'To ustawienie jest zapisane na tym urządzeniu.',
  );
  String get saveFailed => text(
    'Could not save this preference. Try again.',
    'Nie udało się zapisać ustawienia. Spróbuj ponownie.',
  );

  String get home => text('Home', 'Główna');
  String get discover => text('Discover', 'Odkrywaj');
  String get findCreators => text('Find creators', 'Znajdź twórców');
  String get chats => text('Chats', 'Czaty');
  String get notifications => text('Notifications', 'Powiadomienia');
  String get friends => text('Friends', 'Znajomi');
  String get more => text('More', 'Więcej');
  String get profile => text('Profile', 'Profil');

  String get email => text('Email', 'E-mail');
  String get password => text('Password', 'Hasło');
  String get logIn => text('LOG IN', 'ZALOGUJ SIĘ');
  String get continueWithGoogle =>
      text('Continue with Google', 'Kontynuuj z Google');
  String get continueWithApple =>
      text('Continue with Apple', 'Kontynuuj z Apple');
  String get noAccount => text("Don't have an account?", 'Nie masz konta?');
  String get signUp => text('Sign up', 'Zarejestruj się');
  String get forgotPassword => text('Forgot password?', 'Nie pamiętasz hasła?');
  String get resetPassword => text('Reset password', 'Zresetuj hasło');
  String get resetPasswordIntro => text(
    'Enter the email address for your YO Voice account. We will send a secure reset link if an account exists.',
    'Wpisz adres e-mail konta YO Voice. Jeśli konto istnieje, wyślemy bezpieczny link do zresetowania hasła.',
  );
  String get emailAddress => text('Email address', 'Adres e-mail');
  String get sendResetLink => text('SEND RESET LINK', 'WYŚLIJ LINK RESETUJĄCY');
  String get backToLogin => text('Back to log in', 'Wróć do logowania');
  String get createAccount => text('CREATE ACCOUNT', 'UTWÓRZ KONTO');
  String get username => text('Username', 'Nazwa użytkownika');
  String get confirmPassword => text('Confirm password', 'Powtórz hasło');
  String get alreadyHaveAccount =>
      text('Already have an account?', 'Masz już konto?');
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
