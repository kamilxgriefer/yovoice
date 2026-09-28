import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/features/likers/data/models/likers_page.dart';
import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/likers/data/services/likers_access_service.dart';
import 'package:yovoice/features/likers/data/services/likers_service.dart';
import 'package:yovoice/features/likers/presentation/likers_copy.dart';
import 'package:yovoice/features/likers/presentation/widgets/likers_list_view.dart';
import 'package:yovoice/features/likers/presentation/widgets/likers_upsell_sheet.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

export 'package:yovoice/features/likers/presentation/widgets/likers_list_view.dart'
    show LikerOpener;

/// Widest the likers and upsell sheets grow (spec §5.2).
const double kLikersSheetMaxWidth = 520;

/// Below this width the list is a draggable phone sheet; at and above it, a
/// fixed-height sheet centred by the adaptive modal constraints.
const double kLikersSheetCompactBreakpoint = 600;

/// How long the cached pre-gate may take before it counts as "no" and the
/// fresh re-check decides.
const Duration _preGateTimeout = Duration(seconds: 4);

final Set<NavigatorState> _openLikersNavigators = <NavigatorState>{};

/// The one entry to "See who liked" / "See who reacted" (spec §5.5).
///
/// 1. The cached pre-gate ([LikersAccessService.watchCanSeeLikers]); when it
///    says no, one fresh re-read ([LikersAccessService.canSeeLikers]), so a
///    paid member whose grant pre-read failed is not upsold.
/// 2. Allowed: the list sheet (owner variant B). Otherwise: the upsell
///    (owner variant U1). If the server answers `likersAccessRequired`
///    mid-session, the list closes into the upsell.
/// 3. [onSheetOpened] fires once before the first sheet and [onSheetClosed]
///    once after the last, so a media host can pause playback and
///    auto-advance for the whole flow; then focus returns to [returnFocus].
///
/// The server stays the authority (spec §2). One flow per Navigator: a
/// second tap while one is opening is ignored.
Future<void> showLikers(
  BuildContext context,
  LikersTarget target, {
  required int totalCount,
  Map<String, int> reactionCounts = const <String, int>{},
  LikersAccessService? access,
  LikersService? service,
  VoidCallback? onSheetOpened,
  VoidCallback? onSheetClosed,
  FocusNode? returnFocus,
  LikerOpener? onOpenLiker,
  String? viewerId,
  PublicIdentityRepository? identityRepository,
}) async {
  final navigator = Navigator.of(context);
  if (!_openLikersNavigators.add(navigator)) return;
  var opened = false;
  try {
    final gate = access ?? LikersAccessService();
    var allowed = await gate.watchCanSeeLikers().first.timeout(
      _preGateTimeout,
      onTimeout: () => false,
    );
    if (!allowed) allowed = await gate.canSeeLikers();
    if (!context.mounted) return;

    onSheetOpened?.call();
    opened = true;

    var upsell = !allowed;
    if (allowed) {
      var accessRequired = false;
      await _showListSheet(
        context,
        target: target,
        totalCount: totalCount,
        reactionCounts: reactionCounts,
        service: service ?? LikersService(),
        viewerId: viewerId ?? _currentUid(),
        onOpenLiker: onOpenLiker ?? _openProfilePreview,
        identityRepository: identityRepository,
        onAccessRequired: () => accessRequired = true,
      );
      upsell = accessRequired;
    }
    if (upsell && context.mounted) {
      await showLikersUpsell(context, target, totalCount: totalCount);
    }
  } finally {
    _openLikersNavigators.remove(navigator);
    if (opened) onSheetClosed?.call();
    final node = returnFocus;
    final nodeContext = node?.context;
    // Not when "Explore Premium" pushed a route over the invoker: focus
    // must not move into a covered route.
    if (node != null &&
        nodeContext != null &&
        nodeContext.mounted &&
        node.canRequestFocus &&
        (ModalRoute.of(nodeContext)?.isCurrent ?? true)) {
      node.requestFocus();
    }
  }
}

/// The non-VIP upsell (owner variant U1) on its own, for hosts that already
/// know the viewer is locked out. A null [target] (the generic
/// `PremiumUpsellContext.seeWhoLiked` entry) omits the count line.
Future<void> showLikersUpsell(
  BuildContext context,
  LikersTarget? target, {
  required int totalCount,
  PremiumCanBuyResolver? canBuyPremium,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(
      context,
      maxWidth: kLikersSheetMaxWidth,
    ),
    builder: (_) => LikersUpsellSheet(
      target: target,
      totalCount: totalCount,
      canBuyPremium: canBuyPremium,
    ),
  );
}

Future<void> _showListSheet(
  BuildContext context, {
  required LikersTarget target,
  required int totalCount,
  required Map<String, int> reactionCounts,
  required LikersService service,
  required String? viewerId,
  required LikerOpener onOpenLiker,
  required PublicIdentityRepository? identityRepository,
  required VoidCallback onAccessRequired,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(
      context,
      maxWidth: kLikersSheetMaxWidth,
    ),
    builder: (sheetContext) {
      Widget body(ScrollController? scroll) => _LikersSheetSurface(
        target: target,
        child: LikersListView(
          target: target,
          totalCount: totalCount,
          reactionCounts: reactionCounts,
          service: service,
          scrollController: scroll,
          viewerId: viewerId,
          onOpenLiker: onOpenLiker,
          identityRepository: identityRepository,
          onClose: () => Navigator.of(sheetContext).maybePop(),
          onAccessRequired: () {
            onAccessRequired();
            Navigator.of(sheetContext).maybePop();
          },
        ),
      );
      final size = MediaQuery.sizeOf(sheetContext);
      if (size.width < kLikersSheetCompactBreakpoint) {
        return DraggableScrollableSheet(
          key: const ValueKey('likers-sheet-draggable'),
          expand: false,
          initialChildSize: .72,
          minChildSize: .4,
          maxChildSize: .95,
          builder: (_, scroll) => body(scroll),
        );
      }
      return SizedBox(
        key: const ValueKey('likers-sheet-fixed'),
        height: math.min(640, size.height * .8),
        child: body(null),
      );
    },
  );
}

class _LikersSheetSurface extends StatelessWidget {
  const _LikersSheetSurface({required this.target, required this.child});

  final LikersTarget target;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = LikersCopy(AppLocalizations.of(context));
    return Material(
      key: const ValueKey('likers-sheet-surface'),
      color: palette.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.vertical(top: AppRadius.xl.topLeft),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          YoModalSheetChrome(
            sheetLabel: copy.title(target),
            surfaceColor: palette.surfaceRaised,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

String? _currentUid() {
  try {
    return FirebaseAuth.instance.currentUser?.uid;
  } catch (_) {
    return null;
  }
}

Future<void> _openProfilePreview(BuildContext context, Liker liker) =>
    showProfilePreview(
      context,
      userId: liker.userId,
      displayName: liker.displayName,
    );
