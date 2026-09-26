import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

import '../../data/services/server_media_connector.dart';
import '../../data/services/server_session_controller.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';

/// The voice scene of boards 01 (turkus) and 03 (zieleń): circular avatars
/// around a central microphone orb.
///
/// Every tile comes from [ServerMediaLink.participants] — the provider's own
/// in-session roster, which is the only readable presence source (contract
/// G3). Before a join there is no roster and therefore no tile, no ring and
/// no count: nothing here can render a person who is not actually connected.
class ServerVoiceStage extends StatelessWidget {
  const ServerVoiceStage({
    required this.participants,
    required this.colors,
    this.compact = false,
    super.key,
  });

  final List<ServerMediaParticipant> participants;
  final ServerIdentityVisuals colors;

  /// Phone and card widths: smaller tiles, smaller orb, tighter gaps.
  final bool compact;

  /// Boards 01 and 03 both put at most three people in a column beside the
  /// orb; a bigger room falls back to a plain wrap under the orb so nothing
  /// is pushed off the surface.
  static const maxPerColumn = 3;

  @override
  Widget build(BuildContext context) {
    final tile = compact ? 84.0 : 104.0;
    final orb = compact ? 76.0 : 104.0;
    final gap = compact ? 10.0 : 20.0;
    final people = participants;
    return LayoutBuilder(
      builder: (context, constraints) {
        final orbit =
            people.isNotEmpty &&
            people.length <= maxPerColumn * 2 &&
            constraints.maxWidth >= tile * 2 + orb + gap * 2;
        if (!orbit) {
          // Narrow, very large text, or a room bigger than the board's
          // arrangement: the orb leads and the tiles wrap under it.
          return Column(
            children: [
              _MicrophoneOrb(size: orb, colors: colors),
              if (people.isNotEmpty) ...[
                SizedBox(height: gap),
                Wrap(
                  key: const ValueKey('server-voice-stage-wrap'),
                  alignment: WrapAlignment.center,
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final person in people)
                      ServerParticipantTile(
                        person: person,
                        colors: colors,
                        width: tile,
                      ),
                  ],
                ),
              ],
            ],
          );
        }
        final split = (people.length + 1) ~/ 2;
        final left = people.take(split).toList();
        final right = people.skip(split).toList();
        return Row(
          key: const ValueKey('server-voice-stage-orbit'),
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Column(people: left, colors: colors, width: tile, gap: gap),
            SizedBox(width: gap),
            _MicrophoneOrb(size: orb, colors: colors),
            SizedBox(width: gap),
            _Column(people: right, colors: colors, width: tile, gap: gap),
          ],
        );
      },
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.people,
    required this.colors,
    required this.width,
    required this.gap,
  });
  final List<ServerMediaParticipant> people;
  final ServerIdentityVisuals colors;
  final double width;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return SizedBox(width: width);
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < people.length; index++) ...[
            if (index > 0) SizedBox(height: gap),
            ServerParticipantTile(
              person: people[index],
              colors: colors,
              width: width,
            ),
          ],
        ],
      ),
    );
  }
}

/// The central microphone orb. It marks the conversation itself, never a
/// person and never a count.
///
/// Refine-look §8.2: the unlit identity glass inside a [ringWidth] ring
/// swept through the voice-playback accent (`audioProgressGradient`'s
/// colours) — the conversation's own light, painted inside the orb's box so
/// the stage geometry is unchanged. It has no glow: the only emitted light
/// in a connected workspace is a speaking tile's. High contrast: a flat
/// fill inside a solid `audioAccent` ring.
class _MicrophoneOrb extends StatelessWidget {
  const _MicrophoneOrb({required this.size, required this.colors});
  final double size;
  final ServerIdentityVisuals colors;

