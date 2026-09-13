import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/servers/presentation/screens/create_server_screen.dart';

/// Compatibility entry point for old callers and links.
///
/// The standalone room/Club selector no longer exists. Keeping the class avoids
/// breaking source integrations while every invocation renders the canonical
/// five-template server creator.
@Deprecated('Use CreateServerScreen.')
class RoomTypeSelectorScreen extends StatelessWidget {
  const RoomTypeSelectorScreen({
    this.entitlementService,
    this.clubService,
    super.key,
  });

  /// Inert legacy seams retained while external previews migrate.
  final EntitlementService? entitlementService;
  final ClubService? clubService;

  // Kept for source compatibility with the historical family visual test.
  static final familyAccent = SpaceIdentity.family.primary;
  static final familyGlow = SpaceIdentity.family.accent;
  static final familySurface = SpaceIdentity.family.surface;
  static final familyBorder = SpaceIdentity.family.border;

  @override
  Widget build(BuildContext context) => const CreateServerScreen();
}
