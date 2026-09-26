import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'package:yovoice/features/bug_reports/data/bug_report_context.dart';

typedef BugReportCallableInvoker =
    Future<Map<Object?, Object?>> Function(
      String name,
      Map<String, Object?> payload,
    );

/// Uploads [bytes] to the reserved [storagePath] with exactly
/// [customMetadata] and returns the committed object's generation.
typedef BugReportScreenshotUploader =
    Future<String> Function({
      required String storagePath,
      required Uint8List bytes,
      required Map<String, String> customMetadata,
    });

/// What the reporter sees after sending.
@immutable
class BugReportSubmission {
  const BugReportSubmission({
    required this.reportId,
    required this.screenshotRequested,
    required this.screenshotAttached,
  });

  final String reportId;
  final bool screenshotRequested;
  final bool screenshotAttached;
}

/// A refusal the reporter UI turns into copy. [code] is the callable's
/// error code (`resource-exhausted`, `failed-precondition`, …) or `network`.
class BugReportException implements Exception {
  const BugReportException(this.code);

  final String code;

  @override
  String toString() => 'BugReportException($code)';
}

/// Sends a bug report: submit -> (optional) upload the reserved screenshot ->
/// attach it.
///
/// The words are sent first and stand on their own: a screenshot that fails
/// to upload or attach never loses the report, it only comes back as
/// [BugReportSubmission.screenshotAttached] false. A retry with the same
/// [requestId] replays the same report on the server instead of filing a
/// second one.
class BugReportService {
  BugReportService({
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
    BugReportCallableInvoker? invoker,
    BugReportScreenshotUploader? uploader,
  }) : _functions = functions,
       _storage = storage,
       _invoker = invoker,
       _uploader = uploader;

  final FirebaseFunctions? _functions;
  final FirebaseStorage? _storage;
  final BugReportCallableInvoker? _invoker;
  final BugReportScreenshotUploader? _uploader;

  static final Random _random = Random.secure();

  /// A fresh idempotency key; the reporter keeps one per report it composes.
  static String newRequestId() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(
      24,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }

  Future<Map<Object?, Object?>> _call(
    String name,
    Map<String, Object?> payload,
  ) async {
    final invoker = _invoker;
    if (invoker != null) return invoker(name, payload);
    final functions =
        _functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
    final response = await functions
        .httpsCallable(name)
        .call<Map<Object?, Object?>>(payload);
    return response.data;
  }

  Future<String> _upload({
    required String storagePath,
    required Uint8List bytes,
    required Map<String, String> customMetadata,
  }) async {
    final uploader = _uploader;
    if (uploader != null) {
      return uploader(
        storagePath: storagePath,
        bytes: bytes,
        customMetadata: customMetadata,
      );
    }
    final reference = (_storage ?? FirebaseStorage.instance).ref(storagePath);
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: customMetadata,
    );
    try {
      final snapshot = await reference.putData(bytes, metadata);
      final generation = snapshot.metadata?.generation;
      if (generation != null && generation.isNotEmpty) return generation;
    } catch (_) {
      // The object may have committed before the answer was lost; the
      // uploader may read it back while the reservation is live.
    }
    final stored = await reference.getMetadata();
    final generation = stored.generation;
    if (generation == null ||
        generation.isEmpty ||
        stored.size != bytes.length) {
      throw const BugReportException('upload');
    }
    return generation;
  }

  Future<BugReportSubmission> submit({
    required String requestId,
    required String description,
    required BugReportContext context,
    Uint8List? screenshot,
  }) async {
    final Map<Object?, Object?> result;
    try {
      result = await _call('submitBugReportV1', <String, Object?>{
        'requestId': requestId,
        'description': description,
        'context': context.toJson(),
        'screenshot': screenshot == null
            ? null
            : <String, Object>{
                'contentType': 'image/jpeg',
                'size': screenshot.length,
              },
      });
    } on FirebaseFunctionsException catch (error) {
      throw BugReportException(error.code);
    } on BugReportException {
      rethrow;
    } catch (_) {
      throw const BugReportException('network');
    }
    final reportId = result['reportId'];
    if (reportId is! String || !reportId.startsWith('br_')) {
      throw const BugReportException('internal');
    }
    if (screenshot == null) {
      return BugReportSubmission(
        reportId: reportId,
        screenshotRequested: false,
        screenshotAttached: false,
      );
    }
    final attached = await _attachScreenshot(
      reportId,
      result['screenshotUpload'],
      screenshot,
    );
    return BugReportSubmission(
      reportId: reportId,
      screenshotRequested: true,
      screenshotAttached: attached,
    );
  }

  Future<bool> _attachScreenshot(
    String reportId,
    Object? upload,
    Uint8List screenshot,
  ) async {
    try {
      if (upload is! Map) return false;
      final storagePath = upload['storagePath'];
      final metadata = upload['uploadMetadata'];
      if (storagePath is! String ||
          !storagePath.startsWith('bug_reports/') ||
          !storagePath.endsWith('/$reportId.jpg') ||
          metadata is! Map) {
        return false;
      }
      final customMetadata = <String, String>{
        for (final entry in metadata.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
      if (customMetadata.length != metadata.length) return false;
      final generation = await _upload(
        storagePath: storagePath,
        bytes: screenshot,
        customMetadata: customMetadata,
      );
      await _call('attachBugReportScreenshotV1', <String, Object?>{
        'reportId': reportId,
        'objectGeneration': generation,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
