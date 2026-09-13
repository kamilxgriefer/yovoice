import 'package:cloud_firestore/cloud_firestore.dart';

const serverCompanyFileMaxBytes = 25 * 1024 * 1024;

const serverCompanyFileExtensions = <String, String>{
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'text/plain': 'txt',
};

final RegExp _companyFileId = RegExp(r'^cf_[a-f0-9]{40}$');
final RegExp _generation = RegExp(r'^[0-9]{1,30}$');

class ServerCompanyFileDescriptor {
  const ServerCompanyFileDescriptor({
    required this.storagePath,
    required this.generation,
    required this.contentType,
    required this.size,
  });

  final String storagePath;
  final String generation;
  final String contentType;
  final int size;

  factory ServerCompanyFileDescriptor.fromMap(
    Object? value, {
    required String serverId,
    required String channelId,
    required String ownerId,
    required String fileId,
  }) {
    final data = _map(value, const {
      'storagePath',
      'generation',
      'contentType',
      'size',
    });
    final contentType = _supportedContentType(data['contentType']);
    final extension = serverCompanyFileExtensions[contentType]!;
    final expectedPath =
        'server_company_files/$serverId/$channelId/$ownerId/$fileId.$extension';
    final storagePath = _text(data['storagePath'], 1024);
    final generation = _text(data['generation'], 30);
    final size = data['size'];
    if (storagePath != expectedPath ||
        !_generation.hasMatch(generation) ||
        size is! int ||
        size < 1 ||
        size > serverCompanyFileMaxBytes) {
      throw const FormatException('Unsupported Company File descriptor.');
    }
    return ServerCompanyFileDescriptor(
      storagePath: storagePath,
      generation: generation,
      contentType: contentType,
      size: size,
    );
  }
}

class ServerCompanyFile {
  const ServerCompanyFile({
    required this.id,
    required this.serverId,
    required this.channelId,
    required this.ownerId,
    required this.ownerDisplayName,
    required this.displayName,
    required this.file,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String serverId;
  final String channelId;
  final String ownerId;
  final String ownerDisplayName;
  final String displayName;
  final ServerCompanyFileDescriptor file;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ServerCompanyFile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String serverId,
    required String channelId,
  }) {
    final data = document.data();
    if (data == null) {
      throw const FormatException('Company File is unavailable.');
    }
    const keys = {
      'schemaVersion',
      'fileKind',
      'serverId',
      'clubId',
      'channelId',
      'fileId',
      'ownerId',
      'ownerDisplayName',
      'ownerPhotoUrl',
      'displayName',
      'status',
      'file',
      'revision',
      'createdAt',
      'updatedAt',
    };
    if (!_sameKeys(data.keys, keys)) {
      throw const FormatException('Unsupported Company File schema.');
    }
    final fileId = _text(data['fileId'], 64);
    final ownerId = _text(data['ownerId'], 128);
    final ownerDisplayName = _text(data['ownerDisplayName'], 120);
    final displayName = _displayName(data['displayName']);
    final revision = data['revision'];
    final createdAt = data['createdAt'];
    final updatedAt = data['updatedAt'];
    if (data['schemaVersion'] != 1 ||
        data['fileKind'] != 'companyFile' ||
        data['serverId'] != serverId ||
        data['clubId'] != serverId ||
        data['channelId'] != channelId ||
        fileId != document.id ||
        !_companyFileId.hasMatch(fileId) ||
        data['ownerPhotoUrl'] != null ||
        data['status'] != 'published' ||
        revision is! int ||
        revision < 1 ||
        createdAt is! Timestamp ||
        updatedAt is! Timestamp) {
      throw const FormatException('Unsupported Company File.');
    }
    return ServerCompanyFile(
      id: fileId,
      serverId: serverId,
      channelId: channelId,
      ownerId: ownerId,
      ownerDisplayName: ownerDisplayName,
      displayName: displayName,
      file: ServerCompanyFileDescriptor.fromMap(
        data['file'],
        serverId: serverId,
        channelId: channelId,
        ownerId: ownerId,
        fileId: fileId,
      ),
      revision: revision,
      createdAt: createdAt.toDate().toUtc(),
      updatedAt: updatedAt.toDate().toUtc(),
    );
  }
}

class ServerCompanyFileUploadTarget {
  const ServerCompanyFileUploadTarget({
    required this.storagePath,
    required this.contentType,
    required this.size,
    required this.uploadMetadata,
  });

  final String storagePath;
  final String contentType;
  final int size;
  final Map<String, String> uploadMetadata;

  factory ServerCompanyFileUploadTarget.fromMap(
    Object? value, {
    required String serverId,
    required String channelId,
    required String fileId,
  }) {
    final data = _map(value, const {
      'storagePath',
      'contentType',
      'size',
      'uploadMetadata',
    });
    final contentType = _supportedContentType(data['contentType']);
    final size = data['size'];
    final metadata = _stringMap(data['uploadMetadata']);
    const metadataKeys = {
      'yovoiceServerId',
      'yovoiceChannelId',
      'yovoiceOwnerUid',
      'yovoiceFileId',
      'yovoiceAssetKind',
    };
    final ownerId = metadata['yovoiceOwnerUid'] ?? '';
    final expectedPath =
        'server_company_files/$serverId/$channelId/$ownerId/$fileId.'
        '${serverCompanyFileExtensions[contentType]}';
    if (!_sameKeys(metadata.keys, metadataKeys) ||
        metadata['yovoiceServerId'] != serverId ||
        metadata['yovoiceChannelId'] != channelId ||
        metadata['yovoiceFileId'] != fileId ||
        metadata['yovoiceAssetKind'] != 'companyFile' ||
        ownerId.isEmpty ||
        data['storagePath'] != expectedPath ||
        size is! int ||
        size < 1 ||
        size > serverCompanyFileMaxBytes) {
      throw const FormatException('Unsupported Company File reservation.');
    }
    return ServerCompanyFileUploadTarget(
      storagePath: expectedPath,
      contentType: contentType,
      size: size,
      uploadMetadata: Map<String, String>.unmodifiable(metadata),
    );
  }
}

