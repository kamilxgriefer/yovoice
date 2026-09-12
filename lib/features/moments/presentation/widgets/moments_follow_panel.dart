import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The calm context panel of the YO Moments overview (wide-3 only).
///
/// It is fed by the ONE real relationship pool the app already holds —
/// the caller's friends minus the people the caller already follows
/// (ADR-110's pool, `FollowService.watchFollowing` as the read-only
/// filter) — under the honest heading "Friends you do not follow yet".
/// There is no recommendation engine, so nothing here is called
/// "recommended" or "close to you", no order is invented (friends arrive in
/// the friend stream's own order) and the panel is HIDDEN, not
/// skeletonised, while the pool is unknown or empty. Below the people a
/// "Add your moment" card opens the recorder through the host's existing
/// create path.
///
/// [inlineFollow] is decision D2: the default draws a real Follow control
/// (`FollowService.follow/unfollow`, double-submit guarded, never for the
/// viewer); the alternative draws no control and lets the whole tile open
/// the profile preview, which is where ADR-110 kept relationship changes.
class MomentsFollowPanel extends StatefulWidget {
  const MomentsFollowPanel({
    required this.onRecord,
    this.onPoolChanged,
    this.friendService,
    this.followService,
    this.auth,
    this.friendsStream,
    this.followingStream,
    this.inlineFollow = true,
    this.maxPeople = 6,
    super.key,
  });

  /// Opens the Voice Moment recorder (the host's existing create path).
  final VoidCallback onRecord;

  /// Tells the host whether the panel has anything to show, so the wide
  /// layout can drop the third column instead of reserving an empty one.
  final ValueChanged<bool>? onPoolChanged;

  final FriendService? friendService;
  final FollowService? followService;
  final FirebaseAuth? auth;

  /// Test seams: the two real streams, injected directly.
  @visibleForTesting
  final Stream<List<FriendUser>>? friendsStream;
  @visibleForTesting
  final Stream<List<FollowUser>>? followingStream;

  final bool inlineFollow;

  /// A calm panel, not a directory: at most this many people are listed.
  final int maxPeople;

  @override
  State<MomentsFollowPanel> createState() => _MomentsFollowPanelState();
}

