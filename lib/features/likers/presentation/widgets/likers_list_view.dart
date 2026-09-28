import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/likers/data/models/likers_page.dart';
import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/likers/data/services/likers_service.dart';
import 'package:yovoice/features/likers/presentation/likers_copy.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';
import 'package:yovoice/shared/widgets/inputs/yo_emoji_picker.dart';
import 'package:yovoice/shared/widgets/interactions/message_reactions.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Opens [liker]'s profile from a row. The sheet stays mounted underneath,
/// so its scroll position survives; the returned future completes when the
/// profile surface closes.
typedef LikerOpener = Future<void> Function(BuildContext context, Liker liker);

/// The shared "See who liked" body (spec §5.2, owner variant B): the title
/// and public total, the server reaction tabs, the rows, paging and every
/// state. The container (sheet, height, chrome) belongs to `showLikers`.
///
/// States: 6 STATIC skeleton rows while the first page loads (ADR-227: no
/// looping motion anywhere, so no spinner either), rows, "Load more" plus
/// auto-load near the end, empty, the partial footer, the quiet Settings
/// hint, a retryable error by failure, "no longer available", "coming
/// soon" and — on `likersAccessRequired` — [onAccessRequired].
class LikersListView extends StatefulWidget {
  const LikersListView({
    required this.target,
    required this.totalCount,
    required this.service,
    this.reactionCounts = const <String, int>{},
    this.scrollController,
    this.viewerId,
    this.onAccessRequired,
    this.onClose,
    this.onOpenLiker,
    this.identityRepository,
    super.key,
  });

  final LikersTarget target;

  /// The public like/reaction total the host already shows.
  final int totalCount;
  final LikersService service;

  /// Server targets only: the public `emoji -> count` aggregate of the
  /// message's reactions, for the tabs and their totals.
  final Map<String, int> reactionCounts;
  final ScrollController? scrollController;

  /// The signed-in uid, so the viewer's own row reads "You".
  final String? viewerId;
  final VoidCallback? onAccessRequired;
  final VoidCallback? onClose;
  final LikerOpener? onOpenLiker;
  final PublicIdentityRepository? identityRepository;

  /// How many empty pages (every candidate hidden) load on their own before
  /// the list waits for "Load more" (spec §5.2).
  static const int maxAutoContinues = 2;

  /// Scroll fraction that loads the next page.
  static const double autoLoadFraction = .8;

  @override
  State<LikersListView> createState() => _LikersListViewState();
}

enum _Terminal { notEnabled, unavailable }

class _LikersListViewState extends State<LikersListView> {
  late LikersTarget _target = widget.target;
  final List<Liker> _rows = <Liker>[];
  final Set<String> _seen = <String>{};
  String? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadedOnce = false;
  LikersFailure? _pageError;
  _Terminal? _terminal;
  bool _restarted = false;
  int _autoContinues = 0;
  int _generation = 0;
  bool _announcedFirst = false;
  bool _announcedPartial = false;

  LikersCopy get _copy => LikersCopy(AppLocalizations.of(context));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  int get _currentTotal {
    final target = _target;
    if (target is ServerMessageReactorsTarget && target.emoji != null) {
      return widget.reactionCounts[target.emoji] ?? 0;
    }
    return widget.totalCount;
  }

  bool get _complete => _loadedOnce && !_hasMore;
  bool get _partial => _complete && _rows.length < _currentTotal;

  void _reset() {
    _generation++;
    _rows.clear();
    _seen.clear();
    _cursor = null;
    _hasMore = true;
    _loading = false;
    _loadedOnce = false;
    _pageError = null;
    _autoContinues = 0;
    _announcedFirst = false;
    _announcedPartial = false;
  }

