import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/creator/data/services/creator_audience_service.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/page_catalog.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_navigation.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/screens/page_settings_screen.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_card_rows.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_focus_ink.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_profile_parts.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';
import 'package:yovoice/shared/widgets/inputs/yo_keyboard_done_bar.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_upsell_sheet.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';

/// The one create entry every surface uses (the Premium block, E2, the
/// phone card, the desktop panel row): create A full screen over the
/// shell, then the new Page's own profile.
Future<void> openCreatePageFlow(
  BuildContext context, {
  String? backLabel,
  Stream<PageAccessState> Function()? accessStream,
  @visibleForTesting WidgetBuilder? screenBuilder,
}) async {
  // R11: an account that cannot run a Page (neither a canonical VIP grant
  // nor active paid Premium, and no Page) gets the honest upsell instead of
  // a form the server would refuse.
  PageAccessState? access;
  try {
    access = await (accessStream?.call() ?? PageAccessService.instance.watch())
        .firstWhere((state) => state.resolved)
        .timeout(const Duration(seconds: 4));
  } catch (_) {
    access = null;
  }
  if (!context.mounted) return;
  if (access != null && !access.canRunPage && access.ownPage == null) {
    await showPremiumUpsellSheet(
      context,
      upsellContext: PremiumUpsellContext.pages,
    );
    return;
  }
  final created = await Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute<String>(
      settings: const RouteSettings(name: 'pages/create'),
      builder: screenBuilder ?? (_) => CreatePageScreen(backLabel: backLabel),
    ),
  );
  if (created == null || !context.mounted) return;
  await openPageProfile(context, pageId: created);
}

/// Create, variant A (approved `tresci-ui/create/A_*`, R2 steps 2-3; spec
/// premium-pages §4.4): 1 Rodzaj (Firma / Społeczność) → 2 Szczegóły (the
/// form under a live preview, A "formularz z podglądem") → 3 Podgląd (the
/// profile header as visitors will see it, "Co się stanie", Opublikuj
/// stronę → `managePageV1 {op:"create"}`).
///
/// Phone: an app bar "Nowa strona · Krok n z 3", a three-segment progress
/// and the bottom action. Wide (≥ 720): the desktop frame of the approved
/// render, a back link, step tabs, a 720 column and the actions on the
/// right. From 1000 the header spans a centred 1040 frame on every step and
/// step 2 splits into the form and a sticky preview column (variant C,
/// approved 2026-09-28). The form state is shared by all of them. Pops with
/// the new Page's id.
class CreatePageScreen extends StatefulWidget {
  const CreatePageScreen({
    this.backLabel,
    this.service,
    this.profileStream,
    this.serverStream,
    this.birthDatePicker,
    this.userId,
    this.clock,
    super.key,
  });

  /// The desktop back link's label (the opener's name, e.g. "Premium").
  final String? backLabel;

  /// Test seams; the app uses the shared instances.
  final PagesService? service;
  final Stream<UserProfile> Function()? profileStream;
  final Stream<List<Server>> Function()? serverStream;
  final Future<DateTime?> Function(BuildContext context)? birthDatePicker;
  final String? userId;
  final DateTime Function()? clock;

  static const double wideBreakpoint = 720;
  static const double wideColumn = 720;

  /// From here every step's header spans [splitFrame] and step 2 splits
  /// into the form and a sticky preview column.
  static const double splitBreakpoint = 1000;

  /// The centred desktop frame from [splitBreakpoint] (UI.md `feed`).
  static const double splitFrame = 1040;

  @override
  State<CreatePageScreen> createState() => _CreatePageScreenState();
}

class _CreatePageScreenState extends State<CreatePageScreen> {
  late final PagesService _service = widget.service ?? PagesService.instance;
  late final Stream<UserProfile> _profileStream =
      (widget.profileStream ?? () => ProfileService().watchCurrentProfile())();
  late final String _userId = widget.userId ?? _currentUserId();
  StreamSubscription<UserProfile>? _profileSub;
  UserProfile? _profile;

  int _step = 1;
  PageKind _kind = PageKind.business;
  String? _category;
  final TextEditingController _description = TextEditingController();
  final TextEditingController _website = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _hours = TextEditingController();
  final TextEditingController _legal = TextEditingController();
  final TextEditingController _rules = TextEditingController();
  String? _linkedServerId;
  String? _linkedServerName;
  DateTime? _birthDate;
  bool _consent = false;
  bool _showErrors = false;
  final FocusNode _categoryFocus = FocusNode(debugLabel: 'create-category');
  final FocusNode _websiteFocus = FocusNode(debugLabel: 'create-website');
  final FocusNode _emailFocus = FocusNode(debugLabel: 'create-email');
  final FocusNode _phoneFocus = FocusNode(debugLabel: 'create-phone');
  final FocusNode _birthFocus = FocusNode(debugLabel: 'create-birth-date');
  final FocusNode _consentFocus = FocusNode(debugLabel: 'create-consent');
  bool _publishing = false;
  PagesFailure? _failure;
  String? _requestId;
  String? _requestKey;

