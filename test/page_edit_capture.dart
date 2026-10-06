// ignore_for_file: avoid_print
// "Edytuj stronę" (pageEdit A) frame harness.
//
// Renders the REAL `PageEditScreen` and the shortened `PageSettingsScreen`
// through their constructor seams: no Firebase app, no callable. The cover
// and the photo resolve through the production media path
// (`ProfileMediaService` grant -> `NetworkImage`) against a local HTTP fake
// that serves two generated pictures (a pottery shelf and a vase, the
// fixture of the owner-approved sheet `6_pageEdit`), so frames can be laid
// beside that sheet.
//
// Matrix: 390x844 (status bar 47), 768x1024 (status bar 24) and 1440x900
// inside the desktop shell (the real sidebar); Dark and Pearl; clean, unsaved,
// scrolled to KONTAKT, the community variant, the read-only (lapsed) form, a
// failed save, 200 % text and an Arabic (RTL) spot check; plus the short
// settings list and one frame through the real `ContentScreen` navigator (the
// Treści panel stepping aside).
//
// The filename has no `_test` suffix, so the ordinary suite skips it. Run:
//
//   flutter test test/page_edit_capture.dart --concurrency=1 \
//     --dart-define=YO_CAPTURE_DIR=<evidence>/page-edit [--dart-define=ONLY=edit_390]
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/pages_local_store.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_navigation.dart';
import 'package:yovoice/features/pages/presentation/pages_flows.dart';
import 'package:yovoice/features/pages/presentation/screens/content_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_edit_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_profile_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_settings_screen.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'support/material_icons_font.dart';

const _outDir = String.fromEnvironment(
  'YO_CAPTURE_DIR',
  defaultValue: 'test/.screenshots/page-edit',
);
const _only = String.fromEnvironment('ONLY');
const _dpr = 2.0;
final _capture = GlobalKey();
final DateTime _now = DateTime.utc(2026, 10, 3, 19, 45);

const _pageName = 'Pracownia Glina';
const _desc =
    'Ręcznie toczona ceramika użytkowa: kubki, miski i wazony. Warsztaty '
    'toczenia na kole w każdy czwartek o 18:00 i w soboty o 11:00. Pracownia '
    'przy ul. Garncarskiej 8 w Gdańsku, zapraszamy od wtorku do soboty 11–18.';

// ------------------------------------------------------------ fonts, pictures

Future<void> _fonts() async {
  final inter = FontLoader('Inter')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('assets/fonts/InterVariable.ttf').readAsBytesSync(),
        ),
      ),
    );
  await inter.load();
  await loadMaterialIconsFont();
}

Color _shade(Color c, double f) =>
    Color.lerp(c, f < 0 ? Colors.black : Colors.white, f.abs())!;

