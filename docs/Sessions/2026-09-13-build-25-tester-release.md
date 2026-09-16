# YO Voice 2.0.0 (25) tester release

## Status and boundary

**Status at 2026-09-13 10:34 CEST: release candidate prepared; store upload,
tester assignment and backend activation are pending.** No Build 25 binary had
been uploaded to App Store Connect or Google Play when this record was created.
No tester notification or release email had been sent.

| Item | Current evidence |
| --- | --- |
| Candidate code anchor | `218ec72c1fd34c4475c028e6c268e1de23187d7d` (`main`) |
| Marketing version / build | `2.0.0 (25)` from `pubspec.yaml` |
| Intended audience | Existing TestFlight and Google Play tester groups only |
| Public-store release | Out of scope; not submitted |
| Hosting / Firebase release | Not performed by this release-preparation step |
| Build 25 iOS artifact | **Pending** |
| Build 25 Android artifact | **Pending** |
| App Store Connect upload | **Pending — do not infer an upload from this file** |
| Google Play upload | **Pending — do not infer an upload from this file** |

The shared checkout contains unrelated local work. Store artifacts must be
created from a clean isolated checkout of the exact pinned candidate. If the
code anchor changes, record the replacement SHA before building and rerun the
gates affected by that change.

## Product scope in the candidate

Build 25 is the first planned tester binary for the completed server-first
interface:

- Servers are the only reachable shared-space product. The selector contains
  exactly Friends, Community, Podcast, Family and Company.
- Home prioritizes server creation and recent Servers while retaining the
  friends activity strip and recent chats.
- YO Moments gives Voice and Reels one visual system. Voice replies are
  implemented for both Voice Moment and Reel comment threads.
- Ordinary Personal accounts no longer receive follower/following surfaces.
  Creator audience tools remain gated by verified Creator status, active
  Premium, verified age and explicit opt-in.
- Standalone Rooms, Discover and Clubs are retired from reachable navigation;
  their existing schemas remain compatibility contracts.
- The historically approved animated **Meniscus Hub Bar** is restored by
  `4342625e7c97e53f380c794362d0f25c28d60ca5`, which is included in the
  candidate. Its shape, animation and navigation behavior are retained. Only
  the former Rooms destination now uses the Servers identity and icon.

## Verification ledger

Evidence is kept at the commit where it was actually produced. A predecessor
result is useful regression evidence, but it is not relabeled as a complete
Build 25 gate.

| Gate | Exact result | Applies to |
| --- | --- | --- |
| Full Flutter suite | **4644/4644 PASS** | Clean `c38862a9`; predecessor to the restored Meniscus bar |
| Firebase Functions suite | **2165/2165 PASS**, 133 suites, 0 failed/skipped/cancelled | `c38862a9`; backend is identical in `218ec72c` |
| Firestore Rules | **564/564 PASS** | Current source rules |
| Storage Rules | **75/75 PASS** | Current source rules |
| Servers Rules | **67/67 PASS** | Current source rules |
| Servers registration/export | **60/60 PASS**: 54 callables, 2 dispatchers, 4 sweeps | Current source |
| Build 25 focused analyzer | **Clean**, 4-item navigation/cutover scope | `218ec72c` |
| Build 25 focused navigation/cutover tests | **78/78 PASS** | `yo_floating_navigation_dock`, main-shell Servers slot and surface cutover on `218ec72c` |
| Meniscus visual harness | **8/8 PASS** | Dark/Pearl at 320/390/430 px plus 200% text and 99+ badge cases |
| CodeQL | **PASS** | `218ec72c`, run `34747666093` |
| Release Web browser smoke | **PASS** | `218ec72c`, run `34747666091` |
| Full verify-and-build workflow | **Pending** | `218ec72c`, run `34747666089` was still running at record creation |
| Full local Flutter suite | **Pending for `218ec72c`** | Do not substitute the predecessor's 4644 result |
| Android release artifact | **Pending** | Compilation/build work had not produced a verified Build 25 artifact |
| iOS native compile/artifact | **Blocked / pending** | See native blocker below |