  static String _currentUserId() {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  PagesCopy get _copy => PagesCopy(AppLocalizations.of(context));

  bool get _needsBirthDate => !(_profile?.creatorAgeVerified ?? false);

  /// What the Page will show from its first second: the account's own
  /// follower counter, shared with the Page (ADR-234). Existing followers
  /// are carried over, so the preview never promises 0 to an account that
  /// already has them.
  int get _followerCount => _profile?.accountFollowerCount ?? 0;

  /// A Creator's public follower list is open now and closes with the Page
  /// (ADR-234: the create transaction switches Creator audience off).
  ///
  /// `creatorAudienceVisible`, not `creatorAudienceEnabled`: the enabled
  /// flag is only the owner's stored preference, and the list is public only
  /// when the server also confirmed Creator Premium and age (the same gate
  /// every public follower surface reads). An account with the preference on
  /// but no public list has nothing to hide; for it the news is that the
  /// count becomes public, so it gets that sentence instead.
  bool get _audienceListOpen => _profile?.creatorAudienceVisible ?? false;

  /// Step 3 discloses the carry-over only when something changes for the
  /// account's audience: followers to carry, or a public list to close.
  bool get _discloseCarry => _followerCount > 0 || _audienceListOpen;

  String get _name => _profile?.displayName.trim().isNotEmpty == true
      ? _profile!.displayName
      : _copy.yourPage;

  @override
  void initState() {
    super.initState();
    _profileSub = _profileStream.listen((profile) {
      if (mounted) setState(() => _profile = profile);
    }, onError: (Object _, StackTrace _) {});
    for (final controller in [
      _description,
      _website,
      _email,
      _phone,
      _address,
      _hours,
      _legal,
      _rules,
    ]) {
      controller.addListener(_onEdit);
    }
  }

  void _onEdit() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_profileSub?.cancel());
    for (final node in [
      _categoryFocus,
      _websiteFocus,
      _emailFocus,
      _phoneFocus,
      _birthFocus,
      _consentFocus,
    ]) {
      node.dispose();
    }
    for (final controller in [
      _description,
      _website,
      _email,
      _phone,
      _address,
      _hours,
      _legal,
      _rules,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------ validity

  String? get _websiteError =>
      PageFieldRules.websiteOk(_website.text) ? null : _copy.websiteError;
  String? get _emailError =>
      PageFieldRules.emailOk(_email.text) ? null : _copy.emailError;
  String? get _phoneError =>
      PageFieldRules.phoneOk(_phone.text) ? null : _copy.phoneError;

  bool get _detailsValid =>
      _category != null &&
      PageCatalog.allowed(_kind, _category!) &&
      _description.text.trim().length <= PageFieldRules.description &&
      (_kind == PageKind.community ||
          (_websiteError == null &&
              _emailError == null &&
              _phoneError == null)) &&
      (!_needsBirthDate || _birthDate != null) &&
      _consent;

  // ------------------------------------------------------------ actions

  void _back() {
    if (_publishing) return;
    if (_step > 1) {
      setState(() {
        _step -= 1;
        _failure = null;
      });
      return;
    }
    unawaited(Navigator.of(context).maybePop());
  }

  void _next() {
    if (_step == 1) {
      setState(() {
        _step = 2;
        if (_category != null && !PageCatalog.allowed(_kind, _category!)) {
          _category = null;
        }
      });
      return;
    }
    if (_step == 2) {
      if (!_detailsValid) {
        setState(() => _showErrors = true);
        _revealFirstError();
        return;
      }
      setState(() {
        _step = 3;
        _failure = null;
      });
      return;
    }
    unawaited(_publish());
  }

  /// After an invalid "Dalej": the first invalid field is scrolled into
  /// view and focused (its error is read with it), and a screen reader hears
  /// what to fix even though nothing else on screen changed.
  void _revealFirstError() {
    final copy = _copy;
    final business = _kind == PageKind.business;
    final (FocusNode node, String message)? first = _category == null
        ? (_categoryFocus, business ? copy.chooseCategory : copy.chooseTopic)
        : business && _websiteError != null
        ? (_websiteFocus, _websiteError!)
        : business && _emailError != null
        ? (_emailFocus, _emailError!)
        : business && _phoneError != null
        ? (_phoneFocus, _phoneError!)
        : _needsBirthDate && _birthDate == null
        ? (_birthFocus, copy.chooseBirthDate)
        : !_consent
        ? (_consentFocus, copy.consentRequired)
        : null;
    if (first == null) return;
    final (node, message) = first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = node.context;
      if (target != null) {
        unawaited(
          Scrollable.ensureVisible(
            target,
            alignment: .2,
            duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
                ? Duration.zero
                : const Duration(milliseconds: 240),
          ),
        );
        node.requestFocus();
      }
      announcePages(context, message, assertive: true);
    });
  }

  PageBusinessInfo get _business => PageBusinessInfo(
    website: PageFieldRules.optional(_website.text),
    email: PageFieldRules.optional(_email.text),
    phone: PageFieldRules.optional(_phone.text),
    address: PageFieldRules.optional(_address.text),
    hours: PageFieldRules.optional(_hours.text),
    legalNotice: PageFieldRules.optional(_legal.text),
  );

