import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

typedef RoomCoverReservationInvoker =
    Future<Map<Object?, Object?>> Function(Map<String, Object> request);
typedef RoomCoverGenerationReader =
    Future<String?> Function(Reference reference, TaskSnapshot snapshot);

class RoomCoverUpload {
  const RoomCoverUpload({
    required this.storagePath,
    required this.objectGeneration,
    required this.reservationId,
  });

  final String storagePath;
  final String objectGeneration;
  final String reservationId;
}

class RoomImageService {
  RoomImageService({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    RoomCoverReservationInvoker? reservationInvoker,
    RoomCoverGenerationReader? generationReader,
    ImagePicker? picker,
  }) : _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functions = functions,
       _reservationInvoker = reservationInvoker,
       _generationReader = generationReader,
       _picker = picker ?? ImagePicker();

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functions;
  final RoomCoverReservationInvoker? _reservationInvoker;
  final RoomCoverGenerationReader? _generationReader;
  final ImagePicker _picker;

  static const maxRoomCoverBytes = 8 * 1024 * 1024;

  /// Selects a room-cover source at twice the final output width so portrait
  /// photos still have enough horizontal detail for a 21:9 crop. The source
  /// byte guard in RoomCoverEditor remains the platform-independent limit.
  Future<XFile?> pickRoomCoverSource() {
    return _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 3200,
      maxHeight: 3200,
    );
  }

  /// Uploads the confirmed crop using a platform-independent contract.
  ///
  /// `XFile.fromData().name` is not stable across every implementation of
  /// cross_file, so deriving Storage metadata from that name could label the
  /// same in-memory crop differently on mobile and web. The crop renderer
  /// always emits JPEG; accept its bytes directly and pin both extension and
  /// MIME type here.
  Future<RoomCoverUpload> uploadRoomCover({
    required String roomId,
    required Uint8List bytes,
  }) {
    if (bytes.isEmpty || bytes.lengthInBytes > maxRoomCoverBytes) {
      throw StateError('The processed room cover must be smaller than 8 MB.');
    }
    final isJpeg =
        bytes.lengthInBytes >= 4 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF &&
        bytes[bytes.lengthInBytes - 2] == 0xFF &&
        bytes[bytes.lengthInBytes - 1] == 0xD9;
    if (!isJpeg) {
      throw StateError('The processed room cover must be a JPEG image.');
    }
    return _uploadBytes(
      roomId: roomId,
      bytes: bytes,
      extension: 'jpg',
      contentType: 'image/jpeg',
    );
  }

  Future<RoomCoverUpload> _uploadBytes({
    required String roomId,
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to upload a room image.');
    }

    final requestId = _newRequestId();
    final request = <String, Object>{
      'roomId': roomId,
      'requestId': requestId,
      'contentType': contentType,
      'size': bytes.lengthInBytes,
    };
    final response = _reservationInvoker == null
        ? (await (_functions ??
                      FirebaseFunctions.instanceFor(region: 'europe-west1'))
                  .httpsCallable('reserveRoomCoverUpload')
                  .call<Map<Object?, Object?>>(request))
              .data
        : await _reservationInvoker(request);
    final storagePath = response['storagePath'];
    final reservationId = response['reservationId'];
    final expiresAtMillis = response['expiresAtMillis'];
    if (response['schemaVersion'] != 1 ||
        storagePath is! String ||
        storagePath.length > 1024 ||
        reservationId is! String ||
        !RegExp(r'^[a-f0-9]{40}$').hasMatch(reservationId) ||
        response['contentType'] != contentType ||
        response['size'] != bytes.lengthInBytes ||
        expiresAtMillis is! int ||
        expiresAtMillis <= DateTime.now().millisecondsSinceEpoch) {
      throw StateError('The room cover service returned an invalid lease.');
    }
    final segments = storagePath.split('/');
    if (segments.length != 3 ||
        segments[0] != 'room_images' ||
        segments[1] != roomId ||
        !RegExp(
          '^${RegExp.escape(user.uid)}_[a-f0-9]{32}\\.$extension\$',
        ).hasMatch(segments[2])) {
      throw StateError('The room cover service returned an unsafe path.');
    }
    final reference = _storage.ref(storagePath);

    final metadata = SettableMetadata(
      contentType: contentType,
      cacheControl: 'private,no-store,max-age=0',
      customMetadata: <String, String>{
        'ownerId': user.uid,
        'roomId': roomId,
        'reservationId': reservationId,
      },
    );

    final snapshot = await reference.putData(bytes, metadata);
    final generation =
        (_generationReader == null
                ? snapshot.metadata?.generation
                : await _generationReader(reference, snapshot))
            ?.trim();
    if (generation == null || !RegExp(r'^[0-9]{1,30}$').hasMatch(generation)) {
      try {
        await reference.delete();
      } catch (_) {
        // The server-side inventory sweep is the fallback cleanup boundary.
      }
      throw StateError('The uploaded room cover has no safe generation.');
    }
    return RoomCoverUpload(
      storagePath: reference.fullPath,
      objectGeneration: generation,
      reservationId: reservationId,
    );
  }

  String _newRequestId() {
    final random = Random.secure();
    final randomPart = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return 'room-cover-'
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-'
        '$randomPart';
  }

  Future<void> deleteManagedRoomCoverPath({
    required String roomId,
    required String? storagePath,
  }) async {
    final normalized = storagePath?.trim();
    if (normalized == null || normalized.isEmpty) return;
    final segments = normalized.split('/');
    if (segments.length != 3 ||
        segments[0] != 'room_images' ||
        segments[1] != roomId ||
        segments[2].isEmpty) {
      return;
    }
    try {
      await _storage.ref(normalized).delete();
    } catch (_) {
      // A finalized pointer is never rolled back for cleanup failure. The
      // operator inventory reports any orphan left behind.
    }
  }

  /// Best-effort removal of a replaced/abandoned cover. Only a Storage
  /// reference whose bucket and exact path belong to this room is eligible;
  /// inherited Club Lounge art and arbitrary external URLs stay untouched.
  Future<void> deleteManagedRoomCover({
    required String roomId,
    required String? url,
  }) async {
    final normalized = url?.trim();
    if (normalized == null || normalized.isEmpty) return;
    Reference reference;
    try {
      reference = _storage.refFromURL(normalized);
    } catch (_) {
      return;
    }
    final segments = reference.fullPath.split('/');
    final isExactRoomObject =
        reference.bucket == _storage.bucket &&
        segments.length == 3 &&
        segments[0] == 'room_images' &&
        segments[1] == roomId &&
        segments[2].isNotEmpty;
    if (!isExactRoomObject) return;
    try {
      await reference.delete();
    } catch (_) {
      // Cleanup must never roll back a cover pointer that already committed.
    }
  }
}
