import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/moment_links.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_detail_chrome.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

/// Loads one Voice Moment by id. Production reads the privacy-filtered
/// `getVoiceMomentViewV2` projection through [MomentService].
typedef MomentLinkLoader = Future<VoiceMoment> Function(String momentId);

/// Where a `?moment=<id>` link lands (ADR-238): the Voice Moment's own
/// detail page once the id resolves, and the detail page's gone-state when
/// it does not.
///
/// An identifier is not permission. Nothing about the Moment is taken from
/// the link: the Moment is read through the same callable as every other
/// surface, so a private, expired, deleted, blocked or unknown Moment all
/// end in the same "no longer available" card, and the answer reveals
/// nothing about which it was.
class MomentLinkDestinationScreen extends StatefulWidget {
  const MomentLinkDestinationScreen({
    required this.momentId,
    this.loader,
    this.detailBuilder,
    super.key,
  });

  final String momentId;

  @visibleForTesting
  final MomentLinkLoader? loader;

  /// Builds the destination for a resolved Moment. Production mounts
  /// [MomentDetailScreen]; tests pass a seam.
  @visibleForTesting
  final Widget Function(BuildContext context, VoiceMoment moment)?
  detailBuilder;

  @override
  State<MomentLinkDestinationScreen> createState() =>
      _MomentLinkDestinationScreenState();
}

class _MomentLinkDestinationScreenState
    extends State<MomentLinkDestinationScreen> {
  VoiceMoment? _moment;
  Object? _error;
  bool _gone = false;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<VoiceMoment> _defaultLoader(String momentId) async =>
      (await MomentService().loadMomentView(momentId)).moment;

  /// The callable's refusals that mean "this is not yours to see, or it is
  /// not there" — the same set the detail page treats as gone.
  static bool _isGoneError(Object error) =>
      error is FirebaseFunctionsException &&
      const <String>{
        'permission-denied',
        'not-found',
        'gone',
      }.contains(error.code);

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _gone = false;
    });
    try {
      if (!isSafeMomentLinkId(widget.momentId)) {
        _gone = true;
        return;
      }
      final moment = await (widget.loader ?? _defaultLoader)(widget.momentId);
      if (!mounted || generation != _generation) return;
      if (moment.id != widget.momentId) {
        _gone = true;
        return;
      }
      _moment = moment;
    } catch (error) {
      if (!mounted || generation != _generation) return;
      if (_isGoneError(error)) {
        _gone = true;
      } else {
        _error = error;
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _back() => unawaited(Navigator.of(context).maybePop());

  @override
  Widget build(BuildContext context) {
    final moment = _moment;
    if (moment != null) {
      return widget.detailBuilder?.call(context, moment) ??
          MomentDetailScreen(moment: moment);
    }

    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final Widget state;
    if (_loading) {
      state = YoLoadingIndicator(message: copy.text('Loading', 'Ładowanie'));
    } else if (_gone) {
      state = Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        // The detail page's own 640 pt measure, filled like its card.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SizedBox(
            width: double.infinity,
            child: MomentGoneCard(onBack: _back),
          ),
        ),
      );
    } else {
      state = YoErrorState(error: _error, onRetry: () => unawaited(_load()));
    }

    return Scaffold(
      key: const ValueKey('moment-link-destination'),
      backgroundColor: palette.background,
      body: SafeArea(
        child: Column(
          children: [
            MomentDetailHeader(onBack: _back),
            Expanded(
              child: Center(child: SingleChildScrollView(child: state)),
            ),
          ],
        ),
      ),
    );
  }
}
