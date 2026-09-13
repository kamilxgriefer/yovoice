import 'package:cloud_firestore/cloud_firestore.dart';

class ServerListItem {
  const ServerListItem({
    required this.id,
    required this.serverId,
    required this.channelId,
    required this.text,
    required this.checked,
    required this.createdById,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.checkedById,
  });

  final String id;
  final String serverId;
  final String channelId;
  final String text;
  final bool checked;
  final String createdById;
  final String? checkedById;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ServerListItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String serverId,
    required String channelId,
  }) {
    final data = document.data();
    final createdAt = _date(data?['createdAt']);
    final updatedAt = _date(data?['updatedAt']);
    final checkedById = data?['checkedById'];
    if (data == null ||
        data['schemaVersion'] != 1 ||
        data['serverId'] != serverId ||
        data['channelId'] != channelId ||
        data['itemId'] != document.id ||
        data['text'] is! String ||
        (data['text'] as String).trim().isEmpty ||
        data['checked'] is! bool ||
        data['createdById'] is! String ||
        (checkedById != null && checkedById is! String) ||
        data['revision'] is! int ||
        (data['revision'] as int) < 1 ||
        createdAt == null ||
        updatedAt == null) {
      throw const FormatException('Unsupported server list item.');
    }
    return ServerListItem(
      id: document.id,
      serverId: serverId,
      channelId: channelId,
      text: (data['text'] as String).trim(),
      checked: data['checked'] as bool,
      createdById: data['createdById'] as String,
      checkedById: checkedById as String?,
      revision: data['revision'] as int,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

DateTime? _date(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => null,
};
