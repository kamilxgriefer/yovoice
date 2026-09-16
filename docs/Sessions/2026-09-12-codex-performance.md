# Codex performance pass — 2026-09-12

## Scope and concurrent ownership

Owner asked Codex to improve loading and delivery performance while Claude
continues the redesign. Coordination was sent to the running Claude task and
confirmed in `docs/agent_handoffs/2026-09-12-claude-codex-coordination.md`.
No UI, navigation, localization, Servers, existing `test/**` or rules files
are owned by this pass. Claude retains those areas. Deployment behavior is
unchanged; the only workflow edit adds an explicit CI verification step.

Codex's reserved implementation files:

- `lib/features/profile/data/services/profile_service.dart`
- `lib/features/messages/data/services/message_service.dart`
- new, explicitly invoked regression tests under `tool/performance/`
- one test-only verification step in `.github/workflows/firebase-hosting-merge.yml`
- this session record

Initial checkout: `main`, `b50bae7f`; `git pull --ff-only origin main` was
already up to date. Both service files were clean. The large existing dirty
tree belongs to Claude/the owner and is preserved. No bulk staging, commit,
push, build, simulator takeover, deployment, backend configuration change or
increase in recurring costs was performed by this pass. The CI addition
only invokes the new tests; deployment conditions, permissions and jobs are
unchanged. Claude identified that default `flutter test` would otherwise omit
the separate directory. No existing `test/**` file is edited.

## Verified findings and implemented fixes

1. `ProfileService._buildSharedProfileStream`: the cancellation continuation
   clears the shared source-subscription slot after awaiting native cleanup.
   A new listener can occupy that slot during the wait and lose its cleanup
   handle. Implemented correction: detach the old handle before awaiting it.
2. `MessageService.resumeOutbox`: persisted attachments wait for the entire
   text drain before recovery starts. The ordinary connectivity path already
   resumes the queues independently. Implemented correction: await both drains
   together, preserving each queue's ordering, retry and account boundaries.

The unchanged-service baseline reproduced both findings: **9 passing / 2
failing** tests. The replacement source listener receives zero cancellation
calls instead of one; a persisted attachment makes zero reservation calls
while text delivery is suspended. These are deterministic reproductions,
not measured production incidence. After the two minimal service fixes, all
11 new regression cases pass, as do the 114 existing focused service tests.

Baseline command:

```sh
flutter test --no-pub --concurrency=1 --reporter expanded tool/performance/profile_listener_lifecycle_test.dart tool/performance/outbox_resume_latency_test.dart
```

Baseline log: `/tmp/yovoice-performance-regressions-20260912.jqoB03/baseline-confirmed.log`.

## Read-only deployed configuration snapshot

Firebase CLI successfully listed the live `yovoice-ec54a` functions. The local
gcloud CLI has no active account, so it was not used to mutate/login/change
credentials. All functions below were ACTIVE in `europe-west1`:

| Endpoint | Minimum instances | Memory MiB |
| --- | ---: | ---: |
| startDirectCall | 1 | 256 |
| acceptDirectCall | 0 | 256 |
| createDirectCallToken | 1 | 256 |
| createLiveKitToken | 1 | 256 |
| openDirectConversation | 1 | 256 |
| sendDirectMessage | 1 | 256 |
| getProfileMediaAccess | 0 | 256 |
| getVoiceMomentsFeedV2 | 0 | 256 |
| listReelsV2 | 0 | 512 |
| getReelMediaAccessV2 | 0 | 512 |
| reserveReelDraftV2 | 1 | 512 |
| finalizeReelDraftV2 | 1 | 512 |

A zero minimum allows scale-to-zero; it does not prove a cold start caused
any particular slow interaction. No warming setting was changed. Existing
media-grant expiry, authorization, cache invalidation and upload limits are
unchanged. Raw logs, message bodies, account identifiers, URLs and credentials
must not be copied into this report.

## Production latency sample

Read-only Firebase logging query returned the latest 400 matching entries in
the checked service set, spanning **2026-09-12 12:43:35–16:28:07 UTC**. These
are mixed diagnostic/request entries, not 400 requests and not a complete
traffic census. This first sample contains only the profile-media and Voice feed
services; it cannot establish current direct-call, text-send or Reel latency.

| Service | Successful HTTP requests | p50 | p95 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| getProfileMediaAccess | 130 | 663 ms | 3,395 ms | 4,512 ms |
| getVoiceMomentsFeedV2 | 16 | 362 ms | 3,111 ms | 3,111 ms |

Profile media also has three HTTP404 request entries; no ERROR-level diagnostic
entries were present in this bounded sample. That does not certify absence of
failures elsewhere. The module-evaluation records number 25 for profile media
(median 1,675 ms, maximum 1,920 ms) and four for Voice feed (median 1,493 ms,
maximum 1,737 ms). Module evaluation is only one part of instance startup;
do not add independently aggregated medians or call it total cold-start time.
These logs show a long tail and repeated initialization, but no individual
request-to-instance causal join was made. HTTP duration is not end-to-end
phone timing, and the 16-request Voice sample is particularly small.

### Additional bounded sample: calls, text delivery and Reels

