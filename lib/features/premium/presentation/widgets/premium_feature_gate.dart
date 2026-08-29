import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/premium_gates.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_badge_pill.dart';

/// A second-line guard for complete Premium destinations.
///
/// Normal navigation checks [PremiumGates.ensureFeatureAccess] before opening
/// a route. This widget still protects a stale desktop slot, a deep link, or a
/// future caller that mounts the destination directly. It also reacts when an
/// active subscription expires while the destination is open.
class PremiumFeatureGate extends StatefulWidget {
  const PremiumFeatureGate({
    required this.feature,
    required this.child,
    this.entitlementService,
    this.isRootTab = false,
    this.now = DateTime.now,
    super.key,
  });

  final PremiumFeature feature;
  final Widget child;
  final EntitlementService? entitlementService;
  final bool isRootTab;

  /// Injectable clock keeps the exact expiry boundary deterministic in tests.
  final DateTime Function() now;

  @override
  State<PremiumFeatureGate> createState() => _PremiumFeatureGateState();
}

class _PremiumFeatureGateState extends State<PremiumFeatureGate> {
  // Browser setTimeout uses a signed 32-bit millisecond delay (~24.8 days).
  // Monthly/yearly periods regularly exceed it, so expiry is watched in
  // bounded slices instead of passing the full subscription duration to JS.
  static const _maxExpiryTimerSlice = Duration(hours: 12);

  late final EntitlementService _service =
      widget.entitlementService ?? EntitlementService();
  late final Stream<SubscriptionEntitlements> _entitlements = _stream();
  Timer? _expiryTimer;
  DateTime? _scheduledPeriodEnd;
  DateTime? _locallyExpiredPeriodEnd;

  Stream<SubscriptionEntitlements> _stream() {
    try {
      return _service.watchCurrentEntitlements();
    } catch (_) {
      return Stream<SubscriptionEntitlements>.value(
        SubscriptionEntitlements.free,
      );
    }
  }

  void _scheduleExpiry(SubscriptionEntitlements entitlements) {
    if (entitlements.hasModeratorBenefits) {
      // Paid expiry is not the expiry of an independently proven moderator
      // preview. Clear any prior local billing timer so it cannot evict an
      // active moderator from an already-open destination.
      _expiryTimer?.cancel();
      _expiryTimer = null;
      _scheduledPeriodEnd = null;
      _locallyExpiredPeriodEnd = null;
      return;
    }
    final periodEnd = entitlements.currentPeriodEnd;
    if (!entitlements.isPremium || periodEnd == null) {
      _expiryTimer?.cancel();
      _expiryTimer = null;
      _scheduledPeriodEnd = null;
      return;
    }
    if (_scheduledPeriodEnd == periodEnd) return;

    _expiryTimer?.cancel();
    _scheduledPeriodEnd = periodEnd;
    _scheduleExpiryCheck(periodEnd);
  }

  void _scheduleExpiryCheck(DateTime periodEnd) {
    final remaining = periodEnd.difference(widget.now());
    if (remaining <= Duration.zero) {
      _locallyExpiredPeriodEnd = periodEnd;
      return;
    }
    final delay = remaining > _maxExpiryTimerSlice
        ? _maxExpiryTimerSlice
        : remaining + const Duration(milliseconds: 1);
    _expiryTimer = Timer(delay, () {
      if (!mounted) return;
      if (_scheduledPeriodEnd != periodEnd) return;
      if (!widget.now().isBefore(periodEnd)) {
        setState(() => _locallyExpiredPeriodEnd = periodEnd);
      } else {
        _scheduleExpiryCheck(periodEnd);
      }
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SubscriptionEntitlements>(
      stream: _entitlements,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          final palette = context.appPalette;
          return Scaffold(
            backgroundColor: palette.background,
            body: Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          );
        }

        final entitlements = snapshot.data ?? SubscriptionEntitlements.free;
        _scheduleExpiry(entitlements);
        final expiredWithoutSnapshot =
            _locallyExpiredPeriodEnd == entitlements.currentPeriodEnd;
        if (!expiredWithoutSnapshot &&
            widget.feature.isEnabledBy(entitlements)) {
          return widget.child;
        }

        return _PremiumLockedDestination(
          feature: widget.feature,
          isRootTab: widget.isRootTab,
        );
      },
    );
  }
}

class _PremiumLockedDestination extends StatelessWidget {
  const _PremiumLockedDestination({
    required this.feature,
    required this.isRootTab,
  });

  final PremiumFeature feature;
  final bool isRootTab;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: isRootTab
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: palette.textPrimary,
              elevation: 0,
            ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PremiumBadgePill(),
                  const SizedBox(height: 22),
                  Container(
                    width: 84,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primaryContainer,
                      border: Border.all(
                        color: colors.primary.withValues(alpha: .65),
                      ),
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      key: ValueKey('premium-destination-lock'),
                      color: colors.onPrimaryContainer,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${feature.label} requires Premium',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    feature.lockedDescription,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const PremiumScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.workspace_premium_rounded),
                      label: const Text('Explore Premium'),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
