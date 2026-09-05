# Testing

An honest picture of what's actually verified in this project, and how —
deliberately not aspirational. Several separate, unequal layers of coverage
exist; know which one you're relying on before trusting it.

## Build 19 tester-release evidence (2026-09-03)

This is the latest evidence for the exact Build 19 source and bounded tester
rollout. It proves the automated gates and the directly observed production
deploy/read-back and tester-channel states described below. It does not prove
the remaining physical-device, mixed-version or full visual matrix, and it is
not evidence of a public App Store or Google Play release.

| Gate | Measured result | What it proves |
|---|---:|---|
| Flutter analysis | clean | final source compiles/analyzes without diagnostics |
| Complete Flutter | **2123/2123** | one full final-tree invocation |
| Independent Build 19 QA | **229/229** | calls, chat/media, Moments, profile and navigation |
| Reels pagination + catalog | **19/19** | cursor/retry and locale catalog contracts |
| Reels visual/localization review | **40/40** | responsive/source contract |
| Cloud Functions | **1166/1166** | 118 backend suites under fresh Auth + Firestore emulators |
| Firestore Rules | **523/523** | authorization behavior in the emulator |
| Storage Rules | **67/67** | object-path/metadata authorization in the emulator |
| Reels + atomic moderation | **64/64** | fresh-emulator security and replay cases |
| Family media | **11/11** | combined media contract |
| Shared DM media probe | **9/9** | byte/container detection contract |
| Direct media integrity | **38/38** | fresh-emulator reservation/finalization cases |
| Browser media/crop/Reels | **39/39** | real Chrome behavior |
| Flutter production Web | built | release artifact compiles |
| Website | **87/87 + clean + built** | tests, lint and release build |
| Production dependency audits | **0 known vulnerabilities** | Functions + Rules harness |
| Changed Node syntax + diff | **7/7 + clean** | `node --check` and `git diff --check` |

The independent targeted buckets may overlap and are not added to the complete
Flutter total. The Functions/index/Rules/Storage/Hosting production rollout
and byte/read-back checks passed, and the signed Build 19 artifacts are
available through the persistent TestFlight and Google Play Internal Testing
cohorts. The following acceptance evidence remains pending:

- Dark/Pearl, 320–desktop, 200% text, keyboard and RTL visual inspection;
- physical iOS/Android camera/library, codecs, background/restart and
  two-account cache/privacy tests;
- mixed-version two-device direct audio/video with APNs/FCM and Bluetooth;
- end-to-end physical playback/upload/notification checks from non-owner
  devices in both tester cohorts.

The complete Functions count includes the legacy direct-attachment migration
suites. The focused migration gate is 12/12 unit tests plus 1/1 Firestore
emulator query test, while Storage remains 67/67. The production dry-run
inspected all 5 legacy direct-message objects from a null cursor: 5 eligible,
0 invalid/missing/raced and 5 tokens observed, with no writes. The controlled
apply then finalized all 5 and revoked the legacy tokens without deleting
media bytes; repeated null-cursor post-apply scans independently reached the
end with 5 already finalized, zero remaining problem/token counts and
`releaseReady=true`.

DM stored-object content sniffing and transaction-time reservation recheck are
source-verified: the probe recognizes JPEG/PNG/WebP, ISO-BMFF/WebM and MP3/WAV,
binds its stream to the stored generation and reports detected type plus
audio/video tracks. Voice requires audio-only media; video requires a real
video track. After probing, metadata is read again and the transaction
revalidates reservation, path, generation, MIME, kind, size, duration and
expiry. The shared contract passed 9/9, fresh-emulator direct integrity passed
38/38, seven Node syntax checks passed and `git diff --check` passed. Deployed
IAM/rules/read-back checks passed; real physical-device media smokes remain
pending, and these focused counts must be rerun if the implementation changes.