class _MomentsFollowPanelState extends State<MomentsFollowPanel> {
  StreamSubscription<List<FriendUser>>? _friendsSubscription;
  StreamSubscription<List<FollowUser>>? _followingSubscription;
  List<FriendUser>? _friends;
  Set<String>? _followingIds;
  FollowService? _follows;
  String _uid = '';
  bool? _reportedNonEmpty;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant MomentsFollowPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.friendsStream, widget.friendsStream) ||
        !identical(oldWidget.followingStream, widget.followingStream) ||
        !identical(oldWidget.friendService, widget.friendService) ||
        !identical(oldWidget.followService, widget.followService) ||
        !identical(oldWidget.auth, widget.auth)) {
      _unsubscribe();
      _friends = null;
      _followingIds = null;
      _subscribe();
    }
  }

  void _subscribe() {
    try {
      _uid = (widget.auth ?? FirebaseAuth.instance).currentUser?.uid ?? '';
    } catch (_) {
      _uid = '';
    }
    try {
      _follows = widget.followService ?? FollowService(auth: widget.auth);
    } catch (_) {
      _follows = null;
    }
    Stream<List<FriendUser>>? friends = widget.friendsStream;
    if (friends == null) {
      try {
        friends = (widget.friendService ?? FriendService(auth: widget.auth))
            .watchFriends();
      } catch (_) {
        friends = null;
      }
    }
    Stream<List<FollowUser>>? following = widget.followingStream;
    if (following == null && _uid.isNotEmpty) {
      try {
        following = _follows?.watchFollowing(_uid);
      } catch (_) {
        following = null;
      }
    }
    // A pool that cannot be read is an EMPTY pool: the panel hides rather
    // than showing anyone it cannot vouch for.
    if (friends == null || following == null) {
      _friends = const <FriendUser>[];
      _followingIds = const <String>{};
      _reportPool();
      return;
    }
    _friendsSubscription = friends.listen(
      (value) {
        if (!mounted) return;
        setState(() => _friends = value);
        _reportPool();
      },
      onError: (Object _) {
        if (!mounted) return;
        setState(() => _friends = const <FriendUser>[]);
        _reportPool();
      },
    );
    _followingSubscription = following.listen(
      (value) {
        if (!mounted) return;
        setState(
          () => _followingIds = value.map((user) => user.uid).toSet(),
        );
        _reportPool();
      },
      onError: (Object _) {
        if (!mounted) return;
        // Without the filter a follow could be suggested again; hide.
        setState(() {
          _friends = const <FriendUser>[];
          _followingIds = const <String>{};
        });
        _reportPool();
      },
    );
  }

  void _unsubscribe() {
    unawaited(_friendsSubscription?.cancel());
    unawaited(_followingSubscription?.cancel());
    _friendsSubscription = null;
    _followingSubscription = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  /// Friends minus following minus the viewer, in the friend stream's own
  /// order, capped. Null while either half is still unknown.
  List<FriendUser>? get _pool {
    final friends = _friends;
    final following = _followingIds;
    if (friends == null || following == null) return null;
    return friends
        .where((friend) => friend.id != _uid && !following.contains(friend.id))
        .take(widget.maxPeople)
        .toList(growable: false);
  }

  void _reportPool() {
    final report = widget.onPoolChanged;
    if (report == null) return;
    // Nothing is reported while either half is still unknown: a premature
    // "empty" would make the host drop a column it is about to need.
    final pool = _pool;
    if (pool == null) return;
    final nonEmpty = pool.isNotEmpty;
    if (_reportedNonEmpty == nonEmpty) return;
    _reportedNonEmpty = nonEmpty;
    // The host answers with a layout change; never mutate it mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) report(nonEmpty);
    });
  }

  Future<void> _openProfile(FriendUser friend) => showProfilePreview(
    context,
    userId: friend.id,
    displayName: friend.displayName,
    photoUrl: friend.photoUrl,
    auth: widget.auth,
  );

  @override
  Widget build(BuildContext context) {
    final pool = _pool;
    if (pool == null || pool.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('moments-follow-panel-empty'));
    }
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('moments-follow-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  copy.text(
                    'Friends you do not follow yet',
                    'Znajomi, których jeszcze nie obserwujesz',
                  ),
                  style: AppTypography.titleMedium.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppRhythm.tight),
              for (final friend in pool)
                _PersonRow(
                  key: ValueKey('moments-follow-row-${friend.id}'),
                  friend: friend,
                  followService: widget.inlineFollow ? _follows : null,
                  viewerUid: _uid,
                  onOpenProfile: () => unawaited(_openProfile(friend)),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppRhythm.title),
        _RecordCard(onTap: widget.onRecord),
      ],
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lg,
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppRhythm.title),
        child: child,
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.friend,
    required this.followService,
    required this.viewerUid,
    required this.onOpenProfile,
    super.key,
  });

  final FriendUser friend;

  /// Null when the owner chose the ADR-110 alternative: no inline control,
  /// the whole tile opens the profile.
  final FollowService? followService;
  final String viewerUid;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final openLabel = copy.template(
      'Open profile of {name}',
      'Otwórz profil: {name}',
      values: <String, Object>{'name': friend.displayName},
    );
    final identity = Row(
      children: <Widget>[
        UserAvatar(
          radius: 20,
          userId: friend.id,
          photoUrl: friend.photoUrl,
          displayName: friend.displayName,
        ),
        const SizedBox(width: AppRhythm.item),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                friend.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleSmall.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              if (friend.username.trim().isNotEmpty)
                Text(
                  '@${friend.username.trim()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    final service = followService;
    if (service == null) {
      return Padding(
        padding: const EdgeInsets.only(top: AppRhythm.tight),
        child: AccessibleTapRegion(
          onTap: onOpenProfile,
          semanticLabel: openLabel,
          minimumSize: const Size(
            AppSizing.minimumTouchTarget,
            AppSizing.standardControlHeight,
          ),
          child: identity,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppRhythm.tight),
      child: Row(
        children: <Widget>[
          Expanded(
            child: AccessibleTapRegion(
              onTap: onOpenProfile,
              semanticLabel: openLabel,
              minimumSize: const Size(
                AppSizing.minimumTouchTarget,
                AppSizing.standardControlHeight,
              ),
              child: identity,
            ),
          ),
          const SizedBox(width: AppRhythm.tight),
          MomentsFollowButton(
            userId: friend.id,
            displayName: friend.displayName,
            viewerUid: viewerUid,
            followService: service,
          ),
        ],
      ),
    );
  }
}

/// The real Follow control: `watchIsFollowing` decides the label, one
/// mutation is in flight at a time, and the viewer's own row draws nothing.
///
/// Shared by the calm panel now and by the Voice detail author line and the
/// Reel footer later (D2), so the three surfaces cannot disagree.
class MomentsFollowButton extends StatefulWidget {
  const MomentsFollowButton({
    required this.userId,
    required this.displayName,
    required this.viewerUid,
    required this.followService,
    this.compact = true,
    super.key,
  });

  final String userId;
  final String displayName;
  final String viewerUid;
  final FollowService followService;

  /// Visible ink 36 tall inside the 48 target (the theme's padded tap
  /// target supplies the rest).
  final bool compact;

  @override
  State<MomentsFollowButton> createState() => _MomentsFollowButtonState();
}

class _MomentsFollowButtonState extends State<MomentsFollowButton> {
  late Stream<bool> _stream = widget.followService.watchIsFollowing(
    widget.userId,
  );
  bool _busy = false;

  @override
  void didUpdateWidget(covariant MomentsFollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        !identical(oldWidget.followService, widget.followService)) {
      _stream = widget.followService.watchIsFollowing(widget.userId);
    }
  }

  Future<void> _toggle(bool following) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final copy = AppLocalizations.of(context);
    try {
      if (following) {
        await widget.followService.unfollow(widget.userId);
      } else {
        await widget.followService.follow(widget.userId);
      }
    } catch (_) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              copy.text(
                'Could not update follow. Try again.',
                'Nie udało się zmienić obserwowania. Spróbuj ponownie.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId.isEmpty || widget.userId == widget.viewerUid) {
      return const SizedBox.shrink();
    }
    final copy = AppLocalizations.of(context);
    return StreamBuilder<bool>(
      stream: _stream,
      builder: (context, snapshot) {
        final following = snapshot.data ?? false;
        final known = snapshot.hasData;
        final label = following
            ? copy.contextualText(
                'yoMoments.followingState',
                'Following',
                'Obserwujesz',
              )
            : copy.contextualText('yoMoments.follow', 'Follow', 'Obserwuj');
        final semanticLabel = following
            ? copy.template(
                'Unfollow {name}',
                'Przestań obserwować: {name}',
                values: <String, Object>{'name': widget.displayName},
              )
            : copy.template(
                'Follow {name}',
                'Obserwuj: {name}',
                values: <String, Object>{'name': widget.displayName},
              );
        final style = OutlinedButton.styleFrom(
          minimumSize: Size(
            AppSizing.minimumTouchTarget,
            widget.compact ? 36 : AppSizing.standardControlHeight,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppRhythm.item),
          // The theme's padded tap target supplies the 48 box around the
          // 36 ink; a compact visual density would shrink that box to 40.
          shape: const StadiumBorder(),
        );
        final icon = _busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                following ? Icons.check_rounded : Icons.person_add_alt_1_rounded,
                size: 18,
              );
        final enabled = known && !_busy;
        // ONE node: the button's own node would only say "Follow", so it is
        // replaced by a node that names the person and carries the state.
        return Semantics(
          container: true,
          button: true,
          enabled: enabled,
          label: semanticLabel,
          toggled: following,
          onTap: enabled ? () => unawaited(_toggle(following)) : null,
          excludeSemantics: true,
          child: OutlinedButton.icon(
            key: ValueKey('moments-follow-${widget.userId}'),
            onPressed: enabled ? () => unawaited(_toggle(following)) : null,
            style: style,
            icon: icon,
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
      },
    );
  }
}

/// "Add your moment / Record a Voice Moment" — the panel's create card.
class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final title = copy.text('Add your moment', 'Dodaj swoją chwilę');
    final subtitle = copy.text('Record a Voice Moment', 'Nagraj Voice Moment');
    return Semantics(
      container: true,
      button: true,
      label: title,
      hint: subtitle,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        key: const ValueKey('moments-follow-panel-record'),
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lg,
          side: BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppRhythm.title),
            child: Row(
              children: <Widget>[
                Container(
                  width: AppSizing.standardControlHeight,
                  height: AppSizing.standardControlHeight,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.mic_rounded, color: colors.onPrimary),
                ),
                const SizedBox(width: AppRhythm.item),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: AppTypography.titleSmall.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.bodySmall.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: palette.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
