// Local-only visual preview of the tester-round work. No sign-in, no writes,
// no publication: every surface below is fed with fixtures so the changes can
// be looked at on a Simulator without an account.
//
//   flutter run -t lib/dev/tester_round_preview.dart -d <simulator>
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/presence/user_availability.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/achievements/data/achievement_catalog.dart';
import 'package:yovoice/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_trim_strip.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/presentation/widgets/invite_to_room_sheet.dart';
import 'package:yovoice/firebase_options.dart';
import 'package:yovoice/shared/widgets/inputs/yo_keyboard_done_bar.dart';
import 'package:yovoice/shared/widgets/profile/availability_picker.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_people_strip.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Same rationale as the other previews: plugin registrants expect an app to
  // exist. Nothing here signs in, reads or writes.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
  } catch (error) {
    debugPrint('Preview: continuing without Firebase ($error)');
  }
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();

  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  bool _pearl = false;
  bool _polish = true;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
    locale: Locale(_polish ? 'pl' : 'en'),
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: _Gallery(
      pearl: _pearl,
      polish: _polish,
      onTheme: (value) => setState(() => _pearl = value),
      onLanguage: (value) => setState(() => _polish = value),
    ),
  );
}

class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.pearl,
    required this.polish,
    required this.onTheme,
    required this.onLanguage,
  });

  final bool pearl;
  final bool polish;
  final ValueChanged<bool> onTheme;
  final ValueChanged<bool> onLanguage;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final entries = <(String, String, WidgetBuilder)>[
      (
        'Dostępność i pierścienie',
        'Zielony dostępny, żółty zaraz wracam, czerwony nie przeszkadzać, szary niewidoczny.',
        (_) => const _AvailabilityDemo(),
      ),
      (
        'Nagrody — wybór odznaczenia',
        'Sekcje, kafelki postępu i wybór tytułu, który zdobi awatar.',
        (_) => AchievementsScreen(profile: _profileFixture()),
      ),
      (
        'Profil z wybranym tytułem',
        'Pierścień i kolor nazwy z wybranej nagrody plus chip dostępności.',
        (_) => const _ProfileHeaderDemo(),
      ),
      (
        'Reels — przycinanie na filmie',
        'Uchwyty na materiale zamiast suwaka pod spodem.',
        (_) => const _TrimDemo(),
      ),
      (
        'Pokój — zaproś znajomego',
        'Lista znajomych, wysyłka zaproszenia i link do udostępnienia.',
        (_) => const _InviteDemo(),
      ),
      (
        'Home — pasek znajomych (bug)',
        'Home pokazywał tylko obserwowanych twórców; teraz są wszyscy znajomi.',
        (_) => const _PeopleStripDemo(),
      ),
      (
        'Klawiatura — przycisk Gotowe',
        'Pasek nad klawiaturą kończy pisanie w opisach.',
        (_) => const _KeyboardDemo(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('YO Voice — podgląd zmian'),
        actions: [
          IconButton(
            tooltip: pearl ? 'Ciemny motyw' : 'Jasny motyw',
            onPressed: () => onTheme(!pearl),
            icon: Icon(pearl ? Icons.dark_mode : Icons.light_mode),
          ),
          TextButton(
            onPressed: () => onLanguage(!polish),
            child: Text(polish ? 'EN' : 'PL'),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final (title, subtitle, builder) = entries[index];
          return Material(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (routeContext) => Scaffold(
                    appBar: AppBar(title: Text(title)),
                    body: builder(routeContext),
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: palette.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

UserProfile _profileFixture() {
  final unlocked = AchievementCatalog.all
      .where((item) => item.threshold <= 50)
      .take(9)
      .toList(growable: false);
  return UserProfile(
    uid: 'preview-user',
    email: 'ada@yovoice.app',
    displayName: 'Ada Lovelace',
    username: 'ada',
    bio: 'Podgląd lokalny',
    country: 'PL',
    nativeLanguage: 'pl',
    spokenLanguages: const ['pl', 'en'],
    learningLanguages: const [],
    photoUrl: null,
    bannerUrl: null,
    premiumIdentity: true,
    availability: UserAvailability.busy,
    website: '',
    accountType: AccountType.creator,
    friendCount: 24,
    followerCount: 130,
    followingCount: 88,
    roomCount: 12,
    communityCount: 3,
    voiceMinutes: 640,
    messageCount: 320,
    activeDays: 41,
    momentCount: 18,
    reactionCount: 210,
    hostMinutes: 180,
    selectedTitleId: unlocked.isEmpty ? null : unlocked.first.id,
    unlockedTitleIds: unlocked.map((item) => item.id).toList(growable: false),
    unlockedTitleTimestamps: <String, DateTime>{
      for (final item in unlocked) item.id: DateTime(2026, 8, 20),
    },
    createdAt: DateTime(2026, 1, 4),
  );
}

class _AvailabilityDemo extends StatefulWidget {
  const _AvailabilityDemo();

  @override
  State<_AvailabilityDemo> createState() => _AvailabilityDemoState();
}

class _AvailabilityDemoState extends State<_AvailabilityDemo> {
  UserAvailability _mine = UserAvailability.available;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final people = <(String, bool, String?)>[
      ('Ada', true, 'available'),
      ('Ola', true, 'away'),
      ('Jan', true, 'busy'),
      ('Ewa', false, 'busy'),
      ('Kuba', false, null),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Jak widzą Cię znajomi',
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 10,
          children: [
            for (final (name, online, availability) in people)
              PeopleStatusAvatar(
                displayName: name,
                status: PeopleStatus.fromPresence(
                  isOnline: online,
                  availability: availability,
                ),
                onTap: () {},
                radius: 24,
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Twój status (kliknij, aby wybrać)',
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: AvailabilityChip(availability: _mine),
        ),
        const SizedBox(height: 18),
        Text(
          'Podgląd wszystkich stanów',
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        for (final option in UserAvailability.values)
          ListTile(
            selected: option == _mine,
            onTap: () => setState(() => _mine = option),
            leading: AvailabilityDot(
              status: PeopleStatus.fromOwnAvailability(option),
              size: 14,
            ),
            title: Text(
              option.localizedLabel(AppLocalizations.of(context)),
              style: TextStyle(color: palette.textPrimary),
            ),
            subtitle: Text(
              option.localizedHint(AppLocalizations.of(context)),
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
            trailing: option == _mine
                ? Icon(
                    Icons.check_rounded,
                    color: palette.interactiveForeground,
                  )
                : null,
          ),
      ],
    );
  }
}

class _ProfileHeaderDemo extends StatelessWidget {
  const _ProfileHeaderDemo();

  @override
  Widget build(BuildContext context) => ListView(
    children: [ProfileHeader(profile: _profileFixture(), onEdit: () {})],
  );
}

class _TrimDemo extends StatefulWidget {
  const _TrimDemo();

  @override
  State<_TrimDemo> createState() => _TrimDemoState();
}

class _TrimDemoState extends State<_TrimDemo> {
  static const int _durationMs = 42000;
  ReelTrimRange _range = const ReelTrimRange(2000, 24000);
  final ValueNotifier<Duration> _playhead = ValueNotifier<Duration>(
    const Duration(seconds: 6),
  );
  String _lastScrub = '—';

  @override
  void dispose() {
    _playhead.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AspectRatio(
          aspectRatio: 9 / 16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Color(0xFF2A1140), Color(0xFF120A22)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Text(
                '${(_playhead.value.inMilliseconds / 1000).toStringAsFixed(1)} s',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ReelTrimStrip(
          durationMs: _durationMs,
          range: _range,
          playhead: _playhead,
          onChanged: (range) => setState(() => _range = range),
          onScrub: (handle, positionMs) {
            _playhead.value = Duration(milliseconds: positionMs);
            setState(
              () => _lastScrub =
                  '${handle.name} → ${(positionMs / 1000).toStringAsFixed(1)} s',
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Zakres: ${(_range.startMs / 1000).toStringAsFixed(1)}–'
          '${(_range.endMs / 1000).toStringAsFixed(1)} s   ·   '
          'ostatnie przeciągnięcie: $_lastScrub',
          style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _InviteDemo extends StatelessWidget {
  const _InviteDemo();

  static VoiceRoom _room() => VoiceRoom(
    id: 'preview-room',
    hostId: 'preview-user',
    hostName: 'Ada Lovelace',
    hostPhotoUrl: '',
    name: 'Wieczorne rozmowy',
    description: 'Podgląd lokalny',
    category: 'talk',
    visibility: 'public',
    language: 'pl',
    maxParticipants: 20,
    participantCount: 4,
    memberCount: 4,
    isLive: true,
    roomType: RoomType.community,
    status: RoomStatus.active,
    imageUrl: '',
    approvalRequired: false,
    slowModeSeconds: 0,
    autoMuteNewUsers: false,
    membersCanStartVoice: true,
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 6),
  );

  static FriendUser _friend(String id, String name, bool online) => FriendUser(
    id: id,
    displayName: name,
    email: '',
    photoUrl: null,
    isOnline: online,
    lastSeen: DateTime(2026, 9, 6),
  );

  @override
  Widget build(BuildContext context) => InviteToRoomPanel(
    room: _room(),
    friendsStream: Stream<List<FriendUser>>.value(<FriendUser>[
      _friend('a', 'Ola Nowak', true),
      _friend('b', 'Jan Kowalski', false),
      _friend('c', 'Ewa Zielińska', true),
      _friend('d', 'Kuba Wilk', false),
    ]),
    send: (friend, text) async =>
        await Future<void>.delayed(const Duration(milliseconds: 600)),
    share: (text, subject) async =>
        await Future<void>.delayed(const Duration(milliseconds: 300)),
  );
}

class _KeyboardDemo extends StatelessWidget {
  const _KeyboardDemo();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: const Padding(
      padding: EdgeInsets.all(16),
      child: TextField(
        maxLines: 6,
        keyboardType: TextInputType.multiline,
        decoration: InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Opis (wieloliniowy)',
          hintText: 'Zacznij pisać, a nad klawiaturą pojawi się „Gotowe”.',
        ),
      ),
    ),
    bottomNavigationBar: const YoKeyboardDoneBar(),
  );
}

class _PeopleStripDemo extends StatelessWidget {
  const _PeopleStripDemo();

  static FriendUser _person(
    String id,
    String name, {
    bool online = false,
    String? availability,
  }) => FriendUser(
    id: id,
    displayName: name,
    email: '',
    photoUrl: null,
    isOnline: online,
    availability: availability,
    lastSeen: DateTime(2026, 9, 6),
  );

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const SizedBox(height: 8),
      HomePeopleStrip(
        friends: Stream<List<FriendUser>>.value(<FriendUser>[
          _person('a', 'Ada', online: true, availability: 'available'),
          _person('b', 'Ola', online: true, availability: 'away'),
          _person('c', 'Jan', online: true, availability: 'busy'),
          _person('d', 'Ewa'),
          _person('e', 'Kuba'),
          _person('f', 'Marta', online: true),
          _person('g', 'Tomek'),
        ]),
        onSeeAll: () {},
      ),
    ],
  );
}
