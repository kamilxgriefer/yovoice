/// Defines the two public room experiences available in YoVoice.
///
/// Firestore used `podcast` in older builds. The parser intentionally keeps
/// accepting that value so existing rooms continue to open as Broadcast Rooms.
enum RoomExperience {
  community,
  broadcast;

  static RoomExperience fromValue(Object? value) {
    return switch (value) {
      'broadcast' || 'podcast' => RoomExperience.broadcast,
      _ => RoomExperience.community,
    };
  }

  /// Canonical value written by current versions of the app.
  String get firestoreValue => name;

  bool get isCommunity => this == RoomExperience.community;
  bool get isBroadcast => this == RoomExperience.broadcast;
}
