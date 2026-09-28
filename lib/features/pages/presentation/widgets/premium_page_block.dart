import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/pages_availability.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_profile_parts.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';

/// What the Premium screen knows about Pages for the signed-in account.
@immutable
class PremiumPagesState {
  const PremiumPagesState({required this.enabled, required this.access});

  static const hidden = PremiumPagesState(
    enabled: false,
    access: PageAccessState.unknown,
  );

  /// `appConfig/pagesV1` lets this account see Pages (PagesAvailability).
  final bool enabled;
  final PageAccessState access;

  /// The "Twoja strona" block: a canonical-grant VIP without a Page (create)
  /// or the owner of one (open). Hidden until Pages are on.
  bool get showBlock =>
      enabled &&
      access.resolved &&
      (access.canCreatePage || access.ownPage != null);

  bool get ownsPage => access.ownPage != null;

  /// The R13 benefit card: honest copy (testers only), shown only while
  /// Pages exist for the account.
  bool get showBenefit => enabled;
}

/// Watches Pages availability and the account's Page access for the
/// Premium screen; rebuilds [builder] as either changes. Everything stays
/// hidden until `appConfig/pagesV1` enables Pages (spec premium-pages §7).
class PremiumPagesGate extends StatefulWidget {
  const PremiumPagesGate({
    required this.builder,
    this.enabled,
    this.accessStream,
    super.key,
  });

  final Widget Function(BuildContext context, PremiumPagesState state) builder;

  /// Test seams; the app uses [PagesAvailability.instance] and
  /// [PageAccessService.instance].
  final ValueListenable<bool>? enabled;
  final Stream<PageAccessState> Function()? accessStream;

  @override
  State<PremiumPagesGate> createState() => _PremiumPagesGateState();
}

class _PremiumPagesGateState extends State<PremiumPagesGate> {
  late final ValueListenable<bool> _enabled =
      widget.enabled ?? PagesAvailability.instance.enabled;
  PageAccessState _access = PageAccessState.unknown;
  StreamSubscription<PageAccessState>? _sub;

  @override
  void initState() {
    super.initState();
    _enabled.addListener(_onEnabled);
    _subscribeIfEnabled();
  }

  void _subscribeIfEnabled() {
    if (!_enabled.value || _sub != null) return;
    final stream =
        widget.accessStream?.call() ?? PageAccessService.instance.watch();
    _sub = stream.listen((state) {
      if (mounted && state != _access) setState(() => _access = state);
    }, onError: (Object _, StackTrace _) {});
  }

  void _onEnabled() {
    _subscribeIfEnabled();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _enabled.removeListener(_onEnabled);
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    PremiumPagesState(enabled: _enabled.value, access: _access),
  );
}

/// The "Twoja strona" block (R2; approved on the active view in create A,
/// and as P on the presentation view for a grant-only VIP). [grantOnly]
/// words it for a VIP without a plan ("Dostępna z Twoim VIP"): it never
/// says the account has Premium.
class PremiumPageBlock extends StatelessWidget {
  const PremiumPageBlock({
    required this.ownsPage,
    required this.grantOnly,
    required this.onCreate,
    required this.onOpen,
    super.key,
  });

  final bool ownsPage;
  final bool grantOnly;
  final VoidCallback onCreate;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final subtitle = grantOnly
        ? Row(
            children: [
              const YoVipRosette(diameter: 14, excludeSemantics: true),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  copy.availableWithVip,
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          )
        : Text(
            copy.businessOrCommunity,
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
              fontSize: 13,
            ),
          );
    return YoCard(
      key: const ValueKey('premium-page-block'),
      tint: AppColors.primary,
      semanticButton: false,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PageGlyph(Icons.article_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        copy.yourPageBlockTitle,
                        style: AppTypography.titleMedium.copyWith(
                          color: palette.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    subtitle,
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            ownsPage ? copy.ownPageBlockBody : copy.yourPageBlockBody,
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textPrimary.withValues(alpha: .86),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          YoButton(
            key: ValueKey(
              ownsPage ? 'premium-page-open' : 'premium-page-create',
            ),
            label: ownsPage ? copy.openPage : copy.createPage,
            height: 50,
            icon: Icon(
              ownsPage ? Icons.arrow_forward_rounded : Icons.add_rounded,
            ),
            onPressed: ownsPage ? onOpen : onCreate,
          ),
        ],
      ),
    );
  }
}
