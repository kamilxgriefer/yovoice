import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/global_chat_panel.dart';
import 'package:yovoice/features/messages/data/services/global_chat_service.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';

/// Global Chat, full screen, for mobile.
///
/// This is a HOST, not a second implementation: the body is the existing
/// [GlobalChatPanel] — the same canonical channel, composer, rate limits,
/// reporting, moderation state and staff deletion the desktop
/// Conversations module uses. The panel carries no fixed width or height,
/// so it fills a phone as happily as a desktop column.
///
/// Pushing it as a route (rather than swapping Home's content) is what
/// makes Back return to the exact Home scroll position.
class GlobalChatScreen extends StatelessWidget {
  const GlobalChatScreen({
    required this.currentUserId,
    this.chatService,
    this.reportService,
    this.isStaff = false,
    super.key,
  });

  final String currentUserId;
  final GlobalChatService? chatService;
  final ReportService? reportService;
  final bool isStaff;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Global chat',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: GlobalChatPanel(
            currentUserId: currentUserId,
            chatService: chatService,
            reportService: reportService,
            isStaff: isStaff,
          ),
        ),
      ),
    );
  }
}
