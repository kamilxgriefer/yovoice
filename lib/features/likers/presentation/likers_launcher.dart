import 'package:flutter/material.dart';

import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/likers/data/services/likers_access_service.dart';
import 'package:yovoice/features/likers/data/services/likers_service.dart';
import 'package:yovoice/features/likers/presentation/show_likers.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// How a host surface opens "See who liked" / "See who reacted".
///
/// Every entry point (spec §5.1) calls [open]; production hosts use the
/// const default, which runs [showLikers] against Firebase. The optional
/// seams exist so a surface's own widget tests can drive the whole flow —
/// pre-gate, list sheet or upsell — without a platform channel.
@immutable
class LikersLauncher {
  const LikersLauncher({
    this.access,
    this.service,
    this.onOpenLiker,
    this.viewerId,
    this.identityRepository,
  });

  final LikersAccessService? access;
  final LikersService? service;
  final LikerOpener? onOpenLiker;
  final String? viewerId;
  final PublicIdentityRepository? identityRepository;

  /// Opens the flow for [target]. [totalCount] is the public count the host
  /// already shows; [reactionCounts] feeds a server list's reaction tabs.
  Future<void> open(
    BuildContext context,
    LikersTarget target, {
    required int totalCount,
    Map<String, int> reactionCounts = const <String, int>{},
    VoidCallback? onSheetOpened,
    VoidCallback? onSheetClosed,
    FocusNode? returnFocus,
  }) => showLikers(
    context,
    target,
    totalCount: totalCount,
    reactionCounts: reactionCounts,
    access: access,
    service: service,
    onSheetOpened: onSheetOpened,
    onSheetClosed: onSheetClosed,
    returnFocus: returnFocus,
    onOpenLiker: onOpenLiker,
    viewerId: viewerId,
    identityRepository: identityRepository,
  );
}

/// Counts each distinct reaction in a server message's `uid -> emoji` map,
/// for the reactors list's tabs. Blank values are ignored, as the summary
/// pill ignores them.
Map<String, int> likersReactionCounts(Iterable<String> reactions) {
  final counts = <String, int>{};
  for (final reaction in reactions) {
    if (reaction.trim().isEmpty) continue;
    counts[reaction] = (counts[reaction] ?? 0) + 1;
  }
  return counts;
}
