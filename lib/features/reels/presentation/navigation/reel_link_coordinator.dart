import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/features/reels/data/reel_links.dart';
import 'package:yovoice/features/reels/presentation/screens/reel_link_destination_screen.dart';

/// One cold-start intent, retained above Login but never persisted to disk.
/// Capturing once prevents a consumed browser query reopening after logout.
class ReelLinkIntentController extends ChangeNotifier {
  ReelLinkIntentController({required Uri initialUri})
    : _pendingReelId = parseReelLink(initialUri) {
    if (_pendingReelId == null) _visitCompleted.complete();
  }

  String? _pendingReelId;
  String? _userId;
  bool _hasPrincipal = false;
  final Completer<void> _visitCompleted = Completer<void>();

  /// Onboarding waits for this visit, just as it waits for a room deep link.
  Future<void> get initialVisitCompleted => _visitCompleted.future;

  void handlePrincipal(String? userId) {
    if (_hasPrincipal && _userId != null && _userId != userId) {
      _pendingReelId = null;
      completeVisit();
    }
    _hasPrincipal = true;
    _userId = userId;
    notifyListeners();
  }

  void handleAuthError() {
    _pendingReelId = null;
    _userId = null;
    _hasPrincipal = true;
    completeVisit();
    notifyListeners();
  }

  String? consumeFor(String userId) {
    if (!_hasPrincipal || userId.isEmpty || _userId != userId) return null;
    final id = _pendingReelId;
    _pendingReelId = null;
    return id;
  }

  void completeVisit() {
    if (!_visitCompleted.isCompleted) _visitCompleted.complete();
  }
}

/// Mounted only AFTER authenticated profile bootstrap has succeeded.
/// Registration/verification routes retain priority until the root is current.
class ReelLinkEntryCoordinator extends StatefulWidget {
  const ReelLinkEntryCoordinator({
    required this.controller,
    required this.userId,
    required this.child,
    this.destinationBuilder,
    super.key,
  });

  final ReelLinkIntentController controller;
  final String userId;
  final Widget child;
  final Widget Function(BuildContext context, String reelId)?
  destinationBuilder;

  @override
  State<ReelLinkEntryCoordinator> createState() =>
      _ReelLinkEntryCoordinatorState();
}

class _ReelLinkEntryCoordinatorState extends State<ReelLinkEntryCoordinator>
    with RouteAware {
  ModalRoute<void>? _route;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_schedule);
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (!identical(_route, route)) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) appRouteObserver.subscribe(this, route);
    }
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ReelLinkEntryCoordinator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_schedule);
      widget.controller.addListener(_schedule);
    }
    _schedule();
  }

  @override
  void didPopNext() => _schedule();

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || _route?.isCurrent != true) return;
      final controller = widget.controller;
      final id = controller.consumeFor(widget.userId);
      if (id == null) return;
      unawaited(
        Navigator.of(context, rootNavigator: true)
            .push<void>(
              MaterialPageRoute<void>(
                // This is not a second named URL route. Keep the public
                // query contract and never put content/IDs in route titles.
                builder: (context) =>
                    widget.destinationBuilder?.call(context, id) ??
                    ReelLinkDestinationScreen(reelId: id),
              ),
            )
            .whenComplete(controller.completeVisit),
      );
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_schedule);
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
