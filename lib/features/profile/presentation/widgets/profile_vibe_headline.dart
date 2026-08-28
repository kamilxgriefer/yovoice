import 'package:flutter/material.dart';

/// The shared visual treatment for a member's short social headline.
///
/// Both the signed-in profile and another member's full profile use this
/// widget so opening a profile can never make a saved Vibe disappear between
/// surfaces.
class ProfileVibeHeadline extends StatelessWidget {
  const ProfileVibeHeadline({required this.vibe, super.key});

  final String vibe;

  @override
  Widget build(BuildContext context) {
    final value = vibe.trim();
    return Semantics(
      container: true,
      label: 'Vibe: $value',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFF9F20F4).withValues(alpha: .12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFB348FF).withValues(alpha: .38),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 19,
                  color: Color(0xFFD986FF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'VIBE',
                      style: TextStyle(
                        color: Color(0xFFD986FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Color(0xFFF4EAF8),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