void _pot(
  Canvas canvas,
  Offset base,
  double w,
  double h,
  int shape,
  Color body,
  Color glaze,
) {
  Path path;
  switch (shape) {
    case 0: // vase
      path = Path()
        ..moveTo(-.28 * w, 0)
        ..cubicTo(-.62 * w, -.25 * h, -.6 * w, -.62 * h, -.2 * w, -.8 * h)
        ..cubicTo(-.12 * w, -.86 * h, -.16 * w, -.94 * h, -.24 * w, -h)
        ..lineTo(.24 * w, -h)
        ..cubicTo(.16 * w, -.94 * h, .12 * w, -.86 * h, .2 * w, -.8 * h)
        ..cubicTo(.6 * w, -.62 * h, .62 * w, -.25 * h, .28 * w, 0)
        ..close();
    case 1: // bowl
      path = Path()
        ..moveTo(-.5 * w, -h)
        ..cubicTo(-.48 * w, -.3 * h, -.3 * w, -.04 * h, -.16 * w, 0)
        ..lineTo(.16 * w, 0)
        ..cubicTo(.3 * w, -.04 * h, .48 * w, -.3 * h, .5 * w, -h)
        ..close();
    case 2: // mug
      path = Path()
        ..addRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(-.38 * w, -h, .38 * w, 0),
            bottomLeft: Radius.circular(.14 * w),
            bottomRight: Radius.circular(.14 * w),
            topLeft: Radius.circular(.03 * w),
            topRight: Radius.circular(.03 * w),
          ),
        );
    default: // jug
      path = Path()
        ..moveTo(-.3 * w, 0)
        ..cubicTo(-.44 * w, -.2 * h, -.44 * w, -.55 * h, -.3 * w, -.68 * h)
        ..cubicTo(-.14 * w, -.76 * h, -.12 * w, -.86 * h, -.15 * w, -h)
        ..lineTo(.15 * w, -h)
        ..cubicTo(.12 * w, -.86 * h, .14 * w, -.76 * h, .3 * w, -.68 * h)
        ..cubicTo(.44 * w, -.55 * h, .44 * w, -.2 * h, .3 * w, 0)
        ..close();
  }
  path = path.shift(base);
  final bounds = path.getBounds();
  canvas.drawOval(
    Rect.fromCenter(
      center: base + Offset(w * .04, h * .01),
      width: w,
      height: h * .09,
    ),
    Paint()
      ..color = Colors.black.withValues(alpha: .35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * .03),
  );
  if (shape == 2) {
    canvas.drawArc(
      Rect.fromCenter(
        center: base + Offset(.42 * w, -.52 * h),
        width: .34 * w,
        height: .46 * h,
      ),
      -math.pi / 2,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .07 * w
        ..strokeCap = StrokeCap.round
        ..color = _shade(body, -.12),
    );
  }
  Shader shader(Color c) => LinearGradient(
    colors: [_shade(c, .16), c, _shade(c, -.28)],
    stops: const [0, .42, 1],
  ).createShader(bounds);
  canvas.drawPath(path, Paint()..shader = shader(body));
  canvas.save();
  canvas.clipPath(path);
  final glazeBottom = bounds.top + bounds.height * .46;
  final drip = Path()..moveTo(bounds.left, bounds.top);
  drip.lineTo(bounds.right, bounds.top);
  drip.lineTo(bounds.right, glazeBottom);
  const waves = 5;
  for (var i = waves; i > 0; i--) {
    final x1 = bounds.left + bounds.width * i / waves;
    final x0 = bounds.left + bounds.width * (i - 1) / waves;
    drip.quadraticBezierTo(
      (x0 + x1) / 2,
      glazeBottom + bounds.height * (i.isEven ? .1 : .04),
      x0,
      glazeBottom,
    );
  }
  drip.close();
  canvas.drawPath(drip, Paint()..shader = shader(glaze));
  canvas.restore();
}

const _terracotta = Color(0xFFC8693F);
const _cream = Color(0xFFEDE3D2);
const _ochre = Color(0xFFD9A441);
const _blue = Color(0xFF2F4B6E);
const _sage = Color(0xFF8FA58E);
const _clay = Color(0xFFB98562);

void _paintBanner(Canvas canvas, Size size) {
  final w = size.width, h = size.height;
  final r = Offset.zero & size;
  canvas.drawRect(
    r,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF6C8676), Color(0xFF465C50), Color(0xFF2E3E36)],
      ).createShader(r),
  );
  for (final f in [.50, .96]) {
    final y = h * f;
    final shelf = Rect.fromLTWH(0, y, w, h * .045);
    canvas.drawRect(
      shelf,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFB07A4C), Color(0xFF7A4F2E)],
        ).createShader(shelf),
    );
  }
  final top = <(double, double, double, int, Color, Color)>[
    (.07, .12, .30, 0, _terracotta, _cream),
    (.17, .13, .16, 1, _cream, _blue),
    (.27, .08, .22, 2, _ochre, _cream),
    (.36, .10, .36, 3, _clay, _sage),
    (.47, .14, .15, 1, _terracotta, _ochre),
    (.58, .09, .22, 2, _cream, _terracotta),
    (.67, .12, .32, 0, _blue, _cream),
    (.78, .08, .20, 2, _sage, _cream),
    (.87, .11, .34, 3, _terracotta, _blue),
    (.96, .12, .14, 1, _ochre, _cream),
  ];
  for (final (x, pw, ph, s, b, g) in top) {
    _pot(canvas, Offset(w * x, h * .50), w * pw * .62, h * ph, s, b, g);
  }
  final low = <(double, double, double, int, Color, Color)>[
    (.04, .10, .30, 3, _blue, _cream),
    (.13, .09, .20, 2, _terracotta, _cream),
    (.23, .13, .15, 1, _sage, _cream),
    (.33, .12, .33, 0, _ochre, _terracotta),
    (.44, .08, .21, 2, _cream, _blue),
    (.53, .12, .29, 0, _clay, _cream),
    (.63, .13, .15, 1, _cream, _terracotta),
    (.73, .10, .34, 3, _cream, _ochre),
    (.83, .08, .21, 2, _blue, _cream),
    (.92, .12, .30, 0, _terracotta, _sage),
  ];
  for (final (x, pw, ph, s, b, g) in low) {
    _pot(canvas, Offset(w * x, h * .96), w * pw * .62, h * ph, s, b, g);
  }
}

