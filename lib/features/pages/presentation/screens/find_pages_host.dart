import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/controllers/pages_controllers.dart';
import 'package:yovoice/features/pages/presentation/page_navigation.dart';
import 'package:yovoice/features/pages/presentation/screens/find_pages_screen.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_state_views.dart';

/// Find Pages opened from OUTSIDE Treści (firstSteps A: the empty
/// Notifications screen's "Znajdź strony do obserwowania").
///
/// The shell hosts it over whatever asked, the way it hosts a Page profile
/// (`PagesShellBridge.host`): the dock shows Treści selected on phones, the
/// rail row is lit on desktop, nothing under it is popped and Back returns to
/// where it was opened. It is the same [FindPagesScreen] Treści pushes on its
/// own navigator, on the Pages canvas, with this route's own follow registry;
/// a Page opens through [openPageProfile], so it lands on the shell host too.
class FindPagesHost extends StatefulWidget {
  const FindPagesHost({this.service, this.onOpenPage, super.key});

  /// Test seams; the app uses the shared instance and [openPageProfile].
  final PagesService? service;
  final Future<void> Function(
    BuildContext context, {
    required String pageId,
    String? displayName,
  })?
  onOpenPage;

  @override
  State<FindPagesHost> createState() => _FindPagesHostState();
}

class _FindPagesHostState extends State<FindPagesHost> {
  late final PagesService _service = widget.service ?? PagesService.instance;
  late final PagesFollowRegistry _follows = PagesFollowRegistry(_service);

  @override
  void dispose() {
    _follows.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PagesCanvas(
    child: FindPagesScreen(
      service: _service,
      follows: _follows,
      onOpenPage: (context, card) => unawaited(
        (widget.onOpenPage ?? openPageProfile)(
          context,
          pageId: card.pageId,
          displayName: card.displayName,
        ),
      ),
    ),
  );
}
