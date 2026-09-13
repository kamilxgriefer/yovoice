# Build 27 internal tester candidate — 2026-09-13

## Status

**Integrated for the internal-tester candidate; public and production-backend
release remains held.** This session record describes the current Build 27
scope. It does not prove that a signed artifact was uploaded or became available
in Play Console or App Store Connect. The release owner must add the frozen
commit, artifact digests and store read-backs before making that claim.

The Build 27 Yeels regression slice is validated: video autoplay, double-tap
like, custom-audio synchronization and the photo progress bar without a numeric
timer passed together with the related frame, overlay and sound coverage. Later
compatibility and shared Free-5/Premium-30 capacity corrections are integrated.
The Creator age picker and backend are being aligned on one UTC date-only
calendar contract, so the complete final-SHA Flutter and Functions results,
rebuilt artifacts and store read-backs remain release gates.

## Integrated client scope

### Desktop parity and navigation

`lib/dev/redesign_preview.dart` now presents the same current Home, Servers,
Chats, Friends and YO Moments surfaces used by the application at 1280 and
1440 px. Servers uses the production slot 13, `ServersScreen` and current
repository wiring. The preview offers direct routes to Servers, Chats and
Friends instead of reporting taps against stale fixture-only destinations.
The Server workspace also retains its narrow-wide boundary at 1100 px with
200% text without overflowing.

The Hub bar/dock is outside this redesign. Its layout, interactions and
animation remain unchanged. The only retained navigation cutover is the
previously approved replacement of the former Rooms destination with Servers.

### YO Moments and Yeels

- The shared selector is text-led and consistently names the formats **Głos**
  and **Yeels**.
- Photo Yeels omit the elapsed-time label; video Yeels continue to show time.
- **Add friend** owns one shared state per author, so repeated cards update
  together. Refused requests expose retry and cannot leave a false success.
- Video Yeels autoplay and double-tap like without pausing playback.
- Video plus selected custom audio shares one synchronized timeline.
- Photo Yeels retain their real backing-audio progress bar without displaying
  an elapsed-time counter.

### Chats

Unread state now belongs to the complete conversation row. Archive and
unarchive preserve one operation identity across an ambiguous lost
acknowledgement: the bounded retry sends the same `requestId`, allowing the
server ledger to replay the result. The row shows a busy state and disables the
conflicting action while the request is in flight, including a cold callable
start. Permanent refusals are surfaced without automatic retry.

### Startup and product sound

Voice Glass remains visible for a minimum of 1.4 seconds, while authentication
and profile provisioning can extend the presentation until the app is ready.
Build 27 uses the generated **Prism Halo v5** family for call states and mapped
semantic notification cues. Deterministic generator parity is source evidence;
physical-device loudness, audio focus and interruption behavior remain distinct
acceptance checks.

### GIF catalog

The app bundles sixteen G-rated **YO Voice Originals** and resolves their
canonical local asset references without a third-party viewer request. The
global production catalog is not enabled: its callables, server-owned data
boundary and authoritative send paths still require the coordinated deployment
and installed-canary sequence in
[DEPLOYMENT.md](../DEPLOYMENT.md#gif-rollout--yo-voice-originals-adr-172173).

## Production and release boundaries

- **Servers V1:** source prepared; production Functions, Rules/index rollout
  and runtime activation remain gated and undeployed. A visible client surface
  is not evidence that the server authority is live.
- **GIFs:** sixteen originals are bundled in the client; global catalog/search,
  moderation and send authority remain gated until the backend rollout.
- **App Check:** telemetry-first rollout remains a known release concern.
  Enforcement is not yet a completed public-launch control for the new
  Servers/GIF surfaces; authentication, server-side authorization and rate
  limits remain separate controls.
- **Distribution:** Build 27 is intended for the existing internal tester
  channels. No public release, production deploy or store availability is
  established by this documentation update.

## Handoff

The latest committed runtime baseline represented by this documentation is
`9cadc1507acae13f4e39ae8eb5f5ddad0333920e`. It is not the final release SHA
because the Creator UTC-calendar correction still changes client and backend
bytes.

The previously generated Android AAB is **superseded and must not be uploaded
or reused** because it predates that correction. Historical identity only:
`app.yovoice`, `2.0.0 (27)`, 126,999,267 B, SHA-256
`3551fa2de019ae958248bf10bd59d0634cabdf94e04837c5c8adb626b1bcc1c4`.

Final release evidence:

- source commit: `<FINAL_SHA_PENDING>`;
- complete Flutter result: `<PENDING>`;
- complete Functions/emulator result: `<PENDING>`;
- rebuilt Android identity, checksum and Play Internal read-back: `<PENDING>`;
- rebuilt iOS identity, checksum and TestFlight read-back: `<PENDING>`.

The release owner must replace every placeholder with the complete final-SHA
results, signed-artifact checksums, upload outcome and store read-back in
[DEPLOYMENT.md](../DEPLOYMENT.md). Do not infer deployment from a green client
suite or infer tester availability from a prepared version number.