void _paintAvatar(Canvas canvas, Size size) {
  final w = size.width, h = size.height;
  final r = Offset.zero & size;
  canvas.drawRect(
    r,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(-.3, -.4),
        radius: 1.1,
        colors: [Color(0xFFE39A68), Color(0xFFB85C32), Color(0xFF8E3F1F)],
      ).createShader(r),
  );
  canvas.drawRect(
    Rect.fromLTWH(0, h * .8, w, h * .2),
    Paint()..color = const Color(0xFF6E3018).withValues(alpha: .55),
  );
  _pot(canvas, Offset(w * .5, h * .82), w * .5, h * .6, 0, _cream, _blue);
}

/// A second cover, for the "picture chosen, not saved yet" frames.
void _paintNewBanner(Canvas canvas, Size size) {
  final r = Offset.zero & size;
  canvas.drawRect(
    r,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE9DECE), Color(0xFFCDBBA3), Color(0xFF9A6A43)],
      ).createShader(r),
  );
  for (final (x, s, b, g) in <(double, int, Color, Color)>[
    (.18, 2, _sage, _cream),
    (.42, 2, _terracotta, _cream),
    (.66, 2, _cream, _sage),
    (.86, 0, _blue, _cream),
  ]) {
    _pot(
      canvas,
      Offset(size.width * x, size.height * .92),
      size.width * .12,
      size.height * .62,
      s,
      b,
      g,
    );
  }
}

Future<Uint8List> _png(int w, int h, void Function(Canvas, Size) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder), Size(w.toDouble(), h.toDouble()));
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

// ------------------------------------------------------------------ network

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.bodies);

  final Map<String, Uint8List> bodies;

  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeRequest(bodies[url.path]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.body);

  final Uint8List? body;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(body);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.body);

  final Uint8List? body;

  @override
  int get statusCode => body == null ? 404 : 200;

  @override
  int get contentLength => body?.length ?? 0;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([?body]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ----------------------------------------------------------------- fixtures

MockFirebaseAuth _auth() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: 'me', email: 'me@yovoice.app', isEmailVerified: true),
);

/// Every grant answers with one of the two pictures the fake HTTP client
/// serves; [pictures] false = an account without a photo or a cover.
ProfileMediaService _media({bool pictures = true}) => ProfileMediaService(
  auth: _auth(),
  invoker: (_, request) {
    final expires = DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    if (!pictures || request['userId'] != 'me') {
      return Future.value(<Object?, Object?>{
        'schemaVersion': 1,
        'available': false,
        'expiresAtMillis': expires,
      });
    }
    return Future.value(<Object?, Object?>{
      'schemaVersion': 1,
      'available': true,
      'expiresAtMillis': expires,
      'url':
          'https://storage.googleapis.com/capture/${request['kind']}.png'
          '?signature=short',
      'generation': '1',
      'contentType': 'image/png',
      'size': 4096,
    });
  },
);