  Future<void> _publish() async {
    if (_publishing) return;
    final category = _category;
    if (category == null) return;
    final business = _kind == PageKind.business ? _business : null;
    final rules = _kind == PageKind.community
        ? PageFieldRules.optional(_rules.text)
        : null;
    final linked = _kind == PageKind.community ? _linkedServerId : null;
    final birth = _needsBirthDate && _birthDate != null
        ? creatorBirthDateValue(_birthDate!)
        : null;
    // A retry of the SAME submission reuses its request id (the server's
    // ledger replays it); any change is a new request.
    final key = jsonEncode(<String, Object?>{
      'kind': _kind.wire,
      'category': category,
      'description': _description.text.trim(),
      'business': business?.toWire(),
      'rules': rules,
      'linked': linked,
      'adult': birth != null,
    });
    if (_requestKey != key) {
      _requestKey = key;
      _requestId = _service.newRequestId();
    }
    setState(() {
      _publishing = true;
      _failure = null;
    });
    try {
      final result = await _service.createPage(
        requestId: _requestId!,
        kind: _kind,
        category: category,
        description: _description.text.trim(),
        business: business,
        rules: rules,
        linkedServerId: linked,
        birthDate: birth,
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(_copy.pagePublished)));
      Navigator.of(
        context,
      ).pop(result.pageId.isEmpty ? _userId : result.pageId);
    } on PagesException catch (error) {
      if (!mounted) return;
      setState(() => _failure = error.failure);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  /// A refusal no retry can change: the flow can only be closed.
  /// `pageHasAudience` is not one of them any more: the server stopped
  /// refusing accounts with followers (owner decision 2026-09-29), so a
  /// stale answer during the rollout is worth another try.
  bool get _terminal => switch (_failure) {
    PagesFailure.adultRequired ||
    PagesFailure.accessRequired ||
    PagesFailure.pageExists ||
    PagesFailure.notEnabled => true,
    _ => false,
  };

  Future<void> _pickCategory() async {
    final picked = await pickPageCategory(
      context,
      kind: _kind,
      selected: _category,
    );
    if (picked != null && mounted) setState(() => _category = picked);
  }

  Future<void> _pickServer() async {
    final picked = await pickLinkedServer(
      context,
      userId: _userId,
      selected: _linkedServerId,
      servers: widget.serverStream,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _linkedServerId = picked.serverId;
      _linkedServerName = null;
    });
    if (picked.serverId != null) {
      final stream = widget.serverStream?.call();
      if (stream != null) {
        final servers = await stream.first;
        for (final server in servers) {
          if (server.id == picked.serverId && mounted) {
            setState(() => _linkedServerName = server.name);
          }
        }
      }
    }
  }

  Future<void> _pickBirthDate() async {
    final injected = widget.birthDatePicker;
    DateTime? picked;
    if (injected != null) {
      picked = await injected(context);
    } else {
      final range = creatorAgePickerRange((widget.clock ?? DateTime.now)());
      picked = await showDatePicker(
        context: context,
        initialDate: _birthDate ?? range.initialDate,
        firstDate: range.firstDate,
        lastDate: range.lastDate,
        helpText: _copy.birthDatePicker,
      );
    }
    if (picked != null && mounted) setState(() => _birthDate = picked);
  }

