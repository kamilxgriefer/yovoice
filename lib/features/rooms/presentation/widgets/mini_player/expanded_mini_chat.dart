import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_chat_sheet.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

/// The expanded chat surface for the mini player. It REUSES [RoomChatPanel]
/// — the one real room chat (messages, role badges, reactions, report,
/// composer) — so there is a single chat implementation, and it never
/// touches the RTC session: expanding and collapsing are pure UI.
class ExpandedMiniChat extends StatelessWidget {
  const ExpandedMiniChat({
    required this.roomId,
    required this.isHost,
    required this.service,
    required this.onCollapse,
    this.scrollController,
    super.key,
  });

  final String roomId;
  final bool isHost;
  final RoomService service;
  final VoidCallback onCollapse;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final isSheet = scrollController != null;
    final panel = RoomChatPanel(
      key: const ValueKey('mini-player-expanded-chat'),
      roomId: roomId,
      isHost: isHost,
      accent: AppColors.voice,
      onClose: isSheet ? null : onCollapse,
      scrollController: scrollController,
      service: service,
      currentUserId: service.currentUserId,
    );
    // The SHEET variant (scrollController != null) carries its own handle
    // ON the surface: the modal wrapper is transparent, so a theme-drawn
    // handle floated ~20px above the visible top as a detached dash.
    if (!isSheet) return panel;
    return Material(
      color: const Color(0xFF110B19),
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          YoModalSheetChrome(
            sheetLabel: 'room chat',
            surfaceColor: const Color(0xFF110B19),
            onClose: onCollapse,
          ),
          Expanded(child: panel),
        ],
      ),
    );
  }
}

/// Mobile expanded chat: a draggable bottom sheet (~55–85% of the screen)
/// with a drag handle and the full chat surface. Returns when collapsed.
Future<void> showExpandedMiniChatSheet(
  BuildContext context, {
  required String roomId,
  required bool isHost,
  required RoomService service,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
    // The theme's handle is drawn on THIS transparent wrapper, ~20px above
    // the visible surface — a lone dash floating over the dim. The surface
    // draws its own handle instead (ExpandedMiniChat, sheet variant).
    showDragHandle: false,
    builder: (sheetContext) => Padding(
      // Keep the composer above the keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .62,
        minChildSize: .45,
        maxChildSize: .85,
        builder: (context, scrollController) => ExpandedMiniChat(
          roomId: roomId,
          isHost: isHost,
          service: service,
          scrollController: scrollController,
          onCollapse: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    ),
  );
}