  static const double ringWidth = 2.5;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final sweep = palette.audioProgressGradient.colors;
    return ExcludeSemantics(
      child: Container(
        key: const ValueKey('server-voice-orb'),
        width: size,
        height: size,
        padding: const EdgeInsets.all(ringWidth),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: highContrast ? palette.audioAccent : null,
          gradient: highContrast
              ? null
              : SweepGradient(
                  // From 12 o'clock, closing on its own first colour so the
                  // ring has no seam.
                  transform: const GradientRotation(-math.pi / 2),
                  colors: [...sweep, sweep.first],
                ),
          boxShadow: AppFinish.blockShadows(
            palette,
            highContrast: highContrast,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // The inner glass is opaque (both unlit stops are composited),
            // so the sweep shows only as the ring.
            color: highContrast ? palette.surface : null,
            gradient: highContrast ? null : colors.unlitGradient,
          ),
          child: Center(
            child: Icon(
              Icons.mic_rounded,
              size: size * .38,
              color: palette.audioAccent,
            ),
          ),
        ),
      ),
    );
  }
}

/// One person the provider reports, with the speaking ring boards 01 and 03
/// draw. The ring is bound to [ServerMediaParticipant.isSpeaking] and the
/// level glyph to the real microphone state — neither is decorative.
class ServerParticipantTile extends StatelessWidget {
  const ServerParticipantTile({
    required this.person,
    required this.colors,
    this.width = 96,
    super.key,
  });

  final ServerMediaParticipant person;
  final ServerIdentityVisuals colors;
  final double width;

