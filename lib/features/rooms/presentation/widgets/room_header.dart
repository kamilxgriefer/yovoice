import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The shared light header row every live-room family renders: collapse
/// control, room identity (avatar or type icon + title + uppercase type
/// label in the room's accent), compact counter pills and room-appropriate
/// trailing actions.
///
/// One component on purpose — Community, Family, Club and Podcast rooms are
/// separate products, but their header is the same instrument panel. The
/// TYPE decides the accent, the icon and the wording; the layout never
/// forks per room.
class RoomHeader extends StatelessWidget {
  const RoomHeader({
    required this.identity,
    required this.title,
    required this.subtitle,
    required this.speaking,
    required this.listeners,
    required this.onBack,
    required this.onSpeakingTap,
    required this.onListenersTap,
    this.avatarUrl,
    this.avatarName,
    this.actions = const <Widget>[],
    super.key,
  });

  final SpaceIdentity identity;
  final String title;

  /// Already-resolved copy — the SCREEN owns liveness wording
  /// ("COMMUNITY LIVE", "FAMILY ROOM · NOT LIVE YET"), because only the
  /// screen knows the room document and the audio transport.
  final String subtitle;
  final int speaking;
  final int listeners;
  final VoidCallback onBack;
  final VoidCallback onSpeakingTap;
  final VoidCallback onListenersTap;

  /// A real image identity (a club's avatar). Falls back to the room-type
  /// icon — never to an empty box.
  final String? avatarUrl;
  final String? avatarName;

  /// Room-appropriate trailing controls (Share, host menu). Never more
  /// than two — the header stays light.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final identityRow = Row(
          children: [
            IconButton(
              onPressed: onBack,
              tooltip: 'Back',
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
              color: Colors.white,
            ),
            if (avatarName != null)
              UserAvatar(
                radius: 17,
                photoUrl: avatarUrl,
                displayName: avatarName,
                // Same reason as the stage tile: the letter fallback takes
                // the room's colour so the header does not open a green or
                // gold room with a purple disc.
                backgroundColor: Color.lerp(
                  identity.primary,
                  const Color(0xFF120C1B),
                  .45,
                )!,
              )
            else
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: identity.wash,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(identity.icon, color: identity.accent, size: 17),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: identity.accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.05,
                    ),
                  ),
                ],
              ),
            ),
            if (!narrow) ...[
              const SizedBox(width: 8),
              // Bounded on purpose: the pill's inner text is flexible and
              // needs a real width to truncate against.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: RoomCounterPill(
                  icon: Icons.graphic_eq_rounded,
                  label: 'Speaking',
                  value: speaking,
                  identity: identity,
                  onTap: onSpeakingTap,
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: RoomCounterPill(
                  icon: Icons.headphones_rounded,
                  label: 'Listeners',
                  value: listeners,
                  identity: identity,
                  onTap: onListenersTap,
                ),
              ),
            ],
            ...actions,
          ],
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 12, 6),
          child: narrow
              ? Column(
                  children: [
                    identityRow,
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const SizedBox(width: 46),
                        Expanded(
                          child: RoomCounterPill(
                            icon: Icons.graphic_eq_rounded,
                            label: 'Speaking',
                            value: speaking,
                            identity: identity,
                            onTap: onSpeakingTap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RoomCounterPill(
                            icon: Icons.headphones_rounded,
                            label: 'Listeners',
                            value: listeners,
                            identity: identity,
                            onTap: onListenersTap,
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : identityRow,
        );
      },
    );
  }
}

/// A compact horizontal counter: icon + count + label. Taps into the
/// existing People surface — the pill is a door, never just a number.
class RoomCounterPill extends StatelessWidget {
  const RoomCounterPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    required this.identity,
    super.key,
  });

  final IconData icon;
  final String label;
  final int value;
  final VoidCallback onTap;
  final SpaceIdentity identity;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '$value $label. Open people',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF151020).withValues(alpha: .8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: identity.accent),
              const SizedBox(width: 6),
              // One rich text with one end-ellipsis: under pressure the
              // LABEL truncates first and the COUNT survives longest.
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$value ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(
                        text: label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .6),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
