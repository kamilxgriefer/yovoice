import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/settings/presentation/screens/settings_screen.dart';

/// R-09: Settings → Account → "Account type" rendered the raw
/// [AccountType.label] enum name, so a Polish UI showed "Typ konta: Personal".
/// The row now resolves through [settingsAccountTypeLabel], which is worded
/// exactly like the account-type badge in `profile_header.dart`.
void main() {
  const english = AppLocalizations(Locale('en'));
  const polish = AppLocalizations(Locale('pl'));

  group('settingsAccountTypeLabel', () {
    test('English keeps the shipped wording for every account type', () {
      expect(
        settingsAccountTypeLabel(english, AccountType.personal),
        'Personal',
      );
      expect(settingsAccountTypeLabel(english, AccountType.creator), 'Creator');
      expect(
        settingsAccountTypeLabel(english, AccountType.official),
        'Official',
      );
    });

    test('Polish translates every account type', () {
      expect(
        settingsAccountTypeLabel(polish, AccountType.personal),
        'Osobiste',
      );
      expect(settingsAccountTypeLabel(polish, AccountType.creator), 'Twórca');
      expect(
        settingsAccountTypeLabel(polish, AccountType.official),
        'Oficjalne',
      );
    });

    test('no account type leaks its English enum label into Polish', () {
      for (final type in AccountType.values) {
        expect(
          settingsAccountTypeLabel(polish, type),
          isNot(type.label),
          reason:
              'AccountType.${type.name} still renders the English label '
              '"${type.label}" in Polish.',
        );
      }
    });

    test('matches the wording of the profile account-type badge', () {
      // profile_header.dart's _AccountTypeBadge uses these exact pairs; the
      // two surfaces describing the same field must not diverge.
      const expected = <AccountType, (String, String)>{
        AccountType.personal: ('Personal', 'Osobiste'),
        AccountType.creator: ('Creator', 'Twórca'),
        AccountType.official: ('Official', 'Oficjalne'),
      };
      for (final type in AccountType.values) {
        final pair = expected[type];
        expect(
          pair,
          isNotNull,
          reason:
              'AccountType.${type.name} has no agreed wording — add it here '
              'and in profile_header.dart together.',
        );
        expect(settingsAccountTypeLabel(english, type), pair!.$1);
        expect(settingsAccountTypeLabel(polish, type), pair.$2);
      }
    });
  });
}
