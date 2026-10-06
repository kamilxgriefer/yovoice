import 'dart:async';
import 'dart:math' as math;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/data/services/pages_availability.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/data/user_links.dart';
import 'package:yovoice/features/profile/presentation/my_link_copy.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

typedef MyLinkShareInvoker = Future<ShareResult> Function(ShareParams params);
typedef MyLinkClipboardWriter = Future<void> Function(String text);

/// Whether the signed-in account opens as a Page for the people who follow
/// its link. Best-effort: a failed lookup means "no".
typedef MyLinkRunsPage = Future<bool> Function(String userId);

final _myLinkFlights = Expando<Future<void>>('My link');

/// From this width "Mój link" is a centred dialog instead of a bottom sheet
/// (the desktop shell's breakpoint; the sheet chrome drops its drag handle at
/// the same width).
const double myLinkDialogBreakpoint = YoModalSheetChrome.desktopBreakpoint;

/// The dialog's width on desktop.
const double myLinkDialogWidth = 420;

/// Hands the signed-in account's own profile link to the system share sheet
/// with the "find me" sentence. Used by every "invite friends" action, so
/// none of them shares a generic download page any more.
///
/// Returns false when there is no link to share (signed out, or an
/// identifier the link contract cannot carry) or the platform refused.
Future<bool> shareMyLink(
  BuildContext context, {
  String? userId,
  FirebaseAuth? auth,
  MyLinkShareInvoker? shareInvoker,
}) async {
  // An empty id is "not known here", not an answer: launchers that carry the
  // session's uid as a non-null string pass '' when it is missing.
  final ownId = userId == null || userId.isEmpty ? _currentUid(auth) : userId;
  final link = tryBuildUserLink(ownId);
  final copy = MyLinkCopy(AppLocalizations.of(context));
  if (link == null) {
    _announce(context, copy.unavailable);
    return false;
  }
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize && !box.size.isEmpty
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  try {
    await (shareInvoker ?? SharePlus.instance.share)(
      ShareParams(text: copy.shareText(link), sharePositionOrigin: origin),
    );
    return true;
  } catch (_) {
    if (context.mounted) _announce(context, copy.cannotShare);
    return false;
  }
}

void _announce(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String? _currentUid(FirebaseAuth? auth) {
  try {
    return (auth ?? FirebaseAuth.instance).currentUser?.uid;
  } catch (_) {
    // Firebase is not initialized (a widget test without a seam).
    return null;
  }
}

Future<bool> _defaultRunsPage(String userId) async {
  try {
    if (!PagesAvailability.instance.enabled.value) return false;
    final identity = await PublicIdentityRepository.instance.resolve(userId);
    return identity.isPage;
  } catch (_) {
    return false;
  }
}

/// Opens "Mój link" (ADR-238): the signed-in account's public profile link
/// as a QR code, with Copy and Share.
///
/// A bottom sheet below [myLinkDialogBreakpoint] (full width on a phone, a
/// centred 520 px sheet on a tablet) and a [myLinkDialogWidth] dialog on
/// desktop. One at a time per navigator: a second tap while it is open
/// returns the first flight.
Future<void> showMyLink(
  BuildContext context, {
  FirebaseAuth? auth,
  ProfileService? profileService,
  ProfileMediaService? mediaService,
  UserProfile? seedProfile,
  @visibleForTesting MyLinkShareInvoker? shareInvoker,
  @visibleForTesting MyLinkClipboardWriter? clipboardWriter,
  @visibleForTesting MyLinkRunsPage? runsPage,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final current = _myLinkFlights[navigator];
  if (current != null) return current;

  final userId = _currentUid(auth);
  Stream<UserProfile>? profile;
  if (userId != null) {
    try {
      profile = (profileService ?? ProfileService(auth: auth))
          .watchCurrentProfile();
    } catch (_) {
      // The link and its code need only the identifier; the name falls back
      // to what the session already knows.
      profile = null;
    }
  }
  String? seedName;
  try {
    seedName =
        seedProfile?.displayName ??
        (auth ?? FirebaseAuth.instance).currentUser?.displayName;
  } catch (_) {
    seedName = seedProfile?.displayName;
  }

  Widget panel({required bool dialog}) => MyLinkPanel(
    userId: userId,
    profile: profile,
    seedProfile: seedProfile,
    seedDisplayName: seedName,
    mediaService: mediaService,
    dialog: dialog,
    shareInvoker: shareInvoker ?? SharePlus.instance.share,
    clipboardWriter:
        clipboardWriter ??
        (text) => Clipboard.setData(ClipboardData(text: text)),
    runsPage: runsPage ?? _defaultRunsPage,
  );

  final palette = context.appPalette;
  final desktop = MediaQuery.sizeOf(context).width >= myLinkDialogBreakpoint;
  late final Future<void> flight;
  flight =
      (desktop
              ? showDialog<void>(
                  context: context,
                  useRootNavigator: true,
                  barrierColor: palette.scrim.withValues(alpha: .72),
                  builder: (_) => Dialog(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    insetPadding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: myLinkDialogWidth,
                      ),
                      child: panel(dialog: true),
                    ),
                  ),
                )
              : showModalBottomSheet<void>(
                  context: context,
                  useRootNavigator: true,
                  useSafeArea: true,
                  isScrollControlled: true,
                  showDragHandle: false,
                  backgroundColor: Colors.transparent,
                  barrierColor: palette.scrim.withValues(alpha: .72),
                  constraints: ResponsiveContentFrame.adaptiveModalConstraints(
                    context,
                    maxWidth: 520,
                  ),
                  builder: (_) => panel(dialog: false),
                ))
          .whenComplete(() {
            if (identical(_myLinkFlights[navigator], flight)) {
              _myLinkFlights[navigator] = null;
            }
          });
  _myLinkFlights[navigator] = flight;
  return flight;
}