  Future<void> _load() async {
    if (!mounted || _loading || !_hasMore || _terminal != null) return;
    final generation = _generation;
    final cursor = _cursor;
    setState(() {
      _loading = true;
      _pageError = null;
    });
    try {
      final page = await widget.service.load(_target, cursor: cursor);
      if (!mounted || generation != _generation) return;
      var added = 0;
      for (final liker in page.likers) {
        if (_seen.add(liker.userId)) {
          _rows.add(liker);
          added++;
        }
      }
      setState(() {
        _loading = false;
        _loadedOnce = true;
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
      _announceAfterPage();
      if (page.hasMore && added == 0) {
        if (_autoContinues < LikersListView.maxAutoContinues) {
          _autoContinues++;
          unawaited(_load());
        }
      } else if (added > 0) {
        _autoContinues = 0;
      }
    } on LikersException catch (error) {
      if (!mounted || generation != _generation) return;
      _handleFailure(error.failure);
    }
  }

  void _handleFailure(LikersFailure failure) {
    switch (failure) {
      case LikersFailure.accessRequired:
        setState(() => _loading = false);
        final onAccessRequired = widget.onAccessRequired;
        if (onAccessRequired != null) {
          onAccessRequired();
        } else {
          setState(() => _terminal = _Terminal.unavailable);
        }
      case LikersFailure.notEnabled:
        setState(() {
          _loading = false;
          _terminal = _Terminal.notEnabled;
        });
        _announce(_copy.comingSoon);
      case LikersFailure.unavailable:
        setState(() {
          _loading = false;
          _terminal = _Terminal.unavailable;
        });
        _announce(_copy.unavailable);
      case LikersFailure.invalidCursor when !_restarted:
        // An expired or foreign cursor: restart from page 1, once, quietly.
        _restarted = true;
        setState(_reset);
        unawaited(_load());
      case LikersFailure.invalidCursor ||
          LikersFailure.rateLimited ||
          LikersFailure.network:
        setState(() {
          _loading = false;
          _pageError = failure;
        });
        _announce(_copy.error(failure));
    }
  }

  void _announceAfterPage() {
    if (!_announcedFirst) {
      if (_rows.isNotEmpty) {
        _announcedFirst = true;
        _announce(_copy.loaded(_target, _rows.length));
      } else if (!_hasMore) {
        _announcedFirst = true;
        _announce(_copy.empty);
      }
    }
    if (_partial && _rows.isNotEmpty && !_announcedPartial) {
      _announcedPartial = true;
      _announce(_copy.partial);
    }
  }

  void _announce(String message) {
    if (!mounted) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ),
    );
  }

  void _retry() {
    if (_loading) return;
    _autoContinues = 0;
    unawaited(_load());
  }

  void _selectEmoji(String? emoji) {
    final base = widget.target;
    if (base is! ServerMessageReactorsTarget) return;
    final next = base.withEmoji(emoji);
    if (next == _target) return;
    setState(() {
      _target = next;
      _restarted = false;
      _reset();
    });
    unawaited(_load());
  }

