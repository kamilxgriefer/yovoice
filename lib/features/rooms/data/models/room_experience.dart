enum RoomExperience {
  community,
  podcast;

  static RoomExperience fromValue(Object? value) {
    return value == 'podcast'
        ? RoomExperience.podcast
        : RoomExperience.community;
  }

  String get firestoreValue => name;
}
