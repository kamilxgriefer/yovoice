enum ProfileVisibility {
  public,
  friends,
  private;

  static ProfileVisibility fromValue(Object? value) {
    return switch (value) {
      null || '' => ProfileVisibility.public,
      'public' => ProfileVisibility.public,
      'friends' => ProfileVisibility.friends,
      'private' => ProfileVisibility.private,
      // Unknown stored values fail closed in both the client and server. Only
      // an actually missing legacy field receives the historical public
      // default.
      _ => ProfileVisibility.private,
    };
  }

  String get label => switch (this) {
    ProfileVisibility.public => 'Everyone',
    ProfileVisibility.friends => 'Friends only',
    ProfileVisibility.private => 'Only me',
  };

  String get description => switch (this) {
    ProfileVisibility.public =>
      'Signed-in people can open your profile and find you in search.',
    ProfileVisibility.friends =>
      'Only confirmed friends can open your full profile.',
    ProfileVisibility.private =>
      'Your full profile is hidden from every other account.',
  };
}