A separate read-only query returned the latest 250 matching entries for these
services, spanning **2026-09-10 23:13:37–2026-09-12 11:50:57 UTC**. These again
include diagnostic entries, are not 250 requests, and are not a representative
or current full-traffic census. Quantiles below use successful HTTP requests
only and nearest-rank selection; the small call samples are especially limited.

| Service | Successful HTTP requests | p50 | p95 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| startDirectCall | 4 | 243 ms | 975 ms | 975 ms |
| createDirectCallToken | 8 | 297 ms | 1,481 ms | 1,481 ms |
| listReelsV2 | 44 | 234 ms | 3,120 ms | 4,020 ms |
| sendDirectMessage | 17 | 246 ms | 1,433 ms | 1,433 ms |
| acceptDirectCall | 4 | 169 ms | 5,174 ms | 5,174 ms |

The Reels service also had six HTTP400 request entries. Module-evaluation
records were present in every service in this sample (14 for Reels, two for
call acceptance and one each for the other three services). This is evidence
for measuring initialization and request work separately, not proof that
initialization caused every slow request. HTTP request timings do not include
complete media download, decoding or end-to-end LiveKit connection setup.

Owner was asked separately whether selective warming of profile-media and
Voice-feed endpoints may be considered if the estimated recurring increase
stays within EUR15/month. This is a proposed spending ceiling, not a verified
price quote. No answer or approval is assumed. No warm-instance change or
deployment has been made.

## Verification and integration

**Complete for this scoped patch:**

- Before implementation: 9/11 new regression cases passed; the two intended
  failures reproduced the actual service defects.
- After implementation: **125/125 tests passed, zero failures or skips** across
  the eight files below, with concurrency limited to one.
- Full repository `flutter analyze --no-pub`: **no issues found**.
- Formatting of both production files: no remaining changes required.
- `git diff --check`: passed. This checks whitespace, not correctness of
  Claude's unrelated dirty changes.
- Independent principal review: **PASS**, no actionable P0–P2 findings in the
  scoped changes. Queue ordering within each queue, account boundaries,
  single-flight guards, backoff and durable retry identities are preserved.
- The regression runner verified that its 11 service/test/workflow inputs did
  not change during the test run. This is not a freeze of the whole working tree.

Focused test command:

```sh
flutter test --no-pub --concurrency=1 --reporter expanded \
  tool/performance/profile_listener_lifecycle_test.dart \
  tool/performance/outbox_resume_latency_test.dart \
  test/message_outbox_test.dart \
  test/messages_silent_failure_test.dart \
  test/direct_message_send_test.dart \
  test/direct_attachment_outbox_test.dart \
  test/profile_photo_source_of_truth_test.dart \
  test/public_profile_privacy_test.dart
```

Evidence:

- `/tmp/yovoice-performance-regressions-20260912.jqoB03/baseline-confirmed.log`
- `/tmp/yovoice-performance-regressions-20260912.jqoB03/retest-expanded.log`
- `/tmp/yovoice-performance-regressions-20260912.jqoB03/retest-inputs-verified.log`

Exact integration allowlist (review/stage these files explicitly, never their
parent directories or the entire dirty tree):

1. `lib/features/profile/data/services/profile_service.dart`
2. `lib/features/messages/data/services/message_service.dart`
3. `tool/performance/profile_listener_lifecycle_test.dart`
4. `tool/performance/outbox_resume_latency_test.dart`
5. `.github/workflows/firebase-hosting-merge.yml`
6. `docs/Sessions/2026-09-12-codex-performance.md`

The new CI step explicitly runs `flutter test --no-pub --concurrency=1
tool/performance`, since the ordinary default suite does not discover that
directory. Existing `test/**` files were executed, not modified.

### Handoff boundaries and remaining work

This slice is ready for Claude's coordinated integration and the shared
release gates; it has **not been committed, pushed, built or deployed** by
Codex. *(Outcome, added 2026-09-16: both fixes, the two
`tool/performance/` tests and the CI step landed in `37059560`
(2026-09-13).)* Claude should append the two verified fixes and evidence to the shared
Bugs/Roadmap records when integrating; Codex intentionally avoided concurrent
edits to those shared documents. This handoff does not authorize a Servers
feature-gate change or waive two-device testing.

Not claimed complete: end-to-end performance acceptance on physical iOS and
Android devices, video/call startup reliability under real network conditions,
all-redesign regression coverage, or elimination of the measured server tail.
The message change removes one deterministic restart queue dependency; it does
not accelerate the network upload itself. The profile change prevents orphaned
listeners; it is not a measured reduction in avatar download time.

Next coordinated performance work: measure the combined build on devices,
separate client/network/backend/media timing, and evaluate selective warming
only after explicit cost approval and a verified estimate. Keep authorization,
signed-media expiry and privacy checks intact.

Final delivery note: the earlier scope/ownership coordination was visibly
acknowledged by Claude. The attempt to send the completed results through the
Claude app was blocked because the Mac is locked; no final message was sent
or assumed delivered. This completed repository record is the handoff until
the owner unlocks the Mac and the final app message can be delivered.
