import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/home/data/first_steps.dart';
import 'package:yovoice/features/home/data/first_steps_store.dart';
import 'package:yovoice/features/home/presentation/first_steps_copy.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

/// What Start draws for "Zacznij tutaj" right now.
enum FirstStepsCardMode {
  /// Nothing: a source is still unknown, the card was closed or completed
  /// earlier, or there is no signed-in account.
  hidden,

  /// The checklist with its progress.
  checklist,

  /// The one line "Gotowe. Znasz już YO Voice." after the last step.
  done,
}

/// Start's "Zacznij tutaj" (firstSteps A, 2026-10-03): the host that reads the
/// account's real state and decides whether the card exists.
///
/// Every step is ticked only from state the client already holds:
///
/// 1. a profile photo — the avatar grant `ProfileMediaService` resolves for
///    the account (the same single-flight the greeting's avatar uses);
/// 2. a first friend — the friends stream Start already listens to. Its
///    relationship rows are the truth (the stream stays silent until the
///    first listed friend's profile has joined, so an empty list really
///    means nobody); the denormalised `friendCount` is not consulted;
/// 3. a server — `watchMyServers()`, joined or created;
/// 4. a first Voice — the Moments achievement counter (`momentCount` ≥ 1);
/// 5. a followed Page or creator — the account's own `followingCount`. Listed
///    only while Treści exists for the account ([contentEnabled]); without it
///    the card counts four.
///
/// The card draws nothing until every source has answered and the local
/// store has been read, so it never shows a step as open on a guess; a failed
/// source keeps it hidden. It closes for good with its X or once every step
/// is done (remembered on this device per account, like the guided tour's
/// progress). The last step done while the checklist was on screen earns the
/// one-line "Gotowe" state for the rest of the session.
///
/// Hidden, the host's layout box is empty: Start's rhythm is exactly what it
/// was without the card.
class HomeFirstSteps extends StatefulWidget {
  const HomeFirstSteps({
    required this.userId,
    required this.profile,
    required this.friendsSnapshot,
    required this.serversSnapshot,
    required this.contentEnabled,
    required this.onAddPhoto,
    required this.onAddFriend,
    required this.onOpenServers,
    required this.onRecordVoice,
    required this.onFollow,
    this.profileMediaService,
    this.store,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final String userId;

  /// The shared `watchCurrentProfile()` stream Start already holds.
  final Stream<UserProfile>? profile;
  final AsyncSnapshot<List<FriendUser>> friendsSnapshot;
  final AsyncSnapshot<List<Server>> serversSnapshot;

  /// Whether Treści (Premium Pages) exists for the account. Null while that
  /// is not known yet: the card waits, because an answer that arrives late
  /// would otherwise turn "4 of 4, done for good" into "4 of 5". The shell
  /// also passes null until the guided tour has had its turn, so the card
  /// never arrives above the create pill that tour is pointing at.
  final bool? contentEnabled;

  final ValueChanged<UserProfile> onAddPhoto;
  final VoidCallback onAddFriend;
  final VoidCallback onOpenServers;
  final VoidCallback onRecordVoice;
  final VoidCallback onFollow;

  final ProfileMediaService? profileMediaService;
  final FirstStepsStore? store;

  /// Space around the card while it is shown (none while hidden).
  final EdgeInsetsGeometry padding;

  @override
  State<HomeFirstSteps> createState() => _HomeFirstStepsState();
}

class _HomeFirstStepsState extends State<HomeFirstSteps> {
  /// A failed avatar grant is asked again a few times (the greeting's avatar
  /// retries the same single-flight), then left until the profile changes.
  static const List<Duration> _photoRetryDelays = <Duration>[
    Duration(seconds: 4),
    Duration(seconds: 15),
    Duration(seconds: 60),
  ];

  StreamSubscription<UserProfile>? _profileSubscription;
  StreamSubscription<ProfileMediaAccessBoundary>? _boundarySubscription;
  ProfileMediaService? _ownedMediaService;
  Timer? _photoRetry;
  int _photoRetries = 0;
  int _photoRequest = 0;
  Object? _photoRevision;

  UserProfile? _profile;
  bool? _hasPhoto;

  bool _storeLoaded = false;
  FirstStepsOutcome? _stored;
  bool _closed = false;
  bool _celebrating = false;
  int _storeRequest = 0;

  FirstStepsStore get _store =>
      widget.store ?? const SharedPreferencesFirstStepsStore();

  @override
  void initState() {
    super.initState();
    _listenToProfile();
    _boundarySubscription = ProfileMediaService.accessBoundaries.listen(
      _handleMediaBoundary,
    );
    unawaited(_loadStore());
  }

  @override
  void didUpdateWidget(HomeFirstSteps oldWidget) {
    super.didUpdateWidget(oldWidget);
    final accountChanged = oldWidget.userId != widget.userId;
    if (accountChanged) {
      _storeLoaded = false;
      _stored = null;
      _closed = false;
      _celebrating = false;
      unawaited(_loadStore());
    }
    if (accountChanged || oldWidget.profile != widget.profile) {
      // Nothing of the previous stream's account is carried over.
      _profile = null;
      _resetPhoto();
      _listenToProfile();
    }
  }

  @override
  void dispose() {
    _photoRetry?.cancel();
    unawaited(_profileSubscription?.cancel());
    unawaited(_boundarySubscription?.cancel());
    super.dispose();
  }

  // ------------------------------------------------------------- sources

  void _listenToProfile() {
    unawaited(_profileSubscription?.cancel());
    _profileSubscription = widget.profile?.listen(
      (profile) {
        if (!mounted) return;
        final previous = _profile;
        setState(() => _profile = profile);
        if (previous?.uid != profile.uid ||
            previous?.profileUpdatedAt != profile.profileUpdatedAt ||
            _hasPhoto == null) {
          _resolvePhoto(profile, fresh: true);
        }
      },
      onError: (Object _) {
        // An unreadable profile leaves two steps unknown: the card stays
        // hidden rather than guessing.
        if (!mounted) return;
        setState(() => _profile = null);
        _resetPhoto();
      },
    );
  }

  void _resetPhoto() {
    _photoRetry?.cancel();
    _photoRetries = 0;
    _photoRequest += 1;
    _photoRevision = null;
    _hasPhoto = null;
  }

  void _handleMediaBoundary(ProfileMediaAccessBoundary boundary) {
    final profile = _profile;
    if (!mounted || profile == null) return;
    if (boundary.userId != null && boundary.userId != profile.uid) return;
    // A new upload (or sign-out) evicted the grant: ask again.
    _resolvePhoto(profile, fresh: true);
  }

  void _resolvePhoto(UserProfile profile, {required bool fresh}) {
    if (profile.uid.isEmpty || profile.uid != widget.userId) return;
    if (fresh) {
      _photoRetry?.cancel();
      _photoRetries = 0;
    }
    final request = ++_photoRequest;
    final revision = profile.profileUpdatedAt;
    _photoRevision = revision;
    Future<ProfileMediaAccess> grant;
    try {
      final service =
          widget.profileMediaService ??
          (_ownedMediaService ??= ProfileMediaService());
      grant = service.resolveAccess(
        userId: profile.uid,
        kind: ProfileMediaKind.avatar,
        revision: revision,
      );
    } catch (_) {
      // No session or no Firebase app: the photo step is unknown.
      return;
    }
    grant.then(
      (access) {
        if (!mounted || request != _photoRequest) return;
        setState(() => _hasPhoto = access.uri != null);
      },
      onError: (Object _) {
        if (!mounted || request != _photoRequest) return;
        if (_photoRetries >= _photoRetryDelays.length) return;
        final delay = _photoRetryDelays[_photoRetries];
        _photoRetries += 1;
        _photoRetry?.cancel();
        _photoRetry = Timer(delay, () {
          final current = _profile;
          if (!mounted || current == null) return;
          if (current.profileUpdatedAt != _photoRevision) return;
          _resolvePhoto(current, fresh: false);
        });
      },
    );
  }

  // --------------------------------------------------------------- store

  Future<void> _loadStore() async {
    final userId = widget.userId.trim();
    final request = ++_storeRequest;
    if (userId.isEmpty) return;
    FirstStepsOutcome? stored;
    try {
      stored = await _store.read(userId);
    } catch (error) {
      // A damaged or unavailable local store must not bring a closed card
      // back on every launch: it stays hidden for this session.
      debugPrint('First-steps progress could not be read: $error');
      return;
    }
    if (!mounted || request != _storeRequest) return;
    setState(() {
      _stored = stored;
      _storeLoaded = true;
    });
  }

  void _persist(FirstStepsOutcome outcome) {
    _stored = outcome;
    final userId = widget.userId.trim();
    if (userId.isEmpty) return;
    unawaited(
      _store.write(userId, outcome).catchError((Object error) {
        debugPrint('First-steps progress could not be saved: $error');
      }),
    );
  }

  void _close() {
    if (_closed) return;
    setState(() => _closed = true);
    if (_stored != FirstStepsOutcome.completed) {
      _persist(FirstStepsOutcome.dismissed);
    }
  }

  // ---------------------------------------------------------------- mode

  /// How many friends the account is known to have, or null while that is
  /// not known (the stream has not answered, or failed).
  ///
  /// The list is the truth on its own: `FriendService.watchFriends()` reads
  /// the canonical relationship rows and stays silent while rows are listed
  /// but no profile has joined yet, so an empty list means the account has
  /// nobody. The account's `friendCount` is a denormalised copy of the same
  /// fact and is deliberately not asked to agree: a counter that drifted
  /// above an empty list would hide the card from exactly the person the
  /// friend step is for.
  int? get _knownFriendCount {
    final friends = widget.friendsSnapshot;
    if (!friends.hasData || friends.hasError) return null;
    return friends.data!.length;
  }

  FirstStepsProgress? get _progress {
    final profile = _profile;
    final servers = widget.serversSnapshot;
    final contentEnabled = widget.contentEnabled;
    if (contentEnabled == null) return null;
    return FirstStepsProgress.evaluate(
      hasPhoto: _hasPhoto,
      friendCount: _knownFriendCount,
      serverCount: servers.hasData && !servers.hasError
          ? servers.data!.length
          : null,
      momentCount: profile?.momentCount,
      followingCount: profile?.accountFollowingCount,
      contentEnabled: contentEnabled,
    );
  }

  /// Decides what to draw and records the two transitions that must outlive
  /// the session (first shown, all done). Idempotent: it only ever moves the
  /// stored outcome forward.
  FirstStepsCardMode _reconcile(FirstStepsProgress? progress) {
    if (!_storeLoaded || _closed || widget.userId.trim().isEmpty) {
      return FirstStepsCardMode.hidden;
    }
    if (_stored == FirstStepsOutcome.dismissed) {
      return FirstStepsCardMode.hidden;
    }
    if (_celebrating) return FirstStepsCardMode.done;
    if (_stored == FirstStepsOutcome.completed || progress == null) {
      return FirstStepsCardMode.hidden;
    }
    if (progress.isComplete) {
      // "Gotowe" is earned by finishing a checklist this device showed. An
      // account that already had everything never sees the card at all.
      final earned = _stored == FirstStepsOutcome.started;
      _persist(FirstStepsOutcome.completed);
      if (!earned) return FirstStepsCardMode.hidden;
      _celebrating = true;
      return FirstStepsCardMode.done;
    }
    if (_stored == null) _persist(FirstStepsOutcome.started);
    return FirstStepsCardMode.checklist;
  }

  void _open(FirstStep step) {
    switch (step) {
      case FirstStep.photo:
        final profile = _profile;
        if (profile != null) widget.onAddPhoto(profile);
      case FirstStep.friend:
        widget.onAddFriend();
      case FirstStep.server:
        widget.onOpenServers();
      case FirstStep.voice:
        widget.onRecordVoice();
      case FirstStep.follow:
        widget.onFollow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final mode = _reconcile(progress);
    final Widget child = switch (mode) {
      FirstStepsCardMode.hidden => const SizedBox(
        key: ValueKey('home-first-steps-hidden'),
        width: double.infinity,
      ),
      FirstStepsCardMode.done => Padding(
        key: const ValueKey('home-first-steps-done-slot'),
        padding: widget.padding,
        child: HomeFirstStepsDoneCard(onClose: _close),
      ),
      FirstStepsCardMode.checklist => Padding(
        key: const ValueKey('home-first-steps-checklist-slot'),
        padding: widget.padding,
        child: HomeFirstStepsCard(
          progress: progress!,
          onStep: _open,
          onClose: _close,
        ),
      ),
    };
    // The card opens and closes by height only (never by width, so a window
    // resize is not animated), from its top edge, and instantly under Reduce
    // Motion. The content below Start moves with it instead of jumping.
    return AnimatedSwitcher(
      duration: AppMotion.resolve(context, AppMotion.standard),
      switchInCurve: AppMotion.standardCurve,
      switchOutCurve: AppMotion.standardCurve,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: AlignmentDirectional.topStart,
        fit: StackFit.passthrough,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: AlignmentDirectional.topStart,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: child,
    );
  }
}

/// The checklist block: the same surface and radius as `HomeRecordMomentCard`
/// (a plain R2 `YoCard`, no tint), a title with the real count and a 48 px
/// close, a 4 px progress line, then one row per step.
///
/// The first open step is the highlighted one: a tonal-accent frame, its
/// hint and a chevron. Every open step is a button that leads to the real
/// place; a done step is a ticked line, not a control. From 520 px of card
/// (at 100 % text) the rows form two columns, as on the tablet frame.
class HomeFirstStepsCard extends StatelessWidget {
  const HomeFirstStepsCard({
    required this.progress,
    required this.onStep,
    required this.onClose,
    super.key,
  });

  final FirstStepsProgress progress;
  final ValueChanged<FirstStep> onStep;
  final VoidCallback onClose;

  /// The card width (at 100 % text) from which the rows form two columns.
  static const double twoColumnWidth = 520;

  @override
  Widget build(BuildContext context) {
    final copy = FirstStepsCopy(AppLocalizations.of(context));
    final palette = context.appPalette;
    final steps = progress.steps;
    final next = progress.next;
    final counter = copy.progress(progress.doneCount, progress.total);

    Widget row(FirstStep step) => _StepRow(
      key: ValueKey('home-first-step-${step.name}'),
      label: copy.label(step),
      hint: copy.hint(step),
      doneLabel: copy.stepDone,
      done: progress.isDone(step),
      next: step == next,
      onTap: () => onStep(step),
    );

    return YoCard(
      key: const ValueKey('home-first-steps'),
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppRhythm.title,
        AppRhythm.tight,
        AppRhythm.tight,
        AppRhythm.item,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // The title starts the line and the count ends it, next to the
              // close target. When the two cannot share a line (enlarged
              // text, a long translation) the count moves under the title
              // instead of squeezing it.
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppRhythm.tight,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        copy.title,
                        style: AppTypography.titleMedium.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      counter,
                      key: const ValueKey('home-first-steps-count'),
                      style: AppTypography.labelMedium.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _CloseButton(onClose: onClose, tooltip: copy.close),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppRhythm.tight),
            child: _ProgressLine(value: progress.doneCount / progress.total),
          ),
          const SizedBox(height: AppRhythm.tight),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppRhythm.tight),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final wide =
                    constraints.maxWidth / scale >=
                    HomeFirstStepsCard.twoColumnWidth - 2 * AppRhythm.title;
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [for (final step in steps) row(step)],
                  );
                }
                final split = (steps.length + 1) ~/ 2;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final step in steps.take(split)) row(step),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppRhythm.title),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final step in steps.skip(split)) row(step),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The line the card collapses to once every step is done.
