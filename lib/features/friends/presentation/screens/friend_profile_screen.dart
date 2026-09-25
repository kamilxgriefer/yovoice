import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/calls/data/models/direct_call.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/calls/presentation/direct_call_launcher.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/moderation/presentation/widgets/report_reason_sheet.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/widgets/invite_person_to_server_sheet.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/creator/presentation/widgets/creator_pinned_moment_card.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_pinned_moment_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/follow_list_screen.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_vibe_headline.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_hero_backdrop.dart';
import 'package:yovoice/shared/widgets/profile/profile_photo_viewer.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

class FriendProfileScreen extends StatefulWidget {
  const FriendProfileScreen({
    required this.friend,
    this.firestore,
    this.auth,
    this.friendService,
    this.messageService,
    this.profileService,
    this.followService,
    this.socialGraphService,
    this.profileMediaService,
    this.creatorPinnedPostService,
    this.isFriend = true,
    this.relationshipStatusResolver,
    this.directCallService,
    this.voiceCallService,
    this.reportService,
    this.serverRepository,
    super.key,
  });

  final FriendUser friend;
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;

  /// Injectable seams keep responsive widget tests on the exact production
  /// screen without requiring a configured Firebase app.
  final FriendService? friendService;
  final MessageService? messageService;
  final ProfileService? profileService;
  final FollowService? followService;
  final SocialGraphService? socialGraphService;
  final ProfileMediaService? profileMediaService;
  final CreatorPinnedPostService? creatorPinnedPostService;

  /// What the route that opened this profile already knows. The Friends list
  /// only lists friends, so it keeps the default; the profile preview passes
  /// its resolved relationship. While true, the relationship read below may
  /// only NARROW the offer (to blocked) — it never takes a friend's actions
  /// away on a read that cannot see the friendship.
  final bool isFriend;

  /// How the screen learns the relationship. Production leaves this null and
  /// uses [FriendService.getRelationshipStatus] (four plain `get`s, no
  /// callable). It only sees the viewer's own block; the backend refuses the
  /// rest.
  final RelationshipStatusInvoker? relationshipStatusResolver;
  final DirectCallGateway? directCallService;
  final VoiceCallService? voiceCallService;
  final ReportService? reportService;
  final ServerRepository? serverRepository;

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  late final FirebaseFirestore _firestore =
      widget.firestore ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final FriendService _friendService =
      widget.friendService ?? FriendService(firestore: _firestore, auth: _auth);
  late final MessageService? _ownedMessageService =
      widget.messageService == null &&
          (widget.firestore != null || widget.auth != null)
      ? MessageService(firestore: _firestore, auth: _auth)
      : null;
  late final MessageService _messageService =
      widget.messageService ?? _ownedMessageService ?? MessageService.live;
  late final ProfileMediaService? _profileMediaService =
      widget.profileMediaService ??
      (widget.auth != null ? ProfileMediaService(auth: _auth) : null);
  late final ProfileService _profileService =
      widget.profileService ??
      ProfileService(firestore: _firestore, auth: _auth);
  late final FollowService _followService =
      widget.followService ?? FollowService(firestore: _firestore, auth: _auth);
  late final SocialGraphService _socialGraphService =
      widget.socialGraphService ?? SocialGraphService();

  late final DirectCallGateway _calls =
      widget.directCallService ??
      DirectCallService(firestore: _firestore, auth: _auth);
  late final VoiceCallService _voice =
      widget.voiceCallService ?? VoiceCallService.instance;

  late final Future<MutualFriendsSummary> _mutualFriendsFuture;

  /// Null while unknown. Starts as friends when the route vouches for it.
  FriendRelationshipStatus? _relationship;

  /// Which call slot is starting, so only the tapped tile shows progress.
  DirectCallMediaType? _startingCallType;
  bool _startingCall = false;
  bool _reporting = false;
  bool _openingChat = false;
  bool _removingFriend = false;
  bool _changingFollow = false;
  bool _blocking = false;
  bool _openingSocialList = false;

  @override
  void initState() {
    super.initState();
    _mutualFriendsFuture = _socialGraphService
        .getMutualFriends(widget.friend.id)
        .catchError((_) => MutualFriendsSummary.empty);
    if (widget.isFriend) _relationship = FriendRelationshipStatus.friends;
    unawaited(_refreshRelationship());
  }

  /// Reads the relationship once on open and again after returning from a
  /// pushed route. A failed read leaves the state as it was: an unknown
  /// relationship keeps the call slots disabled, and never guesses "friends".
  Future<void> _refreshRelationship() async {
    final RelationshipStatusInvoker resolve;
    try {
      resolve =
          widget.relationshipStatusResolver ??
          _friendService.getRelationshipStatus;
    } catch (_) {
      return;
    }
    try {
      final status = await resolve(widget.friend.id);
      if (!mounted) return;
      setState(() {
        if (widget.isFriend) {
          _relationship = status == FriendRelationshipStatus.blocked
              ? FriendRelationshipStatus.blocked
              : FriendRelationshipStatus.friends;
        } else {
          _relationship = status;
        }
      });
    } catch (_) {
      // Unknown stays unknown.
    }
  }

