import 'package:flutter/material.dart';

/// One app-level observer for route-aware shell features.
///
/// Guided onboarding uses it to wait until registration verification, a deep
/// link, or another pushed screen has fully left the root shell before showing
/// a modal product tour. It deliberately carries no feature state itself.
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