enum _MyLinkFeedback { copied, unconfirmed, cannotShare, cannotCopy }

/// The surface of "Mój link": the sheet's (or dialog's) chrome, the identity
/// card with the QR code and the link, and the two actions.
///
/// Public so the capture harness and the widget tests mount THIS widget with
/// fixture data. Everything it draws is real: the identifier is the signed-in
/// account's own, the code encodes exactly the link printed under it, and the
/// name comes from the account's profile.
class MyLinkPanel extends StatefulWidget {
  const MyLinkPanel({
    required this.userId,
    required this.shareInvoker,
    required this.clipboardWriter,
    required this.runsPage,
    this.profile,
    this.seedProfile,
    this.seedDisplayName,
    this.mediaService,
    this.dialog = false,
    super.key,
  });

  /// The signed-in account's public id, or null when there is no session.
  final String? userId;

  /// The account's own profile, for the name, the handle and the avatar
  /// revision. Null renders [seedDisplayName] only.
  final Stream<UserProfile>? profile;
  final UserProfile? seedProfile;
  final String? seedDisplayName;
  final ProfileMediaService? mediaService;

  /// True inside the desktop dialog (all four corners rounded, no bottom
  /// safe-area band), false inside the bottom sheet.
  final bool dialog;

  final MyLinkShareInvoker shareInvoker;
  final MyLinkClipboardWriter clipboardWriter;
  final MyLinkRunsPage runsPage;

  /// The QR tile's side on the approved render; narrower slots shrink it.
  static const double qrSize = 220;

  /// White margin inside the tile. A profile link is a 33-module code, so
  /// 20 px of a 220 px tile is 3.7 modules — the standard asks for four.
  static const double qrQuietZone = 20;

  @override
  State<MyLinkPanel> createState() => _MyLinkPanelState();
}

class _MyLinkPanelState extends State<MyLinkPanel> {
  late final Uri? _link = tryBuildUserLink(widget.userId);
  bool _runsPage = false;
  bool _busy = false;
  _MyLinkFeedback? _feedback;

  @override
  void initState() {
    super.initState();
    final userId = widget.userId;
    if (_link != null && userId != null) {
      unawaited(
        widget
            .runsPage(userId)
            .then((runsPage) {
              if (mounted && runsPage != _runsPage) {
                setState(() => _runsPage = runsPage);
              }
            })
            .catchError((Object _) {}),
      );
    }
  }

