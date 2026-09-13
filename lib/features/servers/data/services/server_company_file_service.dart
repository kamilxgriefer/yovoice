import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/server_company_file.dart';

typedef ServerCompanyFileCall =
    Future<Map<Object?, Object?>> Function(
      String callable,
      Map<String, Object?> payload,
    );
typedef ServerCompanyFileUploader =
    Future<String> Function(
      Uint8List bytes,
      ServerCompanyFileUploadTarget target,
    );

class ServerCompanyFileSelection {
  const ServerCompanyFileSelection({
    required this.displayName,
    required this.contentType,
    required this.bytes,
  });

  final String displayName;
  final String contentType;
  final Uint8List bytes;
}

/// One intended upload. Reservation, immutable bytes and request identities
/// survive a transient finalize failure, so Retry never reserves or uploads a
/// second object for the same press.
class ServerCompanyFileUploadAttempt {
  ServerCompanyFileUploadAttempt({
    required this.serverId,
    required this.channelId,
    required this.selection,
    required this.reserveRequestId,
    required this.finalizeRequestId,
  });

  final String serverId;
  final String channelId;
  final ServerCompanyFileSelection selection;
  final String reserveRequestId;
  final String finalizeRequestId;

  ServerCompanyFileReservation? reservation;
  String? generation;
}

abstract interface class ServerCompanyFileRepository {
  String get currentUserId;
  String newRequestId();

  Stream<List<ServerCompanyFile>> watchCompanyFiles(
    String serverId,
    String channelId,
  );

  ServerCompanyFileUploadAttempt newCompanyFileUploadAttempt({
    required String serverId,
    required String channelId,
    required ServerCompanyFileSelection selection,
  });

  Future<String> publishCompanyFile(
    ServerCompanyFileUploadAttempt attempt, {
    void Function(double progress)? onProgress,
  });

  Future<ServerCompanyFileAccess> getCompanyFileAccess({
    required ServerCompanyFile file,
  });

  Future<void> deleteCompanyFile({
    required ServerCompanyFile file,
    required String requestId,
  });
}

