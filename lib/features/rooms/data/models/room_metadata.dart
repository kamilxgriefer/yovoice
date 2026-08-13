/// Bounded metadata a room carries about itself.
///
/// All of it is DESCRIPTIVE. None of it is authorization: a room's target
/// audience never decides who may join, and `firestore.rules` does not
/// consult any of it when granting access. It exists to help people find
/// a room they will actually enjoy, and to let a host say what the room
/// is for before anyone arrives.
///
/// Every value is an enum rather than a free string so that rules can
/// validate it exhaustively and a client cannot invent capabilities by
/// writing a word the app has never heard of.
library;

/// Who a host has in mind. Descriptive only — see the note above.
enum TargetAudience {
  everyone('everyone', 'Everyone'),
  newcomers('newcomers', 'Newcomers'),
  enthusiasts('enthusiasts', 'Enthusiasts'),
  professionals('professionals', 'Professionals');

  const TargetAudience(this.value, this.label);

  final String value;
  final String label;

  /// Legacy rooms carry no `targetAudience`, so absence reads as
  /// "everyone" — the least restrictive, and true of every room that
  /// existed before this field did.
  static TargetAudience fromValue(Object? value) {
    for (final audience in TargetAudience.values) {
      if (audience.value == value) return audience;
    }
    return TargetAudience.everyone;
  }
}

/// Community only. How the conversation is meant to feel.
enum ConversationStyle {
  casual('casual', 'Casual'),
  focused('focused', 'Focused'),
  networking('networking', 'Networking'),
  supportive('supportive', 'Supportive');

  const ConversationStyle(this.value, this.label);

  final String value;
  final String label;

  static ConversationStyle? fromValue(Object? value) {
    for (final style in ConversationStyle.values) {
      if (style.value == value) return style;
    }
    return null;
  }
}

/// Podcast only. The shape of the show.
enum ShowFormat {
  solo('solo', 'Solo'),
  interview('interview', 'Interview'),
  panel('panel', 'Panel'),
  qAndA('qAndA', 'Q&A'),
  openDiscussion('openDiscussion', 'Open discussion');

  const ShowFormat(this.value, this.label);

  final String value;
  final String label;

  static ShowFormat? fromValue(Object? value) {
    for (final format in ShowFormat.values) {
      if (format.value == value) return format;
    }
    return null;
  }
}

/// Shared limits, mirrored exactly by `firestore.rules`. Kept here so the
/// client refuses what the server would refuse, rather than discovering
/// it as a permission error after the fact.
abstract final class RoomMetadataLimits {
  static const int maxTopicTags = 3;
  static const int maxTopicTagLength = 24;
  static const int maxGuidelinesLength = 280;

  /// Normalises a tag list to what rules will accept: trimmed, non-empty,
  /// de-duplicated, length-capped, and no more than three.
  static List<String> normalizeTags(Iterable<String> tags) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in tags) {
      final tag = raw.trim();
      if (tag.isEmpty || tag.length > maxTopicTagLength) continue;
      if (!seen.add(tag.toLowerCase())) continue;
      result.add(tag);
      if (result.length == maxTopicTags) break;
    }
    return List.unmodifiable(result);
  }
}