  void _openProfileEditor() {
    final profile = _profile;
    if (profile == null) return;
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => EditProfileScreen(profile: profile),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 1 && !_publishing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= CreatePageScreen.wideBreakpoint
            ? _wideLayout(context)
            : _phoneLayout(context),
      ),
    );
  }

  String get _primaryLabel => _step == 3 ? _copy.publishPage : _copy.next;

  Widget _phoneLayout(BuildContext context) {
    final palette = context.appPalette;
    final copy = _copy;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(
          key: const ValueKey('create-back'),
          onPressed: _back,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              copy.newPage,
              style: AppTypography.titleMedium.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              copy.stepOf(_step),
              key: const ValueKey('create-step-label'),
              style: AppTypography.overline.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
      // Scaffold pins this slot to the bottom of the window, behind the
      // keyboard (UI.md "Placement invariant", ADR-169): the wrapper lifts
      // Done and Dalej onto the keyboard, so they are never stranded under
      // it once the fields are filled.
      bottomNavigationBar: YoKeyboardSafeBottomBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const YoKeyboardDoneBar(),
            _BottomAction(
              child: _terminal
                  ? PageTonalButton(
                      key: const ValueKey('create-close'),
                      label: copy.close,
                      height: 52,
                      expand: true,
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : YoButton(
                      key: const ValueKey('create-primary'),
                      label: _primaryLabel,
                      height: 52,
                      isLoading: _publishing,
                      onPressed: _publishing ? null : _next,
                    ),
            ),
          ],
        ),
      ),
      body: ListView(
        key: ValueKey('create-step-$_step'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _StepProgress(step: _step),
          const SizedBox(height: 20),
          ..._stepBody(context, wide: false),
        ],
      ),
    );
  }

  Widget _wideLayout(BuildContext context) {
    final palette = context.appPalette;
    final copy = _copy;
    Widget stepTab(int n, String label) {
      final current = n == _step;
      return Container(
        padding: const EdgeInsets.only(bottom: 10),
        margin: const EdgeInsetsDirectional.only(end: 28),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: current
                  ? palette.interactiveForeground
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          '$n  $label',
          style: AppTypography.labelLarge.copyWith(
            color: current ? palette.textPrimary : palette.textTertiary,
            fontWeight: current ? FontWeight.w700 : FontWeight.w600,
            fontSize: 14,
          ),
        ),
      );
    }

    final chrome = <Widget>[
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('create-back'),
          onPressed: _back,
          style: TextButton.styleFrom(
            foregroundColor: palette.textSecondary,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          icon: const Icon(Icons.chevron_left_rounded),
          label: Text(
            _step > 1 ? copy.goBack : widget.backLabel ?? copy.goBack,
          ),
        ),
      ),
      const SizedBox(height: 20),
      Semantics(
        label: copy.stepOf(_step),
        child: Wrap(
          key: const ValueKey('create-step-tabs'),
          children: [
            stepTab(1, copy.stepKind),
            stepTab(2, copy.stepDetails),
            stepTab(3, copy.stepPreview),
          ],
        ),
      ),
      Container(height: 1, color: palette.hairline),
    ];
    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 140,
          child: PageTonalButton(
            key: const ValueKey('create-secondary'),
            label: _step == 1 || _terminal ? copy.cancel : copy.goBack,
            height: 48,
            expand: true,
            onPressed: _terminal
                ? () => Navigator.of(context).maybePop()
                : _back,
          ),
        ),
        if (!_terminal)
          SizedBox(
            width: 200,
            child: YoButton(
              key: const ValueKey('create-primary'),
              label: _primaryLabel,
              height: 48,
              isLoading: _publishing,
              onPressed: _publishing ? null : _next,
            ),
          ),
      ],
    );

    // Scaffold hands the body's bottom safe-area inset to ANY
    // bottomNavigationBar, even one that draws nothing, so the Done bar is
    // attached only while the software keyboard is up. At rest the body's
    // SafeArea keeps the home-indicator / gesture inset.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: palette.background,
      // Wróć / Dalej scroll with the form here; Done is the way out of a
      // multi-line field on a touch tablet (it renders nothing with a
      // hardware keyboard).
      bottomNavigationBar: keyboardUp
          ? const YoKeyboardSafeBottomBar(child: YoKeyboardDoneBar())
          : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= CreatePageScreen.splitBreakpoint) {
              return _framedLayout(
                context,
                constraints.maxWidth,
                chrome: chrome,
                actions: actions,
              );
            }
            return SingleChildScrollView(
              key: ValueKey('create-step-$_step'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: CreatePageScreen.wideColumn,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...chrome,
                      const SizedBox(height: 36),
                      ..._stepBody(context, wide: true),
                      const SizedBox(height: 36),
                      actions,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// From [CreatePageScreen.splitBreakpoint] every step shares one centred
  /// [CreatePageScreen.splitFrame] (UI.md `feed`), so the back link, the step
  /// tabs and the title stand still while the steps change. Steps 1 and 3
  /// keep their approved [CreatePageScreen.wideColumn] column at the frame's
  /// start with the actions at its foot; step 2 splits (variant C).
  ///
  /// One scroll view scrolls the whole page, so the wheel works anywhere.
  /// Keyboard order is explicit: the header, then the step's form with
  /// Wróć / Dalej, then (step 2) the preview column's change-name link.
  Widget _framedLayout(
    BuildContext context,
    double width, {
    required List<Widget> chrome,
    required Widget actions,
  }) {
    final gutter = math.max(24.0, (width - CreatePageScreen.splitFrame) / 2);
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...chrome,
        const SizedBox(height: 36),
        _startColumn(_stepTitle(context, wide: true)),
      ],
    );
    final body = _step == 2
        ? _splitStep2(context, actions: actions)
        : SliverToBoxAdapter(
            child: _inOrder(
              1,
              _startColumn(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ..._stepContent(context, wide: true),
                    const SizedBox(height: 36),
                    actions,
                  ],
                ),
              ),
            ),
          );
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: CustomScrollView(
        key: ValueKey('create-step-$_step'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter, 28, gutter, 0),
            sliver: SliverToBoxAdapter(child: _inOrder(0, header)),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 40),
            sliver: body,
          ),
        ],
      ),
    );
  }

  /// [child] at most [CreatePageScreen.wideColumn] wide, at the frame's start.
  static Widget _startColumn(Widget child) => Align(
    alignment: AlignmentDirectional.topStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: CreatePageScreen.wideColumn),
      child: child,
    ),
  );

  /// [child] as one unit of the framed layout's keyboard order.
  static Widget _inOrder(double order, Widget child) => FocusTraversalOrder(
    order: NumericFocusOrder(order),
    child: FocusTraversalGroup(child: child),
  );

  /// Step 2 in the frame (variant C, approved 2026-09-28): the form, with
  /// Wróć / Dalej at its foot, on the left; on the right two captioned
  /// previews, the Page as it appears on the Content wall (the suggestion
  /// row) and its profile header (step 3's), with the change-name link. The
  /// right column pins [_stickyTop] under the window's top edge while the
  /// form scrolls, and scrolls with the page if it is taller than the window.
  Widget _splitStep2(BuildContext context, {required Widget actions}) {
    final copy = _copy;
    final palette = context.appPalette;
    final form = Padding(
      key: const ValueKey('create-form-column'),
      padding: const EdgeInsets.only(top: _stickyTop),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._step2Fields(context),
          const SizedBox(height: 36),
          actions,
        ],
      ),
    );
    final card = PageCard(
      pageId: _userId,
      displayName: _name,
      kind: _kind,
      category: _category ?? '',
      followerCount: _followerCount,
      onYoVoiceSinceMs: null,
      viewerFollows: false,
      lastPostAtMs: null,
    );
    final preview = Padding(
      key: const ValueKey('create-preview-column'),
      padding: const EdgeInsets.only(top: _stickyTop),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A picture only: inert, out of the focus order and hidden from
          // screen readers with its caption (the form says everything it
          // shows), like the header below.
          ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _overline(context, copy.previewOnWall),
                ExcludeFocus(
                  child: IgnorePointer(
                    child: YoCard(
                      key: const ValueKey('create-preview-wall'),
                      semanticButton: false,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: PageListRow(
                        card: card,
                        follow: PageFollowBinding(
                          follows: (_) => false,
                          busy: (_) => false,
                          onToggle: (_) {},
                        ),
                        onOpen: () {},
                        showMeta: false,
                        divider: false,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _overline(context, copy.previewProfile),
          _InertHeader(
            pageId: _userId,
            name: _name,
            kind: _kind,
            followerCount: _followerCount,
            description: _description.text.trim(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('create-change-profile'),
              onPressed: _profile == null ? null : _openProfileEditor,
              style: TextButton.styleFrom(
                foregroundColor: palette.interactiveForeground,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(copy.changeNameAndPhoto),
            ),
          ),
        ],
      ),
    );
    return SliverCrossAxisGroup(
      slivers: [
        SliverCrossAxisExpanded(
          flex: 1,
          sliver: SliverToBoxAdapter(child: _inOrder(1, form)),
        ),
        const SliverConstrainedCrossAxis(
          maxExtent: 64,
          sliver: SliverToBoxAdapter(),
        ),
        SliverConstrainedCrossAxis(
          maxExtent: 360,
          sliver: _StickySliver(child: _inOrder(2, preview)),
        ),
      ],
    );
  }

  /// The pinned column's distance from the window's top edge.
  static const double _stickyTop = 24;

  List<Widget> _stepBody(BuildContext context, {required bool wide}) => [
    _stepTitle(context, wide: wide),
    ..._stepContent(context, wide: wide),
  ];

  Widget _stepTitle(BuildContext context, {required bool wide}) {
    final copy = _copy;
    return switch (_step) {
      1 => _title(
        context,
        copy.step1Title,
        wide ? copy.step1LeadWide : copy.step1Lead,
        wide,
      ),
      2 => _title(context, copy.step2Title, copy.step2Lead, wide),
      _ => _title(context, copy.step3Title, copy.step3Lead, wide),
    };
  }

  /// The step under its title.
  List<Widget> _stepContent(BuildContext context, {required bool wide}) =>
      switch (_step) {
        1 => _step1(context, wide: wide),
        2 => _step2(context),
        _ => _step3(context),
      };

  Widget _title(BuildContext context, String title, String lead, bool wide) {
    final palette = context.appPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: AppTypography.screenTitle.copyWith(
              color: palette.textPrimary,
              fontSize: wide ? 30 : null,
              letterSpacing: wide ? -.8 : null,
            ),
          ),
        ),
        SizedBox(height: wide ? 10 : 8),
        Text(
          lead,
          style: AppTypography.bodyMedium.copyWith(
            color: palette.textSecondary,
            fontSize: wide ? 15 : 14,
            height: wide ? 1.5 : 1.45,
          ),
        ),
      ],
    );
  }

  // ---- Step 1 --------------------------------------------------------------

  List<Widget> _step1(BuildContext context, {required bool wide}) {
    final copy = _copy;
    final business = _KindCard(
      key: const ValueKey('create-kind-business'),
      icon: Icons.storefront_outlined,
      title: copy.businessTitle,
      example: copy.businessExample,
      bullets: copy.businessBullets,
      selected: _kind == PageKind.business,
      vertical: wide,
      onTap: () => setState(() => _kind = PageKind.business),
    );
    final community = _KindCard(
      key: const ValueKey('create-kind-community'),
      icon: Icons.groups_2_outlined,
      title: copy.communityTitle,
      example: copy.communityExample,
      bullets: copy.communityBullets,
      selected: _kind == PageKind.community,
      vertical: wide,
      onTap: () => setState(() => _kind = PageKind.community),
    );
    return [
      SizedBox(height: wide ? 28 : 24),
      if (wide)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: business),
              const SizedBox(width: 24),
              Expanded(child: community),
            ],
          ),
        )
      else ...[
        business,
        const SizedBox(height: 12),
        community,
      ],
      SizedBox(height: wide ? 20 : 16),
      PageFootnote(copy.step1Info, padding: EdgeInsets.zero),
    ];
  }

  // ---- Step 2 --------------------------------------------------------------

  Widget _overline(BuildContext context, String text, {Widget? trailing}) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 12, start: 2),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text.toUpperCase(),
                style: AppTypography.overline.copyWith(
                  color: palette.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _publicHelper(BuildContext context, [String? extra]) {
    final palette = context.appPalette;
    final copy = _copy;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.public_rounded,
            size: 14,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            extra == null ? copy.publicHelper : '${copy.publicHelper} · $extra',
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(
    BuildContext context, {
    required Key key,
    required String label,
    required TextEditingController controller,
    String? publicExtra,
    int maxLines = 1,
    int? maxLength,
    int? limit,
    String? hint,
    String? error,
    TextInputType? keyboard,
    FocusNode? focusNode,
  }) {
    final palette = context.appPalette;
    // A one-line value (the server refuses line breaks in it) still wraps on
    // screen and the field grows with it (its character limit bounds it): at
    // a large text size a narrow column would otherwise scroll the value
    // sideways and cut its start ("n–Pt 7:00…"). Enter stays the keyboard's
    // action and never inserts a line break, as in a one-line field.
    final multiLine = maxLines > 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        key: key,
        controller: controller,
        focusNode: focusNode,
        maxLines: multiLine ? maxLines : null,
        minLines: multiLine ? 3 : 1,
        maxLength: maxLength,
        inputFormatters: [
          if (!multiLine) FilteringTextInputFormatter.singleLineFormatter,
          if (limit != null) LengthLimitingTextInputFormatter(limit),
        ],
        keyboardType: multiLine
            ? TextInputType.multiline
            : keyboard ?? TextInputType.text,
        // R1 (UI.md): a one-line field is always followed by another field
        // here, so Return walks the form; the long-form ones keep Return as
        // a line break and finish with the Done bar (R3).
        textInputAction: multiLine ? null : TextInputAction.next,
        style: AppTypography.bodyLarge.copyWith(
          color: palette.textPrimary,
          fontSize: 16,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          errorText: error,
          errorMaxLines: 3,
          helper: error == null ? _publicHelper(context, publicExtra) : null,
          counterStyle: AppTypography.bodySmall.copyWith(
            color: palette.textTertiary,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _pickerField(
    BuildContext context, {
    required Key key,
    required String label,
    required String? value,
    required VoidCallback onTap,
    String? helperText,
    Widget? helper,
    String? error,
    IconData suffix = Icons.expand_more_rounded,
    FocusNode? focusNode,
  }) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        button: true,
        child: InkWell(
          key: key,
          focusNode: focusNode,
          onTap: onTap,
          borderRadius: AppRadius.md,
          child: InputDecorator(
            isEmpty: value == null,
            decoration: InputDecoration(
              labelText: label,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              helper: error == null ? helper : null,
              helperText: error == null && helper == null ? helperText : null,
              helperMaxLines: 3,
              errorMaxLines: 3,
              errorText: error,
              suffixIcon: Icon(suffix, color: palette.textSecondary),
            ),
            child: Text(
              value ?? '',
              style: AppTypography.bodyLarge.copyWith(
                color: palette.textPrimary,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _livePreview() {
    final copy = _copy;
    final meta = _category == null
        ? copy.kindLabel(_kind)
        : '${copy.kindLabel(_kind)} · ${copy.categoryLabel(_category!)}';
    return _LivePreview(
      pageId: _userId,
      name: _name,
      kind: _kind,
      meta: meta,
      onEditProfile: _profile == null ? null : _openProfileEditor,
    );
  }

  /// Step 2 in one column (phone and below the frame): the live preview
  /// card above the fields.
  List<Widget> _step2(BuildContext context) => [
    const SizedBox(height: 20),
    _livePreview(),
    const SizedBox(height: 24),
    ..._step2Fields(context),
  ];

  /// Step 2's fields, from Kategoria to the consent row.
  List<Widget> _step2Fields(BuildContext context) {
    final copy = _copy;
    final palette = context.appPalette;
    final show = _showErrors;
    final categoryLabel = _category == null
        ? null
        : copy.categoryLabel(_category!);
    final children = <Widget>[
      _pickerField(
        context,
        key: const ValueKey('create-category'),
        focusNode: _categoryFocus,
        label: '${copy.categoryField(_kind)} *',
        value: categoryLabel,
        onTap: () => unawaited(_pickCategory()),
        helper: _publicHelper(context),
        error: show && _category == null
            ? (_kind == PageKind.business
                  ? copy.chooseCategory
                  : copy.chooseTopic)
            : null,
      ),
      _field(
        context,
        key: const ValueKey('create-description'),
        label: copy.descriptionLabel,
        controller: _description,
        maxLines: 4,
        maxLength: PageFieldRules.description,
      ),
    ];
    if (_kind == PageKind.business) {
      children.addAll([
        const SizedBox(height: 8),
        _overline(
          context,
          copy.contactOverline,
          trailing: Text(
            copy.allOptional,
            style: AppTypography.bodySmall.copyWith(
              color: palette.textTertiary,
              fontSize: 12,
            ),
          ),
        ),
        _field(
          context,
          key: const ValueKey('create-website'),
          focusNode: _websiteFocus,
          label: copy.websiteLabel,
          controller: _website,
          publicExtra: copy.httpsOnly,
          keyboard: TextInputType.url,
          limit: PageFieldRules.website,
          error: _website.text.isEmpty ? null : _websiteError,
        ),
        _field(
          context,
          key: const ValueKey('create-email'),
          focusNode: _emailFocus,
          label: copy.contactEmailLabel,
          controller: _email,
          keyboard: TextInputType.emailAddress,
          limit: PageFieldRules.email,
          error: _email.text.isEmpty ? null : _emailError,
        ),
        _field(
          context,
          key: const ValueKey('create-phone'),
          focusNode: _phoneFocus,
          label: copy.phoneLabel,
          controller: _phone,
          keyboard: TextInputType.phone,
          limit: 32,
          error: _phone.text.isEmpty || !show ? null : _phoneError,
        ),
        _field(
          context,
          key: const ValueKey('create-address'),
          label: copy.addressOrAreaLabel,
          controller: _address,
          limit: PageFieldRules.address,
        ),
        _field(
          context,
          key: const ValueKey('create-hours'),
          label: copy.hoursLabel,
          controller: _hours,
          limit: PageFieldRules.hours,
        ),
        _field(
          context,
          key: const ValueKey('create-legal'),
          label: copy.legalNoticeFieldLabel,
          controller: _legal,
          hint: copy.legalNoticeHint,
          maxLines: 3,
          limit: PageFieldRules.legalNotice,
        ),
      ]);
    } else {
      children.addAll([
        _field(
          context,
          key: const ValueKey('create-rules'),
          label: copy.rulesTitle,
          controller: _rules,
          maxLines: 4,
          maxLength: PageFieldRules.rules,
        ),
        _pickerField(
          context,
          key: const ValueKey('create-linked-server'),
          label: copy.linkedServerLabel,
          value: _linkedServerId == null
              ? copy.noLinkedServer
              : _linkedServerName ?? copy.linkedServerLabel,
          onTap: () => unawaited(_pickServer()),
          helper: _publicHelper(context, copy.linkedServerHelper),
        ),
      ]);
    }
    children.addAll([
      const SizedBox(height: 8),
      _overline(context, copy.confirmationOverline),
      if (_needsBirthDate)
        _pickerField(
          context,
          key: const ValueKey('create-birth-date'),
          focusNode: _birthFocus,
          label: copy.birthDateLabel,
          value: _birthDate == null
              ? null
              : AppLocalizations.of(context).calendarDate(_birthDate!),
          onTap: () => unawaited(_pickBirthDate()),
          suffix: Icons.calendar_today_outlined,
          helperText: copy.birthDateHelper,
          error: show && _birthDate == null ? copy.chooseBirthDate : null,
        ),
      _ConsentRow(
        key: const ValueKey('create-consent'),
        focusNode: _consentFocus,
        value: _consent,
        text: _kind == PageKind.business
            ? copy.consentBusiness
            : copy.consentCommunity,
        error: show && !_consent ? copy.consentRequired : null,
        onChanged: (value) => setState(() => _consent = value),
      ),
    ]);
    return children;
  }

  // ---- Step 3 --------------------------------------------------------------

  List<Widget> _step3(BuildContext context) {
    final copy = _copy;
    final palette = context.appPalette;
    final failure = _failure;
    return [
      const SizedBox(height: 18),
      _overline(context, copy.previewOverline),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _InertHeader(
            pageId: _userId,
            name: _name,
            kind: _kind,
            followerCount: _followerCount,
            description: _description.text.trim(),
          ),
        ),
      ),
      // The count is already in the preview ("Firma · 1,2 tys.
      // obserwujących"); the caption under it, as wide as the preview, says
      // where it comes from (ADR-234, variant C, owner decision 2026-09-29).
      // With no followers and no public list nothing changes for the
      // audience, and step 3 stays as it was.
      if (_discloseCarry)
        Center(
          child: ConstrainedBox(
            // The preview is its 390 layout, fitted down, never scaled up.
            constraints: const BoxConstraints(
              maxWidth: _InertHeader.layoutWidth,
            ),
            child: PageFootnote(
              copy.carryCaption(_followerCount, listClosing: _audienceListOpen),
              key: const ValueKey('create-carry'),
              icon: Icons.arrow_upward_rounded,
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
              scaleIcon: true,
              semanticsLabel: copy.carryCaptionLabel(
                _followerCount,
                listClosing: _audienceListOpen,
              ),
            ),
          ),
        ),
      const SizedBox(height: 24),
      _overline(context, copy.whatHappens),
      _WhatRow(Icons.public_rounded, copy.whatFollow),
      _WhatRow(Icons.account_circle_outlined, copy.whatProfile),
      _WhatRow(Icons.workspace_premium_outlined, copy.whatLapse),
      if (failure != null) ...[
        const SizedBox(height: 4),
        Container(
          key: const ValueKey('create-error'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.dangerSurface,
            borderRadius: AppRadius.md,
            border: Border.all(
              color: palette.dangerForeground.withValues(alpha: .35),
            ),
          ),
          child: Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 20,
                  color: palette.dangerForeground,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        copy.publishFailed,
                        style: AppTypography.bodyMedium.copyWith(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        copy.manageError(failure),
                        style: AppTypography.bodySmall.copyWith(
                          color: palette.textPrimary.withValues(alpha: .86),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ];
  }
}

// ---------------------------------------------------------------------------
// Pieces (ported from the approved create A / R2 renders)
// ---------------------------------------------------------------------------

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 1; i <= 3; i++) ...[
            if (i > 1) const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: AppRadius.pill,
                  color: i <= step
                      ? palette.interactiveForeground
                      : palette.border,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? palette.interactiveForeground
                  : palette.borderStrong,
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: selected
              ? Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.interactiveForeground,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.icon,
    required this.title,
    required this.example,
    required this.bullets,
    required this.selected,
    required this.vertical,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String example;
  final List<String> bullets;
  final bool selected;
  final bool vertical;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final titleText = Text(
      title,
      style: AppTypography.titleMedium.copyWith(
        color: palette.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -.2,
      ),
    );
    final exampleText = Text(
      example,
      style: AppTypography.bodySmall.copyWith(
        color: palette.textPrimary.withValues(alpha: .78),
        fontSize: 13,
        height: 1.3,
      ),
    );
    final bulletRows = [
      for (final bullet in bullets)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: palette.interactiveForeground,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  bullet,
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
    final Widget body;
    if (vertical) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageGlyph(icon, size: 52),
              const Spacer(),
              Transform.translate(
                offset: const Offset(0, -8),
                child: _Radio(selected: selected),
              ),
            ],
          ),
          const SizedBox(height: 16),
          titleText,
          const SizedBox(height: 4),
          exampleText,
          const SizedBox(height: 10),
          ...bulletRows,
        ],
      );
    } else {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageGlyph(icon, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 1),
                titleText,
                const SizedBox(height: 3),
                exampleText,
                const SizedBox(height: 8),
                ...bulletRows,
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -10),
            child: _Radio(selected: selected),
          ),
        ],
      );
    }
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: YoCard(
        selected: selected,
        onTap: onTap,
        semanticButton: false,
        padding: vertical
            ? const EdgeInsets.fromLTRB(20, 20, 12, 22)
            : const EdgeInsets.fromLTRB(16, 16, 6, 16),
        child: body,
      ),
    );
  }
}

