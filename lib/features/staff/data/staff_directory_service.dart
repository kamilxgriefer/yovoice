import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// One row of the owner's user search, exactly as the server returned
/// it. The role here is the PUBLIC effective role (the server demotes a
/// forged superAdmin before it ever reaches a client); authoritative
/// account state for the detail view comes from getUserRole separately.
@immutable
class DirectoryUser {
  const DirectoryUser({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.email,
    required this.photoUrl,
    required this.staffRole,
    required this.isVip,
    required this.banned,
    required this.restricted,
    required this.createdAt,
  });

  factory DirectoryUser.fromMap(Map<String, dynamic> data) => DirectoryUser(
    uid: data['uid'] as String? ?? '',
    displayName: data['displayName'] as String? ?? '',
    username: data['username'] as String? ?? '',
    email: data['email'] as String?,
    photoUrl: data['photoUrl'] as String?,
    staffRole: data['staffRole'] as String? ?? 'user',
    isVip: data['isVip'] == true,
    banned: data['banned'] == true,
    restricted: data['restricted'] == true,
    createdAt: DateTime.tryParse(data['createdAt'] as String? ?? ''),
  );

  final String uid;
  final String displayName;
  final String username;
  final String? email;
  final String? photoUrl;
  final String staffRole;
  final bool isVip;
  final bool banned;
  final bool restricted;
  final DateTime? createdAt;

  /// The status ladder a row displays: the heaviest state wins.
  String get status => banned
      ? 'BANNED'
      : restricted
      ? 'MUTED'
      : 'ACTIVE';
}

@immutable
class DirectorySearchPage {
  const DirectorySearchPage({
    required this.users,
    required this.nextCursor,
    required this.mode,
  });

  final List<DirectoryUser> users;
  final String? nextCursor;
  final String mode;
}

/// Why a search failed — kept as DISTINCT kinds so the UI can say
/// "you're offline" or "you're not allowed" instead of the lie
/// "user not found".
enum DirectorySearchErrorKind { permission, network, invalidQuery, server }

class DirectorySearchException implements Exception {
  const DirectorySearchException(this.kind, this.message);

  final DirectorySearchErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// The Flutter side of the owner-only searchUserDirectory callable.
class StaffDirectoryService {
  StaffDirectoryService({FirebaseFunctions? functions})
    : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  Future<DirectorySearchPage> search({
    String query = '',
    String filter = 'all',
    String? cursor,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('searchUserDirectory')
          .call<Map<String, dynamic>>(<String, dynamic>{
            'query': query,
            'filter': filter,
            'cursor': ?cursor,
          });
      final data = Map<String, dynamic>.from(result.data);
      final rawUsers = (data['users'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => DirectoryUser.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false);
      return DirectorySearchPage(
        users: rawUsers,
        nextCursor: data['nextCursor'] as String?,
        mode: data['mode'] as String? ?? 'name',
      );
    } on FirebaseFunctionsException catch (error) {
      final kind = switch (error.code) {
        'permission-denied' ||
        'unauthenticated' => DirectorySearchErrorKind.permission,
        'unavailable' ||
        'deadline-exceeded' => DirectorySearchErrorKind.network,
        'invalid-argument' => DirectorySearchErrorKind.invalidQuery,
        _ => DirectorySearchErrorKind.server,
      };
      throw DirectorySearchException(kind, switch (kind) {
        DirectorySearchErrorKind.permission =>
          'User search is not available for this account.',
        DirectorySearchErrorKind.network =>
          'The server could not be reached. Check your connection.',
        DirectorySearchErrorKind.invalidQuery =>
          'Enter a valid name, username, email address or account ID.',
        DirectorySearchErrorKind.server =>
          'The search failed on the server. Try again.',
      });
    } catch (_) {
      throw const DirectorySearchException(
        DirectorySearchErrorKind.network,
        'Could not reach the server.',
      );
    }
  }
}