OwnPage _own({
  PageKind kind = PageKind.business,
  String status = 'active',
  bool paused = false,
  bool suspended = false,
  String? linkedServerId,
}) => OwnPage(
  kind: kind,
  status: status,
  ownerPaused: paused,
  suspended: suspended,
  suspensionReason: suspended ? 'impersonation' : null,
  category: kind == PageKind.business ? 'music_arts' : 'hobby_crafts',
  description: _desc,
  business: kind == PageKind.business
      ? const PageBusinessInfo(
          website: 'https://pracowniaglina.pl',
          email: 'kontakt@pracowniaglina.pl',
          phone: '+48585550142',
          address: 'ul. Garncarska 8, 80-894 Gdańsk',
          hours: 'Wt–Pt 11:00–18:00 · Sb 10:00–14:00',
        )
      : null,
  linkedServerId: linkedServerId,
  displayName: _pageName,
);

UserProfile _me({DateTime? nameChangedAt}) => UserProfile(
  uid: 'me',
  email: 'me@example.com',
  displayName: _pageName,
  username: 'pracowniaglina',
  bio: '',
  country: 'PL',
  nativeLanguage: 'pl',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  website: '',
  accountType: AccountType.personal,
  friendCount: 0,
  followerCount: 0,
  accountFollowerCount: 128,
  followingCount: 0,
  roomCount: 0,
  communityCount: 0,
  voiceMinutes: 0,
  messageCount: 0,
  activeDays: 0,
  momentCount: 0,
  reactionCount: 0,
  hostMinutes: 0,
  selectedTitleId: null,
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: null,
  displayNameChangedAt: nameChangedAt,
  profileVisibility: ProfileVisibility.public,
);

class _Account implements PageEditAccount {
  _Account({this.profile, this.renameError, this.picked});

  final UserProfile? profile;
  final DisplayNameChangeException? renameError;
  final Map<ProfileImageKind, Uint8List>? picked;

  @override
  Stream<UserProfile> watchProfile() => Stream.value(profile ?? _me());

  @override
  Future<DisplayNameChangeResult> rename(String displayName) async {
    final error = renameError;
    if (error != null) throw error;
    return DisplayNameChangeResult(
      displayName: displayName,
      changed: true,
      canChange: false,
      displayNameChangedAt: _now,
      nextDisplayNameChangeAt: _now.add(const Duration(days: 30)),
    );
  }

  @override
  Future<void> uploadImage(PickedProfileImage image) async {}

  @override
  Future<PickedProfileImage?> pickImage(
    BuildContext context,
    ProfileImageKind kind,
  ) async {
    final bytes = picked?[kind];
    return bytes == null
        ? null
        : PickedProfileImage(
            kind: kind,
            bytes: bytes,
            format: ProfileImageFormat.png,
          );
  }
}

PagesService _service({Object? manage}) => PagesService(
  clock: () => _now,
  invoker: (name, payload) async {
    if (name == PagesService.managePageCallable) {
      if (manage is Exception) throw manage;
      return {
        'pageId': 'me',
        'kind': 'business',
        'status': 'active',
        'ownerPaused': false,
      };
    }
    if (name == PagesService.pageCallable) return _ownerPageWire();
    if (name == PagesService.feedCallable) {
      return {
        'schemaVersion': 1,
        'posts': <Object>[],
        'nextCursor': null,
        'hasMore': false,
        'suggestions': <Object>[],
      };
    }
    if (name == PagesService.findCallable) {
      return {
        'schemaVersion': 1,
        'pages': <Object>[],
        'nextCursor': null,
        'hasMore': false,
      };
    }
    return {'ok': true};
  },
);

Map<String, Object?> _ownerPageWire() => {
  'schemaVersion': 1,
  'page': {
    'pageId': 'me',
    'displayName': _pageName,
    'kind': 'business',
    'category': 'music_arts',
    'description': _desc,
    'followerCount': 128,
    'postCount': 0,
    'onYoVoiceSinceMs': DateTime.utc(2026, 3, 10).millisecondsSinceEpoch,
    'about': {
      'business': {
        'website': 'https://pracowniaglina.pl',
        'email': 'kontakt@pracowniaglina.pl',
        'phone': '+48585550142',
        'address': 'ul. Garncarska 8, 80-894 Gdańsk',
        'hours': 'Wt–Pt 11:00–18:00 · Sb 10:00–14:00',
        'legalNotice': null,
      },
      'community': null,
    },
    'state': 'active',
  },
  'viewer': {
    'isOwner': true,
    'following': false,
    'canFollow': false,
    'canMessage': false,
  },
  'pinned': null,
  'posts': <Object>[],
  'nextCursor': null,
  'hasMore': false,
};

