// firebase-functions v2 invokes every onCall handler as
// handler(request, responseProxy) — the second argument is the streaming
// CallableResponse, always present (lib/common/providers/https.js). Any
// execute* function registered directly while carrying extra
// dependency-injection parameters therefore receives that proxy in its
// injection slot and calls LiveKit methods on it, which is exactly how
// production broke on 2026-08-18: deleteRoomSelf/leaveRoomSelf/
// setOwnRoomParticipantMute all threw `... .endRoom is not a function`
// AFTER committing their Firestore transaction, stranding zombie rooms.
//
// Two defenses, both here:
//   1. Behavior: invoking the REGISTERED callable the way the framework
//      does (two arguments) must never treat the second argument as an
//      injected dependency.
//   2. Structure: no onCall registration anywhere in the codebase may pass
//      a named handler whose declared arity is greater than one.

const assert = require("node:assert/strict");
const { test, before, describe } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  deleteRoomSelf,
  leaveRoomSelf,
  setOwnRoomParticipantMute,
} = require("../rooms/participants");

const db = getFirestore();
const P = "cic-";
const HOST = `${P}host`;
const GUEST = `${P}guest`;
const ROOM = `${P}room`;

function request(uid, data) {
  return { auth: { uid, token: {} }, data };
}

// Mimics what a CallableResponse proxy is to the handler: a truthy object
// that is NOT a LiveKit control. Recording property reads lets the test
// assert the handler never treats it as one.
function trackedSecondArgument() {
  const reads = [];
  return {
    reads,
    proxy: new Proxy(
      {},
      {
        get(_target, property) {
          reads.push(String(property));
          return undefined;
        },
      },
    ),
  };
}

async function seedRoom() {
  await db.recursiveDelete(db.collection("rooms").doc(ROOM));
  await db
    .collection("users")
    .doc(HOST)
    .set({ uid: HOST, accountStatus: "active" });
  await db
    .collection("users")
    .doc(GUEST)
    .set({ uid: GUEST, accountStatus: "active" });
  await db.collection("rooms").doc(ROOM).set({
    hostId: HOST,
    name: "Contract room",
    status: "active",
    isLive: true,
    roomType: "scheduled",
    participantCount: 2,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  });
  await db
    .collection("rooms")
    .doc(ROOM)
    .collection("participants")
    .doc(GUEST)
    .set({
      userId: GUEST,
      role: "listener",
      isMuted: true,
      joinedAt: Timestamp.now(),
    });
}

describe("onCall invocation contract", () => {
  before(seedRoom);

  test("leaveRoomSelf ignores the framework's second argument", async () => {
    const second = trackedSecondArgument();
    await assert.rejects(
      () => leaveRoomSelf.run(request(GUEST, { roomId: ROOM }), second.proxy),
      (error) =>
        /LiveKit control-plane configuration is incomplete/.test(
          String(error?.message),
        ),
      "expected the production control path, not the injected second argument",
    );
    assert.deepEqual(
      second.reads.filter((name) =>
        ["endRoom", "revokeParticipant", "setParticipantPermissions"].includes(
          name,
        ),
      ),
      [],
      "the CallableResponse stand-in must never be used as a LiveKit control",
    );
  });

  test("setOwnRoomParticipantMute ignores the second argument", async () => {
    await seedRoom();
    const second = trackedSecondArgument();
    await assert.rejects(
      () =>
        setOwnRoomParticipantMute.run(
          request(GUEST, { roomId: ROOM, isMuted: false }),
          second.proxy,
        ),
      (error) =>
        /LiveKit control-plane configuration is incomplete/.test(
          String(error?.message),
        ),
    );
    assert.deepEqual(
      second.reads.filter((name) => name === "setParticipantPermissions"),
      [],
    );
  });

  test("deleteRoomSelf ignores the second argument", async () => {
    await seedRoom();
    const second = trackedSecondArgument();
    await assert.rejects(
      () => deleteRoomSelf.run(request(HOST, { roomId: ROOM }), second.proxy),
      (error) =>
        /LiveKit control-plane configuration is incomplete/.test(
          String(error?.message),
        ),
    );
    assert.deepEqual(
      second.reads.filter((name) => name === "endRoom"),
      [],
    );
  });
});

describe("onCall registration structure", () => {
  test("no onCall registration passes a multi-parameter named handler", () => {
    const root = path.join(__dirname, "..");
    const skip = new Set(["node_modules", "test", "scripts", ".git"]);
    const files = [];
    (function walk(dir) {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory()) {
          if (!skip.has(entry.name)) walk(path.join(dir, entry.name));
        } else if (entry.name.endsWith(".js")) {
          files.push(path.join(dir, entry.name));
        }
      }
    })(root);

    const declarationPattern = /(?:async\s+)?function\s+([A-Za-z0-9_]+)\s*\(/g;
    const arity = new Map();
    const sources = new Map();
    for (const file of files) {
      const source = fs.readFileSync(file, "utf8");
      sources.set(file, source);
      let match;
      while ((match = declarationPattern.exec(source)) !== null) {
        let depth = 1;
        let parameters = "";
        for (let i = match.index + match[0].length; depth > 0; i += 1) {
          const character = source[i];
          if (character === "(") depth += 1;
          else if (character === ")") depth -= 1;
          if (depth > 0) parameters += character;
        }
        const count = parameters
          .split(",")
          .map((part) => part.trim())
          .filter(Boolean).length;
        arity.set(match[1], count);
      }
    }

    const offenders = [];
    for (const [file, source] of sources) {
      const registration = /\bonCall\s*\(/g;
      let match;
      while ((match = registration.exec(source)) !== null) {
        let depth = 1;
        let argumentText = "";
        for (let i = match.index + match[0].length; depth > 0; i += 1) {
          const character = source[i];
          if (character === "(") depth += 1;
          else if (character === ")") depth -= 1;
          if (depth > 0) argumentText += character;
        }
        const topLevel = [];
        let nested = 0;
        let current = "";
        for (const character of argumentText) {
          if ("([{".includes(character)) nested += 1;
          if (")]}".includes(character)) nested -= 1;
          if (character === "," && nested === 0) {
            topLevel.push(current);
            current = "";
          } else {
            current += character;
          }
        }
        topLevel.push(current);
        const meaningful = topLevel.map((part) => part.trim()).filter(Boolean);
        const last = meaningful[meaningful.length - 1] ?? "";
        if (/^[A-Za-z0-9_]+$/.test(last) && (arity.get(last) ?? 0) > 1) {
          offenders.push(
            `${path.relative(root, file)}: onCall(..., ${last}) — ` +
              `${last} declares ${arity.get(last)} parameters`,
          );
        }
      }
    }

    assert.deepEqual(
      offenders,
      [],
      "register a one-argument wrapper instead; the framework always passes " +
        "(request, responseProxy)",
    );
  });
});
