enum MessagePrivacyOption {
  everyone('everyone'),
  peopleYouFollow('peopleYouFollow'),
  friends('friends'),
  nobody('nobody');

  const MessagePrivacyOption(this.storageValue);

  final String storageValue;

  /// Missing is the backwards-compatible default for accounts created before
  /// this setting shipped. Unknown persisted values fail closed in the client
  /// just as they do in Functions and Firestore Rules.
  static MessagePrivacyOption fromStoredValue(Object? value) {
    if (value == null) return MessagePrivacyOption.everyone;
    return MessagePrivacyOption.values.firstWhere(
      (option) => option.storageValue == value,
      orElse: () => MessagePrivacyOption.nobody,
    );
  }

  String get label => switch (this) {
    MessagePrivacyOption.everyone => 'Everyone',
    MessagePrivacyOption.peopleYouFollow => 'People you follow',
    MessagePrivacyOption.friends => 'Friends only',
    MessagePrivacyOption.nobody => 'Nobody',
  };

  String get description => switch (this) {
    MessagePrivacyOption.everyone =>
      'Any active YO Voice member can start a conversation with you.',
    MessagePrivacyOption.peopleYouFollow =>
      'Only people you chose to follow can send you a direct message.',
    MessagePrivacyOption.friends =>
      'Only accepted friends can send new text, photo or voice messages.',
    MessagePrivacyOption.nobody =>
      'No one can send you new direct messages. Your existing history stays visible.',
  };
}
