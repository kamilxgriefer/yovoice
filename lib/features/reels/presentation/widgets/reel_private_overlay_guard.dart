import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';

/// Separate routes cannot inherit a parent's rebuild. This boundary owns only
/// the private report/confirmation subtree, never navigation of another route.
/// A background/auth/expiry transition permanently retires that old snapshot;
/// the revalidated comments host can open a fresh overlay after returning.
class ReelPrivateOverlayGuard extends StatefulWidget {
  const ReelPrivateOverlayGuard({
    required this.service,
    required this.viewerId,
    required this.now,
    required this.contentExpiresAt,
    required this.initiallyAllowed,
    required this.contentBuilder,
    super.key,
  });

  final ReelService service;
  final String viewerId;
  final DateTime Function() now;
  final DateTime? contentExpiresAt;
  final bool initiallyAllowed;
  final WidgetBuilder contentBuilder;

  @override
  State<ReelPrivateOverlayGuard> createState() =>
      _ReelPrivateOverlayGuardState();
}

class _ReelPrivateOverlayGuardState extends State<ReelPrivateOverlayGuard>
    with WidgetsBindingObserver {
  StreamSubscription<String?>? _identity;
  Timer? _expiry;
  WidgetBuilder? _contentBuilder;
  bool _identityEnded = false;
  late final ReelService _service = widget.service;
  late final String _viewerId = widget.viewerId;
  late final DateTime? _contentExpiresAt = widget.contentExpiresAt;
  late final DateTime Function() _now = widget.now;

  bool get _sameViewer =>
      !_identityEnded && _service.currentUserId == _viewerId;
  bool get _withinDeadline =>
      _contentExpiresAt == null || _now().isBefore(_contentExpiresAt);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (widget.initiallyAllowed &&
        _sameViewer &&
        _withinDeadline &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
      _contentBuilder = widget.contentBuilder;
      _armExpiry();
    }
    _identity = _service.identityChanges.listen((uid) {
      if (uid != _viewerId) _invalidate(identityEnded: true);
    }, onError: (Object _) => _invalidate(identityEnded: true));
  }

  @override
  void didUpdateWidget(covariant ReelPrivateOverlayGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.initiallyAllowed ||
        !identical(widget.service, _service) ||
        widget.viewerId != _viewerId ||
        widget.contentExpiresAt != _contentExpiresAt) {
      _invalidate();
    }
  }

  void _invalidate({bool identityEnded = false}) {
    if (!mounted) return;
    _expiry?.cancel();
    setState(() {
      _identityEnded = _identityEnded || identityEnded;
      _contentBuilder = null;
    });
  }

  void _armExpiry() {
    _expiry?.cancel();
    final deadline = _contentExpiresAt;
    if (deadline == null) return;
    final remaining = deadline.difference(_now());
    if (remaining <= Duration.zero) {
      _invalidate();
      return;
    }
    _expiry = Timer(
      remaining > const Duration(hours: 12)
          ? const Duration(hours: 12)
          : remaining,
      _armExpiry,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _invalidate();
  }

  @override
  void dispose() {
    _contentBuilder = null;
    _expiry?.cancel();
    unawaited(_identity?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contentBuilder = _contentBuilder;
    if (_sameViewer && _withinDeadline && contentBuilder != null) {
      return contentBuilder(context);
    }
    final copy = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('reel-link-comment-overlay-unavailable'),
      content: Text(
        _sameViewer
            ? copy.text(
                'This Reel is unavailable right now.',
                'Ten Reel jest teraz niedostępny.',
              )
            : copy.text(
                'Sign in to open this Reel.',
                'Zaloguj się, aby otworzyć ten Reel.',
              ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('reel-link-comment-overlay-close'),
          onPressed: () {
            if (ModalRoute.of(context)?.isCurrent == true) {
              Navigator.of(context).pop();
            }
          },
          child: Text(copy.text('Close', 'Zamknij')),
        ),
      ],
    );
  }
}
