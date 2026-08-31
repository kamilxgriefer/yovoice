import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/offline_voice_moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_card.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_boundary.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

/// Opens ONE Voice Moment so it can actually be heard.
///
/// This exists because "open a Moment" meant different things in
/// different places: Home's avatar rail pushed the COMMENTS screen, which
/// lists replies and has no player at all — tapping your own face on Home
/// could not play your own Moment. There is now a single answer, and it
/// is the existing [MomentCard]: play/pause, the real duration, like,
/// comment, report and the offline download, none of them reimplemented.
///
/// Responsive on purpose: a bottom sheet stretched across a 1440 pt
/// desktop window is a phone layout that grew, so the sheet is capped at
/// a readable measure and centred, and it scrolls rather than clipping a
/// long caption at a large text scale.
Future<void> showMomentSheet(
  BuildContext context, {
  required VoiceMoment moment,
  bool isOwn = false,
  bool canReport = false,
  HomeFeedService? feedService,
  ContentReportService? contentReportService,
  OfflineVoiceMomentService? offlineService,
  MomentService? momentService,

  /// Injection seam for playback, forwarded to the card. Production
  /// passes nothing; a harness passes a player that touches no platform
  /// channel.
  AudioPlayer Function()? playerFactory,
  MomentExpiryClock? expiryClock,
  MomentExpiryTimerFactory? expiryTimerFactory,
}) async {
  // Resolved here rather than demanded from every caller: without it the
  // heart renders as an inert indicator, and a Moment you cannot like is
  // not the surface anyone asked for. Guarded because constructing it
  // needs a Firebase app.
  HomeFeedService? feed = feedService;
  if (feed == null) {
    try {
      feed = HomeFeedService();
    } catch (_) {
      feed = null;
    }
  }

  // The sheet re-reads the Moment it was handed, so a like made INSIDE
  // it updates its own counter. The tile that opened it carries a
  // snapshot from whenever its feed last emitted; acting on a stale
  // number and watching it not move is the defect this closes.
  MomentService? moments = momentService;
  if (moments == null) {
    try {
      moments = MomentService();
    } catch (_) {
      moments = null;
    }
  }
  final live = moments?.watchMoment(moment.id);

  final navigator = Navigator.of(context);
  final palette = context.appPalette;
  final expiryAnnouncer = MomentExpiryAnnouncer();
  var expiryHandled = false;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: palette.surfaceRaised,
    isScrollControlled: true,
    showDragHandle: false,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (sheetContext) {
      final viewport = MediaQuery.sizeOf(sheetContext).height;
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          // Never full height: the board or feed underneath stays visible,
          // which is what makes this feel like opening a Moment rather
          // than navigating away from where you were.
          constraints: BoxConstraints(maxHeight: viewport * .82),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              YoModalSheetChrome(
                sheetLabel: 'Moment',
                surfaceColor: palette.surfaceRaised,
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: StreamBuilder<VoiceMoment>(
                    stream: live,
                    initialData: moment,
                    builder: (context, snapshot) {
                      // An errored or empty document stream keeps the Moment
                      // the caller passed: it is real, just not live.
                      final current = snapshot.data ?? moment;
                      return MomentExpiryBoundary(
                        moment: current,
                        clock: expiryClock,
                        timerFactory: expiryTimerFactory,
                        onExpired: () {
                          if (expiryHandled) return;
                          expiryHandled = true;
                          if (sheetContext.mounted) {
                            expiryAnnouncer.announce(
                              sheetContext,
                              transition: 'sheet-gone-${current.id}',
                              message: 'Voice Moment expired. Closing player.',
                            );
                            final navigator = Navigator.of(sheetContext);
                            final sheetRoute = ModalRoute.of(sheetContext);
                            if (sheetRoute != null && sheetRoute.isActive) {
                              navigator.removeRoute(sheetRoute);
                            } else {
                              unawaited(navigator.maybePop());
                            }
                          }
                        },
                        child: MomentCard(
                          // Keyed by id, so switching Moments rebuilds the
                          // card's player rather than reusing another
                          // Moment's state.
                          key: ValueKey('moment-sheet-${current.id}'),
                          moment: current,
                          isOwn: isOwn,
                          canReport: canReport,
                          feedService: feed,
                          offlineService: offlineService,
                          contentReportService: contentReportService,
                          playerFactory: playerFactory,
                          onComments: () => unawaited(
                            navigator.push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => MomentCommentsScreen(
                                  moment: current,
                                  expiryClock: expiryClock,
                                  expiryTimerFactory: expiryTimerFactory,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
