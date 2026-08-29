import 'package:flutter/material.dart';

import 'package:yovoice/features/creator/data/models/creator_pinned_post.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_boundary.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

const _background = Color(0xFF09050F);
const _surface = Color(0xFF17101F);
const _border = Color(0xFF3C2C45);
const _muted = Color(0xFFA99DB3);
const _accent = Color(0xFFB932FF);

class CreatorPinnedPostsScreen extends StatefulWidget {
  const CreatorPinnedPostsScreen({
    this.pinnedPostService,
    this.momentService,
    this.isRootTab = false,
    this.expiryClock,
    this.expiryTimerFactory,
    super.key,
  });

  final CreatorPinnedPostService? pinnedPostService;
  final MomentService? momentService;
  final bool isRootTab;

  @visibleForTesting
  final MomentExpiryClock? expiryClock;

  @visibleForTesting
  final MomentExpiryTimerFactory? expiryTimerFactory;

  @override
  State<CreatorPinnedPostsScreen> createState() =>
      _CreatorPinnedPostsScreenState();
}

class _CreatorPinnedPostsScreenState extends State<CreatorPinnedPostsScreen> {
  late final CreatorPinnedPostService _pins =
      widget.pinnedPostService ?? CreatorPinnedPostService();
  late final MomentService _moments = widget.momentService ?? MomentService();
  late final Stream<CreatorPinnedPost?> _pinStream = _pins.watchMyPin();
  late final Stream<List<VoiceMoment>> _momentStream = _moments
      .watchMyMoments();
  String? _pendingMomentId;
  bool _unpinning = false;
  final FocusNode _expiryRecoveryFocus = FocusNode(
    debugLabel: 'Pinned posts heading after expiry',
  );
  final MomentExpiryAnnouncer _expiryAnnouncer = MomentExpiryAnnouncer();

  @override
  void dispose() {
    _expiryRecoveryFocus.dispose();
    super.dispose();
  }

  void _handleExpiryDeadline(DateTime deadline) {
    final previousFocus = FocusManager.instance.primaryFocus;
    final recoverFocus = momentExpiryFocusIsWithin(context, previousFocus);
    _expiryAnnouncer.announce(
      context,
      transition: 'pinned-management-${deadline.microsecondsSinceEpoch}',
      message: 'Voice Moment expired and is no longer available to pin.',
    );
    recoverMomentExpiryFocusAfterFrame(
      context: context,
      fallback: _expiryRecoveryFocus,
      previousFocus: recoverFocus ? previousFocus : null,
    );
  }

