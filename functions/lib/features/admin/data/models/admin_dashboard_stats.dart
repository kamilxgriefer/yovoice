class AdminDashboardStats {
  const AdminDashboardStats({
    required this.users,
    required this.rooms,
    required this.clubs,
    required this.liveRooms,
  });

  final int users;
  final int rooms;
  final int clubs;
  final int liveRooms;

  factory AdminDashboardStats.fromMap(Map<String, dynamic> map) {
    return AdminDashboardStats(
      users: _readInt(map['users']),
      rooms: _readInt(map['rooms']),
      clubs: _readInt(map['clubs']),
      liveRooms: _readInt(map['liveRooms']),
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic> toMap() {
    return {
      'users': users,
      'rooms': rooms,
      'clubs': clubs,
      'liveRooms': liveRooms,
    };
  }

  AdminDashboardStats copyWith({
    int? users,
    int? rooms,
    int? clubs,
    int? liveRooms,
  }) {
    return AdminDashboardStats(
      users: users ?? this.users,
      rooms: rooms ?? this.rooms,
      clubs: clubs ?? this.clubs,
      liveRooms: liveRooms ?? this.liveRooms,
    );
  }

  static const empty = AdminDashboardStats(
    users: 0,
    rooms: 0,
    clubs: 0,
    liveRooms: 0,
  );

  @override
  String toString() {
    return 'AdminDashboardStats('
        'users: $users, '
        'rooms: $rooms, '
        'clubs: $clubs, '
        'liveRooms: $liveRooms'
        ')';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AdminDashboardStats &&
            runtimeType == other.runtimeType &&
            users == other.users &&
            rooms == other.rooms &&
            clubs == other.clubs &&
            liveRooms == other.liveRooms;
  }

  @override
  int get hashCode {
    return Object.hash(users, rooms, clubs, liveRooms);
  }
}