The successful `c38862a9` CI also completed Firestore, Storage, Family-media,
Servers Rules, Functions, deployed-binding smoke and release Web build steps.
The later navigation implementation changed Flutter production and test code,
so Build 25 still requires the current full Flutter and verify-and-build result.

### Native iOS blocker reproduced during preparation

`flutter build ios --simulator --debug --no-pub` currently exits 1. Runner and
the Podfile declare iOS 15, but the generated
`FlutterGeneratedPluginSwiftPackage` resolves iOS 13 while eight Firebase
package products require iOS 15. This blocks a fresh trustworthy iOS compile
and therefore blocks a signed Build 25 archive. The blocker must be fixed and
the native build rerun; the presence of valid signing material does not waive
the compile gate.

## Store baselines before Build 25

### App Store Connect / TestFlight — live read at 2026-09-13 10:16 CEST

- Latest upload: **YO Voice 2.0.0 (24)**, created Sep 12 at 12:26 AM.
- Upload processing: **Complete**.
- TestFlight state: **Testing**, expiring in 89 days at read time.
- Assigned groups: **YO Voice Internal Testers** and
  **YO Voice Beta Testers**.
- Build metrics: **8 invites, 8 installs, 33 sessions, no recorded crashes and
  no feedback**.
- The internal group contains one tester; the owner showed
  `Installed 2.0.0 (24)` dated Sep 12.
- Build 25 did not exist in the console during this read, so 25 was the next
  observed free iOS build number.

The local `build/ios/archive/Runner.xcarchive` is the already-uploaded Build 24
archive. It is 30 commits and 574 changed paths behind the Build 25 code anchor
and must never be reused or presented as the new tester artifact.

### Google Play — live read pending

The current Play Console track and next free version code have **not** been
read live for this record. The last repository record says Build 24 was active
on the existing internal track, but that historical entry is not a current
console observation. Confirm the track and version-code vacancy before building
or uploading the Build 25 AAB. Do not create a new track or change the tester
list for this release.

## Production backend readiness — HOLD

The Build 25 client can be distributed only after deciding how Servers should
be activated for testers. The production backend is currently the older
runtime:

| Production item | Live result | Candidate requirement |
| --- | --- | --- |
| Cloud Functions | **180 ACTIVE; 0/60 Servers V1 exports live** | Deploy the reviewed Servers set in the required order |
| Registration flag | No live Function carries `YOVOICE_SERVERS_V1`; the flag is absent from `functions/.env` | Activation decision pending |
| Servers App Check flag | `YOVOICE_ENFORCE_SERVERS_APP_CHECK` absent | Keep enforcement false until attestation is proven |
| Firestore Rules | Live ruleset `166ad205-c543-4626-b710-15362fbce57a`, source SHA-256 `6c2704d53b9beb59045ee22aa4a2dc88b650a5c062efc040f7e6435e5828554e` | Repo SHA-256 is `12cb243755c5f5dc790f9f1d606a044f9e11a7dce9459b9e96f402dfb33317ad`; Servers branches are not live |
| Storage Rules | Live ruleset `5a4004f7-e0be-488d-b3d1-8b43abf78572`, source SHA-256 `bce9925b397ab6bba0b5ccf8ea8cefd9db4ef02303f28dcd3e466c3a574af280` | Repo SHA-256 is `8a64a5f6830e05804fb3c263ea7441c2cd22aafd50a7fcf93f90cda26c10ab15`; Servers branches are not live |
| Firestore indexes | Live **33 composites + 8 overrides** | Repo **45 + 10**; 12 composites and 2 overrides are missing live |
| Required Server indexes | Missing live | At minimum `channels(accessMode,status,position)` and collection-group `channelSessions.livekitRoomName`, plus reviewed specialist indexes |
| LiveKit secrets | `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` exist | Provider/device smoke remains pending |
| Podcast egress credential | `PODCAST_EGRESS_GCP_CREDENTIALS` is absent (`404/not found`) | Create/configure the dedicated credential and verify service-account and bucket IAM before claiming recording/archive completion |
| Existing-data migration | Not performed or authorised | Not required to test newly created Servers; legacy migration remains a separate action |