class ServerCompanyFileService implements ServerCompanyFileRepository {
  ServerCompanyFileService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
    ServerCompanyFileCall? callOverride,
    ServerCompanyFileUploader? uploader,
    DateTime Function()? clock,
    String Function()? requestIdFactory,
  }) : _firestoreOverride = firestore,
       _authOverride = auth,
       _functionsOverride = functions,
       _storageOverride = storage,
       _callOverride = callOverride,
       _uploader = uploader,
       _clock = clock ?? DateTime.now,
       _requestIdFactory = requestIdFactory;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;
  final FirebaseFunctions? _functionsOverride;
  final FirebaseStorage? _storageOverride;
  final ServerCompanyFileCall? _callOverride;
  final ServerCompanyFileUploader? _uploader;
  final DateTime Function() _clock;
  final String Function()? _requestIdFactory;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  @override
  String get currentUserId => _auth.currentUser?.uid ?? '';

  @override
  String newRequestId() {
    final override = _requestIdFactory;
    if (override != null) return override();
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  Stream<List<ServerCompanyFile>> watchCompanyFiles(
    String serverId,
    String channelId,
  ) {
    _requireId(serverId, 'serverId');
    _requireId(channelId, 'channelId');
    return _firestore
        .collection('clubs')
        .doc(serverId)
        .collection('channels')
        .doc(channelId)
        .collection('files')
        .where('status', isEqualTo: 'published')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          final files = <ServerCompanyFile>[];
          for (final document in snapshot.docs) {
            try {
              files.add(
                ServerCompanyFile.fromFirestore(
                  document,
                  serverId: serverId,
                  channelId: channelId,
                ),
              );
            } on FormatException {
              // A malformed descriptor never becomes an openable link. Keep
              // the rest of the authorized channel usable and omit this row.
            }
          }
          return List<ServerCompanyFile>.unmodifiable(files);
        });
  }

  @override
  ServerCompanyFileUploadAttempt newCompanyFileUploadAttempt({
    required String serverId,
    required String channelId,
    required ServerCompanyFileSelection selection,
  }) {
    _requireId(serverId, 'serverId');
    _requireId(channelId, 'channelId');
    _validateSelection(selection);
    return ServerCompanyFileUploadAttempt(
      serverId: serverId,
      channelId: channelId,
      selection: selection,
      reserveRequestId: newRequestId(),
      finalizeRequestId: newRequestId(),
    );
  }

  @override
  Future<String> publishCompanyFile(
    ServerCompanyFileUploadAttempt attempt, {
    void Function(double progress)? onProgress,
  }) async {
    _validateSelection(attempt.selection);
    final reservation = attempt.reservation ??= await _reserveCompanyFile(
      attempt,
    );
    if (reservation.serverId != attempt.serverId ||
        reservation.channelId != attempt.channelId ||
        reservation.displayName != attempt.selection.displayName ||
        reservation.file.contentType != attempt.selection.contentType ||
        reservation.file.size != attempt.selection.bytes.lengthInBytes) {
      throw const FormatException('Company File reservation changed.');
    }
    if (!reservation.expiresAt.isAfter(_clock().toUtc())) {
      throw TimeoutException('Company File upload reservation expired.');
    }
    final generation = attempt.generation ??= await _upload(
      attempt.selection.bytes,
      reservation.file,
      onProgress: onProgress,
    );
    final result = await _invoke('finalizeServerCompanyFileV1', {
      'serverId': attempt.serverId,
      'channelId': attempt.channelId,
      'fileId': reservation.fileId,
      'generation': generation,
      'requestId': attempt.finalizeRequestId,
    });
    _validateFinalizeReceipt(result, reservation.fileId, attempt);
    onProgress?.call(1);
    return reservation.fileId;
  }

  Future<ServerCompanyFileReservation> _reserveCompanyFile(
    ServerCompanyFileUploadAttempt attempt,
  ) async {
    final result = ServerCompanyFileReservation.fromMap(
      await _invoke('reserveServerCompanyFileV1', {
        'serverId': attempt.serverId,
        'channelId': attempt.channelId,
        'requestId': attempt.reserveRequestId,
        'displayName': attempt.selection.displayName,
        'contentType': attempt.selection.contentType,
        'size': attempt.selection.bytes.lengthInBytes,
      }),
    );
    return result;
  }

  Future<String> _upload(
    Uint8List bytes,
    ServerCompanyFileUploadTarget target, {
    void Function(double progress)? onProgress,
  }) async {
    final override = _uploader;
    if (override != null) {
      onProgress?.call(0);
      final generation = await override(bytes, target);
      onProgress?.call(1);
      return _validGeneration(generation);
    }
    final upload = _storage
        .ref(target.storagePath)
        .putData(
          bytes,
          SettableMetadata(
            contentType: target.contentType,
            customMetadata: target.uploadMetadata,
          ),
        );
    final progress = upload.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) {
        onProgress?.call(snapshot.bytesTransferred / snapshot.totalBytes);
      }
    });
    late final TaskSnapshot snapshot;
    try {
      snapshot = await upload.timeout(const Duration(minutes: 2));
    } on TimeoutException {
      try {
        await upload.cancel().timeout(const Duration(seconds: 2));
      } catch (_) {
        // Finalization is generation-bound, so a late immutable upload cannot
        // publish different bytes under this attempt.
      }
      rethrow;
    } finally {
      await progress.cancel();
    }
    var generation = snapshot.metadata?.generation?.trim();
    if (generation == null || generation.isEmpty) {
      generation = (await snapshot.ref.getMetadata()).generation?.trim();
    }
    return _validGeneration(generation ?? '');
  }

  @override
  Future<ServerCompanyFileAccess> getCompanyFileAccess({
    required ServerCompanyFile file,
  }) async {
    final access = ServerCompanyFileAccess.fromMap(
      await _invoke('getServerCompanyFileAccessV1', {
        'serverId': file.serverId,
        'channelId': file.channelId,
        'fileId': file.id,
      }),
    );
    if (access.serverId != file.serverId ||
        access.channelId != file.channelId ||
        access.fileId != file.id ||
        access.displayName != file.displayName ||
        access.generation != file.file.generation ||
        access.contentType != file.file.contentType ||
        access.size != file.file.size ||
        !access.expiresAt.isAfter(_clock().toUtc())) {
      throw const FormatException('Company File access grant changed.');
    }
    return access;
  }

  @override
  Future<void> deleteCompanyFile({
    required ServerCompanyFile file,
    required String requestId,
  }) async {
    await _invoke('deleteServerCompanyFileV1', {
      'serverId': file.serverId,
      'channelId': file.channelId,
      'fileId': file.id,
      'expectedRevision': file.revision,
      'requestId': requestId,
    });
  }

  Future<Map<Object?, Object?>> _invoke(
    String name,
    Map<String, Object?> payload,
  ) async {
    final override = _callOverride;
    if (override != null) return override(name, payload);
    final result = await _functions
        .httpsCallable(name)
        .call<Map<Object?, Object?>>(payload);
    return result.data;
  }

  static void _validateSelection(ServerCompanyFileSelection selection) {
    final displayName = selection.displayName;
    if (displayName.isEmpty ||
        displayName != displayName.trim() ||
        displayName.length > 180 ||
        RegExp(r'[\x00-\x1f\x7f/\\]').hasMatch(displayName) ||
        selection.bytes.isEmpty ||
        selection.bytes.lengthInBytes > serverCompanyFileMaxBytes ||
        detectServerCompanyFileContentType(selection.bytes) !=
            selection.contentType) {
      throw const FormatException('Unsupported Company File selection.');
    }
  }

  static void _validateFinalizeReceipt(
    Map<Object?, Object?> result,
    String fileId,
    ServerCompanyFileUploadAttempt attempt,
  ) {
    const keys = {
      'schemaVersion',
      'serverId',
      'channelId',
      'fileId',
      'revision',
      'status',
    };
    final actual = result.keys.toList(growable: false);
    if (actual.length != keys.length ||
        !actual.every((key) => key is String && keys.contains(key)) ||
        result['schemaVersion'] != 1 ||
        result['serverId'] != attempt.serverId ||
        result['channelId'] != attempt.channelId ||
        result['fileId'] != fileId ||
        result['revision'] != 1 ||
        result['status'] != 'published') {
      throw const FormatException('Unsupported Company File receipt.');
    }
  }

  static void _requireId(String value, String label) {
    if (value.isEmpty || value != value.trim() || value.length > 128) {
      throw ArgumentError.value(value, label);
    }
  }

  static String _validGeneration(String generation) {
    if (!RegExp(r'^[0-9]{1,30}$').hasMatch(generation)) {
      throw const FormatException('Unsupported Company File generation.');
    }
    return generation;
  }
}

