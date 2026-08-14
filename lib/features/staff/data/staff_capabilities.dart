import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// What the signed-in account may do, as the SERVER decided it.
///
/// This object renders UI; it never authorizes anything. Every privileged
/// action goes through a callable that re-derives the same matrix
/// server-side, so a forged or stale instance of this class can produce
/// at most a button that fails.
@immutable
class StaffCapabilities {
  const StaffCapabilities({
    this.staffRole = 'user',
    this.isOwner = false,
    this.isVip = false,
    this.permanentDeleteSpaces = false,
    this.deleteAnyMessage = false,
    this.permanentBan = false,
    this.manageRoles = false,
    this.fullAuditAccess = false,
    this.viewAllQueues = false,
    this.quarantineSpaces = false,
    this.endAnyRoom = false,
    this.handleAssignedReports = false,
    this.removeReportedContent = false,
    this.warnUsers = false,
    this.endPublicRoomWithReason = false,
    this.suspendUsers = false,
    this.suspensionLimitHours,
    this.liftSuspensions = false,
    this.sanctionStaff = false,
    this.readAuditLogs = false,
    this.supportLookup = false,
    this.guideMode = false,
  });

  /// The ordinary account: renders exactly the UI the app always had.
  static const none = StaffCapabilities();

  final String staffRole;
  final bool isOwner;
  final bool isVip;
  final bool permanentDeleteSpaces;
  final bool deleteAnyMessage;
  final bool permanentBan;
  final bool manageRoles;
  final bool fullAuditAccess;
  final bool viewAllQueues;
  final bool quarantineSpaces;
  final bool endAnyRoom;
  final bool handleAssignedReports;
  final bool removeReportedContent;
  final bool warnUsers;
  final bool endPublicRoomWithReason;
  final bool suspendUsers;
  final int? suspensionLimitHours;
  final bool liftSuspensions;
  final bool sanctionStaff;
  final bool readAuditLogs;
  final bool supportLookup;
  final bool guideMode;

  /// Whether ANY room-level staff control should exist for this account.
  bool get hasRoomModeration =>
      permanentDeleteSpaces || endAnyRoom || endPublicRoomWithReason;

  factory StaffCapabilities.fromMap(Map<String, dynamic> data) {
    bool flag(String key) => data[key] == true;
    return StaffCapabilities(
      staffRole: data['staffRole'] as String? ?? 'user',
      isOwner: flag('isOwner'),
      isVip: flag('isVip'),
      permanentDeleteSpaces: flag('permanentDeleteSpaces'),
      deleteAnyMessage: flag('deleteAnyMessage'),
      permanentBan: flag('permanentBan'),
      manageRoles: flag('manageRoles'),
      fullAuditAccess: flag('fullAuditAccess'),
      viewAllQueues: flag('viewAllQueues'),
      quarantineSpaces: flag('quarantineSpaces'),
      endAnyRoom: flag('endAnyRoom'),
      handleAssignedReports: flag('handleAssignedReports'),
      removeReportedContent: flag('removeReportedContent'),
      warnUsers: flag('warnUsers'),
      endPublicRoomWithReason: flag('endPublicRoomWithReason'),
      suspendUsers: flag('suspendUsers'),
      suspensionLimitHours: (data['suspensionLimitHours'] as num?)?.toInt(),
      liftSuspensions: flag('liftSuspensions'),
      sanctionStaff: flag('sanctionStaff'),
      readAuditLogs: flag('readAuditLogs'),
      supportLookup: flag('supportLookup'),
      guideMode: flag('guideMode'),
    );
  }
}

/// Fetches and caches the account's capabilities.
///
/// The cache is keyed by uid and cleared the moment the signed-in user
/// changes, so a signed-out staff member's capabilities can never leak
/// into the next session on the same device. A fetch failure returns
/// [StaffCapabilities.none]: the app degrades to the ordinary UI rather
/// than guessing.
class StaffCapabilityService {
  StaffCapabilityService({FirebaseFunctions? functions, FirebaseAuth? auth})
    : _functionsOverride = functions,
      _auth = auth;

  final FirebaseFunctions? _functionsOverride;
  final FirebaseAuth? _auth;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  StaffCapabilities? _cached;
  String? _cachedForUid;

  Future<StaffCapabilities> load({bool refresh = false}) async {
    String? uid;
    try {
      uid = (_auth ?? FirebaseAuth.instance).currentUser?.uid;
    } catch (_) {
      uid = null;
    }
    if (uid == null) {
      _cached = null;
      _cachedForUid = null;
      return StaffCapabilities.none;
    }

    if (!refresh && _cached != null && _cachedForUid == uid) {
      return _cached!;
    }

    try {
      final result = await _functions
          .httpsCallable('getMyStaffCapabilities')
          .call<Map<String, dynamic>>(<String, dynamic>{});
      final map = Map<String, dynamic>.from(
        result.data['capabilities'] as Map? ?? const <String, dynamic>{},
      );
      _cached = StaffCapabilities.fromMap(map);
      _cachedForUid = uid;
      return _cached!;
    } catch (_) {
      // No capabilities on failure — ordinary UI, never a guess.
      return StaffCapabilities.none;
    }
  }

  void clear() {
    _cached = null;
    _cachedForUid = null;
  }
}