Stream<PageAccessState> Function() _access(OwnPage page, {bool vip = true}) =>
    () => Stream.value(
      PageAccessState(resolved: true, hasVipGrant: vip, ownPage: page),
    );

const _glina = Server(
  id: 'srv_glina',
  name: 'Glina po godzinach',
  description: '',
  ownerId: 'me',
  type: ServerType.community,
  privacy: ServerPrivacy.public,
  status: 'active',
);

PageEditScreen _edit({
  OwnPage? page,
  bool vip = true,
  _Account? account,
  PagesService? service,
  ProfileMediaService? media,
  bool previewExpanded = true,
}) => PageEditScreen(
  service: service ?? _service(),
  account: account ?? _Account(),
  accessStream: _access(page ?? _own(), vip: vip),
  serverStream: () => Stream.value(const [_glina]),
  mediaService: media ?? _media(),
  userId: 'me',
  clock: () => _now,
  initialPreviewExpanded: previewExpanded,
);

Widget _settings({OwnPage? page}) => PageSettingsScreen(
  service: _service(),
  accessStream: _access(page ?? _own()),
  profileStream: () => Stream.value(_me()),
  userId: 'me',
  editBuilder: (_) => _edit(page: page),
);

class _SidebarProfile extends ProfileService {
  _SidebarProfile() : super(firestore: FakeFirebaseFirestore(), auth: _auth());

  @override
  Stream<UserProfile> watchCurrentProfile() => Stream.value(_me());
}

/// The desktop shell around [body]: the real rail, and [body] in a navigator
/// that says it is Treści's desktop column (what `ContentScreen` provides),
/// over a blank route so Back has somewhere to go.
Widget _desktop(Widget body) => Scaffold(
  body: Row(
    children: [
      DesktopSidebar(
        profileService: _SidebarProfile(),
        active: DesktopNavItem.content,
        showContent: true,
        unreadConversationCount: 2,
        unreadNotificationCount: 3,
        onSelect: (_) {},
        onCreateRoom: () {},
        onCreateMoment: () {},
        onOpenProfile: () {},
        onOpenProfileSettings: () {},
      ),
      Expanded(child: PagesNavigatorScope(desktop: true, child: _pushed(body))),
    ],
  ),
);

Widget _pushed(Widget child) => Navigator(
  onGenerateInitialRoutes: (navigator, _) => [
    PageRouteBuilder<void>(
      pageBuilder: (context, _, _) =>
          ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
    ),
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => child,
      transitionDuration: Duration.zero,
    ),
  ],
);

Widget _app(
  Widget home, {
  required EdgeInsets safe,
  bool pearl = false,
  double textScale = 1,
  Locale locale = const Locale('pl'),
}) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
        padding: safe,
        viewPadding: safe,
      ),
      child: child!,
    ),
    home: home,
  ),
);

// ------------------------------------------------------------------ capture

final List<String> _problems = [];
final Map<String, Uint8List> _bodies = <String, Uint8List>{};

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _dpr);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      print('wrote ${file.path} ${image.width}x${image.height}');
    } finally {
      image.dispose();
    }
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var round = 0; round < 4; round++) {
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Image decoding and the fake network need real async time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
  }
  await tester.pump();
}

void _drain(WidgetTester tester, String name) {
  Object? error;
  while ((error = tester.takeException()) != null) {
    final line =
        'EXCEPTION in $name: ${'$error'.split('\n').take(14).join(' / ')}';
    print(line);
    _problems.add(line);
  }
}

const _phone = Size(390, 844);
const _tablet = Size(768, 1024);
const _desk = Size(1440, 900);

EdgeInsets _safeFor(Size size) => size.width >= 1000
    ? EdgeInsets.zero
    : size.width >= 600
    ? const EdgeInsets.only(top: 24, bottom: 20)
    : const EdgeInsets.only(top: 47, bottom: 34);

