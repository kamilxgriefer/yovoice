import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/reels/data/reel_links.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

typedef ReelShareInvoker = Future<ShareResult> Function(ShareParams params);
typedef ReelLinkClipboardWriter = Future<void> Function(String text);

final _shareFlights = Expando<Future<void>>('Reel share sheets');

/// Authorizes first, then offers a fresh user gesture for platform sharing.
/// In particular, a web share call after an awaited network read can lose the
/// browser's transient activation. The second, explicit tap avoids that race.
///
/// The payload is ONLY the public identifier URL. No preview, author, caption,
/// grant, signed URL, bytes, credential or metadata-fetching `uri` is shared.
/// Loading this sheet never initializes a player or records a viewed event.
Future<void> showReelShareSheet(
  BuildContext context, {
  required String reelId,
  required ReelService service,
  @visibleForTesting ReelShareInvoker? shareInvoker,
  @visibleForTesting ReelLinkClipboardWriter? clipboardWriter,
  @visibleForTesting DateTime Function()? now,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final current = _shareFlights[navigator];
  if (current != null) return current;
  late final Future<void> flight;
  flight =
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        constraints: ResponsiveContentFrame.adaptiveModalConstraints(
          context,
          maxWidth: 520,
        ),
        builder: (_) => _ReelShareSheet(
          reelId: reelId,
          service: service,
          shareInvoker: shareInvoker ?? SharePlus.instance.share,
          clipboardWriter:
              clipboardWriter ??
              (text) => Clipboard.setData(ClipboardData(text: text)),
          now: now ?? DateTime.now,
        ),
      ).whenComplete(() {
        if (identical(_shareFlights[navigator], flight)) {
          _shareFlights[navigator] = null;
        }
      });
  _shareFlights[navigator] = flight;
  return flight;
}

enum _ShareFeedback { copied, unconfirmed, cannotShare, cannotCopy }

class _ReelShareSheet extends StatefulWidget {
  const _ReelShareSheet({
    required this.reelId,
    required this.service,
    required this.shareInvoker,
    required this.clipboardWriter,
    required this.now,
  });

  final String reelId;
  final ReelService service;
  final ReelShareInvoker shareInvoker;
  final ReelLinkClipboardWriter clipboardWriter;
  final DateTime Function() now;

  @override
  State<_ReelShareSheet> createState() => _ReelShareSheetState();
}

class _ReelShareSheetState extends State<_ReelShareSheet> {
  late final String? _viewerId = widget.service.currentUserId;
  StreamSubscription<String?>? _identity;
  Timer? _authorizationTimer;
  DateTime? _validUntil;
  bool _identityEnded = false;
  bool _loading = true;
  bool _busy = false;
  int _generation = 0;
  _ShareFeedback? _feedback;

  bool get _sameViewer =>
      !_identityEnded &&
      _viewerId != null &&
      widget.service.currentUserId == _viewerId;

  bool get _authorized =>
      _sameViewer && _validUntil != null && widget.now().isBefore(_validUntil!);

  @override
  void initState() {
    super.initState();
    _identity = widget.service.identityChanges.listen((uid) {
      if (uid != _viewerId) _endIdentity();
    }, onError: (Object _) => _endIdentity());
    unawaited(_load());
  }