  bool _onScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis == Axis.vertical &&
        _hasMore &&
        !_loading &&
        _pageError == null &&
        _loadedOnce &&
        metrics.maxScrollExtent > 0 &&
        metrics.pixels >=
            metrics.maxScrollExtent * LikersListView.autoLoadFraction) {
      unawaited(_load());
    }
    return false;
  }

  List<MapEntry<String, int>> get _tabs {
    if (!widget.target.isReactions) return const [];
    final entries =
        widget.reactionCounts.entries
            .where(
              (entry) =>
                  entry.value > 0 && kMessageReactionEmojis.contains(entry.key),
            )
            .toList()
          ..sort((a, b) {
            final byCount = b.value.compareTo(a.value);
            if (byCount != 0) return byCount;
            return kMessageReactionEmojis
                .indexOf(a.key)
                .compareTo(kMessageReactionEmojis.indexOf(b.key));
          });
    // One emoji needs no filter: its tab would repeat "All".
    return entries.length < 2 ? const [] : entries;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = _copy;
    final tabs = _tabs;
    final selected = switch (_target) {
      ServerMessageReactorsTarget(:final emoji) => emoji,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, AppRhythm.item),
          child: Semantics(
            header: true,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: copy.title(widget.target)),
                  TextSpan(
                    text: ' · ${widget.totalCount}',
                    style: TextStyle(color: palette.textSecondary),
                  ),
                ],
              ),
              style: AppTypography.titleLarge.copyWith(
                color: palette.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        if (tabs.isNotEmpty) ...[
          _ReactionTabs(
            tabs: tabs,
            total: widget.totalCount,
            selected: selected,
            copy: copy,
            onSelected: _selectEmoji,
          ),
          const SizedBox(height: AppRhythm.tight),
        ],
        Divider(height: 1, thickness: 1, color: palette.hairline),
        Expanded(
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
              SingleActivator(LogicalKeyboardKey.arrowUp):
                  PreviousFocusIntent(),
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: _body(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final copy = _copy;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final items = <Widget>[];

    final terminal = _terminal;
    if (terminal != null) {
      items.add(
        _StatusBlock(
          key: ValueKey('likers-${terminal.name}'),
          icon: terminal == _Terminal.notEnabled
              ? Icons.schedule_rounded
              : Icons.visibility_off_rounded,
          message: terminal == _Terminal.notEnabled
              ? copy.comingSoon
              : copy.unavailable,
          actionLabel: copy.close,
          onAction: widget.onClose,
          actionKey: const ValueKey('likers-close'),
        ),
      );
    } else if (_rows.isEmpty && _pageError != null) {
      items.add(
        _StatusBlock(
          key: const ValueKey('likers-error'),
          icon: Icons.error_outline_rounded,
          message: copy.error(_pageError!),
          actionLabel: copy.tryAgain,
          onAction: _retry,
          actionKey: const ValueKey('likers-retry'),
        ),
      );
    } else if (_rows.isEmpty && (!_loadedOnce || _loading)) {
      items.add(
        _LoadingSkeleton(
          key: const ValueKey('likers-skeleton'),
          label: copy.loading,
          rows: 6,
        ),
      );
    } else if (_rows.isEmpty && _hasMore) {
      // Every candidate so far was hidden and the auto-continue budget is
      // spent: wait for the reader instead of scanning on.
      items.add(_loadMoreButton(copy));
    } else if (_rows.isEmpty) {
      items.add(
        _StatusBlock(
          key: const ValueKey('likers-empty'),
          icon: Icons.favorite_border_rounded,
          message: copy.empty,
        ),
      );
      items.add(_QuietFooter(text: copy.hideHint));
    } else {
      for (var i = 0; i < _rows.length; i++) {
        final liker = _rows[i];
        items.add(
          _LikerRow(
            key: ValueKey('likers-row-${liker.userId}'),
            liker: liker,
            isSelf: liker.userId == widget.viewerId,
            reactions: widget.target.isReactions,
            copy: copy,
            onOpen: widget.onOpenLiker,
            identityRepository: widget.identityRepository,
          ),
        );
        if (i < _rows.length - 1) items.add(const _RowDivider());
      }
      if (_loading) {
        items.add(
          _LoadingSkeleton(
            key: const ValueKey('likers-more-skeleton'),
            label: copy.loading,
            rows: 1,
          ),
        );
      } else if (_pageError != null) {
        items.add(
          _InlineError(
            message: copy.error(_pageError!),
            actionLabel: copy.tryAgain,
            onRetry: _retry,
          ),
        );
      } else if (_hasMore) {
        items.add(_loadMoreButton(copy));
      }
      if (_complete) {
        if (_partial) {
          items.add(
            _QuietFooter(
              key: const ValueKey('likers-partial'),
              text: copy.partial,
              emphasis: true,
            ),
          );
        }
        items.add(_QuietFooter(text: copy.hideHint));
      }
    }

    return ListView.builder(
      controller: widget.scrollController,
      padding: EdgeInsets.only(top: 4, bottom: bottomInset + 8),
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }

  Widget _loadMoreButton(LikersCopy copy) => Padding(
    key: const ValueKey('likers-load-more-slot'),
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
    child: Center(
      child: YoGradientFilledButton(
        buttonKey: const ValueKey('likers-load-more'),
        onPressed: _retry,
        emphasis: YoActionEmphasis.neutral,
        child: Text(copy.loadMore),
      ),
    ),
  );
}

class _LikerRow extends StatefulWidget {
  const _LikerRow({
    required this.liker,
    required this.isSelf,
    required this.reactions,
    required this.copy,
    required this.onOpen,
    required this.identityRepository,
    super.key,
  });

  final Liker liker;
  final bool isSelf;
  final bool reactions;
  final LikersCopy copy;
  final LikerOpener? onOpen;
  final PublicIdentityRepository? identityRepository;

  @override
  State<_LikerRow> createState() => _LikerRowState();
}

class _LikerRowState extends State<_LikerRow> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'liker-row');
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final onOpen = widget.onOpen;
    if (onOpen == null) return;
    final hadFocus = _focusNode.hasFocus;
    await onOpen(context, widget.liker);
    // Back from the stacked profile: keyboard focus returns to this row.
    if (mounted && hadFocus && _focusNode.canRequestFocus) {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final liker = widget.liker;
    final name = widget.isSelf ? widget.copy.you : liker.displayName;
    final reaction = liker.reaction;
    final label = widget.reactions && reaction != null
        ? widget.copy.reactedRow(name, reaction)
        : name;
    final trailing = widget.reactions && reaction != null
        ? Text(reaction, style: yoEmojiGlyphStyle(20))
        : const Icon(
            Icons.favorite_rounded,
            size: 18,
            color: AppColors.secondary,
          );
    final opens = widget.onOpen != null;
    return MergeSemantics(
      child: Semantics(
        // The row opens a profile: say so ("button", "double-tap to open
        // profile") rather than reading it as plain text.
        button: opens ? true : null,
        onTapHint: opens ? widget.copy.openProfile : null,
        child: InkWell(
          focusNode: _focusNode,
          onTap: opens ? _open : null,
          onFocusChange: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          child: DecoratedBox(
            key: ValueKey('likers-row-focus-${liker.userId}'),
            position: DecorationPosition.foreground,
            // The theme's focus tint alone measures about 1.28:1 on
            // surfaceRaised; keyboard focus is a 2 px palette.focus ring
            // (docs/UI.md), inset so the sheet's edge never clips it.
            decoration: BoxDecoration(
              border: _focused
                  ? Border.all(color: palette.focus, width: 2)
                  : null,
              borderRadius: AppRadius.md,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: UserAvatar(
                        radius: 20,
                        userId: liker.userId,
                        displayName: liker.displayName,
                        finish: UserAvatarFinish.brand,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: NameWithVipMark(
                          uid: liker.userId,
                          name: name,
                          semanticsLabel: label,
                          repository: widget.identityRepository,
                          style: AppTypography.rowTitle.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ExcludeSemantics(
                      child: SizedBox(
                        width: 28,
                        child: Center(child: trailing),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: 72,
    endIndent: 20,
    color: context.appPalette.hairline,
  );
}

class _ReactionTabs extends StatelessWidget {
  const _ReactionTabs({
    required this.tabs,
    required this.total,
    required this.selected,
    required this.copy,
    required this.onSelected,
  });

  final List<MapEntry<String, int>> tabs;
  final int total;
  final String? selected;
  final LikersCopy copy;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _ReactionTab(
            key: const ValueKey('likers-tab-all'),
            label: TextSpan(text: '${copy.tabAll} $total'),
            semanticLabel: copy.tabLabel(copy.tabAll, total),
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final tab in tabs)
            _ReactionTab(
              key: ValueKey('likers-tab-${tab.key}'),
              label: TextSpan(
                children: [
                  TextSpan(
                    text: tab.key,
                    style: yoEmojiGlyphStyle(AppFinish.chipFontSize + 1),
                  ),
                  // The space rides in the text span: an emoji face's own
                  // space is twice as wide.
                  TextSpan(text: ' ${tab.value}'),
                ],
              ),
              semanticLabel: copy.tabLabel(tab.key, tab.value),
              selected: selected == tab.key,
              onTap: () => onSelected(tab.key),
            ),
        ],
      ),
    );
  }
}

class _ReactionTab extends StatefulWidget {
  const _ReactionTab({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final InlineSpan label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ReactionTab> createState() => _ReactionTabState();
}

class _ReactionTabState extends State<_ReactionTab> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final selected = widget.selected;
    final highContrast = MediaQuery.highContrastOf(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      // One node per tab: the label and state from here, the tap action and
      // focusability from the InkWell below (the visible text is excluded so
      // the name is not read twice).
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        label: widget.semanticLabel,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          onHover: (hovered) {
            if (_hovered != hovered) setState(() => _hovered = hovered);
          },
          borderRadius: AppRadius.pill,
          // The chip paints hover and focus itself (AppFinish).
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              widthFactor: 1,
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: AppFinish.chipHeight,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppFinish.chipPaddingH,
                  vertical: 4,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppFinish.chipFill(
                    palette,
                    selected: selected,
                    hovered: _hovered,
                    highContrast: highContrast,
                  ),
                  border: AppFinish.chipBorder(
                    palette,
                    selected: selected,
                    focused: _focused,
                    highContrast: highContrast,
                  ),
                  borderRadius: AppRadius.pill,
                ),
                child: ExcludeSemantics(
                  child: Text.rich(
                    widget.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontFamilyFallback: AppTypography.fontFamilyFallback,
                      fontSize: AppFinish.chipFontSize,
                      fontWeight: AppFinish.chipWeight(selected: selected),
                      color: AppFinish.chipLabel(palette, selected: selected),
                      fontFeatures: const [FontFeature.tabularFigures()],
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
}

/// The static skeleton, named for assistive technology: a polite live
/// region reading "Loading" while the first page, a reaction tab's list or
/// the next page is on its way (the rows themselves are decoration).
class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton({required this.label, required this.rows, super.key});

  final String label;
  final int rows;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: label,
    child: ExcludeSemantics(
      child: Column(
        children: [for (var i = 0; i < rows; i++) const _SkeletonRow()],
      ),
    ),
  );
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    super.key,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final label = actionLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 16),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 28, color: palette.textTertiary),
          ),
          const SizedBox(height: AppRhythm.item),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textSecondary,
              height: 1.45,
            ),
          ),
          if (label != null && onAction != null) ...[
            const SizedBox(height: 20),
            YoGradientFilledButton(
              buttonKey: actionKey,
              onPressed: onAction,
              emphasis: YoActionEmphasis.neutral,
              child: Text(label),
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({
    required this.message,
    required this.actionLabel,
    required this.onRetry,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      key: const ValueKey('likers-page-error'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: AppRhythm.tight),
          YoGradientFilledButton(
            buttonKey: const ValueKey('likers-retry'),
            onPressed: onRetry,
            emphasis: YoActionEmphasis.neutral,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _QuietFooter extends StatelessWidget {
  const _QuietFooter({required this.text, this.emphasis = false, super.key});

  final String text;

  /// The partial footer reads in secondary copy; the Settings hint is
  /// tertiary.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        emphasis ? 16 : 12,
        24,
        emphasis ? 0 : 20,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTypography.bodySmall.copyWith(
          color: emphasis ? palette.textSecondary : palette.textTertiary,
        ),
      ),
    );
  }
}

/// A static placeholder row (the `invite_person_to_server_sheet` pattern):
/// no shimmer, no pulse, nothing that loops (ADR-227 decision 7).
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: .55,
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: palette.surfaceMuted,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