Production migration evidence is data-state evidence, not playback evidence:
five Voice Moment objects are migrated, Firestore legacy `audioUrl` is zero,
and both inventoried Voice Moment prefixes contain zero download tokens. No
media bytes were deleted. Identifiers, URLs and token material are not recorded
here. The operational detail is in
[DEPLOYMENT.md](DEPLOYMENT.md#completed-production-data-prerequisite-voice-moments).

## Build 20 source-complete release candidate (2026-09-05; HELD)

This is the current source evidence for the coordinated `1.0.0 (20)`
candidate. The YO Moments destination, strict Voice Moment v2 read boundary,
Reels availability/retention and canonical moderation work are source-complete.
They are **not deployed, uploaded, assigned to testers or physically
accepted**. Build 19 remains the deployed tester baseline above.

| Gate | Measured result | What it proves |
|---|---:|---|
| Flutter analysis | clean | current source analyzes without diagnostics |
| Complete Flutter VM | **2255/2255** | one complete final-tree Flutter gate |
| Chrome browser | **18/18** | selected browser widget/runtime behavior |
| Production Flutter Web build | **PASS** | release-mode Web artifact compiles |
| Playwright built-artifact smoke | **2/2 PASS** | selected browser smoke passes against the built artifact |
| YO Moments screenshot harness | **50/50 PASS** | 320–1440 px plus populated, empty, error, loading, following, story, detail and 200% text renders |
| Dock Dark/Pearl screenshot harness | **8/8 PASS** | 320/390/430 px, 200% text and 99+ renders |
| Independent Voice re-review | **84/84 — APPROVE** | no P0, P1 or P2 finding in the targeted source/runtime scope |
| Cloud Functions | **1277/1277** | complete non-overlapping shards after the monolithic emulator run hit a transaction-lock hang |
| Firestore Rules | **524/524** | current authorization behavior in the Firestore emulator |
| Storage Rules | **67/67** | current object-path, metadata and media authorization boundary |
| Family media | **11/11** | combined Firestore/Storage media contract |
| Functions smoke | **PASS** | local Functions/Auth/Firestore emulator boundary |
| Sound asset check | **PASS** | generated assets match the deterministic sound manifest/check |
| Functions production dependency audit | **0 vulnerabilities** | production dependency tree reported no known npm advisory finding |
| Firestore-test production dependency audit | **0 vulnerabilities** | rules-harness production dependency tree reported no known npm advisory finding |

The Functions total is the complete non-overlapping sharded result. Sharding
was required because the monolithic emulator process stopped on a transaction-
lock hang; the room-control 32/32 and tail 174/174 boundaries also passed in
isolation and are included in, not added to, 1277/1277. These automated gates
do not prove production index/TTL readiness, deployed Rules/Functions,
friendship reconciliation, signed artifact/store-number uniqueness, rendered
or physical-device quality, store processing, tester availability or
notification delivery. Those boundaries keep Build 20 operationally
**HELD**.

The generated screenshot PNGs were inspected. Frame Echo Clean has no internal
lines or skew, and no overlap was observed in the bounded YO Moments and
dock matrices. This remains source-rendered evidence, not physical-device,
keyboard, RTL or full-app visual acceptance.

## Earlier Post-Build-19 P0 checkpoint (2026-09-04; not deployed)

Tester reports after Build 19 exposed two production-only compatibility gaps:
some legitimate legacy friendships predated the server-owned
`friendshipGuards` cutover, and valid iOS camera videos could present a
QuickTime filename/MIME while their immutable ISO-BMFF bytes identified an MP4
brand, or could omit parser-reported duration despite valid classic ISO-BMFF
track timelines. The same
tester wave also exposed duplicated Friends/Requests reads, stale avatar-grant
invalidation and profile routes that could be stacked by rapid taps.

This table records the earlier P0-only checkpoint that preceded the complete
Build 20 evidence above. It does not replace the exact Build 19 evidence and
does not claim that production or either tester channel contains the repair.

| Gate | Measured result | What it proves |
|---|---:|---|
| Flutter analysis | clean | checkpoint source analyzes without diagnostics |
| Complete Flutter | **2192/2192** | one full-tree VM invocation after the final P0 fixes |
| Direct-call + localization Flutter | **67/67** | mixed-device UX and all 43 selectable locale variants' current-release call copy |
| Friend recovery Flutter | **22/22** | child profile/presence recovery, stale generations, remove/re-add, auth isolation and timer cleanup |
| Avatar/profile focused review | **91/91** | expiring/auth-bound cache, mutual avatars and navigation locks; no P0/P1 finding |
| DM media/outbox focused aggregate | **68/68** | authoritative rotation, exact canonical reconciliation and retry/restart cleanup |
| Independent cleanup re-review | **41/41** | delete failure, restart, concurrency and wrong sender/type/conversation; no P0/P1/P2 finding |
| Cloud Functions | **1218/1218** | 118 suites on fresh Auth + Firestore emulators |
| Firestore Rules | **523/523** | checkpoint authorization rules against the Firestore emulator |
| Storage Rules | **67/67** | checkpoint media-path, size, type and read boundaries |
| Family media | **11/11** | combined Firestore/Storage family-media boundary |
| Direct media integrity | **39/39** | generation-bound finalization, MOV/MP4 equivalence and duration corroboration |
| Focused trusted media probe | **29/29** | timing plus sample maps, self-contained data references, `mdat` bounds and overlap rejection |
| Direct calls | **47/47** | accept-time video negotiation, device binding, replay and raw-secret non-persistence |
| Reviewed legacy friendship reconciliation | **12/12** | precise schema-v2 timestamp/digest, bounded dry-run/apply and conflict refusal |
| Modified JavaScript syntax | **8/8** | every changed/new backend or test file parses under Node |
| Dart format | **615 files, 0 changed** | final Dart tree was already formatted |
| Diff integrity | clean | no whitespace errors |

For DM media lost acknowledgements, production-shaped authoritative
`deadline-exceeded` expiry and `aborted` reservation-change responses are
recognized before generic ambiguity and rotate both the reservation and
`messageId`. Generic ambiguous failures preserve the durable retry identity.
Canonical reconciliation requires an exact sender, conversation, `messageId`
and media-type match. Outbox completion deletes the payload before removing the
manifest entry; a delete failure therefore remains durable across retry and
restart. Wrong sender, conversation or type never suppresses the visible
failure or removes its payload, and concurrent reconciliation/delivery is
pinned to one completion.

Private avatar grants are viewer/auth-bound and held in a 256-entry LRU. Expiry
or an auth/global boundary clears the mounted provider and its Flutter
`ImageCache` entry. Mutual-friend rendering goes through `UserAvatar` and its
viewer grant, while preview, full-profile and social-stat navigation use
single-flight locks. Non-blocking P2: the target-scoped epoch map can grow in a
very long session with many unique target evictions; it is globally cleared at
logout/auth reset and is not a privacy or correctness blocker.

The reconciliation utility never scans or auto-promotes client-writable
friend mirrors. It accepts only an operator-reviewed explicit pair allowlist,
defaults to dry-run, pins the production project, limits input size/count and
requires the exact SHA-256 dry-run digest for apply. The normalized schema-v2
manifest binds `{seconds, nanoseconds}` and preserves the exact Firestore
timestamp in both guards. Auth state and all
Firestore predicates are re-read before writes; the two guards for one pair
are created in one transaction. A production apply has **not** been run.

Remaining release gates are a reviewed Functions deployment, a controlled
aggregate-only friendship dry-run/apply/post-check for the independently
verified affected pairs, and physical two-device iOS/Android checks for calls,
avatar visibility and real camera/library codecs. The simulator/UI pass is
also still pending because the host was locked when screen automation was
attempted. At that checkpoint, the npm advisory endpoint also returned
`socket hang up` on all three attempts, so its dependency audit was
**unavailable** rather than inferred from Build 19. The complete 2026-09-05
candidate above supersedes that audit state with two successful production
audits at 0 vulnerabilities. Automated success is not presented as physical-
device success.

## Current counts

**Current coordinated tester-release baseline: 2026-09-03 (build 19).** One table,
so there is a single place to correct when
these move. Every figure is a suite run, not an estimate; file counts are
`find`. *(The date used to live in the heading; it moved into the body on
2026-08-20 because three other docs deep-link to this section and every
correction silently broke all three anchors.)*

| Suite | Command | Count |
|---|---|---|
| Firestore rules | `npm --prefix firestore-tests test` | **523** checks |
| Storage rules | `npm --prefix firestore-tests run test:storage` | **67** checks |
| Family media (combined) | `npm --prefix firestore-tests run test:family-media` | **11** checks |
| Cloud Functions | `npm --prefix functions test` | **1166** tests (118 suites) |
| Flutter VM | `flutter test` | **2123** tests |
| Flutter browser | Build 19 media/crop/Reels Chrome gate | **39** tests |

**Where these numbers came from.** Every current row was re-measured on
2026-09-03 against exact source commit
`7ef9816fd3ee289cd065b37b83bd14d748a44e0c`, not inferred from an older
release. Flutter VM passed **2123/2123** in one invocation and
`flutter analyze --no-pub` reported no issues. Cloud Functions passed
**1166/1166** across 118 suites under Node 22 on fresh Auth/Firestore
emulators. Firestore Rules passed **523/523**; isolated Storage and combined
Family-media gates passed **67/67** and **11/11**. The real-Chrome Build 19
media/crop/Reels gate passed **39/39**; the production Web artifact built and
its Hosting workflow/live route checks passed. The Functions and Rules-harness
production-dependency audits reported **0 known vulnerabilities**. Historical
count movement remains below.

> **Movement, 2026-09-05 (Build 20 source-complete candidate; operationally
> HELD).** The complete current gate is Flutter VM **2255/2255**, Chrome
> **18/18**, production Flutter Web build **PASS**, Playwright built-artifact
> smoke **2/2 PASS**, YO Moments screenshots **50/50 PASS**, dock Dark/Pearl
> screenshots **8/8 PASS**, Voice re-review **84/84 APPROVE**, Functions
> **1277/1277** in non-overlapping shards after an emulator transaction-lock
> hang, Firestore Rules **524/524**, Storage Rules **67/67** and Family media
> **11/11**. Functions smoke and the deterministic sound-asset check pass;
> production npm audits report **0 vulnerabilities** in both `functions` and
> `firestore-tests`. This movement records source evidence only: Build 20 is
> not deployed or available to testers, and production configuration,
> reconciliation, signed artifacts, rendered/physical QA and distribution
> remain open.

> **Movement, 2026-09-03 (Build 19 coordinated tester release).** Flutter VM
> **2044 → 2123**, Functions **1100 → 1166**, Firestore Rules **522 → 523**,
> Storage Rules **60 → 67** and Chrome **18 → 39** cover the integrated
> chat/media, Voice Moment, avatar, Reels, direct-call compatibility,
> localization and moderation release. Family media remains **11/11**. The
> focused shared DM probe is **9/9**, direct integrity is **38/38**, and all
> seven changed Node files pass syntax checks. Production rollout/read-back and
> both bounded tester channels were directly observed; physical two-device and
> full visual acceptance remain separate residuals.

> **Movement, 2026-09-02 (build-18 coordinated tester candidate).** Flutter VM
> **1925 → 2044** covers the merged friends/avatar revision path, actionable
> verification banner, passive room prejoin, default-visible compact room
> chat, permission readiness, safe localized failures, direct-message retry,
> promoted-listener microphone consent across the room and mini-player,
> production Polish and 41 additional locale catalogs. Functions
> **1098 → 1100** adds exact latency-critical warm-instance configuration
> coverage. Firestore **522/522**, Storage **60/60**, Family media **11/11**,
> Chrome **18/18**, Playwright **2/2**, sound generation, release Web build,
> `git diff --check` and static analysis are green. Store availability and the
> physical two-device matrix are separate release gates and are not claimed by
> these source results.

> **Movement, 2026-09-01 (build-16 final release gate).** Flutter VM
> **1867 → 1925** includes the integrated private-media, direct-call,
> room-cover, profile/avatar, Voice Moment and release regressions. Functions
> **938 → 1098** adds the committed RTC/Club/room-control quotas,
> idempotency, bounded cleanup and authorization contracts. The exact final
> rules gates are Firestore **522/522**, Storage **60/60** and Family media
> **11/11**. All emulators were fresh and shut down cleanly after the run.

> **Movement, 2026-08-31 (coordinated tester release candidate).** Flutter VM
> **1672 → 1867** covers the responsive auth Voice Relay/curtain, the Dark and
> Pearl semantic colour contract, final sculpted dock geometry and hover,
> compact live-room capsule, guided onboarding, profile identity/Vibe,
> room-cover crop/export, TOTP motion/error recovery and the cross-tab
> registration identity race, full 200% text inheritance in live-room surfaces,
> and stale-session mute protection during a room A→B transition. The final
> registration boundary refuses to seed
> a canonical name from an email while the password-registration owner is
> still publishing the chosen pseudonym; reload plus a second profile read
> protects a separate browser tab. Backend totals moved to Functions
> **938/938** and Firestore Rules **523/523**; Storage **60/60**, Family media
> **11/11** and browser **18/18** remain green. This is source verification,
> not evidence that a signed store build has been uploaded or assigned.

> **Movement, 2026-08-29 (first-run guided product tour).** Flutter VM
> **1644 → 1672** adds per-account/version completion and fail-closed storage,
> true-new-account startup eligibility, notification-prompt readiness on both
> success, failure and bounded platform hangs, cold-start notification route
> ownership before token/network work, single-flight and full reverse-route
> ownership, modal blocking, keyboard focus retention, reduced motion, replay
> from Settings and production dock/sidebar resize anchoring. The final
> startup/route matrix passed 18/18; the complete VM suite passed 1672/1672 in
> one invocation and `flutter
> analyze` remained clean. Twelve Dark/Pearl real-theme frames cover 320×568
> at 200% text, 390 px and 1440 px across the five-step route. Physical
> VoiceOver/TalkBack behavior remains an explicit native tester smoke.

> **Movement, 2026-08-29 (compact Profile identity passport).** Flutter VM
> **1622 → 1629** adds exact two-level owner geometry, full-width badge-rail
> gutters, a semantic display-name heading, 320 px/200% text completeness,
> Pearl role/VIP/account contrast and revision-listener replacement across an
> injected repository swap. Dark/Pearl real-font screenshot frames cover
> 320/390/768/1100/1440 px plus 390 px at 200% text. The complete VM suite
> passed 1629/1629 and `flutter analyze` remained clean.

> **Movement, 2026-08-29 (Vibe and identity colour hierarchy).** Flutter VM
> **1629 → 1633** adds exact production-card Dark/Pearl contrast gates for
> the Vibe label, informative icons, provider actions and all three identity
> chip tones, plus full-identity completeness at 320 px/200% text in both
> themes. The existing failed-launch regression now also pins the paired error
> surface at 4.5:1. A separate explicit real-theme harness rendered and passed
> **10** Dark/Pearl frames at 320/390/768/1440 px plus 320 px/200% text. The
> complete VM suite passed 1633/1633 and `flutter analyze` remained clean. The
> production `main.dart.js` fetched through both Hosting domains is byte-exact
> to the verified local release (SHA-256 `1a23f11d8e816a0d`, 6,445,943 bytes).

> **Movement, 2026-08-29 (room-cover Web decoder regression).** Flutter VM
> **1633 → 1636** adds supported-format decode, a real EXIF-orientation-6 JPEG
> bounded on its displayed long edge and a forced root-route reset while the
> cropper owns a decoded frame. The browser gate expands **1 → 18** across the
> Blob lifecycle, JPEG/PNG/WebP decode, hostile bounds, EXIF rotation and the
> complete picked-bytes → crop editor → canonical 1600×686 JPEG path. This is
> the exact web seam that the VM-only safety tests missed when encoded
> `ImageDescriptor` dimensions were introduced. Production Hosting was then
> read back through both `yovoice-ec54a.web.app` and `app.yovoice.app`; each
> `main.dart.js` is byte-exact to the verified local release (SHA-256
> `b15e426c3e44833f`, 6,467,715 bytes).

> **Movement, 2026-08-29 (compact active-room YO Live Capsule).** Flutter VM
> **1636 → 1644** adds exact 84 px maximum mobile geometry, 48 px circular
> Chat/Mic/More targets, isolated gap behavior, complete tap semantics, busy
> Mute swallowing without a false accessibility action, truthful host/member
> actions and two remote-session cleanup races. The controls route regression
> uses a real sentinel screen and advances 16 ms into the sheet's reverse
> transition, proving cleanup cannot pop the route underneath it. The focused
> interaction matrix passed **26/26**; the Dark/Pearl production-dock render
> matrix passed **18/18** across 320/360/390/430 px, 200% text, long copy,
> reconnecting, muted, unread, More and expanded states. The complete VM suite
> passed 1644/1644 and `flutter analyze` remained clean. The workflow artifact
> and both production Hosting domains are byte-exact at SHA-256
> `1835920f7c1c5505` (6,476,304 bytes).

**A trap worth naming, because it cost a full diagnosis pass.**
`firestore-tests/storage.test.js` used to hardcode Firestore 8080 and Storage
9199. Storage rules read Firestore state, so an unrelated tunnel on 8080 made
the suite silently talk to the wrong process and report **19 of 52 failing**,
all `storage/unauthorized` on allow-cases. The harness now reads the emulator
host/port variables injected by `emulators:exec`, matching the family-media
suite, so isolated ports are real isolation rather than documentation only.

> **Correction, 2026-08-16.** These numbers were wrong in several docs for
> most of a week — TESTING.md claimed 268 rules checks and 43 Storage
> checks, Firebase.md claimed 265, Bugs.md and Roadmap.md claimed 225, and
> Bugs.md additionally claimed Cloud Functions had *zero* automated
> coverage while 510 tests were passing. The rules suite grew
> 268 → 281 (`56e7ea7`) → 295 (`2fc05e5`) → 301 (`952d8e4`) across one
> session and no doc followed it. If you change a suite, change this table
> in the same commit.

> **Movement, 2026-08-24 (Friends request and notification lifecycle).** Rules
> 485 → **489** adds the real following/follower list-query privacy boundary
> for legacy and generation-bound edges. The stale Functions table was
> corrected from 783/62 to the measured **786/64**; this wave adds exact
> notification-generation/source validation, a source-aware retired-
> notification scrub and its concurrent-rewrite precondition. The stale
> Flutter table was corrected from 1198/114 to **1270/118**; this wave itself
> adds two test files plus actionable request routing, accept/decline,
> retry/reflow, mobile unread badges, blocked-user failure states and
> cross-account push-token retirement coverage. Storage **52** and
> family-media **11** were re-run and remain unchanged. Baseline drift is not
> presented as feature-attributable growth.

> **Movement, 2026-08-27 (avatar crop and stacked Profile Preview).** The
> immediately preceding local source baseline was **1292/118**. This follow-up
> adds one five-test crop-screen file plus two Profile Preview route tests:
> first-pinch cover/export geometry, 44 px single-pointer and keyboard crop
> controls, stacked-modal Chat routing, visible failure/busy feedback and
> injected Auth/MessageService optimistic reconciliation. The measured result
> is **1299/119**. Rules, Storage and Functions are unchanged.

> **Movement, 2026-08-27 (desktop Recent Chats artwork correction).** The
> immediately preceding measured source baseline was **1299/119**. Three tests
> added to existing files pin replacement of empty conversation artwork from
> the current public profile projection, the Desktop Home integration path,
> and a real white-image/200%-text geometry and contrast boundary with a
> two-tone focus indicator. The measured result is **1302/119**. Mobile's
> standard avatar layout, Rules, Storage and Functions are unchanged.

> **Movement, 2026-08-27 (Voice Moment local review, user-sized availability
> and server authority).** Flutter VM **1302 → 1343** adds local play/pause/seek
> without upload, cleanup ordering, web Blob URL ownership, arbitrary whole
> hours/days/permanent, retry-contract locking, voice-reply behavior,
> validation focus/live announcements, 320×640 at 200% text, and exact
> no-snapshot deadline removal/stop across feeds, detail, story, sheet,
> comments, pinned/trending and Creator-management surfaces. Exact-expiry
> regressions also pin one deduplicated accessibility announcement, focus
> recovery, nested-route closure and deterministic first-surviving Story
> selection after a multi-deadline resume. They also cover 30-day browser-timer
> chunking, overdue parent rebuilds, suppression from cached hidden tabs, and
> visible/hidden Home plus Following stream races with focused tiles.
> Functions
> **786 → 793** pins an exact unbounded active-set check, the per-author
> capacity mutex, more than 100 newer drafts and concurrent contention for the
> tenth slot, per-attempt preflight quota with free completed replay, and
> server deadline refusal for likes and text/voice replies. Rules **489 → 494** make root and engagement mutations
> server-only while preserving parent-gated reads. Storage **52 → 60** covers
> canonical private draft upload/read, client-delete denial, published/expired reads and legacy
> mixed-case object compatibility, plus exact voice-reply reservation binding
> and finalized-media delete denial. A dedicated real-Chrome case also proves
> object-URL reuse and revocation, and the voice-reply retry test proves one
> logical comment after a committed finalize response is lost. Family media
> remains **11**. The complete measured result is Flutter VM **1343/120** plus
> browser **1/1** (121 total files), Functions **793/64**, Rules **494**,
> Storage **60** and family media **11**.

> **Movement, 2026-08-27 (More double-tap navigation).** Flutter VM
> **1343 → 1347** adds four regressions in existing files: one synchronous
> single-flight guard, one same-frame dock callback proving exactly one pop and
> action, one launcher-position retap during sheet entry, and one reverse-
> animation boundary proving presentation stays locked until the modal route
> has completely left the Navigator. File counts and every backend suite are
> unchanged.

> **Movement, 2026-08-27 (Velvet Prism product sound).** Flutter VM
> **1347 → 1361** adds fourteen regressions in existing files: deterministic
> 48 kHz/stereo/duration/loudness/tail checks; cache-versioned asset inventory;
> byte-identical Flutter/Android/iOS notification masters; Android v3 channel
> parity; completion-bound, no-hard-cut playback; newest-queued-wins and
> idempotent disposal; foreground FCM/Firestore reservation, failure and
> messenger retry paths; id-less delivery; and consumption of the initial join
> cue after room creation. The generator's `--check` command and the focused
> Functions payload suite pass, while the full Functions count remains
> **793/64**. File counts and browser coverage are unchanged.

> **Movement, 2026-08-28 (ADR-119 moderator Premium preview and billing
> recovery).** The immediately preceding measured table was Functions
> **841/65**, Rules **499** and Flutter VM **1361/120**. The exact final source
> now passes Functions **892/67**, Rules **509** and Flutter VM **1404/124**;
> Storage **60**, family media **11** and real-Chrome **1/1** remain green.
> Coverage includes exact claim/mirror authority, fail-closed role-transition
> retries, server-only marker immutability, paid-plus-preview coexistence,
> Creator/Club cleanup and quotas, Auth deletion, projection backfills, public
> Creator privacy during transitions, and the client billing-recovery path.

> **Movement, 2026-08-28 (ADR-120 Podcast Studio).** Flutter VM
> **1404/124 → 1407/125** adds persisted Podcast production metadata, legacy
> defaults and host controls for episode topic, format, guest guidelines and
> the listener-request queue. Firestore Rules **509 → 512** proves that only a
> Podcast/Broadcast listener may raise a stage request while the queue is open,
> that lowering remains available after the host closes it, and that Community
> speakers cannot forge the same state; a production-shaped legacy
> `experience=podcast` room can also use the new settings. The responsive visual harness now
> covers **55** Podcast/room frames, including the populated 1440 px producer
> queue; phone, tablet and desktop layouts were inspected at 320, 390, 768,
> 1100 and 1440 px. Functions, Storage, family media and browser-only coverage
> are unchanged.

> **Movement, 2026-08-28 (full-profile Vibe rendering).** Flutter VM
> **1407/125 → 1410/126** adds a three-test production-widget suite: a saved
> Vibe renders as its own Voice identity section, the exact 80-character editor
> limit wraps at 320 px/200% text without overflow, and website-only identity
> no longer falls into the empty state. The existing end-to-end profile Save
> test now also pins `statusMessage` in Firestore and the shared profile stream;
> the full friend-profile responsive matrix pins the same Vibe after opening a
> different member's full profile. Rules, Functions, Storage, family media and
> browser-only coverage are unchanged.

> **Movement, 2026-08-28 (ADR-121 direct chat, media, push and calls).**
> Flutter VM **1410/126 → 1461/130** adds active-conversation foreground
> suppression, silent paged receipts, cross-conversation text outbox fairness,
> durable image/voice payloads, expiry/clock-skew rotation, failed-only
> Retry/Discard, restart-safe direct-call request identity and bounded
> exactly-one alert arbitration. Functions **899/67 → 907/69** adds terminal
> push-claim/source-conflict and managed-ledger-TTL coverage; the focused
> backend re-review passed **9/9** pure and **24/24** emulator tests, then four
> replacement-lock regressions closed the final direct-call race. Rules
> **512 → 519** closes conversation-root and message mutation fallbacks.
> Storage **60**, family media **11** and real-Chrome **1/1** remain green. A
> Four final race regressions additionally pin account-switch revalidation,
> active-call lost-ACK recovery, atomic same-pair start acquisition and an
> independently expiring token-safe alert claim. The final independent review
> reproduced every prior P1/P2 failure and returned SHIP with no P0-P3 finding.

> **Movement, 2026-08-29 (ADR-126 actionable Vibe music links).** The exact
> final Flutter source passes **1551/137**, up from the preceding measured
> **1538/136** baseline. A new 12-test parser/widget suite and one compact-
> preview fallback regression cover ordered multi-link extraction, Unicode
> URLs, balanced punctuation, exact provider-host boundaries, public-HTTPS
> rejection rules, truthful link semantics and keyboard activation,
> single-flight/cooldown behavior, inline retry feedback and disposal during a
> pending launch. The focused gate passed **29/29**, `flutter analyze` is clean,
> and the explicit visual harness passed and was inspected at 390 px, 768 px
> and 320 px with 200% text. Rules, Functions, Storage, family media and the
> browser-only lifecycle suite are unchanged.

> **Movement, 2026-08-29 (ADR-129 native Pearl runtime boundary).** Flutter VM
> **1617/147 → 1618/148** adds one source-level release regression proving the
> iOS application no longer globally pins `UIUserInterfaceStyle=Dark`. The
> branded dark launch storyboard remains unchanged; physical Dark/Pearl/System
> behavior is part of signed build-12 acceptance.

> **Movement, 2026-08-29 (ADR-127 premium Pearl light theme).** Flutter VM
> **1551/137 → 1617/147** adds semantic light/dark palette contracts,
> WCAG contrast checks, shared-component matrices at 320/768/1440 px and 200%
> text, Pearl coverage for Friends, Moments, Notifications, Premium, Clubs and
> Discover, plus an explicit immersive-dark wrapper contract for voice rooms,
> calls, crop/review and branded authentication surfaces. A final independent
> review added real DesktopSidebar/right-column contrast coverage and route
> tests proving Pearl hands intentional dark journeys the complete dark theme
> and system chrome. The complete VM
> suite passed in one invocation and `flutter analyze` remained clean. A
> developer-only screenshot harness (not counted as a `*_test.dart` file) was
> rendered and inspected in populated/empty/error states on mobile and desktop.
> Rules, Functions, Storage, family media and browser-only coverage are
> unchanged.

> **Movement, 2026-08-29 (ADR-130 canonical profile identity).** Functions
> **907/69 → 920/70** adds convergent current-source fan-out, authoritative
> avatar removal, malformed identity sanitization, bounded multi-page
> transactions, exact Club/Moment/conversation target revalidation,
> missing/disabled Auth and retired-profile denial, plus a resumable
> aggregate-only repair whose failure output cannot disclose account paths.
> The focused gates passed **14/14** fan-out emulator and **4/4** repair tests;
> the complete fresh Auth/Firestore run passed **920/920**. Flutter VM
> **1618 → 1622** covers live Chats/Home/open-chat identity, authoritative null
> photos and New Message overlay/search/routing; the complete VM suite passed
> **1622/1622** and `flutter analyze` was clean. Rules, Storage, family media
> and browser-only coverage are unchanged. A physical two-account build-13
> Chats/Home check remains release evidence, not an automated claim.

> **Movement, 2026-08-17.** Rules 301 → **318** (`c75720a`, the
> account-status gating; the suite ran 310 passed / 8 failed against the
> live ruleset before the fix). Flutter 438/52 → 486/54 (`6ef4380`) →
> **521/55** (`cefa81a`), all from the Voice Moment recording work.
> Storage, family-media and Cloud Functions are unchanged — no
> `storage.rules` or `functions/` change landed in either round.

> **Movement, 2026-08-17 (ADR-062, the server-only conversation binding).**
> Every row above was re-measured by running all five suites, and three
> were stale by more than this change accounts for — the same drift the
> 2026-08-16 correction was written to stop.
>
> - Rules 318 → **347**. Only **3** checks are from this change (the
>   server-only `conversations` create, the `resource == null` get branch
>   for old installs, and `directConversationPairs` being default-denied).
>   The table had missed 318 → 344 from the two commits before it.
> - Cloud Functions 510/82 → **564/93**. Only **1** test is from this
>   change (pinning the pre-migration fork in
>   `functions/test/direct_integrity.test.js`); the baseline was measured
>   at **563/93** by stashing that one file and re-running, so 510/82 had
>   been stale for two commits. File count 45 → 47 by `find`.
> - Flutter 521/55 → **565/58**. **19** tests and 1 file are from this
>   change: the new `test/direct_conversation_open_test.dart` (18 cases)
>   plus a net +1 in `test/direct_message_send_test.dart`, where one case
>   asserting the defective `not-found` fallback was replaced by two
>   asserting the refusal. The measured baseline was 546/57 — the
>   `8f7aa03` round, recorded in Roadmap but never carried into this
>   table.
> - Storage **46** and family-media **11** re-measured and genuinely
>   unchanged.
>
> If you change a suite, run all five and correct this table in the same
> commit. Two consecutive rounds have now been reconstructed after the
> fact instead.

> **Movement, 2026-08-17 (Family Room creation hardening).** All five
> suites were run again after the Family flow changed. Rules **347 → 351**:
> the old root-only positive case was replaced by the real seven-write
> production batch, a missing-canonical-id probe, and negative root-only,
> incomplete-graph and malformed-channel cases. Flutter **565/58 → 573/59**:
> five lifecycle cases plus banner, concurrent-create and Family success
> screen regressions. Cloud Functions **564/93**, Storage **46** and combined
> family-media **11** were re-measured and remain unchanged.

> **Movement, 2026-08-17 (private DM media and Safari upload recovery).**
> The complete release gates were run again after both chat attachment
> placeholders became real private-media flows and the browser recorder began
> preserving its native Blob. Storage **46 → 53** adds reservation, identity,
> privacy, immutability, MIME/path and size checks for photo and voice
> attachments. Cloud Functions **564 → 572** adds reservation/finalization,
> cleanup, binding and canonical-bucket bootstrap regressions. Flutter
> **573/59 → 591/63** adds upload/finalize retry, media playback/state,
> narrow-screen layout and browser/native audio seam coverage. Firestore rules
> **351** and combined family-media **11** were re-run and remain unchanged.

> **Movement, 2026-08-17 (room creation reliability and shared stage).**
> Firestore **351 → 353** adds an immutable room-experience transition and
> the fail-closed Family artwork graph. Storage is **52/52** after replacing
> the pre-root upload permission with root-first Club media tests and explicit
> Family artwork denial. Functions **572/93 → 579/94** adds the
> generation-pinned `finalizeClubMedia` contract and its attack cases. Flutter
> **591/63 → 620/64** adds the four-identity stage matrix, atomic Podcast
> creation, Family no-media behavior and notification/dock clearance. The
> combined Family media suite remains **11/11**. `flutter analyze` and
> `flutter build web --release` also passed in the same final verification.

> **Movement, 2026-08-17 (consent-backed public website showcase).** Rules
> **353 → 363** add exact owner-controlled profile/Club consent documents and
> a pinned, read-only `publicShowcase/live` projection. Functions **579/94 →
> 593/98** add the bounded one-minute publisher, Auth/status/role revalidation,
> activity-cohort privacy, lifecycle cleanup and transfer-revocation cases.
> Flutter **620/64 → 622/65** adds the exact consent service and its profile/
> Club opt-in behavior. The complete Functions suite, Rules suite, focused
> Flutter tests and full `flutter analyze` were re-run after the final privacy
> review; the website separately passed its exact-schema parser tests, lint and
> a 42-route production build.

> **Correction and movement, 2026-08-20 (the reachability wave).** The table
> above had drifted again — it claimed **593/98** for Cloud Functions, **363**
> for rules and **622/65** for Flutter, all of which predate several rounds of
> work. Corrected figures and their provenance are stated under the table.
> Movement across `3d54bc3` → `b0f1062`, from the commit messages that
> measured each step:
>
> - **Firestore rules 403 → 446** (`b3c27fd`, club chat moderation: two
>   disjoint authority branches plus the forged-tombstone create allowlist;
>   22 cases fail against HEAD's ruleset) **→ 466** (`01c0ab2`, room chat
>   write validation and the club `list` rule; the 12 new cases fail against
>   HEAD's ruleset). The 363 → 403 step was never recorded here.
> - **Cloud Functions 690 → 699** (`2c086c7`; seven of nine new tests fail
>   against the unmodified function, and the two that passed did so for the
>   wrong reason and now pass for the right one). 593 → 690 was never
>   recorded here; 690 is the figure ADR-081's session measured.
> - **Flutter 885 → 1036.** The intermediate figures are *checkpoints from
>   parallel sessions*, not a single chain, so they are recorded as each
>   commit measured them rather than reconciled into one sequence:
>   **885** after sign-out cleanup (`3d54bc3`, 8 of 10 new tests fail
>   pre-fix) and club chat moderation (`b3c27fd`, 31 new client tests, 11
>   failing against the reverted behaviour); **898** after the
>   club-moderation accessibility pass (`f817b41`) and the Moments discovery
>   feed (`cef05e6`); **978** reached independently by club-discovery rail
>   states (`155ad61`, 948 → 978, 29 new) and by reporting (`9f3ce7f`,
>   898 → 978, 51 new); **1036** after room voice liveness (`b0f1062`, 978 →
>   1036, three cases failing against the pre-fix service). Only the
>   endpoints — 885 and 1036 — are chain-consistent.
>
> The fail-before discipline is worth noting as the thing that makes these
> counts mean something: several of these rounds demonstrated failure by
> restoring the old behaviour and re-running (`9f3ce7f` restored the report
> read-back for 4 failures and the hardcoded reason for 6, then reverted).
> A count that only ever ran green proves less than a smaller count that was
> shown to fail first.

## The stated limitation: a green suite can coexist with a feature that cannot work

Read this before trusting any number in the table above. It is not a
hypothetical — between 2026-08-19 and 2026-08-20, **four separate features
were found to exist in source, pass their tests, and (where a backend was
involved) be deployed and ACTIVE, while being unusable by any user**: voice
in Community rooms and lounges, club chat moderation, message reporting, and
Home's club-discovery rail. See
[Bugs.md](Bugs.md) and
[ADR-082](Decisions.md#adr-082-a-feature-is-not-shipped-until-a-user-can-reach-it--reachability-is-part-of-done-and-a-green-suite-cannot-prove-it).

Three properties of these suites are the mechanism, and each is a real
limitation of the tool rather than a gap someone forgot to fill:

1. **The emulator does not enforce composite indexes.** A query that throws
   `FAILED_PRECONDITION` in production runs green locally. This has already
   cost the project twice — `expirePremiumIdentity` (Premium never expired
   for any account) and the two moment-cleanup schedules (never once
   succeeded).
2. **Rules tests exercise fixtures the test author wrote, not what the client
   actually sends.** A rules test written from the rule's own text proves the
   rule is self-consistent. It cannot notice that the shipped client sends a
   different shape, queries different fields, or never calls the path at all
   — which is exactly how an author-only club-chat delete rule and a
   moderator-authorising client both passed their own suites for months.
3. **`fake_cloud_firestore` does not evaluate rules at all.** Every Dart test
   asserting "the client may do X" proves the client's *mirror* of the rule,
   never the server's answer. Where a Dart class deliberately mirrors a
   deployed rule branch — `RoomVoiceStartAuthority` is the current example —
   the test proves the mirror and the mirror only.

Each layer is honest about itself and silent about the seam. Three habits
close most of it, and they are cheap:

- **Assert on the client's real payload or query.** Copy it out of the
  service rather than writing it from the rule.
- **Name the caller.** If a feature depends on a state transition, a role
  claim, an index or a verified email, name the code that satisfies it. "It
  is in the file" is not an answer; `HomeScreen` is in the file and mounted
  nowhere.
- **Demonstrate failure before success.** Several rounds in this wave
  restored the old behaviour and re-ran to show the new tests fail against it
  (`9f3ce7f`: 4 failures from restoring the report read-back, 6 from
  restoring the hardcoded reason). A test that has never been seen red is a
  test whose subject is unproven.

## Firestore rules — the most mature coverage in the project

`firestore-tests/` — a standalone Node project running regression and
attack-scenario checks against `firestore.rules` via
`@firebase/rules-unit-testing` and the Firestore emulator — **523 checks
passing** — plus `storage.test.js`, the same treatment for `storage.rules`
against the Storage emulator (67 checks: path ownership, size caps,
content-type allowlists, read gating, default deny), plus 11 combined
family-media checks. All three run in CI on every push to `main` and gate
the Hosting release (see [DEPLOYMENT.md](DEPLOYMENT.md)). Full workflow in
[`firestore-tests/README.md`](../firestore-tests/README.md) and
[Firebase.md](Firebase.md#firestore-rules-testing); the short version:

```bash
brew install openjdk           # one-time, needed for the emulator's JVM
export PATH="/usr/local/opt/openjdk/bin:$PATH"
firebase emulators:start --only firestore --project yovoice-ec54a
cd firestore-tests && npm install && npm test
```

For the same verification as CI:

```bash
./firestore-tests/node_modules/.bin/firebase emulators:exec --only firestore --project demo-yovoice 'npm --prefix firestore-tests test'
./firestore-tests/node_modules/.bin/firebase emulators:exec --only firestore,storage --project demo-yovoice 'npm --prefix firestore-tests run test:storage'
./firestore-tests/node_modules/.bin/firebase emulators:exec --only firestore,storage --project demo-yovoice 'npm --prefix firestore-tests run test:family-media'
./firestore-tests/node_modules/.bin/firebase emulators:exec --only auth,firestore --project demo-yovoice 'npm --prefix functions test'
./firestore-tests/node_modules/.bin/firebase emulators:exec --only functions,auth,firestore --project demo-yovoice 'npm --prefix functions run test:smoke'
```

**Why this layer exists and matters more than usual for this project**:
Security Rules are the entire authorization layer here, not a secondary
check behind an API ([ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)).
A bug in a rule is not a bug in one feature — it's a bug in the
authorization system itself. This suite is what stands between a rules
change and finding that out in production.

**The non-obvious failure mode this suite specifically guards against**:
a check that calls `getDoc()`/`getDocs()` on a fully-specified path proves
nothing about whether the same collection is safely queryable via
`collectionGroup()` — those are genuinely different code paths inside
Firestore's rule evaluator. A 40-check suite, entirely green, once shipped
a completely broken `collectionGroup()` query to production because none
of the 40 checks exercised that path
([ADR-007](Decisions.md#adr-007-firestore-rules-changes-are-always-emulator-tested-against-a-real-collectiongroup-query)).
Any rule touching a collection that's ever queried via `collectionGroup()`
needs a real `collectionGroup()` check, not just a direct-path one.

The rules suite also pins the Premium boundary introduced in
ADR-053: a normal full profile bootstrap and a partial presence-first create
are allowed, forged Creator/Premium/staff first documents are denied, and an
active subscription with a disabled Creator or Clubs feature flag cannot use
that capability. Its Club-creation case commits the production-shaped batch —
Club root, owner member, user projection, three default channels and lounge
room — proving the `getAfter()` owner/channel checks work atomically after the
unused root-user `clubCount` write was removed. It also proves that accepting a
Club invitation can create only a plain `member` with the exact production
membership shape: attempts to self-assign owner/co-owner/admin or smuggle
permission fields are rejected. The matching Club-counter update must be in
the same batch as membership creation and invite deletion, can change no Club
metadata, and increments both counters exactly once. *(Until 2026-08-16 this
paragraph ended "the 2026-08-16 `firestore.rules` update still needs a manual
production deploy." That deploy has now happened — twice on 2026-08-16, at
20:40 and 21:06, per Console → Firestore → Rules version history. Passing
locally still does not deploy a rule.)*

ADR-119 extends that matrix with a non-billing moderator preview. Rules tests
prove exact `moderator` and `superModerator` claim–mirror pairs can use
Creator, while a crossed staff pair, stale claim, `superAdmin`, ban,
disablement and deletion fail closed. Backend tests repeat the same boundary
for Club creation and Creator pins, keep subscription/refund truth independent,
and prove demotion removes preview state without destroying separately valid
paid access. Flutter tests prove the role stream is reactive, source failures
stay isolated, raw billing fields are never fabricated and a paid-expiry timer
cannot evict an active moderator.

### What the 2026-08-16 hardening pass added (`56e7ea7` → `2fc05e5` → `952d8e4`)

Each of these was a case that failed before its fix, on rules that were
live in production:

- Club manager role updates carry `role`, `roleUpdatedAt` and
  `roleUpdatedBy`, so an allowlist of only `['role','updatedAt']` denied
  **every** promotion and demotion.
- `canAccessRoom()` had no `isRoomMember` branch: a Community room flipped
  to private became unreadable to its own members, and one unreadable room
  emptied the entire Communities list because `watchMyCommunities()`
  hydrates every id in a single `Future.wait`.
- `isRoomMember()` had no account-status check, so widening
  `canAccessRoom()` handed private rooms to banned and disabled accounts.
- Role attribution was forgeable by omitting the field or resending the
  stored value — `diff().affectedKeys()` reports only fields whose *value*
  changed, so a `hasAny()`-gated guard never fires on a resent value.
  Attribution is now required unconditionally against the post-write
  document.
- `roomMembers` update had no field allowlist: a host could repoint their
  own membership row at a victim's uid, permanently and remotely emptying
  the victim's Communities tab with no action available to the victim.
- The rules-level eviction path added in `2fc05e5` was removed entirely in
  `952d8e4` — see
  [ADR-056](Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row).
- The `collectionGroup()` PROOF cases are built by transforming the live
  ruleset, and the variant helper now **asserts each snippet is present
  before substituting** — so a reformatted rule fails loudly instead of
  silently running a control that proves nothing. Test scaffolding that
  can degrade into a no-op is worse than no test.

ADR-054 adds the private-profile boundary cases: an account can read its own
raw root, while ordinary users, moderators and super-admin clients cannot get
foreign roots, list `users`, or query by email/username. Public projections are
known-id get only, server-write-only and contain no private fields; inactive
targets and unauthenticated callers fail closed. Presence requires both
server-owned friendship guards; client-created mirror pairs cannot grant it.
Exact public-profile, presence and follow-edge schemas fail closed on extra
fields, while friendship guards and private quota documents are invisible and
immutable to all clients.

### What the 2026-08-17 account-status pass added (`c75720a`)

Seventeen checks, and the suite ran **310 passed / 8 failed** against the
then-live ruleset before the fix — the failures are the evidence, not the
fix's own green run. They cover a banned or disabled host attempting a room
metadata edit and a voice start, an inactive account attempting host-
admitted participation, `roomMembers` create, and a message reaction
update.

The `roomMembers` create case is the one worth copying. It was already
gated — on `isRestrictedAccount()`, which reads `banned` only and returns
**false when the account document does not exist**, so a disabled account
passed a check that read as though it covered account status. A test that
only exercises a *banned* account passes against that rule. **When a
status helper has more than one failing state, every state needs its own
case**; otherwise the suite proves the helper is called, not that it is
right.

**Always run against a freshly-started emulator.** A long-running emulator
can accumulate state between runs that makes a check pass or fail for the
wrong reason.

### What ADR-082 changed here — direct messages became server-only

Six DM-privacy checks that asserted a client-direct send SUCCEEDS in the
permitted privacy modes now assert it is denied, and one older
`a verified user can still send a message` regression became a denial too.
The count did not move; what each check proves did.

The finding behind it: `conversations/{id}/messages/{id}` create checked
`isVerified()` — a token claim that says an email was confirmed once and
nothing about whether the account may still speak — but not the sender's
standing. `activeProfile()` and `assertNotRestricted()` run *inside*
`sendDirectMessage`, and `message_service.dart`'s `_sendTextMessageDirectly`
wrote the message document straight from the client whenever the callable
was unreachable. A banned or communication-muted account kept full direct
messaging by taking that path.

**The fix could not be "add the missing check", and that is the part worth
remembering.** Adding `canCommunicate()` to the rule was measured against
the emulator and exceeded Firestore's per-request document access-call
budget: the friends-privacy path had exactly one access call of headroom
(verified by adding synthetic `exists()` probes — +1 passed, +2 failed),
and a complete sender-status check costs more than one. An exhausted rule
does not skip the check; it errors, and an error denies — so the "fix"
broke legitimate friends-mode sends, failing
`SECURITY DM PRIVACY: friends requires both canonical guard halves` with
`Service call error. Function: [exists]`. Consolidating the rule's five
redundant re-reads of the conversation document, collapsing
`accountIsActive()` to one `get`, and collapsing `canonicalFriendshipGuard`'s
seven access calls were each tried; none freed enough.

Two lessons generalize:

1. **A server-side check inside a callable is not a control if a client
   fallback writes the same document.** Ask of every callable, "what happens
   when this is unavailable?" If the answer is a direct client write, the
   rule must repeat every check the callable makes — because the rule is the
   one that will actually run.
2. **A rule has a budget, and authorization that does not fit in it belongs
   somewhere else.** When a rule cannot afford all of its checks, the answer
   is not to ship the subset it can afford; it is to move the write behind
   something that can afford all of them.

Losing the fallback must not mean losing the message, so the client keeps a
bounded local outbox instead — see the Flutter section below.

## Cloud Functions — real coverage, unevenly distributed

`functions/test/` — **1218 tests across 91 `*.test.js` files and 118 suites**,
run with `node --test --test-concurrency=1 test/*.test.js` against fresh Auth +
Firestore emulators, and
gating the Hosting release in CI like the rules suites do. A separate
`npm --prefix functions run test:smoke` drives two trigger smokes and one
callable social-graph smoke against the Functions emulator.

**A real trap this suite has already sprung, worth knowing before you add
to it.** The older `node --test test/*.test.js` command ran files concurrently
against one shared emulator. Any assertion on an *absolute* count over a
collection that another file also writes was therefore load-bearing on
interleaving: it passed locally and failed on the runner, or vice versa.
`legacy_identity_scrub.test.js` asserted `scanned === 1` while
`scrubIdentitySnapshots` scans the whole `conversations` collection and
takes no uid or prefix scope, so it could not isolate itself the way its
own `wipe()` isolates its fixtures. That turned CI red on three
consecutive pushes — including a docs-only commit, which is what gave it
away, since 509 of 510 passed every time. Fixed in `38b29f7` by measuring
the **delta** around the test's own write, which keeps the assertion
exactly as strong (one document scanned, one scrub planned, nothing
written) while being independent of what else exists.

The general rule remains: assert on a delta or on a scoped fixture, never on an
absolute count over a collection your file does not exclusively own. The
current package gate additionally pins `--test-concurrency=1`; it is serial,
not concurrent. The 2026-08-28 direct-chat result of **907/907** is historical
evidence from the older command, not the current suite inventory.

### Premium billing release matrix

`functions/test/stripe_billing.test.js` is the executable source contract for
ADR-118. Before any provider rollout it must cover all of these independently:

- exact catalog values: recurring EUR 6/month and EUR 60/year, prepaid BLIK
  PLN 26/30 days and PLN 260/365 days;
- strict `{plan, paymentMethod?}` parsing, including default `recurring`,
  explicit `blik` and refusal of every unexpected or client-authoritative
  field;
- configured-Price validation for two live/test-matched recurring EUR Prices
  and two live/test-matched one-time PLN Prices, including wrong Product,
  interval, amount, currency, tax contract and mixed livemode refusal;
- subscription Checkout with exactly `[card,paypal]` for the recurring path and
  one-time Checkout with exactly `[blik]` for the prepaid path, with retry
  idempotency bound to both plan and method;
- paid-Invoice authority for card/PayPal, successful signed one-time-payment
  authority for BLIK, no grant from a redirect/unpaid event, exact fixed BLIK
  period end, replay absorption and no second Subscription;
- recurring Portal/cancel-at-period-end behavior, explicit absence of a BLIK
  Portal action, Auth-deletion cancellation, pagination over every open
  Checkout Session, Customer-create/delete races and late-event
  non-resurrection;
- export discovery with `STRIPE_BILLING_EXPORTS` disabled (catalog only,
  checkout unavailable) and enabled (exactly Checkout, Portal, webhook and
  Auth-deletion billing handlers added);
- the production guard rejecting `sk_test_`, test Prices, test webhook events
  or `STRIPE_EXPECTED_MODE=test` for `yovoice-ec54a`.

Those tests use provider fakes and the Firestore emulator. They prove mapping,
authorization, transactions and idempotency in source; they do **not** prove
that Stripe has activated PayPal/BLIK for the live account, that either method
is offered to a particular customer, or that production webhooks arrive. The
four live-method smokes and reconciliation in DEPLOYMENT.md are separate release
evidence. Stripe test mode may run only against the Functions emulator or a
future non-production Firebase project, never production.

The 2026-08-28 catalog-only production smoke is intentionally narrower: the
callable returned EUR 6/EUR 60, 17% annual savings and both capability flags
false. It proves truthful fail-closed catalog availability, not a working
provider checkout.

## Dart tests — real, but narrow

`test/` — **2192 VM tests across 199 compatible files**, with **200
`*_test.dart` files total** (one is browser-only), green in current local
verification and grown mostly
out of real bugs rather than an even coverage discipline. The
pattern throughout: fake the Firebase backends
(`firebase_auth_mocks` / `fake_cloud_firestore` /
`firebase_storage_mocks`), drive the real production code. Highlights:

- **`message_outbox_test.dart`**, **`direct_message_send_test.dart`**
  (2026-08-19, ADR-082) — the client no longer writes a direct message to
  Firestore under any circumstance, so "the callable is unavailable" had to
  stop meaning "write it yourself" without starting to mean "lose it". The
  outbox suite covers the three states (Pending / Retrying / Failed), the
  bound (it refuses past capacity, and evicts a FAILED entry rather than an
  unsent one to make room), persistence across a restart, a corrupt queue
  being dropped rather than thrown, and one unreadable entry not stranding
  the rest. The send suite covers the seam: nothing is written to Firestore,
  the message is queued, and a later flush delivers it exactly once.

  Two cases are the ones worth keeping if the rest were ever trimmed. The
  first is that a retry reuses the ORIGINAL `requestId` — the callable keys
  its idempotency ledger on it, so a regenerated id would turn every
  ambiguous failure into a duplicate message. The second is
  `_LosesTheResponse`, which commits the server write and *then* throws:
  the client cannot distinguish "never arrived" from "arrived and the
  acknowledgement was dropped", so it retries, and the test proves the
  replay leaves one message rather than two. A backoff case is included
  precisely because the others zero the backoff to make a same-tick flush
  due — without it, "no delay" would be untestable and a real regression in
  the delay could hide behind the convenience.

- **`profile_save_e2e_test.dart`** — drives the REAL EditProfileScreen
  through pick → crop editor → Save → Storage → Firestore → stream
  emission; asserts the stored objects are the cropped 1024²/1920×1080
  JPEGs and that `statusMessage` survives the same Firestore/stream round trip.
- **`profile_voice_identity_test.dart`** — renders the exact production Voice
  identity card and pins saved Vibe, the full 80-character value at
  320 px/200% text, the long website-only populated state, and Dark/Pearl
  contrast for Vibe, provider actions and external/voice/learning metadata.
- **`friend_profile_responsive_test.dart`** — keeps that same saved Vibe on
  another member's full-profile route across 320–2560 px and in the 320 px/200%
  semantics pass.
- **`friend_accept_notification_test.dart`** — the friend-request
  notification lifecycle (sender notified on accept, dedupe, retirement,
  silent decline).
- **`error_messages_test.dart`** — no raw exception text can reach the
  UI (includes the exact web-interop wrapper string users once saw).
- **`more_destination_nav_test.dart`** — More destinations keep the
  shell bottom navigation; bar taps pop back to the shell first, commit only
  once under a same-frame double tap, and wait for the old route to finish
  before opening another surface.
- **`image_crop_test.dart`**, **`profile_image_rules_test.dart`**,
  **`room_cover_editor_test.dart`** — crop geometry/output dimensions,
  validation budgets, JPEG/PNG/WebP Web decode, EXIF-oriented edge bounds,
  forced-route cleanup and picked bytes → crop → canonical JPEG export.
- Plus layout-regression suites (message-bubble overflow, profile
  header at 7 widths, auth link tap targets) and
  `auth_service_verification_test.dart`, the original template for the
  service-with-mocks shape.
- **`identity_badges_test.dart`** — the authoritative identity-badge
  system (ADR-045): exact role labels and hex colors, role×VIP
  coexistence and ordering, owner wire-value mapping, USER fallback,
  repository batching (one request per flush window, 20-uid chunking,
  in-flight dedup), cache invalidation and account-switch clearing,
  overflow at 120px, and achievement cosmetics being unable to replace
  official badges. `global_chat_test.dart` additionally proves message
  rows badge by SENDER UID from the projection, not by message flags.
- **`profile_journey_card_test.dart`** — imports the production compact
  journey list and renders it at 320/390/768/1024/1440 px, asserting no
  overflow and a bounded, width-independent height.
- **`premium_entitlements_test.dart`**, **`mobile_staff_parity_test.dart`**,
  **`desktop_shell_test.dart`** and **`family_room_test.dart`** — capability
  paid capability flags, complimentary-VIP non-access, the separate
  moderator-preview overlay and demotion lifecycle, locked More entries on mobile/desktop,
  navigation/direct-destination guards, save-time Creator expiry, Premium Club
  creation and the free Family Room exception. `family_room_lifecycle_test.dart`
  additionally drives the complete create/reopen/invite accept/decline flow and
  proves that a second create does not fork the deterministic Family graph.
- **`public_profile_privacy_test.dart`** — self profile reads stay on private
  `users`, foreign identity reads use `publicProfiles`, friend presence joins
  only `socialPresence`, public search goes through its injectable callable and
  discards injected private fields, new conversations contain no email
  snapshot, historical email snapshots are ignored, and follow identity is
  resolved from current public projections rather than stale edge fields.

- **`voice_moment_recording_seam_test.dart`**,
  **`record_voice_moment_screen_test.dart`** and
  **`record_voice_moment_accessibility_test.dart`** (2026-08-17) — the
  recording platform seam driven through `VoiceRecorderBackend` and
  `AudioCapture` test doubles rather than the plugin, which is the only
  way recording hardware is reachable from a widget test. They pin the
  MIME negotiation rule (`audio/mp4;codecs=mp4a` unsupported /
  `audio/mp4;codecs=mp4a.40.2` supported, codec parameter normalized away
  before the allowlist comparison), each `MicrophoneOutcome` mapping to its
  own copy, the timer never rendering `0:60`, and the amplitude stream
  reaching the waveform. **What they cannot prove**: that a real browser
  refuses in the way the mapping expects, or that a real microphone
  produces bytes Storage accepts.

- **`room_voice_entry_coordinator_test.dart`**,
  **`room_voice_liveness_test.dart`**, **`room_voice_entry_screen_test.dart`**,
  **`room_mic_affordance_test.dart`** and **`room_voice_teardown_test.dart`**
  (2026-08-20) — the room liveness path from
  [ADR-088](Decisions.md#adr-088-entering-a-room-performs-the-liveness-transition-through-one-ordered-coordinator-that-mirrors-the-deployed-rule):
  the ordered liveness → roster → token coordinator, the client authority
  mirroring each deployed rule branch, legacy documents defaulting rather
  than raising, and a mute control being unrepresentable in a dormant room.
  **What they cannot prove**: that the deployed rules accept the write.
  `fake_cloud_firestore` evaluates no rules, so these pin the mirror.
- **`club_chat_moderation_test.dart`**, **`content_report_test.dart`**,
  **`report_failure_copy_test.dart`**, **`moment_report_reachability_test.dart`**,
  **`home_discover_clubs_test.dart`**, **`moments_discovery_test.dart`** and
  **`sign_out_cleanup_test.dart`** (2026-08-19/20) — the reachability wave.
  Two are worth copying as patterns: `sign_out_cleanup_test.dart` asserts
  **when** rather than whether, recording `_auth.currentUser != null` at the
  moment of each write so a write outside a live session is a write the
  deployed ruleset denies; and `home_discover_clubs_test.dart` proves a
  denial *after* a successful emission replaces the stale list rather than
  hiding behind it, which is the `StreamBuilder`-retains-data trap.

**What this means in practice**: coverage is regression-driven — deep
where something once broke (profile media, notifications, navigation,
error copy, moment recording, and since 2026-08-19 rooms, club chat
moderation, reporting and the Moments feed), thin where nothing has broken
yet. `test/widget_test.dart` is still the generated boilerplate and provides
nothing. Growth is not the same as reach: the wave that took this suite from
622 to 1036 was largely spent proving that features which already had green
tests could not be used.

Run with:

```bash
flutter test
```

### TOTP Voice Constellation evidence (source only, 2026-08-30)

The redesigned sign-in challenge has a focused deterministic suite covering
input, single-flight Firebase resolution, Back/lifecycle races, captured motion
continuity, invalid/network/rate-limit recovery, reduced motion, exact live
regions and responsive layouts. The final focused command passed **82/82**:

```bash
flutter test test/two_factor_authentication_test.dart \
  test/totp_challenge_animation_test.dart
```

The repository-wide `flutter test` gate then passed **1799/1799** on the same
source revision.

The developer-only screenshot harness passed **16/16** and wrote its PNGs
outside the repository for actual visual inspection:

```bash
flutter test \
  --dart-define=TOTP_SCREENSHOT_DIR=/private/tmp/yovoice-totp-visual-qa \
  test/totp_challenge_screenshot.dart
```

The preview target was also exercised on an iPhone simulator at normal speed
and with Flutter's real 0.5× time dilation. Editing, fast and slow success,
invalid/retry, network recovery, 200% text, multiple factors and reduced motion
were inspected. This is local simulator and screenshot evidence only: it does
not prove production configuration or deployment, and VoiceOver/TalkBack has
not been verified on a physical device.

## Static analysis — the actual baseline gate

`flutter analyze` is the one form of verification that's both
consistently applied and enforced outside of human discipline: the GitHub
Actions Hosting-deploy workflow runs it before every deploy and fails the
build if it's not clean (see [DEPLOYMENT.md](DEPLOYMENT.md)). Zero issues
is the bar — not "zero errors, some warnings are fine."

## Manual verification — UI and voice flows

There are widget/layout regression tests, but no `integration_test/` suite and
no golden-image baseline. UI changes still need manual verification: run the
app (iOS Simulator when possible), exercise the actual golden path plus
loading/empty/error states. Voice-room flows (joining, muting, hand-raise,
moderation) are
particularly hard to cover automatically since they need a real LiveKit
connection and multiple simulated participants — these have historically
been verified with two real accounts on two real devices/simulators
rather than any automated harness.

**If a screen or flow genuinely can't be verified** (no test credentials
available in a given session, for example), that should be stated
explicitly rather than claimed as checked — an unverifiable claim of
"tested" is worse than an honest "couldn't verify this part."

## What has zero coverage today

Worth naming plainly rather than leaving implicit:

- Cloud Functions coverage is now present but uneven. The Node suites execute
  security-sensitive modules against the Firestore emulator; ADR-054 covers
  exact profile derivation, trigger replay/idempotency, block-filtered callable
  search, concurrent transactional quota/window reset and bounded dry-run/apply
  backfill. This is not a deployed-environment integration test and many older
  functions still lack focused coverage.
- Premium store purchase verification: no IAP client or App Store/Google Play
  adapter is configured, so there is no real checkout path to exercise.
  `verifyPurchase` deliberately declines and only the protected-owner grant
  path works.
- Stripe web billing has focused fake/emulator coverage but no deployed provider
  integration. No automated suite proves live card or PayPal renewal, live BLIK
  presentation/settlement, Portal configuration or production webhook delivery.
  Do not bridge that gap by putting Stripe test-mode credentials in
  `yovoice-ec54a`; use the isolated environment rule above and retain the live
  operator smoke as explicit release evidence.
- Crash visibility on web: Crashlytics (added 2026-08-08) covers iOS and
  Android only — the Flutter web build still has no crash/error
  reporting channel beyond the browser console.
- **Real browsers and real microphones.** The default `flutter test` suite
  runs on the VM, so that suite does not execute `dart:js_interop`,
  `MediaRecorder`, `getUserMedia` or a `DOMException`. The separate Chrome
  case does execute `dart:js_interop` for the local Blob URL lifecycle, but it
  does not invoke `MediaRecorder` or `getUserMedia`. The web recording path is
  otherwise verified by seam tests plus a manual Chromium 148 check of MIME
  negotiation;
  Safari, Firefox, an actual permission refusal, an unplugged or busy
  input device, and an end-to-end publish into production Storage and
  Firestore are all **UNVERIFIED**. The local Voice Moment preview is covered
  through `audioplayers` test doubles plus a real-Chrome test of Blob object
  URL creation, reuse and revocation. It still does not prove decoded audible
  playback on Safari, iOS or Android, which requires a physical browser/device
  smoke. No screen reader has been run against any screen in this project, on
  any platform; keyboard behavior is widget-tested only.
- **No test proves anything about what is deployed.** Every suite above
  runs against an emulator or a fake. A green run is evidence about the
  *repository*, never about production. On 2026-08-16 the deployed
  scheduled `expirePremiumIdentity` had been failing on a missing
  composite index — Premium never expired for any account — while every
  suite was green, because the emulator does not require composite
  indexes. Production claims need production evidence: `firebase
  functions:list`, the Console's rules version history, or fingerprinting
  the served bytes (see
  [ADR-055](Decisions.md#adr-055-the-2026-08-16-production-cutover--order-the-deploy-by-what-fails-closed-and-verify-by-fingerprinting-served-bytes)).
- **`voiceMinutes` has a server writer, but not a real LiveKit end-to-end
  test.** `receiveLiveKitAchievementWebhook` is exported and its signed-event,
  accrual and failure contracts are covered against fakes/emulators. No test
  in this repo has held a real LiveKit connection, so production delivery is
  still a manual integration claim. See [Bugs.md](Bugs.md#achievements).
- Broad service coverage remains uneven despite the 199 VM-compatible test files;
  **live audio in particular has none.** The room *liveness* path gained real
  coverage on 2026-08-20, but audio quality, reconnect, device routing and
  the web microphone permission path are untouched and unretested, and no
  test in this repo has ever held a real LiveKit connection. Multi-user club
  flows still rely on manual checks.
- Any cross-cutting integration flow (the join-room → LiveKit token flow
  described in [Architecture.md](Architecture.md#data-flow-a-concrete-example-joining-a-broadcast-room),
  for example) is verified manually end-to-end, not by any test.

This is a real gap, not a hidden one — see [Roadmap.md](Roadmap.md) and
[Bugs.md](Bugs.md) for related tracked items. Expanding coverage should
prioritize the same places `firestore-tests/` already treats as
high-stakes: anything touching authorization, permissions, or money
(Roadmap's monetization item, whenever that starts).