  void _endIdentity() {
    if (!mounted || _identityEnded) return;
    _generation++;
    _authorizationTimer?.cancel();
    setState(() {
      _identityEnded = true;
      _validUntil = null;
      _feedback = null;
      _loading = false;
      _busy = false;
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _authorizationTimer?.cancel();
    setState(() {
      _validUntil = null;
      _feedback = null;
      _loading = true;
    });
    try {
      if (!_sameViewer || !isSafeReelLinkId(widget.reelId)) return;
      final view = await widget.service.loadView(
        widget.reelId,
        commentLimit: 1,
      );
      if (!mounted || generation != _generation || !_sameViewer) return;
      final now = widget.now();
      if (view.reel.id != widget.reelId ||
          !view.reel.availability.isAvailableAt(now)) {
        return;
      }
      // This is only a short-lived presentation hint, NOT a capability. The
      // recipient still authorizes independently when opening the ID link.
      var deadline = now.add(const Duration(seconds: 30));
      final expiry = view.reel.availability.contentExpiresAt;
      if (expiry != null && expiry.isBefore(deadline)) deadline = expiry;
      setState(() => _validUntil = deadline);
      _authorizationTimer = Timer(deadline.difference(now), () {
        if (mounted) setState(() => _validUntil = null);
      });
    } catch (_) {
      // Same presentation for missing, private, blocked, expired and malformed
      // content. Never expose backend exception messages or fetched metadata.
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    if (_busy || !_authorized) return;
    final generation = _generation;
    final box = buttonContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final result = await widget.shareInvoker(
        ShareParams(
          text: buildReelLink(widget.reelId).toString(),
          sharePositionOrigin: origin,
          downloadFallbackEnabled: false,
          mailToFallbackEnabled: false,
        ),
      );
      // An unavailable result is not proof of delivery. Offer an explicit
      // fallback without silently overwriting the clipboard. A dismissal or
      // nominal success also never claims that a recipient received the link.
      if (result.status == ShareResultStatus.unavailable &&
          mounted &&
          generation == _generation &&
          _authorized) {
        _setFeedback(_ShareFeedback.unconfirmed);
      }
    } catch (_) {
      if (mounted && generation == _generation && _sameViewer) {
        _setFeedback(_ShareFeedback.cannotShare);
      }
    } finally {
      if (mounted && generation == _generation && _sameViewer) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _copy() async {
    if (_busy || !_authorized) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await widget.clipboardWriter(buildReelLink(widget.reelId).toString());
      if (mounted && generation == _generation && _sameViewer) {
        _setFeedback(_ShareFeedback.copied);
      }
    } catch (_) {
      if (mounted && generation == _generation && _sameViewer) {
        _setFeedback(_ShareFeedback.cannotCopy);
      }
    } finally {
      if (mounted && generation == _generation && _sameViewer) {
        setState(() => _busy = false);
      }
    }
  }

  void _setFeedback(_ShareFeedback feedback) {
    if (!mounted || !_authorized) return;
    setState(() => _feedback = feedback);
    // ADR-058: errors use the separate assertive channel; non-error statuses
    // share one polite region. Rebuilds must not repeat announcements.
    if (feedback == _ShareFeedback.copied ||
        feedback == _ShareFeedback.unconfirmed ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        _feedbackMessage(feedback),
        Directionality.of(context),
        assertiveness: Assertiveness.assertive,
      ),
    );
  }

  String _feedbackMessage(_ShareFeedback feedback) {
    final copy = AppLocalizations.of(context);
    return switch (feedback) {
      _ShareFeedback.copied => copy.text(
        'Reel link copied.',
        'Link do Reela skopiowany.',
      ),
      _ShareFeedback.unconfirmed => copy.text(
        'Sharing could not be confirmed. You can copy the link.',
        'Nie można potwierdzić udostępnienia. Możesz skopiować link.',
      ),
      _ShareFeedback.cannotShare => copy.text(
        'Sharing is unavailable here. Copy the link instead.',
        'Udostępnianie jest tutaj niedostępne. Skopiuj link.',
      ),
      _ShareFeedback.cannotCopy => copy.text(
        'The link could not be copied. Try again.',
        'Nie udało się skopiować linku. Spróbuj ponownie.',
      ),
    };
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_identity?.cancel());
    _authorizationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final title = copy.text('Share Reel', 'Udostępnij Reel');
    final feedback = _feedback == null ? null : _feedbackMessage(_feedback!);
    return Material(
      key: const ValueKey('reel-share-sheet'),
      color: palette.surfaceRaised,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YoModalSheetChrome(
                sheetLabel: title,
                surfaceColor: palette.surfaceRaised,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    if (_loading)
                      YoLoadingIndicator(
                        message: copy.text('Loading Reel', 'Ładowanie Reela'),
                      )
                    else if (!_authorized) ...[
                      Text(
                        _sameViewer
                            ? copy.text(
                                'This Reel is unavailable right now.',
                                'Ten Reel jest teraz niedostępny.',
                              )
                            : copy.text(
                                'Sign in to open this Reel.',
                                'Zaloguj się, aby otworzyć ten Reel.',
                              ),
                      ),
                      if (_sameViewer && isSafeReelLinkId(widget.reelId)) ...[
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: _load,
                          child: Text(
                            copy.text('Try again', 'Spróbuj ponownie'),
                          ),
                        ),
                      ],
                    ] else ...[
                      Text(
                        copy.text(
                          'Only people with access can view this Reel.',
                          'Ten Reel mogą obejrzeć tylko osoby z dostępem.',
                        ),
                      ),
                      const SizedBox(height: 20),
                      Builder(
                        builder: (buttonContext) => FilledButton.icon(
                          key: const ValueKey('reel-share-platform'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(44, 48),
                          ),
                          onPressed: _busy ? null : () => _share(buttonContext),
                          icon: const Icon(Icons.share_outlined),
                          label: Text(title),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const ValueKey('reel-share-copy'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(44, 48),
                        ),
                        onPressed: _busy ? null : _copy,
                        icon: const Icon(Icons.copy_outlined),
                        label: Text(
                          copy.text('Copy Reel link', 'Skopiuj link do Reela'),
                        ),
                      ),
                    ],
                    if (feedback != null && _sameViewer) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion:
                            _feedback == _ShareFeedback.copied ||
                            _feedback == _ShareFeedback.unconfirmed,
                        child: Text(feedback),
                      ),
                    ],
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