There is **no strict backend tester-cohort gate**. `YOVOICE_SERVERS_V1` is a
global deploy-time registration switch. Enabling it exposes the endpoints to
all otherwise authorized accounts, even if Build 25 itself is distributed only
through store tester groups. A tester-only store rollout therefore is not a
technical backend canary. Before backend activation, either implement and
verify a real cohort allowlist/claim gate or explicitly record acceptance of
global endpoint availability. Store distribution alone cannot make this
decision.

## Clean artifact and distribution requirements

1. Complete the full `218ec72c` verification workflow and a full local Flutter
   gate, or pin a later replacement commit and rerun the affected gates.
2. Fix the iOS package-platform blocker and prove a clean native compile.
3. Resolve the Servers activation/cohort decision. Deploy and read back any
   authorized Functions, indexes and Rules before promising Server testing.
4. Configure and exercise Podcast egress before store text promises working
   recording/archive behavior, or keep that capability visibly unavailable and
   remove it from the release promise.
5. Read both store consoles immediately before artifact creation and confirm
   Build/version code 25 remains unused.
6. Build signed iOS and Android artifacts from one clean pinned commit. Read
   `app.yovoice`, `2.0.0` and build `25` from each artifact itself; record size,
   SHA-256, signing identity/profile and entitlements.
7. For iOS, `ios/ExportOptionsUpload.plist` uses `destination=upload`. It may
   upload successfully without producing a local IPA, and a final Flutter
   message can be misleading. Check App Store Connect before any retry.
8. After Apple reports the upload **Complete**, assign the same two permanent
   groups, save the approved What to Test text and leave automatic TestFlight
   notification enabled. Do not add/remove testers or create another group.
9. Verify Play reports the existing internal track active on code 25. Google
   Play does not automatically email internal testers; any separate email wave
   needs its own exact recipient review and release authorization.

## Draft store copy — conditional, not submitted

These drafts may be used for TestFlight **What to Test** and Google Play
internal release notes only after the backend and artifact gates above pass.
Counts include spaces and punctuation. Both counts are Unicode character
counts and UTF-16 code-unit counts; each remains below Google Play's
500-character per-language limit.

### English — 447 characters

> Meet YO Voice 2.0.0 (25): a server-first home with five focused spaces for friends, communities, podcasts, families and companies. YO Moments brings Voice and Reels into one visual system, including voice replies to comments. The familiar Meniscus Hub Bar keeps its look and behavior; only the former Rooms destination is now Servers. Please test server creation, invitations, channels, media, comments and navigation on phone, tablet and desktop.

### Polski — 454 znaki

> Poznaj YO Voice 2.0.0 (25): ekran główny oparty na serwerach z pięcioma przestrzeniami dla znajomych, społeczności, podcastów, rodzin i firm. YO Moments łączy Voice i Reels w jednym stylu, także z głosowymi odpowiedziami na komentarze. Meniscus Hub Bar zachowuje wygląd i działanie; tylko miejsce Pokoi prowadzi teraz do Serwerów. Sprawdź tworzenie serwerów, zaproszenia, kanały, multimedia, komentarze i nawigację na telefonie, tablecie oraz komputerze.

## Pending evidence to append

- final result and completion time for workflow `34747666089`;
- exact full Flutter result for the pinned Build 25 commit;
- fixed iOS compile plus signed archive identity/hash;
- signed Android AAB identity/hash;
- live Google Play baseline and confirmed free version code;
- backend activation/cohort decision and any authorized deployment readback;
- final App Store Connect and Play availability after an actual upload;
- physical tester-device acceptance for navigation, Server creation/invites,
  Voice/Reels voice replies and specialist media paths.

Until those entries are filled with observed evidence, Build 25 remains a
prepared tester candidate, not a delivered tester release.

## Outcome (added 2026-09-16)

No committed record of a Build 25 upload exists. The iOS compile blocker
recorded above was fixed by `3008996e fix(ios): resolve plugins through
CocoaPods`. The next committed release record is Build 26 (`d1c036b7`; see
[DEPLOYMENT.md](../DEPLOYMENT.md)).
