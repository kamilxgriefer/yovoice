import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/likers/presentation/likers_copy.dart';
import 'package:yovoice/features/premium/data/services/premium_billing_service.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Resolves whether Premium can be bought right now (see
/// [premiumCheckoutAvailable]).
typedef PremiumCanBuyResolver = Future<bool> Function();

/// What a viewer without Premium or VIP sees (owner variant U1, spec §13):
/// the same sheet family as the list, five anonymous blurred placeholder
/// avatars under a lock, the PUBLIC count, the benefit, and — while Premium
/// cannot be bought — the honest "not available to buy yet" line with one
/// neutral Close button: no purchase CTA and no link (owner answer §12.5,
/// App Store 3.1.1).
///
/// Billing-aware (spec §5.4): only when a purchase can actually complete
/// ([premiumCheckoutAvailable]: the web with checkout on) does the line give
/// way to "Explore Premium" (into [PremiumScreen] and its plans) plus
/// "Not now". iOS and Android resolve to the honest variant without a
/// network call; on the web the Close button is live while the answer loads
/// and the status line's space is held, so nothing jumps.
///
/// The placeholders are generic person glyphs, never real likers: this
/// viewer is not entitled to know who they are. With no [target] (the
/// generic `PremiumUpsellContext.seeWhoLiked` entry) the count line is
/// omitted.
class LikersUpsellSheet extends StatefulWidget {
  const LikersUpsellSheet({
    this.target,
    this.totalCount = 0,
    this.canBuyPremium,
    this.premiumDestination,
    super.key,
  });

  final LikersTarget? target;
  final int totalCount;

  /// Test seam; production resolves [premiumCheckoutAvailable].
  final PremiumCanBuyResolver? canBuyPremium;

  /// Test seam for the "Explore Premium" destination; defaults to
  /// [PremiumScreen].
  final WidgetBuilder? premiumDestination;

  @override
  State<LikersUpsellSheet> createState() => _LikersUpsellSheetState();
}

class _LikersUpsellSheetState extends State<LikersUpsellSheet> {
  /// null while the web billing answer is loading.
  bool? _canBuy;

  @override
  void initState() {
    super.initState();
    final resolver = widget.canBuyPremium;
    if (resolver == null && !kIsWeb) {
      // No in-app purchase client exists: known without asking.
      _canBuy = false;
      return;
    }
    _resolve(resolver ?? premiumCheckoutAvailable);
  }

  Future<void> _resolve(PremiumCanBuyResolver resolver) async {
    bool canBuy;
    try {
      canBuy = await resolver();
    } catch (_) {
      canBuy = false;
    }
    if (mounted) setState(() => _canBuy = canBuy);
  }

  void _explorePremium() {
    final navigator = Navigator.of(context);
    final destination =
        widget.premiumDestination ?? (_) => const PremiumScreen();
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(builder: destination));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = LikersCopy(AppLocalizations.of(context));
    final target = widget.target;
    final totalCount = widget.totalCount;
    final canBuy = _canBuy;
    return Material(
      key: const ValueKey('likers-upsell-surface'),
      color: palette.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.vertical(top: AppRadius.xl.topLeft),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                YoModalSheetChrome(
                  sheetLabel: copy.upsellSheetLabel,
                  surfaceColor: palette.surfaceRaised,
                  horizontalPadding: 0,
                ),
                const SizedBox(height: 4),
                const _BlurredLikers(),
                if (target != null && totalCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    copy.countLine(target, totalCount),
                    key: const ValueKey('likers-upsell-count'),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    copy.upsellTitle,
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineSmall.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  copy.upsellBody,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: palette.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                if (canBuy == true)
                  ..._buyActions(copy)
                else ...[
                  // While the web answer loads, the status line's space is
                  // held (invisible, unannounced) and Close already works.
                  Visibility(
                    visible: canBuy == false,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    child: _NotForSaleLine(text: copy.notForSale),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: YoGradientFilledButton(
                      buttonKey: const ValueKey('likers-upsell-close'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      emphasis: YoActionEmphasis.neutral,
                      minimumSize: const Size.fromHeight(48),
                      child: Text(copy.close),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buyActions(LikersCopy copy) {
    final palette = context.appPalette;
    return [
      const SizedBox(height: 4),
      SizedBox(
        width: double.infinity,
        child: YoGradientFilledButton(
          buttonKey: const ValueKey('likers-upsell-explore'),
          onPressed: _explorePremium,
          minimumSize: const Size.fromHeight(48),
          child: Text(copy.explorePremium),
        ),
      ),
      const SizedBox(height: 8),
      TextButton(
        key: const ValueKey('likers-upsell-close'),
        onPressed: () => Navigator.of(context).maybePop(),
        style: TextButton.styleFrom(
          minimumSize: const Size(88, 48),
          foregroundColor: palette.textSecondary,
        ),
        child: Text(copy.notNow),
      ),
    ];
  }
}

class _NotForSaleLine extends StatelessWidget {
  const _NotForSaleLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      key: const ValueKey('likers-upsell-not-for-sale'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.glass,
        borderRadius: AppRadius.md,
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: ExcludeSemantics(
              child: Icon(
                Icons.schedule_rounded,
                size: 18,
                color: palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                color: palette.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Five anonymous person glyphs, blurred, under a lock. Pure decoration.
class _BlurredLikers extends StatelessWidget {
  const _BlurredLikers();

  static const double _radius = 22;
  static const double _step = 30;
  static const int _count = 5;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return ExcludeSemantics(
      child: SizedBox(
        width: _step * (_count - 1) + _radius * 2,
        height: _radius * 2 + 8,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
              child: Stack(
                children: [
                  for (var i = 0; i < _count; i++)
                    PositionedDirectional(
                      start: i * _step,
                      top: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: palette.surfaceRaised,
                            width: 2,
                          ),
                        ),
                        child: const UserAvatar(
                          radius: _radius - 2,
                          displayName: '',
                          fallbackIcon: Icons.person_rounded,
                          finish: UserAvatarFinish.brand,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.surfaceRaised,
                border: Border.all(color: palette.hairlineControl),
                boxShadow: [
                  BoxShadow(
                    color: palette.contactShadow,
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                Icons.lock_rounded,
                size: 18,
                color: palette.interactiveForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
