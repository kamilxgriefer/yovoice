import 'package:flutter/material.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

const _background = Color(0xFF09050F);
const _surface = Color(0xFF17101F);
const _border = Color(0xFF3C2C45);
const _muted = Color(0xFFA99DB3);

/// Focused, playable view for the Voice Moment selected from a profile.
/// Comments are a secondary action on [MomentCard], not a replacement for
/// the audio content itself.
class CreatorPinnedMomentScreen extends StatelessWidget {
  const CreatorPinnedMomentScreen({required this.moment, super.key});

  final VoiceMoment moment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 48),
            children: [
              Row(
                children: [
                  YoIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    iconSize: 18,
                    size: 48,
                    backgroundColor: _surface,
                    borderColor: _border,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pinned Voice Moment',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Listen first, then join the conversation.',
                          style: TextStyle(color: _muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              MomentCard(
                moment: moment,
                onComments: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => MomentCommentsScreen(moment: moment),
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
