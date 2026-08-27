/// Process-local guard against stacking the same private call route from two
/// delivery paths (the foreground Firestore stream and an FCM notification
/// tap racing during app resume).
class DirectCallRouteRegistry {
  DirectCallRouteRegistry._();

  static final Set<String> _claimedCallIds = <String>{};

  static bool claim(String callId) => _claimedCallIds.add(callId);

  static void release(String callId) => _claimedCallIds.remove(callId);
}