class HomeFirstStepsDoneCard extends StatelessWidget {
  const HomeFirstStepsDoneCard({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final copy = FirstStepsCopy(AppLocalizations.of(context));
    final palette = context.appPalette;
    return YoCard(
      key: const ValueKey('home-first-steps-done'),
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppRhythm.title,
        AppRhythm.tight,
        AppRhythm.tight,
        AppRhythm.tight,
      ),
      child: Row(
        children: [
          const ExcludeSemantics(child: _Check(done: true)),
          const SizedBox(width: AppRhythm.item),
          Expanded(
            child: Text(
              copy.allDone,
              style: AppTypography.titleSmall.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _CloseButton(onClose: onClose, tooltip: copy.close),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onClose, required this.tooltip});

  final VoidCallback onClose;
  final String tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('home-first-steps-close'),
    onPressed: onClose,
    tooltip: tooltip,
    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    padding: EdgeInsets.zero,
    style: IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: Icon(
      Icons.close_rounded,
      size: 20,
      color: context.appPalette.textSecondary,
    ),
  );
}

/// 4 px of real progress: the done share of the listed steps.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: AppRadius.pill,
        child: SizedBox(
          height: 4,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: highContrast
                    ? palette.borderStrong
                    : palette.textPrimary.withValues(alpha: .10),
              ),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: value.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: highContrast ? palette.interactiveForeground : null,
                    gradient: highContrast
                        ? null
                        : AppGradients.primaryAction(
                            Theme.of(context).colorScheme,
                            begin: AlignmentDirectional.centerStart,
                            end: AlignmentDirectional.centerEnd,
                          ),
                    borderRadius: AppRadius.pill,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 22 px step mark: the logo gradient with a white tick when done, an
/// empty ring otherwise (violet on the highlighted step).
class _Check extends StatelessWidget {
  const _Check({required this.done, this.next = false});

  final bool done;
  final bool next;

  static const double size = 22;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: done ? AppGradients.primary : null,
        border: done
            ? null
            : Border.all(
                color: next
                    ? palette.interactiveForeground
                    : palette.borderStrong,
                width: 1.5,
              ),
      ),
      child: done
          ? const Icon(Icons.check_rounded, size: 15, color: AppColors.white)
          : null,
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.hint,
    required this.doneLabel,
    required this.done,
    required this.next,
    required this.onTap,
    super.key,
  });

