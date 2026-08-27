import 'package:characters/characters.dart';

/// Produces a Firestore-rules-safe identity label from a federated account.
///
/// Provider names are not constrained by YO Voice. Firestore Rules measure
/// string size in UTF-16 code units, while cutting an arbitrary Dart string at
/// a code-unit offset can split an emoji/ZWJ sequence. Keep whole graphemes but
/// enforce the same 2–120 UTF-16-unit budget as the rules.
String resolveAuthProfileName({String? displayName, String? email}) {
  final normalizedDisplayName = displayName?.trim() ?? '';
  final emailLocalPart = (email?.trim().split('@').firstOrNull ?? '').trim();

  for (final candidate in [normalizedDisplayName, emailLocalPart]) {
    final bounded = _truncateToUtf16Budget(candidate, 120);
    if (bounded.length >= 2) {
      return bounded;
    }
  }

  return 'YO Voice User';
}

String _truncateToUtf16Budget(String value, int maxCodeUnits) {
  final result = StringBuffer();
  var usedCodeUnits = 0;

  for (final grapheme in value.characters) {
    final nextCodeUnits = usedCodeUnits + grapheme.length;
    if (nextCodeUnits > maxCodeUnits) break;
    result.write(grapheme);
    usedCodeUnits = nextCodeUnits;
  }

  return result.toString();
}