/// Mirrors the backend byte probe. This catches a renamed executable or a
/// mismatched extension before any reservation or upload starts.
String? detectServerCompanyFileContentType(Uint8List bytes) {
  if (bytes.lengthInBytes >= 12 &&
      _startsWith(bytes, const [0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e]) &&
      bytes[7] >= 0x30 &&
      bytes[7] <= 0x39) {
    final tail = ascii.decode(
      bytes.sublist(max(0, bytes.lengthInBytes - 1024)),
      allowInvalid: true,
    );
    if (tail.contains('%%EOF')) return 'application/pdf';
  }
  if (bytes.lengthInBytes >= 5 &&
      _startsWith(bytes, const [0xff, 0xd8, 0xff]) &&
      bytes[bytes.lengthInBytes - 2] == 0xff &&
      bytes[bytes.lengthInBytes - 1] == 0xd9) {
    return 'image/jpeg';
  }
  const pngStart = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  const pngEnd = [0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82];
  if (bytes.lengthInBytes >= 20 &&
      _startsWith(bytes, pngStart) &&
      _endsWith(bytes, pngEnd)) {
    return 'image/png';
  }
  if (bytes.lengthInBytes >= 20 &&
      _startsWith(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
      _littleEndian32(bytes, 4) + 8 == bytes.lengthInBytes &&
      _matchesAt(bytes, 8, const [0x57, 0x45, 0x42, 0x50]) &&
      (_matchesAt(bytes, 12, const [0x56, 0x50, 0x38, 0x20]) ||
          _matchesAt(bytes, 12, const [0x56, 0x50, 0x38, 0x4c]) ||
          _matchesAt(bytes, 12, const [0x56, 0x50, 0x38, 0x58]))) {
    return 'image/webp';
  }
  if (bytes.isEmpty || bytes.contains(0)) return null;
  try {
    utf8.decode(bytes, allowMalformed: false);
    return 'text/plain';
  } on FormatException {
    return null;
  }
}

bool _startsWith(Uint8List bytes, List<int> prefix) =>
    _matchesAt(bytes, 0, prefix);

bool _endsWith(Uint8List bytes, List<int> suffix) =>
    _matchesAt(bytes, bytes.lengthInBytes - suffix.length, suffix);

bool _matchesAt(Uint8List bytes, int offset, List<int> expected) {
  if (offset < 0 || offset + expected.length > bytes.lengthInBytes) {
    return false;
  }
  for (var index = 0; index < expected.length; index++) {
    if (bytes[offset + index] != expected[index]) return false;
  }
  return true;
}

int _littleEndian32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);