  final String label;
  final String hint;
  final String doneLabel;
  final bool done;
  final bool next;
  final VoidCallback onTap;

  static const double minHeight = 48;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final title = Text(
      label,
      style: AppTypography.titleSmall.copyWith(
        color: done ? palette.textSecondary : palette.textPrimary,
        fontWeight: next ? FontWeight.w700 : FontWeight.w500,
      ),
    );
    final content = Row(
      children: [
        _Check(done: done, next: next),
        const SizedBox(width: AppRhythm.item),
        Expanded(
          child: next
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    title,
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                )
              : title,
        ),
        if (next) ...[
          const SizedBox(width: AppRhythm.hairline),
          // `chevron_right` mirrors itself in RTL (matchTextDirection).
          Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: palette.interactiveForeground,
          ),
        ],
      ],
    );

    if (done) {
      // A ticked line is a fact, not a control.
      return Semantics(
        container: true,
        label: label,
        value: doneLabel,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minHeight),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: content,
            ),
          ),
        ),
      );
    }

    final accent = palette.interactiveForeground;
    final framed = next
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: highContrast
                  ? palette.surface
                  : accent.withValues(alpha: .06),
              borderRadius: AppRadius.card,
              border: Border.all(
                color: highContrast
                    ? palette.borderStrong
                    : accent.withValues(alpha: .55),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 4, 8),
              child: content,
            ),
          )
        : content;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: next ? 2 : 0),
      child: AccessibleTapRegion(
        onTap: onTap,
        semanticLabel: next ? '$label. $hint' : label,
        borderRadius: 12,
        minimumSize: const Size(minHeight, minHeight),
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minHeight),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              heightFactor: 1,
              child: framed,
            ),
          ),
        ),
      ),
    );
  }
}
