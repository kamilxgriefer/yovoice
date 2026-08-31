import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/premium/data/models/premium_billing_context.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/premium_plans.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/data/services/premium_billing_service.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_badge_pill.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

List<Color> _premiumPlanGradientColors(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return <Color>[colors.primary, colors.secondary];
}

/// The plans & purchase screen — where the "Check plans" CTA lands.
///
/// Pricing, tax copy, checkout availability and billing ownership all come
/// from the trusted billing context. Web checkout and the Stripe customer
/// portal are server-created; App Store / Play subscriptions open their own
/// management surfaces. Nothing is unlocked optimistically.
class PremiumPlansScreen extends StatefulWidget {
  const PremiumPlansScreen({
    this.entitlementService,
    this.billingService,
    super.key,
  });

  final EntitlementService? entitlementService;
  final PremiumBillingGateway? billingService;

  @override
  State<PremiumPlansScreen> createState() => _PremiumPlansScreenState();
}

class _PremiumPlansScreenState extends State<PremiumPlansScreen> {
  late final EntitlementService _entitlements =
      widget.entitlementService ?? EntitlementService();
  late final PremiumBillingGateway _billing =
      widget.billingService ?? PremiumBillingService();
  late Future<PremiumBillingContext> _billingContext;

  PremiumPlan _selected = PremiumPlan.yearly;
  bool _busy = false;
  bool _wasPremiumOnOpen = false;
  bool _checkedInitial = false;
  bool _popScheduled = false;

  @override
  void initState() {
    super.initState();
    _billingContext = _loadBillingContext();
  }

  Future<PremiumBillingContext> _loadBillingContext() => _billing.getContext(
    countryCode: WidgetsBinding.instance.platformDispatcher.locale.countryCode,
  );

  void _retryBilling() {
    setState(() => _billingContext = _loadBillingContext());
  }