void _frame(
  String name,
  Size size,
  Widget Function() home, {
  bool pearl = false,
  double textScale = 1,
  Locale locale = const Locale('pl'),
  Future<void> Function(WidgetTester tester)? then,
}) {
  if (_only.isNotEmpty && !_only.split(',').any(name.startsWith)) return;
  testWidgets(name, (tester) async {
    tester.view.physicalSize = size * _dpr;
    tester.view.devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    // Painting debug switches must be back at their defaults when the test
    // body ends (the binding checks), so they are set per frame.
    debugDisableShadows = false;
    debugNetworkImageHttpClientProvider = () => _FakeHttpClient(_bodies);
    try {
      await _run(
        tester,
        name,
        size,
        home,
        pearl: pearl,
        textScale: textScale,
        locale: locale,
        then: then,
      );
    } finally {
      debugNetworkImageHttpClientProvider = null;
      debugDisableShadows = true;
    }
  });
}

Future<void> _run(
  WidgetTester tester,
  String name,
  Size size,
  Widget Function() home, {
  required bool pearl,
  required double textScale,
  required Locale locale,
  Future<void> Function(WidgetTester tester)? then,
}) async {
  {
    await tester.pumpWidget(
      _app(
        home(),
        safe: _safeFor(size),
        pearl: pearl,
        textScale: textScale,
        locale: locale,
      ),
    );
    await _settle(tester);
    _drain(tester, name);
    if (then != null) {
      try {
        await then(tester);
      } catch (error) {
        // Still shoot: the frame shows where the steps stopped.
        final line = 'STEP FAILED in $name: ${'$error'.split('\n').first}';
        print(line);
        _problems.add(line);
      }
      await _settle(tester);
      _drain(tester, name);
    }
    await _shoot(tester, name);
    // Unmount before the fake client is removed.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    _drain(tester, '$name (teardown)');
  }
}

Finder _key(String key) => find.byKey(ValueKey(key));