  Future<void> _copy() async {
    final link = _link;
    if (_busy || link == null) return;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await widget.clipboardWriter(link.toString());
      _setFeedback(_MyLinkFeedback.copied);
    } catch (_) {
      _setFeedback(_MyLinkFeedback.cannotCopy);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    final link = _link;
    if (_busy || link == null) return;
    final box = buttonContext.findRenderObject();
    final origin = box is RenderBox && box.hasSize && !box.size.isEmpty
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final text = MyLinkCopy(AppLocalizations.of(context)).shareText(link);
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final result = await widget.shareInvoker(
        ShareParams(
          text: text,
          sharePositionOrigin: origin,
          downloadFallbackEnabled: false,
          mailToFallbackEnabled: false,
        ),
      );
      // An unavailable result is not proof of delivery: offer the explicit
      // fallback instead of silently overwriting the clipboard. A dismissal
      // or a nominal success claims nothing either.
      if (result.status == ShareResultStatus.unavailable) {
        _setFeedback(_MyLinkFeedback.unconfirmed);
      }
    } catch (_) {
      _setFeedback(_MyLinkFeedback.cannotShare);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setFeedback(_MyLinkFeedback feedback) {
    if (!mounted) return;
    setState(() => _feedback = feedback);
    // ADR-058: failures use the assertive channel; "copied" and
    // "unconfirmed" are read by the polite live region below.
    if (feedback == _MyLinkFeedback.copied ||
        feedback == _MyLinkFeedback.unconfirmed) {
      return;
    }
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        _feedbackMessage(feedback),
        Directionality.of(context),
        assertiveness: Assertiveness.assertive,
      ),
    );
  }

  String _feedbackMessage(_MyLinkFeedback feedback) {
    final copy = MyLinkCopy(AppLocalizations.of(context));
    return switch (feedback) {
      _MyLinkFeedback.copied => copy.copied,
      _MyLinkFeedback.unconfirmed => copy.shareUnconfirmed,
      _MyLinkFeedback.cannotShare => copy.cannotShare,
      _MyLinkFeedback.cannotCopy => copy.cannotCopy,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = MyLinkCopy(AppLocalizations.of(context));
    final radius = widget.dialog
        ? AppRadius.xl
        : const BorderRadius.vertical(top: Radius.circular(28));
    final highContrast = MediaQuery.highContrastOf(context);
    final edge = highContrast ? palette.borderStrong : palette.hairline;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .92,
      ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: widget.dialog
              ? Border.all(color: edge)
              : Border(top: BorderSide(color: edge)),
        ),
        child: Material(
          key: const ValueKey('my-link-panel'),
          color: palette.surfaceRaised,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            bottom: !widget.dialog,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                YoModalSheetChrome(
                  sheetLabel: copy.title,
                  surfaceColor: palette.surfaceRaised,
                ),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('my-link-scroll'),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: _body(context, copy),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The one sentence under the title: what the link does for whoever opens
  /// it. An account whose profile is not visible to everyone is told so —
  /// for the people its setting does not admit, the link shows "not
  /// available" and offers no way to add them.
  String _sentence(MyLinkCopy copy, UserProfile? profile) {
    if (_link == null) return copy.unavailable;
    if (profile != null &&
        profile.profileVisibility != ProfileVisibility.public) {
      return copy.bodyNotPublic;
    }
    return copy.body(runsPage: _runsPage);
  }

  Widget _body(BuildContext context, MyLinkCopy copy) =>
      StreamBuilder<UserProfile>(
        // The account's own profile: the card's name, handle and avatar, and
        // the visibility the sentence above it has to be honest about.
        stream: widget.profile,
        initialData: widget.seedProfile,
        builder: (context, snapshot) =>
            _bodyFor(context, copy, snapshot.data ?? widget.seedProfile),
      );

  Widget _bodyFor(BuildContext context, MyLinkCopy copy, UserProfile? profile) {
    final palette = context.appPalette;
    final link = _link;
    final feedback = _feedback;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            copy.title,
            style: AppTypography.screenTitle.copyWith(
              color: palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppRhythm.hairline),
        Text(
          _sentence(copy, profile),
          key: const ValueKey('my-link-body'),
          style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
        ),
        if (link != null) ...[
          const SizedBox(height: 14),
          YoCard(
            padding: const EdgeInsets.all(AppRhythm.title),
            child: _MyLinkCard(
              userId: widget.userId!,
              link: link,
              profile: profile,
              seedDisplayName: widget.seedDisplayName,
              mediaService: widget.mediaService,
              qrLabel: copy.qrLabel,
            ),
          ),
          const SizedBox(height: 14),
          _actions(context, copy),
          if (feedback != null) ...[
            const SizedBox(height: AppRhythm.item),
            Semantics(
              liveRegion:
                  feedback == _MyLinkFeedback.copied ||
                  feedback == _MyLinkFeedback.unconfirmed,
              child: Text(
                _feedbackMessage(feedback),
                key: const ValueKey('my-link-feedback'),
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color:
                      feedback == _MyLinkFeedback.copied ||
                          feedback == _MyLinkFeedback.unconfirmed
                      ? palette.textSecondary
                      : palette.dangerForeground,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _actions(BuildContext context, MyLinkCopy copy) {
    final palette = context.appPalette;
    const minimumSize = Size(64, 48);
    final copyButton = FilledButton.icon(
      key: const ValueKey('my-link-copy'),
      onPressed: _busy ? null : _copy,
      style:
          AppFinish.tonalNeutral(
            palette,
            foreground: palette.textPrimary,
            highContrast: MediaQuery.highContrastOf(context),
          ).copyWith(
            minimumSize: const WidgetStatePropertyAll(minimumSize),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
      icon: const Icon(Icons.copy_rounded, size: 20),
      label: _ActionLabel(copy.copyLink),
    );
    final shareButton = Builder(
      builder: (buttonContext) => YoGradientFilledButton(
        buttonKey: const ValueKey('my-link-share'),
        onPressed: _busy ? null : () => _share(buttonContext),
        minimumSize: minimumSize,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        icon: const Icon(Icons.ios_share_rounded, size: 20),
        child: _ActionLabel(copy.share),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Two labelled 48 px actions share the row only while BOTH labels
        // fit at their own size: a longer language, a narrow slot or large
        // text stacks them full width, so no label is cut or shrunk.
        final style = Theme.of(context).textTheme.labelLarge;
        final scaler = MediaQuery.textScalerOf(context);
        double measure(String label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        // Per button: 16 px padding on each side, the 20 px glyph and its
        // 8 px gap, plus 4 px of slack for rounding.
        const chrome = 16.0 * 2 + 20 + 8 + 4;
        final slot = (constraints.maxWidth - 10) / 2 - chrome;
        final stack =
            measure(copy.copyLink) > slot || measure(copy.share) > slot;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [shareButton, const SizedBox(height: 10), copyButton],
          );
        }
        return Row(
          children: [
            Expanded(child: copyButton),
            const SizedBox(width: 10),
            Expanded(child: shareButton),
          ],
        );
      },
    );
  }
}

/// One line that shrinks before it clips: the two actions keep their 48 px
/// height in the longest languages.
class _ActionLabel extends StatelessWidget {
  const _ActionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(label, maxLines: 1, softWrap: false),
  );
}

class _MyLinkCard extends StatelessWidget {
  const _MyLinkCard({
    required this.userId,
    required this.link,
    required this.profile,
    required this.seedDisplayName,
    required this.mediaService,
    required this.qrLabel,
  });

  final String userId;
  final Uri link;
  final UserProfile? profile;
  final String? seedDisplayName;
  final ProfileMediaService? mediaService;
  final String qrLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final name = (profile?.displayName ?? seedDisplayName ?? '').trim();
    final username = profile?.username.trim() ?? '';
    final shown = displayUserLink(link);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            UserAvatar(
              radius: 32,
              userId: userId,
              displayName: name.isEmpty ? null : name,
              mediaRevision: profile?.profileUpdatedAt,
              mediaService: mediaService,
              premium: profile?.premiumIdentity ?? false,
              fallbackIcon: Icons.person_rounded,
              finish: UserAvatarFinish.brand,
            ),
            const SizedBox(width: AppRhythm.item),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name.isNotEmpty)
                    Text(
                      name,
                      key: const ValueKey('my-link-name'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleLarge.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (username.isNotEmpty)
                    Text(
                      '@$username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // A handle is Latin: in an RTL locale the leading "@"
                      // must stay in front of it.
                      textDirection: TextDirection.ltr,
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppRhythm.title),
        LayoutBuilder(
          builder: (context, constraints) {
            final side = math.min(MyLinkPanel.qrSize, constraints.maxWidth);
            return Semantics(
              label: qrLabel,
              image: true,
              child: ExcludeSemantics(
                child: Container(
                  key: const ValueKey('my-link-qr'),
                  width: side,
                  height: side,
                  // The quiet zone: about four modules of white around the
                  // code, so it scans against the dark card.
                  padding: const EdgeInsets.all(MyLinkPanel.qrQuietZone),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: AppRadius.tile,
                    // On Pearl's near-white card the white tile needs an
                    // edge to read as a tile.
                    border: palette.isDark
                        ? null
                        : Border.all(color: palette.border),
                  ),
                  child: BarcodeWidget(
                    barcode: Barcode.qrCode(
                      errorCorrectLevel: BarcodeQRCorrectionLevel.medium,
                    ),
                    data: link.toString(),
                    drawText: false,
                    color: AppColors.contrastInk,
                    backgroundColor: AppColors.white,
                    errorBuilder: (context, error) => const Center(
                      child: Icon(
                        Icons.qr_code_2_rounded,
                        color: AppColors.contrastInk,
                        size: 56,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppRhythm.item),
        // The whole link, never elided: it is the thing being handed over.
        Text(
          displayUserLinkBreakable(link),
          key: const ValueKey('my-link-text'),
          semanticsLabel: shown,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: const <String>[
              AppTypography.fontFamily,
              ...AppTypography.fontFamilyFallback,
            ],
            fontSize: 12,
            height: 1.45,
            color: palette.textSecondary,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
