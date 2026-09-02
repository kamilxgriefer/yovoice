import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shared P1 surfaces cannot regress to raw English presentation copy',
    () {
      final forbidden = <String, List<String>>{
        'lib/shared/widgets/identity/official_role_badge.dart': <String>[
          'label: role.label',
        ],
        'lib/shared/widgets/overlays/yo_modal_sheet_chrome.dart': <String>[
          "final closeLabel = 'Close ",
        ],
        'lib/shared/widgets/buttons/yo_icon_button.dart': <String>[
          "return 'Back';",
          "return 'Close';",
          "return 'Settings';",
          "return 'Search';",
          "return 'Add';",
          "return 'More options';",
          r"'$effectiveLabel, loading'",
        ],
        'lib/shared/widgets/buttons/yo_button.dart': <String>[
          r"'${widget.label}, loading'",
        ],
        'lib/shared/widgets/buttons/yo_social_button.dart': <String>[
          r"'$label, loading'",
        ],
        'lib/shared/widgets/profile/people_status_ring.dart': <String>[
          'value: status.label',
          'Text(\n                      status.label',
        ],
        'lib/shared/widgets/states/yo_error_state.dart': <String>[
          'friendlyErrorMessage(error!);',
          "Text(\n                    'Something went wrong'",
          "label: 'Try again'",
        ],
      };

      final violations = <String>[];
      for (final entry in forbidden.entries) {
        final source = File(entry.key).readAsStringSync();
        for (final fragment in entry.value) {
          if (source.contains(fragment)) {
            violations.add('${entry.key}: raw fragment `$fragment`');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Visible copy and accessibility labels in shared components must '
            'cross AppLocalizations.\n${violations.join('\n')}',
      );
    },
  );

  test('shared templates use stable catalog keys with named placeholders', () {
    final buttonFiles = <String>[
      'lib/shared/widgets/buttons/yo_icon_button.dart',
      'lib/shared/widgets/buttons/yo_button.dart',
      'lib/shared/widgets/buttons/yo_social_button.dart',
    ];

    for (final path in buttonFiles) {
      final source = File(path).readAsStringSync();
      expect(source, contains("'{label}, loading'"), reason: path);
      expect(source, contains("'{label}, trwa ładowanie'"), reason: path);
    }

    final modal = File(
      'lib/shared/widgets/overlays/yo_modal_sheet_chrome.dart',
    ).readAsStringSync();
    expect(modal, contains("'Close {sheet}'"));
    expect(modal, contains("'Zamknij: {sheet}'"));

    final role = File(
      'lib/shared/identity/public_identity.dart',
    ).readAsStringSync();
    final status = File(
      'lib/shared/widgets/profile/people_status_ring.dart',
    ).readAsStringSync();
    final errors = File(
      'lib/core/helpers/error_messages.dart',
    ).readAsStringSync();
    expect(role, contains('localizedLabel(AppLocalizations copy)'));
    expect(status, contains('localizedLabel(AppLocalizations copy)'));
    expect(errors, contains('AppLocalizations? copy'));
    expect(errors, contains('copy?.text(english, polish)'));
  });
}