  Future<void> _attemptPurchase(PremiumLocalizedPlan product) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final uri = await _billing.createCheckout(product.plan);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Billing link could not be opened.');
      }
    } on FirebaseFunctionsException catch (error) {
      _showBillingError(error);
    } catch (_) {
      _showMessage('We couldn\'t open checkout. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openManagement(PremiumBillingContext billing) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final uri = switch (billing.billingManagedBy) {
        PremiumBillingManager.apple => Uri.parse(
          'https://apps.apple.com/account/subscriptions',
        ),
        PremiumBillingManager.google => Uri.parse(
          'https://play.google.com/store/account/subscriptions',
        ),
        _ => await _billing.createPortal(),
      };
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Billing portal could not be opened.');
      }
    } on FirebaseFunctionsException catch (error) {
      _showBillingError(error);
    } catch (_) {
      _showMessage(
        'We couldn\'t open subscription management. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showBillingError(FirebaseFunctionsException error) {
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    final message = switch (reason) {
      'billing-managed-elsewhere' =>
        'This subscription is managed by your app store. Open your store subscription settings to make changes.',
      'stripe-customer-missing' =>
        'We couldn\'t find a billing profile for this subscription. Contact support if this keeps happening.',
      'billing-not-configured' =>
        'Billing is temporarily unavailable. Please try again later.',
      'stripe-subscription-exists' =>
        'You already have a web subscription. Open subscription management to change it.',
      'checkout-in-progress' =>
        'A checkout is already in progress. Finish it or try again in a moment.',
      _ => 'We couldn\'t open billing. Please try again.',
    };
    _showMessage(message);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: palette.textPrimary,
        elevation: 0,
      ),
      body: StreamBuilder<SubscriptionEntitlements>(
        stream: _entitlements.watchCurrentEntitlements(),
        builder: (context, snapshot) {
          final entitlements = snapshot.data ?? SubscriptionEntitlements.free;

          if (!_checkedInitial && snapshot.hasData) {
            _wasPremiumOnOpen = entitlements.isPremium;
            _checkedInitial = true;
          }

          // A purchase (or grant) landed while this screen was open —
          // return to PremiumScreen, which now shows the welcome state.
          if (_checkedInitial &&
              !_wasPremiumOnOpen &&
              entitlements.isPremium &&
              !_popScheduled) {
            _popScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            });
          }

          return FutureBuilder<PremiumBillingContext>(
            future: _billingContext,
            builder: (context, billingSnapshot) {
              if (billingSnapshot.connectionState != ConnectionState.done) {
                return Center(
                  child: CircularProgressIndicator(color: colors.primary),
                );
              }
              if (billingSnapshot.hasError || !billingSnapshot.hasData) {
                return _BillingLoadError(onRetry: _retryBilling);
              }
              final billing = billingSnapshot.requireData;
              final billingRecoveryAvailable =
                  !entitlements.isPremium && billing.portalAvailable;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 40),
                    children: [
                      const Center(child: PremiumBadgePill()),
                      const SizedBox(height: 16),
                      Text(
                        entitlements.isPremium
                            ? 'Manage your plan'
                            : billingRecoveryAvailable
                            ? 'Review your billing'
                            : 'Choose your plan',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entitlements.isPremium
                            ? 'See your current plan, compare options or manage billing.'
                            : billingRecoveryAvailable
                            ? 'A web billing profile is linked to this account. Check its status securely in Stripe.'
                            : 'Unlock the full YO Voice experience',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (entitlements.isPremium) ...[
                        _CurrentPlanCard(
                          entitlements: entitlements,
                          billing: billing,
                          busy: _busy,
                          onManage: () => _openManagement(billing),
                        ),
                        const SizedBox(height: 20),
                      ] else if (billingRecoveryAvailable) ...[
                        _BillingRecoveryCard(
                          busy: _busy,
                          onManage: () => _openManagement(billing),
                        ),
                        const SizedBox(height: 20),
                      ],
                      _PlanToggle(
                        selected: _selected,
                        yearlySavingsPercent: billing.plans
                            .firstWhere(
                              (plan) => plan.plan == PremiumPlan.yearly,
                            )
                            .savingsPercent,
                        onChanged: (plan) => setState(() => _selected = plan),
                      ),
                      const SizedBox(height: 20),
                      _PlanCards(
                        plans: billing.plans,
                        selected: _selected,
                        busy: _busy,
                        checkoutAvailable: kIsWeb && billing.checkoutAvailable,
                        onSelect: (plan) => setState(() => _selected = plan),
                        onChoose: _attemptPurchase,
                      ),
                      if (!kIsWeb &&
                          billing.billingManagedBy !=
                              PremiumBillingManager.admin) ...[
                        const SizedBox(height: 12),
                        Text(
                          'To start or change a web subscription, continue on yovoice.app. App Store and Google Play purchases stay managed by their store.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        billing.taxNotice,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Everything Premium includes:',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const _EverythingIncluded(),
                      const SizedBox(height: 20),
                      const _TrustFooter(),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () =>
                                _openUrl('https://yovoice.app/terms'),
                            child: Text(
                              'Terms',
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            '·',
                            style: TextStyle(color: palette.textSecondary),
                          ),
                          TextButton(
                            onPressed: () =>
                                _openUrl('https://yovoice.app/privacy'),
                            child: Text(
                              'Privacy',
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _BillingLoadError extends StatelessWidget {
  const _BillingLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, color: colors.primary, size: 38),
              const SizedBox(height: 14),
              Text(
                'Plans are temporarily unavailable',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We couldn\'t load plan pricing. Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cancellation and invoice recovery when the provider binding exists but the
/// local access projection is missing, inactive or still reconciling.
///
/// This surface deliberately makes no statement about an active plan, renewal
/// or period end. Stripe remains the authority for those billing details while
/// the entitlement projection remains the authority for product access.
class _BillingRecoveryCard extends StatelessWidget {
  const _BillingRecoveryCard({required this.busy, required this.onManage});

  final bool busy;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Stripe billing management',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.primary.withValues(alpha: .65)),
        ),
        child: Wrap(
          spacing: 18,
          runSpacing: 16,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 410),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Billing management',
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stripe billing portal',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Review billing status, invoices and cancellation options. Premium access may still be syncing.',
                    style: TextStyle(color: palette.textSecondary, height: 1.4),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: busy ? null : onManage,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open billing portal'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({
    required this.entitlements,
    required this.billing,
    required this.busy,
    required this.onManage,
  });

  final SubscriptionEntitlements entitlements;
  final PremiumBillingContext billing;
  final bool busy;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final end = billing.currentPeriodEnd;
    final periodText = billing.billingManagedBy == PremiumBillingManager.admin
        ? 'Complimentary Premium access'
        : billing.renewalBehavior == 'ends' && end != null
        ? 'Ends ${end.day}.${end.month}.${end.year}'
        : billing.renewalBehavior == 'renews' && end != null
        ? 'Renews ${end.day}.${end.month}.${end.year}'
        : end == null
        ? 'Premium active'
        : 'Premium active';
    final manager = switch (billing.billingManagedBy) {
      PremiumBillingManager.apple => 'Managed in the App Store',
      PremiumBillingManager.google => 'Managed in Google Play',
      PremiumBillingManager.admin => 'Complimentary access',
      PremiumBillingManager.stripe => 'Managed securely by Stripe',
      PremiumBillingManager.none => 'Billing details unavailable',
    };
    return Semantics(
      container: true,
      label: 'Current Premium subscription',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.primary.withValues(alpha: .65)),
        ),
        child: Wrap(
          spacing: 18,
          runSpacing: 16,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 410),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Current plan',
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'YO Voice Premium · ${entitlements.plan.label}',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$periodText · $manager',
                    style: TextStyle(color: palette.textSecondary, height: 1.4),
                  ),
                ],
              ),
            ),
            if (billing.portalAvailable ||
                billing.billingManagedBy == PremiumBillingManager.apple ||
                billing.billingManagedBy == PremiumBillingManager.google)
              FilledButton.icon(
                onPressed: busy ? null : onManage,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Change or cancel'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Monthly | Yearly segmented control with the server-provided savings chip.
class _PlanToggle extends StatelessWidget {
  const _PlanToggle({
    required this.selected,
    required this.yearlySavingsPercent,
    required this.onChanged,
  });

  final PremiumPlan selected;
  final int yearlySavingsPercent;
  final ValueChanged<PremiumPlan> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      // Four pixels of inset on each side still leaves a 48px target for
      // both keyboard- and touch-selectable segments.
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _segment(
              context: context,
              label: 'Monthly',
              plan: PremiumPlan.monthly,
            ),
            _segment(
              context: context,
              label: 'Yearly',
              plan: PremiumPlan.yearly,
              chip: yearlySavingsPercent > 0 ? '-$yearlySavingsPercent%' : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment({
    required BuildContext context,
    required String label,
    required PremiumPlan plan,
    String? chip,
  }) {
    final palette = context.appPalette;
    final active = selected == plan;
    return Expanded(
      child: AccessibleTapRegion(
        onTap: () => onChanged(plan),
        semanticLabel: 'Select $label billing plan',
        tooltip: 'Select $label billing',
        selected: active,
        borderRadius: 999,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: active ? palette.surfaceRaised : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? palette.borderStrong : Colors.transparent,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 7,
                runSpacing: 4,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: active
                          ? palette.textPrimary
                          : palette.textSecondary,
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  if (chip != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(
                          colors: _premiumPlanGradientColors(context),
                        ),
                      ),
                      child: Text(
                        chip,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
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

/// The Monthly + Yearly cards side by side; the selected plan carries the
/// glow treatment and the gradient button. "Best value" stays on Yearly
/// regardless of selection — it's a fact about the plan, not a UI state.
class _PlanCards extends StatelessWidget {
  const _PlanCards({
    required this.plans,
    required this.selected,
    required this.busy,
    required this.checkoutAvailable,
    required this.onSelect,
    required this.onChoose,
  });

  final List<PremiumLocalizedPlan> plans;
  final PremiumPlan selected;
  final bool busy;
  final bool checkoutAvailable;
  final ValueChanged<PremiumPlan> onSelect;
  final ValueChanged<PremiumLocalizedPlan> onChoose;

  @override
  Widget build(BuildContext context) {
    final checkColor = context.appPalette.interactiveForeground;
    final monthly = plans.firstWhere(
      (plan) => plan.plan == PremiumPlan.monthly,
    );
    final yearly = plans.firstWhere((plan) => plan.plan == PremiumPlan.yearly);
    final monthlyCard = _PlanCard(
      product: monthly,
      selected: selected == PremiumPlan.monthly,
      checkColor: checkColor,
      busy: busy || !checkoutAvailable,
      onSelect: onSelect,
      onChoose: onChoose,
    );
    final yearlyCard = _PlanCard(
      product: yearly,
      selected: selected == PremiumPlan.yearly,
      checkColor: checkColor,
      busy: busy || !checkoutAvailable,
      onSelect: onSelect,
      onChoose: onChoose,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 560 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        if (stacked) {
          return Column(
            children: [monthlyCard, const SizedBox(height: 18), yearlyCard],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: monthlyCard),
              const SizedBox(width: 12),
              Expanded(child: yearlyCard),
            ],
          ),
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.product,
    required this.selected,
    required this.checkColor,
    required this.busy,
    required this.onSelect,
    required this.onChoose,
  });

  final PremiumLocalizedPlan product;
  final bool selected;
  final Color checkColor;
  final bool busy;
  final ValueChanged<PremiumPlan> onSelect;
  final ValueChanged<PremiumLocalizedPlan> onChoose;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final card = AccessibleTapRegion(
      onTap: () => onSelect(product.plan),
      semanticLabel:
          'Select ${product.plan.label} plan, ${product.formattedPrice}',
      tooltip: 'Select ${product.plan.label} plan',
      selected: selected,
      borderRadius: 22,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: selected ? palette.surfaceRaised : palette.surface,
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: .8)
                : palette.border,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: .16),
                    blurRadius: 30,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.plan.label,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              product.formattedPrice,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              product.interval == 'month' ? '/ month' : '/ year',
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 3),
            Text(
              'Base price · final local price at checkout',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 11,
                height: 1.3,
              ),
            ),
            if (product.formattedEquivalent != null) ...[
              const SizedBox(height: 4),
              Text(
                '${product.formattedEquivalent!} / month',
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
            ],
            if (product.savingsPercent > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4.5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    colors: _premiumPlanGradientColors(context),
                  ),
                ),
                child: Text(
                  'Save ${product.savingsPercent}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            for (final item in PremiumPlans.planChecklist)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Icon(Icons.check_rounded, size: 14, color: checkColor),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            _chooseButton(context),
          ],
        ),
      ),
    );

    // Reserve headroom so the "Best value" pill can straddle the border
    // while both cards stay top-aligned.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(padding: const EdgeInsets.only(top: 13), child: card),
        if (product.plan == PremiumPlan.yearly)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              // Half-width cards on narrow phones can't always fit the
              // pill at full size — scale it rather than overflow.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      colors: _premiumPlanGradientColors(context),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondary.withValues(alpha: .45),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.workspace_premium_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Best value',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _chooseButton(BuildContext context) {
    final palette = context.appPalette;
    final label = 'Choose\n${product.plan.label.toLowerCase()}';

    if (selected) {
      return SizedBox(
        width: double.infinity,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: _premiumPlanGradientColors(context),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: .35),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: busy ? null : () => onChoose(product),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  child: Center(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Material(
          color: palette.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: busy ? null : () => onChoose(product),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.border),
              ),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EverythingIncluded extends StatelessWidget {
  const _EverythingIncluded();

  static const _icons = [
    Icons.person_outline_rounded,
    Icons.workspace_premium_outlined,
    Icons.graphic_eq_rounded,
    Icons.auto_awesome_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: palette.surface,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < PremiumPlans.everythingIncluded.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(_icons[i], size: 19, color: colors.primary),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      PremiumPlans.everythingIncluded[i],
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TrustFooter extends StatelessWidget {
  const _TrustFooter();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 13,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                'Secure checkout',
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 13,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                'Cancel anytime',
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