  bool get _isFriends => _relationship == FriendRelationshipStatus.friends;
  bool get _isBlocked => _relationship == FriendRelationshipStatus.blocked;

  @override
  void dispose() {
    unawaited(_ownedMessageService?.dispose());
    super.dispose();
  }

  Future<void> _openChat({
    ChatLaunchAction initialAction = ChatLaunchAction.none,
  }) async {
    if (_openingChat || _startingCall || _removingFriend) return;
    setState(() => _openingChat = true);
    try {
      final friend = widget.friend;
      final conversationId = await _messageService.openOrCreateConversation(
        otherUserId: friend.id,
        otherDisplayName: friend.displayName,
        otherEmail: friend.email,
        otherPhotoUrl: friend.photoUrl ?? '',
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            otherUserId: friend.id,
            otherDisplayName: friend.displayName,
            otherEmail: friend.email,
            otherPhotoUrl: friend.photoUrl ?? '',
            otherProfileUpdatedAt: friend.profileUpdatedAt,
            messageService: _messageService,
            profileMediaService: _profileMediaService,
            firestore: _firestore,
            auth: _auth,
            initialAction: initialAction,
          ),
        ),
      );
      if (mounted) unawaited(_refreshRelationship());
    } catch (error) {
      // See ADR-062: a refusal from `openDirectConversation` now reaches
      // this handler instead of being swallowed into a client-side write.
      if (mounted) {
        _showError(
          AppLocalizations.of(context).isPolish
              ? 'Nie udało się otworzyć rozmowy.'
              : intentionalOrFriendly(
                  error,
                  fallback: 'Could not open this conversation.',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  /// Zadzwoń / Wideo: the shared direct-call flow. Permissions are the first
  /// await (the web gesture chain), then the DM is opened the same way
  /// Message opens it — `openDirectConversation` also enforces the friend's
  /// message privacy — then the backend starts the call.
  Future<void> _startCall(DirectCallMediaType mediaType) async {
    if (_startingCall || _openingChat || _removingFriend) return;
    final friend = widget.friend;
    // The tile's busy state is owned by the launcher: it may refuse before it
    // ever reports busy (a live voice session), so the tapped media type is
    // only recorded once the launcher actually starts.
    await launchDirectCall(
      context,
      calls: _calls,
      voice: _voice,
      calleeId: friend.id,
      mediaType: mediaType,
      resolveConversationId: () => _messageService.openOrCreateConversation(
        otherUserId: friend.id,
        otherDisplayName: friend.displayName,
        otherEmail: friend.email,
        otherPhotoUrl: friend.photoUrl ?? '',
      ),
      currentUserId: _auth.currentUser?.uid ?? '',
      participantName: () =>
          _auth.currentUser?.displayName ??
          _auth.currentUser?.email ??
          AppLocalizations.of(
            context,
          ).text('YO Voice user', 'Użytkownik YO Voice'),
      showMessage: _showMessage,
      onBusyChanged: (busy) => setState(() {
        _startingCall = busy;
        _startingCallType = busy ? mediaType : null;
      }),
      onStartAudioInstead: () =>
          unawaited(_startCall(DirectCallMediaType.audio)),
      describeError: (error, copy) =>
          error is FirebaseFunctionsException &&
              error.code == 'permission-denied'
          ? copy.text(
              "You can't call this person from their profile right now.",
              'Nie możesz teraz zadzwonić do tej osoby z profilu.',
            )
          : null,
    );
    if (mounted) unawaited(_refreshRelationship());
  }

  Future<void> _report() async {
    if (_reporting) return;
    final copy = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final name = widget.friend.displayName;
    final uid = widget.friend.id;
    final reason = await showReportReasonSheet(
      context: context,
      title: copy.template(
        'Report {name}',
        'Zgłoś użytkownika {name}',
        values: {'name': name},
      ),
      subtitle: copy.template(
        'Your report goes to the YO Voice moderation team. {name} is not told who reported them.',
        'Zgłoszenie trafi do zespołu moderacji YO Voice. Użytkownik {name} nie otrzyma informacji, kto go zgłosił.',
        values: {'name': name},
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _reporting = true);
    try {
      await (widget.reportService ??
              ReportService(firestore: _firestore, auth: _auth))
          .report(
            targetType: ReportTargetType.user,
            targetId: uid,
            reportedUserId: uid,
            reason: reason,
            contextPath: 'users/$uid',
          );
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            copy.template(
              'Reported {name}. Our team will review.',
              'Zgłoszono użytkownika {name}. Nasz zespół je sprawdzi.',
              values: {'name': name},
            ),
          ),
        ),
      );
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            copy.isPolish
                ? 'Nie udało się wysłać zgłoszenia. Spróbuj ponownie.'
                : intentionalOrFriendly(
                    error,
                    fallback:
                        'Your report could not be sent. Please try again.',
                  ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

  Future<void> _inviteToServer() async {
    final ServerRepository repository;
    try {
      repository =
          widget.serverRepository ??
          ServerService(firestore: _firestore, auth: _auth);
    } catch (error) {
      _showError(error.toString());
      return;
    }
    if (!mounted) return;
    await showInvitePersonToServerSheet(
      context,
      inviteeId: widget.friend.id,
      inviteeName: widget.friend.displayName,
      repository: repository,
    );
  }

  /// A neutral snackbar for call outcomes, the same presentation the chat
  /// uses for them.
  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message
                .replaceFirst('Bad state: ', '')
                .replaceFirst('Invalid argument(s): ', ''),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  Future<void> _toggleFollow(bool isFollowing) async {
    if (_changingFollow) return;
    setState(() => _changingFollow = true);
    try {
      if (isFollowing) {
        await _followService.unfollow(widget.friend.id);
      } else {
        await _followService.follow(widget.friend.id);
      }
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _changingFollow = false);
    }
  }

  Future<void> _confirmRemoveFriend() async {
    if (_openingChat || _removingFriend) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final palette = dialogContext.appPalette;
        final colors = Theme.of(dialogContext).colorScheme;
        final copy = AppLocalizations.of(dialogContext);
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            copy.text('Remove friend?', 'Usunąć ze znajomych?'),
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            copy.text(
              '${widget.friend.displayName} will be removed from your friends list.',
              '${widget.friend.displayName} zniknie z Twojej listy znajomych.',
            ),
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: Text(copy.text('Remove', 'Usuń')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removingFriend = true);
    try {
      await _friendService.removeFriend(widget.friend.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _removingFriend = false);
    }
  }

  Future<void> _confirmBlock() async {
    if (_blocking || _removingFriend) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final palette = dialogContext.appPalette;
        final colors = Theme.of(dialogContext).colorScheme;
        final copy = AppLocalizations.of(dialogContext);
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            copy.text('Block user?', 'Zablokować użytkownika?'),
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            copy.text(
              '${widget.friend.displayName} will be removed as a friend and '
                  "won't be able to message, follow, or send you requests. You can "
                  'unblock them anytime from Blocked users.',
              '${widget.friend.displayName} zostanie usunięty ze znajomych i nie będzie '
                  'mógł wysyłać Ci wiadomości, obserwować Cię ani zapraszać do znajomych. '
                  'Możesz go odblokować w dowolnej chwili.',
            ),
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: Text(copy.text('Block', 'Zablokuj')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _blocking = true);
    try {
      await _friendService.blockUser(widget.friend.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _blocking = false);
    }
  }

  void _showError(String message) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message.contains('permission-denied')
                ? copy.text(
                    'Your account is not allowed to do that right now.',
                    'Twoje konto nie może teraz wykonać tej czynności.',
                  )
                : copy.text(
                    'Something went wrong. Please try again.',
                    'Coś poszło nie tak. Spróbuj ponownie.',
                  ),
            style: TextStyle(color: palette.dangerForeground),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: palette.dangerSurface,
        ),
      );
  }

  Future<void> _openList(FollowListType type) async {
    if (_openingSocialList) return;
    _openingSocialList = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => FollowListScreen(
            userId: widget.friend.id,
            type: type,
            service: _followService,
          ),
        ),
      );
    } finally {
      _openingSocialList = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile>(
      stream: _profileService.watchProfile(widget.friend.id),
      builder: (context, profileSnapshot) {
        if (profileSnapshot.hasError) {
          return _UnavailableProfile(
            onBack: () => Navigator.of(context).maybePop(),
          );
        }
        if (!profileSnapshot.hasData) {
          return const _ProfileLoading();
        }
        final profile = profileSnapshot.data;
        return StreamBuilder<bool>(
          stream: _followService.watchIsFollowing(widget.friend.id),
          builder: (context, followSnapshot) {
            final isFollowing = followSnapshot.data ?? false;
            final palette = context.appPalette;
            final colors = Theme.of(context).colorScheme;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final copy = AppLocalizations.of(context);
            return Scaffold(
              backgroundColor: palette.background,
              body: YoPageBackground(
                key: const ValueKey('friend-profile-background'),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-.8, -1),
                    radius: 1.3,
                    colors: [
                      Color.lerp(
                        palette.backgroundTop,
                        colors.primary,
                        isDark ? .18 : .055,
                      )!,
                      palette.backgroundTop,
                      palette.background,
                    ],
                  ),
                ),
                // The banner is the header's full-bleed background: it runs
                // under the status bar and edge to edge (landscape insets
                // included), so only the bottom inset stays a SafeArea and
                // the scroll view spans the whole route. Readable content
                // keeps the 880pt list measure through the hero and the
                // measured padding below.
                child: SafeArea(
                  top: false,
                  left: false,
                  right: false,
                  child: ResponsiveContentFrame(
                    width: ResponsiveContentWidth.fullBleed,
                    alignment: ResponsiveContentAlignment.topCenter,
                    child: CustomScrollView(
                      key: const ValueKey('friend-profile-content-frame'),
                      slivers: [
                        SliverToBoxAdapter(
                          child: _header(profile, isFollowing),
                        ),
                        ProfileMeasuredSliverPadding(
                          maxWidth: ResponsiveContentWidth.list.maxWidth,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                          sliver: SliverList.list(
                            children: [
                              // Slim header: the hero (banner behind the
                              // toolbar and the identity row — avatar, name,
                              // handle, presence), then badges, bio, Follow
                              // and the quick actions (call, video, message,
                              // more), then the social block.
                              const SizedBox(height: 10),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: UserIdentityBadges(
                                  uid: widget.friend.id,
                                  variant: IdentityBadgeVariant.full,
                                ),
                              ),
                              if ((profile?.bio ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: ConstrainedBox(
                                    key: const ValueKey(
                                      'friend-profile-bio-frame',
                                    ),
                                    constraints: const BoxConstraints(
                                      maxWidth: 680,
                                    ),
                                    child: Text(
                                      profile!.bio,
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              ..._actionsBlock(profile, isFollowing),
                              const SizedBox(height: 14),
                              _profileBody(profile),
                              // Remove / Block at the foot are a friend's
                              // controls; a non-friend or a person already
                              // blocked reaches Block and Report from More.
                              if (_isFriends) ...[
                                const SizedBox(height: 20),
                                TextButton.icon(
                                  onPressed: _removingFriend
                                      ? null
                                      : _confirmRemoveFriend,
                                  icon: _removingFriend
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.person_remove_outlined,
                                        ),
                                  label: Text(
                                    _removingFriend
                                        ? copy.text(
                                            'Removing...',
                                            'Usuwanie...',
                                          )
                                        : copy.text(
                                            'Remove friend',
                                            'Usuń ze znajomych',
                                          ),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: palette.dangerForeground,
                                    disabledForegroundColor:
                                        palette.textTertiary,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _blocking ? null : _confirmBlock,
                                  icon: _blocking
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.block_rounded),
                                  label: Text(
                                    _blocking
                                        ? copy.text(
                                            'Blocking...',
                                            'Blokowanie...',
                                          )
                                        : copy.text(
                                            'Block user',
                                            'Zablokuj użytkownika',
                                          ),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: palette.dangerForeground,
                                    disabledForegroundColor:
                                        palette.textTertiary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// The hero: the friend's banner as the full-bleed background of the
  /// header, Back floating over it, and the identity row (avatar, name,
  /// handle, presence, and Follow when it fits) on the photo's melt. The
  /// same [ProfileHeroLayout] the own profile uses, on this screen's 880pt
  /// list measure and 20px gutter.
  Widget _header(UserProfile? profile, bool isFollowing) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return ProfileHeroLayout(
      contentMaxWidth: ResponsiveContentWidth.list.maxWidth,
      backdrop: (context, frame) => _banner(profile, frame.geometry),
      toolbar: (context, frame) => Padding(
        padding: frame.inset(start: 8, end: 18),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              tooltip: copy.text('Back', 'Wstecz'),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              // A raised fill keeps Back legible on any photo.
              style: IconButton.styleFrom(
                backgroundColor: palette.surfaceRaised.withValues(alpha: .92),
              ),
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: palette.textPrimary,
              ),
            ),
            // No visible title over the photo — the display name is the
            // page's headline — but the page is still announced as a profile.
            Expanded(
              child: Semantics(
                container: true,
                namesRoute: true,
                label: copy.text('Profile', 'Profil'),
                child: const SizedBox(height: 44),
              ),
            ),
          ],
        ),
      ),
      identity: (context, frame) => Padding(
        padding: frame.inset(start: 20, end: 20),
        child: _identity(profile, isFollowing),
      ),
    );
  }

  /// The friend's banner ("zdjęcie w tle") as the hero's full-bleed
  /// background. Own Profile has always drawn one and a friend's profile
  /// drew none, so the same identity read differently depending on whose
  /// profile you opened. Its size comes from [ProfileHeroGeometry]: the
  /// available width, never a device label.
  Widget _banner(UserProfile? profile, ProfileHeroGeometry geometry) {
    final name = profile?.displayName ?? widget.friend.displayName;
    final revision =
        profile?.profileUpdatedAt ?? widget.friend.profileUpdatedAt;
    return ProfileBannerButton(
      userId: widget.friend.id,
      displayName: name,
      mediaRevision: revision,
      mediaService: _profileMediaService,
      borderRadius: 0,
      focusContrastColor: context.appPalette.scrim,
      child: ProfileHeroBackdrop(
        geometry: geometry,
        userId: widget.friend.id,
        mediaRevision: revision,
        mediaService: _profileMediaService,
      ),
    );
  }

  Widget _avatar(UserProfile? profile, {required double radius}) {
    final name = profile?.displayName ?? widget.friend.displayName;
    final revision =
        profile?.profileUpdatedAt ?? widget.friend.profileUpdatedAt;
    const ring = 3.0;
    final extent = (radius + ring) * 2;
    return ProfilePhotoButton(
      userId: widget.friend.id,
      displayName: name,
      mediaRevision: revision,
      mediaService: _profileMediaService,
      minimumSize: Size(extent, extent),
      // Slim: a flat hairline ring from the palette (the former violet →
      // magenta hex gradient was decoration, not state).
      child: Container(
        padding: const EdgeInsets.all(ring),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.appPalette.background,
          border: Border.all(color: context.appPalette.border),
        ),
        child: UserAvatar(
          radius: radius,
          userId: widget.friend.id,
          mediaRevision: revision,
          mediaService: _profileMediaService,
          displayName: name,
          backgroundColor: context.appPalette.surfaceSunken,
          premium: profile?.premiumIdentity ?? widget.friend.premiumIdentity,
        ),
      ),
    );
  }

  /// Stats, actions, mutual friends, the pinned Moment and the Voice identity
  /// as ONE group: the profile's social block reads (and scrolls, and is
  /// announced) as a unit, the way the own profile groups them under its
  /// header.
  Widget _profileBody(UserProfile? profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The same readable measure as the own profile header's counters
        // and buttons.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _socialStats(profile),
          ),
        ),
        _mutualFriends(),
        if (profile != null && profile.accountType != AccountType.personal)
          CreatorPinnedMomentCard(
            creatorId: widget.friend.id,
            service: widget.creatorPinnedPostService,
            outerPadding: const EdgeInsets.only(top: 12),
            onOpen: (moment) => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => CreatorPinnedMomentScreen(moment: moment),
              ),
            ),
          ),
        const SizedBox(height: 12),
        _voiceIdentity(profile),
      ],
    );
  }

  /// Avatar beside name, handle and presence — the own profile header's
  /// identity row, read from the public projection instead.
  /// Follow rides at the end of the identity row once the band is wide and
  /// the name is not stacked; otherwise it is a full-width bar under the bio.
  /// Either way it sits above the quick actions.
  bool _followInIdentity(BuildContext context, double width) =>
      width >= 700 && MediaQuery.textScalerOf(context).scale(14) < 21;

  bool _showFollow(UserProfile? profile, bool isFollowing) =>
      !_isBlocked &&
      // A hidden audience cannot gain new followers. Existing followers
      // keep the Unfollow action so opting out never traps a relationship.
      (profile?.canExposeCreatorAudience == true || isFollowing);

  Widget _identity(UserProfile? profile, bool isFollowing) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trailingFollow =
            _showFollow(profile, isFollowing) &&
            _followInIdentity(context, constraints.maxWidth);
        final palette = context.appPalette;
        final isWide = constraints.maxWidth >= 700;
        final radius = switch (constraints.maxWidth) {
          < 360 => 34.0,
          < 700 => 40.0,
          _ => 46.0,
        };
        final username = profile?.username ?? '';
        // At large text the name gets the full measure under the avatar
        // instead of a narrow column beside it.
        final stack = MediaQuery.textScalerOf(context).scale(14) >= 21;
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                profile?.displayName ?? widget.friend.displayName,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: isWide ? 26 : 22,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.3,
                ),
              ),
            ),
            if (username.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '@${profile!.username.replaceAll(' ', '').toLowerCase()}',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 8),
            _status(),
          ],
        );
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(profile, radius: radius),
              const SizedBox(height: 12),
              details,
            ],
          );
        }
        return Row(
          // Top-anchored: the row starts on the hero's text line, so a long
          // name grows downward instead of pushing the avatar out of the hero.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _avatar(profile, radius: radius),
            const SizedBox(width: 14),
            Expanded(child: details),
            if (trailingFollow) ...[
              const SizedBox(width: 12),
              ProfileActionBar(
                key: const ValueKey('friend-profile-actions'),
                primary: _followButton(isFollowing),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Follow (when offered and not already in the identity row), then the
  /// quick actions, then — only when calls are unavailable — why.
  List<Widget> _actionsBlock(UserProfile? profile, bool isFollowing) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    Widget measure(Widget child) => Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: child,
      ),
    );
    final callsUnavailable = switch (_relationship) {
      FriendRelationshipStatus.none ||
      FriendRelationshipStatus.requestSent ||
      FriendRelationshipStatus.requestReceived => true,
      _ => false,
    };
    return [
      if (_showFollow(profile, isFollowing))
        LayoutBuilder(
          builder: (context, constraints) {
            if (_followInIdentity(context, constraints.maxWidth)) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 14),
              // A full-width 44 px bar on the narrow / stacked layout.
              child: measure(
                SizedBox(
                  width: double.infinity,
                  child: ProfileActionBar(
                    key: const ValueKey('friend-profile-actions'),
                    primary: _followButton(isFollowing),
                  ),
                ),
              ),
            );
          },
        ),
      const SizedBox(height: 14),
      if (_isBlocked)
        measure(
          Row(
            key: const ValueKey('friend-profile-blocked'),
            children: [
              Expanded(
                child: Text(
                  copy.text(
                    'You have blocked this user.',
                    'Ta osoba jest przez Ciebie zablokowana.',
                  ),
                  style: TextStyle(color: palette.textSecondary, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              ProfileActionIconButton(
                key: const ValueKey('friend-profile-more-button'),
                icon: Icons.more_horiz_rounded,
                tooltip: copy.text('More options', 'Więcej opcji'),
                onPressed: _showMoreSheet,
              ),
            ],
          ),
        )
      else ...[
        measure(_quickActions()),
        if (callsUnavailable) ...[
          const SizedBox(height: 8),
          measure(
            Text(
              copy.text(
                'Calls are available between friends.',
                'Połączenia są dostępne tylko między znajomymi.',
              ),
              key: const ValueKey('friend-profile-call-unavailable'),
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                height: 16 / 12,
              ),
            ),
          ),
        ],
      ],
    ];
  }

  Widget _quickActions() {
    final copy = AppLocalizations.of(context);
    final name = widget.friend.displayName;
    final busy = _startingCall || _openingChat || _removingFriend;
    final canCall = _isFriends && !busy;
    final callHint = _relationship == null
        ? copy.text('Checking…', 'Sprawdzanie…')
        : copy.text(
            'Available to friends only',
            'Dostępne tylko dla znajomych',
          );
    final connecting = copy.text('Connecting…', 'Łączenie…');
    return ProfileQuickActions(
      key: const ValueKey('friend-profile-quick-actions'),
      actions: [
        ProfileQuickAction(
          key: const ValueKey('friend-profile-call-button'),
          icon: Icons.call_rounded,
          label: copy.text('Call', 'Zadzwoń'),
          semanticLabel: copy.template(
            'Call {name}',
            'Zadzwoń do {name}',
            values: {'name': name},
          ),
          emphasis: ProfileQuickActionEmphasis.primary,
          onPressed: canCall
              ? () => _startCall(DirectCallMediaType.audio)
              : null,
          busy: _startingCallType == DirectCallMediaType.audio,
          busyLabel: connecting,
          disabledHint: _isFriends ? null : callHint,
        ),
        ProfileQuickAction(
          key: const ValueKey('friend-profile-video-button'),
          icon: Icons.videocam_outlined,
          label: copy.text('Video', 'Wideo'),
          semanticLabel: copy.template(
            'Video call with {name}',
            'Połączenie wideo z {name}',
            values: {'name': name},
          ),
          onPressed: canCall
              ? () => _startCall(DirectCallMediaType.video)
              : null,
          busy: _startingCallType == DirectCallMediaType.video,
          busyLabel: connecting,
          disabledHint: _isFriends ? null : callHint,
        ),
        ProfileQuickAction(
          key: const ValueKey('friend-profile-message-button'),
          icon: Icons.chat_bubble_outline_rounded,
          label: copy.text('Message', 'Wiadomość'),
          semanticLabel: copy.template(
            'Message {name}',
            'Napisz do {name}',
            values: {'name': name},
          ),
          // The server enforces the friend's message privacy, so Message
          // stays offered to non-friends exactly as before.
          onPressed: busy ? null : _openChat,
          busy: _openingChat,
          busyLabel: copy.text('Opening…', 'Otwieranie…'),
        ),
        ProfileQuickAction(
          key: const ValueKey('friend-profile-more-button'),
          icon: Icons.more_horiz_rounded,
          label: copy.more,
          semanticLabel: copy.text('More options', 'Więcej opcji'),
          onPressed: _showMoreSheet,
          iconOnlyWhenWide: true,
        ),
      ],
    );
  }

  /// Więcej: the everyday extras first (voice message, invite to a server),
  /// then the safety group (report, remove, block). A bottom sheet, because
  /// contextual actions live in sheets, not dialogs. Remove and Block stay
  /// at the foot of a friend's profile too; both paths run the same
  /// confirmation.
  Future<void> _showMoreSheet() async {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final friends = _isFriends;
    final blocked = _isBlocked;
    Widget tile({
      required String key,
      required IconData icon,
      required String label,
      required String choice,
      bool danger = false,
      bool enabled = true,
    }) {
      final ink = danger ? palette.dangerForeground : palette.textPrimary;
      return Builder(
        builder: (sheetContext) => ListTile(
          key: ValueKey(key),
          enabled: enabled,
          minTileHeight: 56,
          leading: Icon(icon, size: 22, color: ink),
          title: Text(
            label,
            style: TextStyle(color: ink, fontWeight: FontWeight.w600),
          ),
          onTap: () => Navigator.pop(sheetContext, choice),
        ),
      );
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: palette.surfaceRaised,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 560,
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (friends) ...[
                tile(
                  key: 'friend-profile-more-voice-message',
                  icon: Icons.mic_none_rounded,
                  label: copy.text(
                    'Send a voice message',
                    'Wyślij wiadomość głosową',
                  ),
                  choice: 'voice',
                  enabled: !_openingChat && !_startingCall,
                ),
                tile(
                  key: 'friend-profile-more-invite',
                  icon: Icons.group_add_outlined,
                  label: copy.text('Invite to a server', 'Zaproś na serwer'),
                  choice: 'invite',
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 72,
                  color: palette.border,
                ),
              ],
              // Reporting is not destructive, so it keeps the neutral ink.
              tile(
                key: 'friend-profile-more-report',
                icon: Icons.flag_outlined,
                label: copy.text('Report user', 'Zgłoś użytkownika'),
                choice: 'report',
                enabled: !_reporting,
              ),
              if (friends)
                tile(
                  key: 'friend-profile-more-remove',
                  icon: Icons.person_remove_outlined,
                  label: copy.text('Remove friend', 'Usuń ze znajomych'),
                  choice: 'remove',
                  danger: true,
                  enabled: !_removingFriend,
                ),
              if (!blocked)
                tile(
                  key: 'friend-profile-more-block',
                  icon: Icons.block_rounded,
                  label: copy.text('Block user', 'Zablokuj użytkownika'),
                  choice: 'block',
                  danger: true,
                  enabled: !_blocking,
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'voice':
        await _openChat(initialAction: ChatLaunchAction.recordVoice);
      case 'invite':
        await _inviteToServer();
      case 'report':
        await _report();
      case 'remove':
        await _confirmRemoveFriend();
      case 'block':
        await _confirmBlock();
    }
  }

  Widget _status() {
    final status = PeopleStatus.fromPresence(
      isOnline: widget.friend.isOnline,
      availability: widget.friend.availability,
    );
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: status == PeopleStatus.online
            ? palette.successSurface
            : palette.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        switch (status) {
          PeopleStatus.online => copy.text('Online now', 'Teraz online'),
          // Every other state, including away, uses the one shared mapping so
          // this card can never disagree with the Home rail or the preview
          // sheet — and can never show untranslated English in a Polish UI.
          _ => status.localizedLabel(copy),
        },
        style: TextStyle(
          color: status == PeopleStatus.away
              ? palette.textSecondary
              : status.foreground(palette),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  /// The public projection (`publicProfiles/{uid}`) carries only
  /// `friendCount`, `followerCount` and `followingCount`, so this row never
  /// shows Servers or Moments; followers / following stay behind the
  /// server-written `creatorAudienceVisible` gate.
  Widget _socialStats(UserProfile? profile) {
    final copy = AppLocalizations.of(context);
    final showCreatorAudience = profile?.canExposeCreatorAudience == true;
    return ProfileStatsRow(
      containerKey: const ValueKey('friend-profile-stats'),
      stats: [
        ProfileStat(
          value: profile?.friendCount ?? 0,
          label: copy.text('Friends', 'Znajomi'),
          keyPrefix: 'friend-profile-stat',
          keyName: 'friends',
        ),
        if (showCreatorAudience) ...[
          ProfileStat(
            value: profile?.followerCount ?? 0,
            label: copy.text('Followers', 'Obserwujący'),
            keyPrefix: 'friend-profile-stat',
            keyName: 'followers',
            onTap: () => _openList(FollowListType.followers),
          ),
          ProfileStat(
            value: profile?.followingCount ?? 0,
            label: copy.text('Following', 'Obserwowani'),
            keyPrefix: 'friend-profile-stat',
            keyName: 'following',
            onTap: () => _openList(FollowListType.following),
          ),
        ],
      ],
    );
  }

  Widget _mutualFriends() {
    return FutureBuilder<MutualFriendsSummary>(
      future: _mutualFriendsFuture,
      builder: (context, snapshot) {
        final palette = context.appPalette;
        final copy = AppLocalizations.of(context);
        final summary = snapshot.data;
        if (summary == null || summary.count == 0) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20 + (summary.sample.length.clamp(0, 4) * 14),
                height: 28,
                child: Stack(
                  children: [
                    for (var i = 0; i < summary.sample.length.clamp(0, 4); i++)
                      Positioned(
                        left: i * 14.0,
                        child: _MutualFriendAvatar(
                          friend: summary.sample[i],
                          mediaService: _profileMediaService,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary.count == 1
                      ? copy.text('1 mutual friend', '1 wspólny znajomy')
                      : copy.text(
                          '${summary.count} mutual friends',
                          '${summary.count} wspólnych znajomych',
                        ),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _followButton(bool isFollowing) {
    final colors = Theme.of(context).colorScheme;
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: ProfileActionBar.buttonHeight,
      ),
      child: FilledButton.icon(
        key: const ValueKey('friend-profile-follow-button'),
        onPressed: _changingFollow ? null : () => _toggleFollow(isFollowing),
        style: FilledButton.styleFrom(
          // Tonal in both states: Zadzwoń is the screen's one violet accent
          // (ADR-209). The icon still tells Follow from Following.
          backgroundColor: colors.secondaryContainer,
          foregroundColor: colors.onSecondaryContainer,
          disabledBackgroundColor: palette.surfaceMuted,
          disabledForegroundColor: palette.textTertiary,
          minimumSize: const Size(0, ProfileActionBar.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ProfileActionBar.radius),
          ),
        ),
        icon: _changingFollow
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                isFollowing
                    ? Icons.check_rounded
                    : Icons.person_add_alt_1_rounded,
                size: 18,
              ),
        label: Text(
          isFollowing
              ? copy.text('Following', 'Obserwujesz')
              : copy.text('Follow', 'Obserwuj'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _voiceIdentity(UserProfile? profile) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final vibe = profile?.statusMessage.trim() ?? '';
    final languages = <String>{
      if ((profile?.nativeLanguage ?? '').isNotEmpty) profile!.nativeLanguage,
      ...?profile?.spokenLanguages,
      ...?profile?.learningLanguages,
    }.toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      // Slim: one flat layer, 1 px hairline, the card radius 12.
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.language_rounded,
                color: palette.interactiveForeground,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  copy.text('Voice identity', 'Tożsamość głosowa'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (vibe.isNotEmpty) ...[
            const SizedBox(height: 14),
            ProfileVibeHeadline(
              key: const ValueKey('friend-profile-vibe'),
              vibe: vibe,
            ),
          ],
          if (languages.isNotEmpty) ...[
            const SizedBox(height: 13),
            Text(
              languages.join(' • '),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ] else if (vibe.isEmpty) ...[
            const SizedBox(height: 13),
            Text(
              copy.text(
                'Voice identity not added yet.',
                'Tożsamość głosowa nie została jeszcze uzupełniona.',
              ),
              style: TextStyle(color: palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('friend-profile-loading'),
      backgroundColor: context.appPalette.background,
      body: YoPageBackground(
        child: Center(
          child: CircularProgressIndicator(
            color: context.appPalette.interactiveForeground,
          ),
        ),
      ),
    );
  }
}

class _UnavailableProfile extends StatelessWidget {
  const _UnavailableProfile({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: YoPageBackground(
        child: SafeArea(
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.list,
            alignment: ResponsiveContentAlignment.topCenter,
            child: Column(
              key: const ValueKey('friend-profile-unavailable'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: copy.text('Back', 'Wstecz'),
                    onPressed: onBack,
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: palette.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: palette.border),
                              ),
                              child: Icon(
                                Icons.lock_outline_rounded,
                                color: palette.interactiveForeground,
                                size: 30,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              copy.text(
                                'This profile isn\'t available',
                                'Ten profil jest niedostępny',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              copy.text(
                                'The person may have changed who can view their profile.',
                                'Ta osoba mogła zmienić ustawienia widoczności profilu.',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: palette.textSecondary,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MutualFriendAvatar extends StatelessWidget {
  const _MutualFriendAvatar({required this.friend, this.mediaService});

  final SuggestedFriend friend;
  final ProfileMediaService? mediaService;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.surfaceSunken,
        border: Border.all(color: palette.surface, width: 2),
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: UserAvatar(
        radius: 12,
        userId: friend.uid,
        mediaRevision: friend.profileUpdatedAt,
        mediaService: mediaService,
        displayName: friend.displayName,
        backgroundColor: palette.surfaceSunken,
      ),
    );
  }
}
