const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const FUNCTIONS_DIR = path.resolve(__dirname, "..");
const readSource = (file) => fs.readFileSync(path.join(FUNCTIONS_DIR, file), "utf8");

test("notification fallbacks use Server and Conversation copy without changing legacy wire names", () => {
  const push = readSource("notifications/push.js");
  const invites = readSource("notifications/invites.js");

  assert.match(push, /clubInvite:[\s\S]*invited you to a server/u);
  assert.match(push, /clubInviteAccepted:[\s\S]*accepted your server invitation/u);
  assert.match(push, /roomInvite:[\s\S]*invited you to a conversation/u);
  assert.doesNotMatch(push, /invited you to a club|accepted your club invitation|invited you to a room/iu);

  assert.doesNotMatch(invites, /["']YO Voice club["']/iu);
  assert.match(invites, /["']YO Voice server["']/u);
  // Persisted type and collection compatibility remains intentionally stable.
  assert.match(push, /clubInvite:/u);
  assert.match(push, /roomInvite:/u);
  assert.match(invites, /type:\s*["']clubInvite["']/u);
  assert.match(invites, /clubs\/\{clubId\}\/invites\/\{inviteeId\}/u);
});