void _scrollTo(WidgetTester tester, double offset) {
  final scrollable = tester.state<ScrollableState>(
    find
        .descendant(
          of: _key('page-edit-scroll'),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  final position = scrollable.position;
  position.jumpTo(math.min(offset, position.maxScrollExtent));
}

/// Types the phone number with spaces: one unsaved change, as on the sheet.
/// The field is built lazily, so the form is moved to it and back (by
/// position, not by a drag: a long description would take the drag itself).
Future<void> _dirty(WidgetTester tester) async {
  final field = _key('page-edit-phone');
  for (var step = 0; step < 40 && field.evaluate().isEmpty; step++) {
    _scrollTo(tester, step * 300.0);
    await tester.pump();
  }
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.enterText(field, '+48 58 555 01 42');
  await tester.pump();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  _scrollTo(tester, 0);
}

void main() {
  late PublicIdentityRepository originalIdentity;
  late Uint8List newBanner;

  setUpAll(() async {
    await _fonts();
    _bodies['/capture/avatar.png'] = await _png(600, 600, _paintAvatar);
    _bodies['/capture/banner.png'] = await _png(1500, 620, _paintBanner);
    newBanner = await _png(1500, 620, _paintNewBanner);
    Directory(_outDir).createSync(recursive: true);
  });

  tearDownAll(() {
    File(
      '$_outDir/_capture_log.txt',
    ).writeAsStringSync(_problems.isEmpty ? 'clean\n' : _problems.join('\n'));
  });

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    EntitlementService.resetCache();
    ProfileService.resetCurrentProfileCache();
    ProfileMediaService.clearAllMediaAccessCaches();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: _auth(),
      fetchOverride: (uids) async => {
        for (final uid in uids)
          uid: {'staffRole': 'user', 'isVip': true, 'page': 'business'},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  // ============================ phone 390 ============================
  _frame('edit_390_dark', _phone, _edit);
  _frame(
    'edit_390_dark_dirty_contact',
    _phone,
    _edit,
    then: (t) async {
      await _dirty(t);
      _scrollTo(t, 760);
    },
  );
  _frame(
    'edit_390_dark_end',
    _phone,
    _edit,
    then: (t) async => _scrollTo(t, 99999),
  );
  _frame(
    'edit_390_dark_community',
    _phone,
    () => _edit(
      page: _own(kind: PageKind.community, linkedServerId: 'srv_glina'),
    ),
    then: (t) async => _scrollTo(t, 500),
  );
  _frame('edit_390_pearl', _phone, _edit, pearl: true);
  _frame(
    'edit_390_pearl_dirty_contact',
    _phone,
    _edit,
    pearl: true,
    then: (t) async {
      await _dirty(t);
      _scrollTo(t, 760);
    },
  );
  _frame('edit_390_dark_text200', _phone, _edit, textScale: 2);
  _frame(
    'edit_390_dark_text200_dirty_contact',
    _phone,
    _edit,
    textScale: 2,
    then: (t) async {
      await _dirty(t);
      _scrollTo(t, 1500);
    },
  );
  _frame(
    'edit_390_dark_rtl',
    _phone,
    _edit,
    locale: const Locale('ar'),
    then: _dirty,
  );
  // A long language (German): the labels at 100 % and, at 200 %, the pinned
  // "Änderungen speichern" taking its second line instead of being cut.
  _frame(
    'edit_390_dark_de_dirty',
    _phone,
    _edit,
    locale: const Locale('de'),
    then: _dirty,
  );
  _frame(
    'edit_390_dark_de_text200_dirty',
    _phone,
    _edit,
    locale: const Locale('de'),
    textScale: 2,
    then: _dirty,
  );
  _frame(
    'edit_390_dark_no_pictures_new_cover',
    _phone,
    () => _edit(
      media: _media(pictures: false),
      account: _Account(picked: {ProfileImageKind.banner: newBanner}),
    ),
    then: (t) async => t.tap(_key('page-edit-cover')),
  );
  _frame(
    'edit_390_dark_name_cooldown',
    _phone,
    () => _edit(
      account: _Account(
        profile: _me(nameChangedAt: _now.subtract(const Duration(days: 9))),
      ),
    ),
  );
  _frame(
    'edit_390_dark_locked',
    _phone,
    () => _edit(page: _own(status: 'readOnly'), vip: false),
  );
  _frame(
    'edit_390_dark_locked_contact',
    _phone,
    () => _edit(page: _own(status: 'readOnly'), vip: false),
    then: (t) async => _scrollTo(t, 99999),
  );
  _frame(
    'edit_390_dark_suspended',
    _phone,
    () => _edit(page: _own(suspended: true)),
  );
  _frame(
    'edit_390_dark_save_failed',
    _phone,
    () => _edit(
      service: _service(manage: const PagesException(PagesFailure.network)),
    ),
    then: (t) async {
      await _dirty(t);
      await t.tap(_key('page-edit-save'));
    },
  );
  _frame(
    'edit_390_dark_name_refused',
    _phone,
    () => _edit(
      account: _Account(
        renameError: const DisplayNameChangeException(
          DisplayNameChangeFailure.nameNotAllowed,
          "This name can't be used for a Page.",
        ),
      ),
    ),
    then: (t) async {
      await t.enterText(_key('page-edit-name'), 'YO Voice Official');
      await t.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await t.tap(_key('page-edit-save'));
    },
  );
  _frame(
    'edit_390_dark_discard',
    _phone,
    _edit,
    then: (t) async {
      await _dirty(t);
      await t.tap(_key('page-edit-back'));
    },
  );
  _frame(
    'edit_390_dark_clear_confirm',
    _phone,
    _edit,
    then: (t) async {
      _scrollTo(t, 99999);
      await _settle(t);
      await t.tap(_key('page-edit-clear-contact'));
    },
  );

  // The smallest phone the app supports, at 200 % text.
  _frame(
    'edit_320_dark_text200_dirty',
    const Size(320, 640),
    _edit,
    textScale: 2,
    then: _dirty,
  );
  _frame(
    'edit_320_dark_text200_end',
    const Size(320, 640),
    _edit,
    textScale: 2,
    then: (t) async => _scrollTo(t, 99999),
  );

  // ============================ tablet 768 ============================
  _frame('edit_768_dark', _tablet, _edit);
  _frame(
    'edit_768_dark_collapsed_dirty',
    _tablet,
    () => _edit(previewExpanded: false),
    then: _dirty,
  );
  _frame('edit_768_pearl', _tablet, _edit, pearl: true);
  _frame('edit_768_dark_text200', _tablet, _edit, textScale: 2);

  // ============================ desktop 1440 ============================
  _frame('edit_1440_dark', _desk, () => _desktop(_edit()));
  _frame('edit_1440_dark_dirty', _desk, () => _desktop(_edit()), then: _dirty);
  _frame(
    'edit_1440_dark_dirty_scrolled',
    _desk,
    () => _desktop(_edit()),
    then: (t) async {
      await _dirty(t);
      _scrollTo(t, 700);
    },
  );
  _frame(
    'edit_1440_dark_community',
    _desk,
    () => _desktop(
      _edit(
        page: _own(kind: PageKind.community, linkedServerId: 'srv_glina'),
      ),
    ),
    then: (t) async => _scrollTo(t, 99999),
  );
  _frame(
    'edit_1440_pearl_dirty',
    _desk,
    () => _desktop(_edit()),
    pearl: true,
    then: _dirty,
  );
  _frame(
    'edit_1440_dark_text200_dirty',
    _desk,
    () => _desktop(_edit()),
    textScale: 2,
    then: _dirty,
  );
  _frame(
    'edit_1440_dark_rtl_dirty',
    _desk,
    () => _desktop(_edit()),
    locale: const Locale('ar'),
    then: _dirty,
  );
  _frame(
    'edit_1440_dark_de_dirty',
    _desk,
    () => _desktop(_edit()),
    locale: const Locale('de'),
    then: _dirty,
  );
  _frame(
    'edit_1440_dark_locked',
    _desk,
    () => _desktop(_edit(page: _own(status: 'readOnly'), vip: false)),
  );
  _frame(
    'edit_1100_dark_dirty',
    const Size(1100, 900),
    () => _desktop(_edit()),
    then: _dirty,
  );

  // ============================ settings ============================
  _frame('settings_390_dark', _phone, () => _pushed(_settings()));
  _frame('settings_390_pearl', _phone, () => _pushed(_settings()), pearl: true);
  _frame(
    'settings_390_dark_text200',
    _phone,
    () => _pushed(_settings()),
    textScale: 2,
  );
  _frame('settings_768_dark', _tablet, () => _pushed(_settings()));
  _frame('settings_1440_dark', _desk, () => _desktop(_settings()));

  // ============== through the real Treści destination (1440) ==============
  _frame(
    'content_1440_dark_edit',
    _desk,
    () {
      final service = _service();
      final access = _access(_own());
      return Scaffold(
        body: Row(
          children: [
            DesktopSidebar(
              profileService: _SidebarProfile(),
              active: DesktopNavItem.content,
              showContent: true,
              unreadConversationCount: 2,
              unreadNotificationCount: 3,
              onSelect: (_) {},
              onCreateRoom: () {},
              onCreateMoment: () {},
              onOpenProfile: () {},
              onOpenProfileSettings: () {},
            ),
            Expanded(
              child: ContentScreen(
                isRootTab: true,
                service: service,
                accessStream: access,
                localStore: MemoryPagesLocalStore(),
                userId: 'me',
                userDisplayName: _pageName,
                clock: () => _now,
                flows: PagesFlows(
                  openPage: (context, {required pageId, displayName}) =>
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          settings: RouteSettings(name: 'pages/page/$pageId'),
                          builder: (_) => PageProfileScreen(
                            pageId: pageId,
                            displayName: displayName,
                            service: service,
                            userId: 'me',
                            clock: () => _now,
                            accessStream: access,
                            flows: const PagesFlows(openPage: _noPage),
                            editBuilder: (_) => _edit(service: service),
                          ),
                        ),
                      ),
                ),
              ),
            ),
          ],
        ),
      );
    },
    then: (t) async {
      // The panel's own-Page row opens the profile; "Edytuj stronę" there
      // opens the form, and the panel steps aside.
      await t.tap(find.text('Twoja strona').first);
      await _settle(t);
      await t.tap(_key('page-edit'));
    },
  );
}

Future<void> _noPage(
  BuildContext context, {
  required String pageId,
  String? displayName,
}) async {}