class _LivePreview extends StatelessWidget {
  const _LivePreview({
    required this.pageId,
    required this.name,
    required this.kind,
    required this.meta,
    required this.onEditProfile,
  });

  final String pageId;
  final String name;
  final PageKind kind;
  final String meta;
  final VoidCallback? onEditProfile;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    return YoCard(
      key: const ValueKey('create-live-preview'),
      semanticButton: false,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PageFace(pageId: pageId, name: name, kind: kind, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NameWithVipMark(
                      uid: pageId,
                      name: name,
                      style: AppTypography.titleMedium.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      key: const ValueKey('create-preview-meta'),
                      style: AppTypography.bodySmall.copyWith(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onEditProfile,
              style: TextButton.styleFrom(
                foregroundColor: palette.interactiveForeground,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(copy.changeNameAndPhoto),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.value,
    required this.text,
    required this.onChanged,
    this.error,
    this.focusNode,
    super.key,
  });

  final FocusNode? focusNode;
  final bool value;
  final String text;
  final String? error;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return MergeSemantics(
      child: InkWell(
        focusNode: focusNode,
        onTap: () => onChanged(!value),
        borderRadius: AppRadius.md,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Checkbox(
                value: value,
                onChanged: (next) => onChanged(next ?? false),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 11, bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.textPrimary.withValues(alpha: .86),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        error!,
                        style: AppTypography.bodySmall.copyWith(
                          color: palette.dangerForeground,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhatRow extends StatelessWidget {
  const _WhatRow(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageGlyph(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                text,
                style: AppTypography.bodyMedium.copyWith(
                  color: palette.textPrimary.withValues(alpha: .9),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 3's preview: the approved profile B header laid out at the phone
/// width (390) and scaled to the card, so it is exactly what visitors get.
/// Inert, out of the focus order and hidden from screen readers (the steps
/// say what happens); its buttons are pictures, not controls.
class _InertHeader extends StatelessWidget {
  const _InertHeader({
    required this.pageId,
    required this.name,
    required this.kind,
    required this.followerCount,
    required this.description,
  });

  final String pageId;
  final String name;
  final PageKind kind;

  /// The account's followers, which become the Page's (ADR-234).
  final int followerCount;
  final String description;

  /// The phone width the header is laid out at before it is fitted to the
  /// card; step 3's caption under it is never wider.
  static const double layoutWidth = 390;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    const cover = 150.0;
    const face = 80.0;
    final tonal = AppFinish.tonalNeutral(palette);
    final header = SizedBox(
      width: layoutWidth,
      child: ColoredBox(
        color: palette.background,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: cover + face / 2 + 3,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: cover,
                    child: PageCover(pageId: pageId, scrim: false),
                  ),
                  Positioned(
                    left: 13,
                    top: cover - face / 2 - 3,
                    child: PageFace(
                      pageId: pageId,
                      name: name,
                      kind: kind,
                      size: face,
                      ring: 3,
                      ringColor: palette.background,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: MediaQuery.withNoTextScaling(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NameWithVipMark(
                      uid: pageId,
                      name: name,
                      maxLines: 2,
                      style: AppTypography.screenTitle.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      copy.headerMeta(kind, followerCount),
                      style: AppTypography.bodySmall.copyWith(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMedium.copyWith(
                          fontSize: 14,
                          height: 1.5,
                          color: palette.textPrimary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: YoGradientFilledButton(
                            onPressed: () {},
                            minimumSize: const Size(132, 44),
                            icon: const Icon(Icons.add_rounded, size: 20),
                            child: Text(copy.follow),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {},
                          style: tonal.merge(
                            OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                            ),
                          ),
                          icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                          ),
                          label: Text(copy.message),
                        ),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          onPressed: () {},
                          style: tonal.merge(
                            IconButton.styleFrom(
                              minimumSize: const Size(44, 44),
                              fixedSize: const Size(44, 44),
                            ),
                          ),
                          icon: const Icon(Icons.more_horiz_rounded, size: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return ExcludeFocus(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: ClipRRect(
            key: const ValueKey('create-preview-header'),
            borderRadius: AppRadius.block,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: AppRadius.block,
                border: Border.all(color: palette.border),
              ),
              child: FittedBox(fit: BoxFit.fitWidth, child: header),
            ),
          ),
        ),
      ),
    );
  }
}

/// A box that sticks to the top of the viewport while the rest of its
/// [SliverCrossAxisGroup] scrolls, and that the group pushes up at its end
/// so it never hangs below the form (CSS `position: sticky` with `top: 0`;
/// the box brings its own top padding). It is painted and hit-tested where
/// it sticks, so what it holds stays usable. When the box is taller than the
/// viewport it scrolls like any other content, so nothing in it is ever out
/// of reach.
class _StickySliver extends SingleChildRenderObjectWidget {
  const _StickySliver({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderStickySliver();
}

class _RenderStickySliver extends RenderSliverSingleBoxAdapter {
  bool _pinned = true;

  @override
  double childMainAxisPosition(RenderBox child) =>
      _pinned ? 0 : -constraints.scrollOffset;

  @override
  void performLayout() {
    final box = child;
    if (box == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    box.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final extent = box.size.height;
    _pinned = extent <= constraints.viewportMainAxisExtent;
    if (!_pinned) {
      final paintExtent = calculatePaintOffset(
        constraints,
        from: 0,
        to: extent,
      );
      geometry = SliverGeometry(
        scrollExtent: extent,
        paintExtent: paintExtent,
        maxPaintExtent: extent,
        hitTestExtent: paintExtent,
        cacheExtent: calculateCacheOffset(constraints, from: 0, to: extent),
        hasVisualOverflow:
            extent > constraints.remainingPaintExtent ||
            constraints.scrollOffset > 0,
      );
      setChildParentData(box, constraints, geometry!);
      return;
    }
    (box.parentData! as SliverPhysicalParentData).paintOffset = Offset.zero;
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintOrigin: constraints.overlap,
      paintExtent: math.min(
        extent,
        constraints.remainingPaintExtent - constraints.overlap,
      ),
      layoutExtent: (extent - constraints.scrollOffset).clamp(
        0,
        constraints.remainingPaintExtent,
      ),
      maxPaintExtent: extent,
      cacheExtent: calculateCacheOffset(constraints, from: 0, to: extent),
      hasVisualOverflow: true,
    );
  }
}
