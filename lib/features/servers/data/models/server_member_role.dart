/// The six server-local roles, exactly `contract.js ROLES` with the same
/// powers (60/50/40/30/20/10). The client reads its own
/// `clubs/{serverId}/members/{uid}` row to decide which affordances to
/// OFFER; every one of them is re-proven by the callable it reaches.
enum ServerMemberRole {
  owner(60),
  coOwner(50),
  admin(40),
  moderator(30),
  member(20),
  guest(10);

  const ServerMemberRole(this.power);

  final int power;

  /// Null for an unknown value: an unrecognised role withholds every
  /// affordance instead of defaulting to `member`.
  static ServerMemberRole? parse(Object? value) => switch (value) {
    'owner' => owner,
    'coOwner' => coOwner,
    'admin' => admin,
    'moderator' => moderator,
    'member' => member,
    'guest' => guest,
    _ => null,
  };

  /// `requireServerManager` in `authority.js`: owner, co-owner, admin.
  bool get canManage => power >= admin.power;

  /// The inviter roles `invites.js` re-proves, and the roles that may start
  /// a stage generation (`capabilitiesFor`: `startSession` on a stage needs
  /// moderator power).
  bool get canModerate => power >= moderator.power;
}
