/// Persistent server identity. It is independent of a room's two-value
/// participation experience and of the kinds of channels inside the server.
enum ServerType {
  friends,
  community,
  podcast,
  family,
  company;

  static ServerType parse(Object? value) => switch (value) {
    'friends' => friends,
    'community' => community,
    'podcast' => podcast,
    'family' => family,
    'company' => company,
    _ => throw const FormatException('Unsupported server type.'),
  };

  bool get allowsPublic => this == community || this == podcast;
  bool get requiresPrivacyChoice => allowsPublic;
}

enum ServerPrivacy {
  public,
  private,
  inviteOnly;

  static ServerPrivacy parse(Object? value) => switch (value) {
    'public' => public,
    'private' => private,
    'inviteOnly' => inviteOnly,
    _ => throw const FormatException('Unsupported server privacy.'),
  };
}
