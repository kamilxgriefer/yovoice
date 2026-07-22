import 'package:flutter/material.dart';

import '../../data/models/achievement_definition.dart';

class TitleBadge extends StatelessWidget {
  const TitleBadge({
    required this.achievement,
    this.compact = false,
    super.key,
  });

  final AchievementDefinition achievement;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = _BadgePalette.forRarity(achievement.rarity);
    final isHighRarity =
        achievement.rarity.index >= AchievementRarity.epic.index;
    final isMythic = achievement.rarity == AchievementRarity.mythic;

    final badge = Container(
      constraints: const BoxConstraints(
        minHeight: 34,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 11 : 14,
        vertical: compact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette.gradient,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: palette.border.withValues(alpha: .9),
        ),
        boxShadow: isHighRarity
            ? [
                BoxShadow(
                  color: palette.glow.withValues(
                    alpha: isMythic ? .40 : .26,
                  ),
                  blurRadius: isMythic ? 22 : 14,
                  spreadRadius: isMythic ? 1 : 0,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isHighRarity) ...[
            Icon(
              isMythic
                  ? Icons.auto_awesome_rounded
                  : Icons.workspace_premium_rounded,
              color: palette.foreground,
              size: compact ? 14 : 16,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              achievement.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.foreground,
                fontSize: compact ? 12 : 13,
                height: 1.15,
                fontWeight:
                    isHighRarity ? FontWeight.w900 : FontWeight.w800,
                letterSpacing: isHighRarity ? .35 : .1,
                fontStyle: isMythic
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );

    if (!isMythic) {
      return badge;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: -1, end: 2),
      duration: const Duration(milliseconds: 1800),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(value - 1, -1),
              end: Alignment(value, 1),
              colors: const [
                Color(0xFFFF79DF),
                Color(0xFFFFD76A),
                Color(0xFF9A72FF),
                Color(0xFF5CE1FF),
                Color(0xFFFF79DF),
              ],
              stops: const [0, .25, .5, .75, 1],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: badge,
    );
  }
}

class _BadgePalette {
  const _BadgePalette({
    required this.gradient,
    required this.border,
    required this.glow,
    required this.foreground,
  });

  final List<Color> gradient;
  final Color border;
  final Color glow;
  final Color foreground;

  static _BadgePalette forRarity(AchievementRarity rarity) {
    return switch (rarity) {
      AchievementRarity.common => const _BadgePalette(
          gradient: [
            Color(0xFF33283A),
            Color(0xFF4A3A53),
          ],
          border: Color(0xFF65566D),
          glow: Color(0xFF65566D),
          foreground: Color(0xFFF1EAF4),
        ),
      AchievementRarity.uncommon => const _BadgePalette(
          gradient: [
            Color(0xFF124532),
            Color(0xFF1B7656),
          ],
          border: Color(0xFF49C894),
          glow: Color(0xFF49C894),
          foreground: Color(0xFFE7FFF5),
        ),
      AchievementRarity.rare => const _BadgePalette(
          gradient: [
            Color(0xFF15355F),
            Color(0xFF276FD0),
          ],
          border: Color(0xFF5FAAFF),
          glow: Color(0xFF5FAAFF),
          foreground: Color(0xFFF0F7FF),
        ),
      AchievementRarity.epic => const _BadgePalette(
          gradient: [
            Color(0xFF4D1767),
            Color(0xFFA52BFF),
          ],
          border: Color(0xFFD07CFF),
          glow: Color(0xFFC052FF),
          foreground: Color(0xFFFFF4FF),
        ),
      AchievementRarity.legendary => const _BadgePalette(
          gradient: [
            Color(0xFF7D3A0D),
            Color(0xFFFF9E24),
          ],
          border: Color(0xFFFFC566),
          glow: Color(0xFFFFA52B),
          foreground: Color(0xFFFFF8E8),
        ),
      AchievementRarity.mythic => const _BadgePalette(
          gradient: [
            Color(0xFF67156A),
            Color(0xFF4B24C9),
            Color(0xFFC52DFF),
          ],
          border: Color(0xFFFF77DF),
          glow: Color(0xFFD84CFF),
          foreground: Color(0xFFFFFFFF),
        ),
    };
  }
}