  /// The resting ring, the speaking ring and the gap between the ring's
  /// widest extent and the avatar. The avatar's box always reserves
  /// [ringGap] + [speakingRingWidth] around it, so a speaker never moves it.
  static const double ringWidth = 1.5;
  static const double speakingRingWidth = 3;
  static const double ringGap = 3;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final name = person.isLocal ? copy.serverYou : person.name;
    final radius = (width * .32).clamp(24.0, 40.0);
    final highContrast = MediaQuery.highContrastOf(context);
    final speaking = person.isSpeaking;
    return Semantics(
      label: [
        name,
        if (person.isSpeaking)
          copy.serverSpeaking
        else if (!person.isMicrophoneEnabled)
          copy.serverMicrophoneOff,
      ].join(', '),
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The ring is a FOREGROUND over a fixed box. It used to be the
              // box's own border, and a `Container` pads its child by its
              // border: the ring grew 1.5 → 3 px INSIDE the padding whenever
              // someone spoke, so the avatar, the name and every tile beside
              // it jiggled by 1.5 px (refine-look §8.2). The box is now
              // always the speaking size and only the paint changes; the
              // voice's light is a soft `audioAccent` glow while — and only
              // while — the provider says this person is speaking.
              Container(
                key: ValueKey('server-participant-ring-${person.identity}'),
                padding: const EdgeInsets.all(
                  ServerParticipantTile.ringGap +
                      ServerParticipantTile.speakingRingWidth,
                ),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // `BlurStyle.outer`: the glow is drawn only OUTSIDE the
                  // ring's circle. A normal shadow also fills the circle
                  // under the avatar, and a letter avatar's identity fill
                  // is translucent, so the whole speaker turned teal in Dark
                  // (the white initial fell from ~13.7:1 to ~5.2:1).
                  boxShadow: speaking && !highContrast
                      ? [
                          BoxShadow(
                            color: palette.audioAccent.withValues(alpha: .40),
                            blurRadius: 12,
                            blurStyle: BlurStyle.outer,
                          ),
                        ]
                      : const <BoxShadow>[],
                ),
                foregroundDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: speaking ? palette.audioAccent : colors.iconBorder,
                    width: speaking
                        ? ServerParticipantTile.speakingRingWidth
                        : ServerParticipantTile.ringWidth,
                  ),
                ),
                child: UserAvatar(
                  radius: radius,
                  userId: person.identity,
                  displayName: person.name,
                  backgroundColor: colors.iconSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.labelMedium.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              Icon(
                person.isMicrophoneEnabled
                    ? Icons.graphic_eq_rounded
                    : Icons.mic_off_rounded,
                size: 16,
                color: person.isSpeaking
                    ? palette.audioAccent
                    : palette.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three round controls both boards draw under the scene: Mikrofon,
/// Słuchawki and a red Opuść.
///
/// Only controls with a real effect are drawn. Without a microphone grant
/// the first control is visibly unavailable and says `Tylko słuchasz`
/// instead of failing when pressed.
class ServerVoiceControls extends StatelessWidget {
  const ServerVoiceControls({
    required this.session,
    required this.colors,
    this.compact = false,
    super.key,
  });

  final ServerSessionController session;
  final ServerIdentityVisuals colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final canPublish = session.canPublish;
    final micOn = canPublish && session.isMicrophoneEnabled;
    final deafened = session.isDeafened;
    return Wrap(
      key: const ValueKey('server-voice-controls'),
      alignment: WrapAlignment.center,
      spacing: compact ? 16 : 24,
      runSpacing: 12,
      children: [
        ServerRoundControl(
          key: const ValueKey('server-session-microphone'),
          icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
          label: canPublish ? copy.serverMicrophone : copy.serverListenOnly,
          semanticLabel: !canPublish
              ? copy.serverListenOnly
              : micOn
              ? copy.serverMicrophoneOn
              : copy.serverMicrophoneOff,
          active: micOn,
          colors: colors,
          compact: compact,
          onPressed: canPublish && !session.microphoneBusy
              ? session.toggleMicrophone
              : null,
        ),
        ServerRoundControl(
          key: const ValueKey('server-session-headphones'),
          icon: deafened
              ? Icons.headset_off_rounded
              : Icons.headphones_rounded,
          label: copy.serverHeadphones,
          semanticLabel: deafened
              ? copy.serverHeadphonesOff
              : copy.serverHeadphonesOn,
          active: !deafened,
          colors: colors,
          compact: compact,
          onPressed: session.headphonesBusy ? null : session.toggleDeafened,
        ),
        ServerRoundControl(
          key: const ValueKey('server-session-leave'),
          icon: Icons.call_end_rounded,
          label: copy.serverLeaveShort,
          semanticLabel: copy.serverLeaveConversation,
          destructive: true,
          colors: colors,
          compact: compact,
          onPressed: session.phase == ServerSessionPhase.leaving
              ? null
              : session.leave,
        ),
      ],
    );
  }
}

/// One round control with its label under it, as both boards draw them.
class ServerRoundControl extends StatelessWidget {
  const ServerRoundControl({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.colors,
    required this.onPressed,
    this.active = false,
    this.destructive = false,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final String label;

  /// What assistive technology hears: the state, not the control's name.
  final String semanticLabel;
  final ServerIdentityVisuals colors;
  final VoidCallback? onPressed;
  final bool active;
  final bool destructive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final diameter = compact ? 52.0 : 60.0;
    final background = destructive
        ? AppColors.error
        : active
        ? palette.audioAccent
        : palette.surfaceMuted;
    // White on the error fill is 2.95:1; `contrastInk` is 5.87:1 on the same
    // fill and is what the active fill already uses (WCAG 1.4.11).
    final foreground = destructive
        ? AppColors.contrastInk
        : active
        ? AppColors.contrastInk
        : scheme.onSurface;
    // Without `onTap` the excluded `IconButton` takes `SemanticsAction.tap`
    // with it and the control cannot be pressed by assistive technology —
    // including the one that leaves a live conversation.
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: diameter,
            height: diameter,
            child: IconButton.filled(
              onPressed: onPressed,
              style:
                  IconButton.styleFrom(
                    backgroundColor: background,
                    foregroundColor: foreground,
                    disabledBackgroundColor: palette.surfaceMuted,
                    disabledForegroundColor: palette.textTertiary,
                    shape: const CircleBorder(),
                  ).copyWith(side: serverFocusRing(foreground)),
              icon: Icon(icon, size: compact ? 22 : 24),
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 84 : 104),
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                color: onPressed == null
                    ? palette.textTertiary
                    : palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
