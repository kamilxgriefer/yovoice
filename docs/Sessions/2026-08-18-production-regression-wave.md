# 2026-08-18 — Production regression wave: diagnosis and same-day repair

One session diagnosed and repaired the full set of P0s reported from real
production testing. Root causes, in one line each:

1. **Rooms (delete/leave/mute/end)** — firebase-functions v2 passes
   `(request, responseProxy)`; seven callables registered multi-parameter
   handlers, so the proxy shadowed the LiveKit control after transactions
   committed. ADR-078; `3f28462`; deployed ~20:36Z.
2. **Friends (no accept/decline, counter 0, Notifications banner)** —
   wildcard liveness `get()`s inside owner LIST rules denied the whole
   query. ADR-079; deployed 20:38Z. A/B: pre-fix rules fail exactly the 3
   new owner-LIST tests (400/3), fixed rules 403/403. Client: add-friend's
   "Accept" actually sent a request (server reciprocal-accept made it look
   like auto-friendship); now routes to a real accept + decline affordance.
3. **DM send "You don't have permission" + stuck unread** — all 5
   production conversations were unmigrated legacy roots (13 keys, no pair
   guard); `validateConversation` answers permission-denied and the same
   guard sits in mark-read. Migrated the 2 threads between living accounts
   in place (Roadmap 0m); 3 involve dead Auth accounts and correctly refuse.
   Client mark-read no longer fires from build and surfaces failures.
4. **Discover "No matching rooms"** — the search was right: the room was a
   mid-deletion zombie. Home was the liar (unfiltered watchOwnedRooms with
   a Start button); Home now hides deletionInProgress and disables ended.
5. **Moment cleanup schedules** — never ran: two composite indexes missing
   (`4cad282`), ADR-055's emulator-can't-catch-it class.
6. **Website double login (PR #2)** — merged after adversarial review;
   hardened `resolveAuthRedirect` against the `/\evil.com` backslash open
   redirect in the same PR (`19599ad`).
7. **Stripe deploy blocker** — undeployable secret validation at discovery;
   exports now behind `STRIPE_BILLING_EXPORTS` (ADR-080, `8063743`).

Also shipped: shared `RoomMuteCoordinator` (screens + mini bar, stale-session
teardown), `RoomLeaveCoordinator` finished with a real-navigation widget
test, simple room-delete confirm with friendly errors, compact profile
header (≤30% of a phone viewport), stream-driven foreground notification
banner, watchFriends degraded rows, fanout displayName cap.

Verified today, not assumed: deployed rules fetched byte-identical twice;
functions redeployed as one 125-function build; Hosting fingerprinted;
production login screen (real Apple button via runtime probe, dedicated
Reset password, friendly popup-blocked copy) inspected in a live browser.
Real-account Google/Apple E2E and the mic/leave/delete in-room smoke need
an authenticated session — see the final report.