class ServerCompanyFileReservation {
  const ServerCompanyFileReservation({
    required this.serverId,
    required this.channelId,
    required this.fileId,
    required this.displayName,
    required this.expiresAt,
    required this.file,
  });

  final String serverId;
  final String channelId;
  final String fileId;
  final String displayName;
  final DateTime expiresAt;
  final ServerCompanyFileUploadTarget file;

  factory ServerCompanyFileReservation.fromMap(Object? value) {
    final data = _map(value, const {
      'schemaVersion',
      'serverId',
      'channelId',
      'fileId',
      'displayName',
      'expiresAtMillis',
      'file',
    });
    final serverId = _text(data['serverId'], 128);
    final channelId = _text(data['channelId'], 128);
    final fileId = _text(data['fileId'], 64);
    final expiresAtMillis = data['expiresAtMillis'];
    if (data['schemaVersion'] != 1 ||
        !_companyFileId.hasMatch(fileId) ||
        expiresAtMillis is! int ||
        expiresAtMillis <= 0) {
      throw const FormatException('Unsupported Company File reservation.');
    }
    return ServerCompanyFileReservation(
      serverId: serverId,
      channelId: channelId,
      fileId: fileId,
      displayName: _displayName(data['displayName']),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiresAtMillis,
        isUtc: true,
      ),
      file: ServerCompanyFileUploadTarget.fromMap(
        data['file'],
        serverId: serverId,
        channelId: channelId,
        fileId: fileId,
      ),
    );
  }
}

class ServerCompanyFileAccess {
  const ServerCompanyFileAccess({
    required this.serverId,
    required this.channelId,
    required this.fileId,
    required this.displayName,
    required this.url,
    required this.expiresAt,
    required this.generation,
    required this.contentType,
    required this.size,
  });

  final String serverId;
  final String channelId;
  final String fileId;
  final String displayName;
  final Uri url;
  final DateTime expiresAt;
  final String generation;
  final String contentType;
  final int size;

  factory ServerCompanyFileAccess.fromMap(Object? value) {
    final data = _map(value, const {
      'schemaVersion',
      'serverId',
      'channelId',
      'fileId',
      'displayName',
      'expiresAtMillis',
      'file',
    });
    final file = _map(data['file'], const {
      'url',
      'generation',
      'contentType',
      'size',
    });
    final rawUrl = _text(file['url'], 4096);
    final url = Uri.tryParse(rawUrl);
    final fileId = _text(data['fileId'], 64);
    final generation = _text(file['generation'], 30);
    final size = file['size'];
    final expiresAtMillis = data['expiresAtMillis'];
    final safePrefix = 'https://storage.googleapis.com/';
    if (data['schemaVersion'] != 1 ||
        !_companyFileId.hasMatch(fileId) ||
        url == null ||
        !rawUrl.startsWith(safePrefix) ||
        url.scheme != 'https' ||
        url.host != 'storage.googleapis.com' ||
        url.userInfo.isNotEmpty ||
        url.fragment.isNotEmpty ||
        !_generation.hasMatch(generation) ||
        size is! int ||
        size < 1 ||
        size > serverCompanyFileMaxBytes ||
        expiresAtMillis is! int ||
        expiresAtMillis <= 0) {
      throw const FormatException('Unsupported Company File access grant.');
    }
    return ServerCompanyFileAccess(
      serverId: _text(data['serverId'], 128),
      channelId: _text(data['channelId'], 128),
      fileId: fileId,
      displayName: _displayName(data['displayName']),
      url: url,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiresAtMillis,
        isUtc: true,
      ),
      generation: generation,
      contentType: _supportedContentType(file['contentType']),
      size: size,
    );
  }
}

Map<Object?, Object?> _map(Object? value, Set<String> keys) {
  if (value is! Map || !_sameKeys(value.keys, keys)) {
    throw const FormatException('Unsupported Company File payload.');
  }
  return value;
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Unsupported Company File metadata.');
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! String) {
      throw const FormatException('Unsupported Company File metadata.');
    }
    result[entry.key as String] = entry.value as String;
  }
  return result;
}

bool _sameKeys(Iterable<Object?> actual, Set<String> expected) {
  final values = actual.toList(growable: false);
  final keys = values.whereType<String>().toSet();
  return values.length == expected.length &&
      keys.length == expected.length &&
      keys.containsAll(expected);
}

String _text(Object? value, int maxLength) {
  if (value is! String ||
      value.isEmpty ||
      value != value.trim() ||
      value.length > maxLength) {
    throw const FormatException('Unsupported Company File text.');
  }
  return value;
}

String _displayName(Object? value) {
  final result = _text(value, 180);
  if (RegExp(r'[\x00-\x1f\x7f/\\]').hasMatch(result)) {
    throw const FormatException('Unsupported Company File display name.');
  }
  return result;
}

String _supportedContentType(Object? value) {
  if (value is! String || !serverCompanyFileExtensions.containsKey(value)) {
    throw const FormatException('Unsupported Company File content type.');
  }
  return value;
}