  Future<void> _setPin(String? momentId) async {
    if (_pendingMomentId != null || _unpinning) return;
    setState(() {
      if (momentId == null) {
        _unpinning = true;
      } else {
        _pendingMomentId = momentId;
      }
    });
    try {
      await _pins.setPinnedMoment(momentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            momentId == null
                ? 'Pinned post removed.'
                : 'Voice Moment pinned to your profile.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The pinned post could not be changed. Check your Premium Creator access and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _pendingMomentId = null;
          _unpinning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.dashboard,
          child: StreamBuilder<CreatorPinnedPost?>(
            stream: _pinStream,
            builder: (context, pinSnapshot) {
              return StreamBuilder<List<VoiceMoment>>(
                stream: _momentStream,
                builder: (context, momentSnapshot) {
                  if (momentSnapshot.hasError || pinSnapshot.hasError) {
                    return _ErrorBody(
                      isRootTab: widget.isRootTab,
                      message: 'Pinned posts could not be loaded.',
                    );
                  }
                  if (!momentSnapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: _accent),
                    );
                  }
                  final snapshotMoments = momentSnapshot.data!;
                  final canonicalMoments = snapshotMoments
                      .where((moment) => moment.isCanonicalPublished)
                      .toList(growable: false);
                  return MomentExpiryListBuilder(
                    moments: canonicalMoments,
                    onDeadline: _handleExpiryDeadline,
                    clock: widget.expiryClock,
                    timerFactory: widget.expiryTimerFactory,
                    builder: (context, now) {
                      final moments = canonicalMoments
                          .where((moment) => moment.isActiveAt(now))
                          .toList(growable: false);
                      return _body(
                        context,
                        moments: moments,
                        pin: pinSnapshot.data,
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }

  Widget _body(
    BuildContext context, {
    required List<VoiceMoment> moments,
    required CreatorPinnedPost? pin,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 48),
      children: [
        Row(
          children: [
            if (!widget.isRootTab) ...[
              YoIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                size: 48,
                backgroundColor: _surface,
                borderColor: _border,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: MomentExpiryFocusTarget(
                focusNode: _expiryRecoveryFocus,
                semanticLabel: 'Pinned post',
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pinned post',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.5,
                      ),
                    ),
                    Text(
                      'Put one real Voice Moment at the top of your profile.',
                      style: TextStyle(color: _muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF301047), Color(0xFF17101F)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF603277)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.push_pin_rounded, color: _accent),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Followers will see this Moment first on your profile. You can replace it or remove it at any time.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your published Moments',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '${moments.length} available',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (moments.isEmpty)
          _EmptyMoments(
            onCreate: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const RecordVoiceMomentScreen(),
                ),
              );
            },
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 12.0;
              final columns = constraints.maxWidth >= 760 ? 2 : 1;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final moment in moments)
                    SizedBox(
                      width: width,
                      child: _MomentChoice(
                        moment: moment,
                        selected: pin?.momentId == moment.id,
                        busy:
                            _pendingMomentId == moment.id ||
                            (_unpinning && pin?.momentId == moment.id),
                        onTap: () => _setPin(
                          pin?.momentId == moment.id ? null : moment.id,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _MomentChoice extends StatelessWidget {
  const _MomentChoice({
    required this.moment,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final VoiceMoment moment;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      selected: selected,
      label: selected
          ? 'Pinned Voice Moment: ${moment.caption}'
          : 'Voice Moment available to pin: ${moment.caption}',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF281137) : _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? _accent : _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: .13),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.graphic_eq_rounded, color: _accent),
                ),
                const Spacer(),
                if (selected)
                  const _SelectedPill()
                else
                  Text(
                    moment.durationLabel,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              moment.caption.trim().isEmpty ? 'Voice Moment' : moment.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _CountMeta(
                  icon: Icons.favorite_border_rounded,
                  value: moment.likeCount,
                ),
                _CountMeta(
                  icon: Icons.chat_bubble_outline_rounded,
                  value: moment.commentCount,
                ),
                Semantics(
                  button: true,
                  enabled: !busy,
                  label: selected
                      ? 'Remove pinned Voice Moment'
                      : 'Pin this Voice Moment',
                  onTap: busy ? null : onTap,
                  excludeSemantics: true,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: busy ? null : onTap,
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            selected
                                ? Icons.close_rounded
                                : Icons.push_pin_outlined,
                            size: 16,
                          ),
                    label: Text(selected ? 'Unpin' : 'Pin'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CountMeta extends StatelessWidget {
  const _CountMeta({required this.icon, required this.value});

  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _muted, size: 14),
        const SizedBox(width: 4),
        Text('$value', style: const TextStyle(color: _muted)),
      ],
    );
  }
}

class _SelectedPill extends StatelessWidget {
  const _SelectedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Text(
        'PINNED',
        style: TextStyle(
          color: _accent,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _EmptyMoments extends StatelessWidget {
  const _EmptyMoments({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          const Icon(Icons.mic_none_rounded, color: _muted, size: 28),
          const SizedBox(height: 10),
          const Text(
            'Publish a Voice Moment before pinning a post.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, height: 1.4),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.mic_rounded),
            label: const Text('Record a Moment'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.isRootTab, required this.message});

  final bool isRootTab;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFFF6687)),
            const SizedBox(height: 10),
            Text(message, style: const TextStyle(color: _muted)),
            if (!isRootTab) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go back'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
