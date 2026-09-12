const assert = require("node:assert/strict");
const { test } = require("node:test");
const { inspectLegacyMigrationInventory } = require("../servers/migration_inventory");

// Independent contract QA for operator-supplied metadata only. No live
// collection, canonical authorization, migration writer or provider is used.
const SCOPES = {
  club: ["members", "invites", "channels"],
  room: ["roomMembers", "participants", "messages"],
};
const stamp = (seconds = 1_800_000_000, nanoseconds = 765432100) => ({ seconds, nanoseconds });
const record = (id, updateTime = stamp()) => ({ id, updateTime });
const inventory = (kind = "club", id = "qa_root") => {
  const path = `${kind === "club" ? "clubs" : "rooms"}/${id}`;
  return {
    inventoryVersion: 1,
    source: { kind, id, path, expectedUpdateTime: stamp() },
    observedRoot: { path, updateTime: stamp(), readTime: stamp(1_800_000_001) },
    readTime: stamp(1_800_000_001),
    pages: SCOPES[kind].map((scope) => ({
      scope, parentPath: path, readTime: stamp(1_800_000_001), pageIndex: 0,
      startAfter: null, nextCursor: null, exhausted: true, records: [],
    })),
  };
};
const coverage = (report, scope) => report.claimedCollectionCoverage.find((row) => row.scope === scope);
const inspect = (input) => inspectLegacyMigrationInventory(input);
const invalid = (input) => assert.throws(() => inspect(input), {
  name: "TypeError", message: "Invalid server migration inventory evidence.",
});
const pageChain = (input, scope, groups, exhausted = true) => {
  const pages = groups.map((ids, pageIndex) => ({
    scope, parentPath: input.source.path, readTime: { ...input.readTime }, pageIndex,
    startAfter: pageIndex === 0 ? null : groups[pageIndex - 1].at(-1),
    nextCursor: pageIndex === groups.length - 1 && exhausted ? null : ids.at(-1),
    exhausted: pageIndex === groups.length - 1 && exhausted,
    records: ids.map((id) => record(id)),
  }));
  input.pages = [...input.pages.filter((page) => page.scope !== scope), ...pages];
  return input;
};
const freeze = (value) => {
  if (value !== null && typeof value === "object") {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
};
const reverseObjectKeys = (value) => Array.isArray(value)
  ? value.map(reverseObjectKeys)
  : value !== null && typeof value === "object"
    ? Object.fromEntries(Object.entries(value).reverse().map(([key, child]) => [key, reverseObjectKeys(child)]))
    : value;
const nullPrototype = (value) => Array.isArray(value)
  ? value.map(nullPrototype)
  : value !== null && typeof value === "object"
    ? Object.assign(Object.create(null), Object.fromEntries(Object.entries(value).map(([key, child]) => [key, nullPrototype(child)])))
    : value;
const limitedInput = (pageCount, recordsPerPage) => {
  const input = inventory();
  const groups = Array.from({ length: pageCount }, (_, pageIndex) =>
    Array.from({ length: recordsPerPage }, (_, index) => `id_${String(pageIndex * recordsPerPage + index).padStart(6, "0")}`));
  pageChain(input, "members", groups);
  input.pages = input.pages.filter((page) => page.scope === "members");
  return input;
};

for (const kind of ["club", "room"]) {
  test(`independent inventory: closed ${kind} metadata claims never become full inventory or apply permission`, () => {
    const input = inventory(kind);
    const output = inspect(input);
    assert.deepEqual(Object.keys(output).sort(), [
      "reportVersion", "scope", "dryRun", "source", "readTime", "sourceVersionMatches",
      "requiredScopes", "claimedCollectionCoverage", "evidenceStatus", "unresolvedReasons",
      "unverifiedGates", "fullInventoryComplete", "applyReady", "writeCount", "reportDigest",
    ].sort());
    assert.equal(output.reportVersion, 1);
    assert.equal(output.scope, "inventory-page-chain-only");
    assert.equal(output.dryRun, true);
    assert.equal(output.sourceVersionMatches, true);
    assert.equal(output.evidenceStatus, "structurally-consistent-claims");
    assert.equal(output.fullInventoryComplete, false);
    assert.equal(output.applyReady, false);
    assert.equal(output.writeCount, 0);
    assert.deepEqual(output.requiredScopes, SCOPES[kind]);
    assert.deepEqual(output.unresolvedReasons, []);
    assert.ok(output.unverifiedGates.length > 0);
    assert.ok(output.unverifiedGates.every((gate) => typeof gate === "string" && gate.length > 0));
    assert.match(output.reportDigest, /^[a-f0-9]{64}$/u);
    for (const scope of SCOPES[kind]) {
      assert.deepEqual(coverage(output, scope), { scope, status: "claimed-exhausted", pageCount: 1, recordCount: 0 });
    }
  });
}

test("independent inventory: missing evidence remains explicitly unresolved", () => {
  const input = inventory();
  input.pages = [];
  const report = inspect(input);
  assert.equal(report.evidenceStatus, "unresolved");
  assert.ok(report.unresolvedReasons.length > 0);
  for (const scope of SCOPES.club) {
    assert.deepEqual(coverage(report, scope), { scope, status: "missing", pageCount: 0, recordCount: 0 });
  }
  assert.equal(report.fullInventoryComplete, false);
  assert.equal(report.applyReady, false);
});

test("independent inventory: a valid open chain is unresolved, not a false closed claim", () => {
  const input = pageChain(inventory(), "members", [["a", "b"], ["c"]], false);
  const report = inspect(input);
  assert.equal(report.evidenceStatus, "unresolved");
  assert.deepEqual(coverage(report, "members"), { scope: "members", status: "unclosed", pageCount: 2, recordCount: 3 });
  assert.equal(coverage(report, "invites").status, "claimed-exhausted");
  assert.equal(report.applyReady, false);
});

test("independent inventory: source version mismatch poisons every present scope without claiming completeness", () => {
  for (const direction of [-1, 1]) {
    const input = pageChain(inventory(), "members", [["a"], ["b"]], false);
    input.pages = input.pages.filter((page) => page.scope !== "channels");
    input.source.expectedUpdateTime.nanoseconds += direction;
    const report = inspect(input);
    assert.equal(report.sourceVersionMatches, false);
    assert.equal(report.evidenceStatus, "unresolved");
    assert.deepEqual(report.source.expectedUpdateTime, input.source.expectedUpdateTime);
    assert.deepEqual(report.source.observedUpdateTime, input.observedRoot.updateTime);
    assert.equal(coverage(report, "members").status, "unresolved-source-change");
    assert.equal(coverage(report, "invites").status, "unresolved-source-change");
    assert.equal(coverage(report, "channels").status, "missing");
    assert.equal(report.fullInventoryComplete, false);
    assert.equal(report.applyReady, false);
  }
});

test("independent inventory: shuffled outer pages and object insertion order produce identical reports", () => {
  const input = pageChain(pageChain(inventory(), "members", [["a"], ["b", "c"]]), "invites", [["a"], []]);
  const expected = inspect(input);
  const permutations = [input.pages.toReversed(), [...input.pages.slice(2), ...input.pages.slice(0, 2)]];
  for (const pages of permutations) assert.deepEqual(inspect(reverseObjectKeys({ ...input, pages })), expected);
  assert.deepEqual(coverage(expected, "invites"), { scope: "invites", status: "claimed-exhausted", pageCount: 2, recordCount: 1 });
});

test("independent inventory: strict UTF-8 ordering differs correctly from UTF-16 and never normalizes IDs", () => {
  const ids = [" ", " A ", "A", "a", "e\u0301", "é", "\uE000", "\u{10000}"];
  const report = inspect(pageChain(inventory(), "members", [ids.slice(0, 4), ids.slice(4)]));
  assert.equal(coverage(report, "members").recordCount, ids.length);
  invalid(pageChain(inventory(), "members", [["\u{10000}", "\uE000"]]));
  invalid(pageChain(inventory(), "members", [["é", "e\u0301"]]));
});

test("independent inventory: duplicate or descending record IDs within and across pages reject", () => {
  for (const groups of [[["a", "a"]], [["b", "a"]], [["a"], ["a"]], [["b"], ["a"]]]) {
    invalid(pageChain(inventory(), "members", groups));
  }
  const input = inventory();
  for (const scope of SCOPES.club) pageChain(input, scope, [["same-opaque-id"]]);
  assert.equal(inspect(input).evidenceStatus, "structurally-consistent-claims");
});

test("independent inventory: exact opaque ID limits are UTF-16 units, not code points or UTF-8 bytes", () => {
  for (const id of ["x".repeat(128), "😀".repeat(64), "é".repeat(128), " ", "constructor", "toString"]) {
    assert.equal(coverage(inspect(pageChain(inventory(), "members", [[id]])), "members").recordCount, 1);
  }
  for (const id of ["x".repeat(129), "😀".repeat(65), "😀".repeat(64) + "a", ""]) {
    invalid(pageChain(inventory(), "members", [[id]]));
  }
});

test("independent inventory: reserved paths, controls and malformed Unicode reject equally for records and cursors", () => {
  for (const id of [".", "..", "__private__", "__id123__", "a/b", "a\u0000b", "a\n", "a\u007Fb", "a\u0085b", "\uD800", "\uDC00", "x\uD800y", 7, null, false]) {
    invalid(pageChain(inventory(), "members", [[id]]));
    const cursor = pageChain(inventory(), "members", [["a"]], false);
    cursor.pages.find((page) => page.scope === "members").nextCursor = id;
    invalid(cursor);
  }
});

test("independent inventory: source IDs retain the exact root ASCII boundary and canonical path binding", () => {
  for (const id of ["A_a-9", "__proto__", "x".repeat(128)]) assert.equal(inspect(inventory("room", id)).source.id, id);
  for (const id of ["", "x".repeat(129), "room/foreign", "é", " room", "room\n"]) invalid(inventory("room", id));
  for (const mutate of [
    (input) => { input.source.kind = "server"; },
    (input) => { input.source.path = "rooms/qa_root"; },
    (input) => { input.source.path += "/"; },
    (input) => { input.observedRoot.path = "clubs/foreign"; },
    (input) => { input.pages[0].parentPath = "clubs/foreign"; },
    (input) => { input.pages[0].parentPath = "clubs/qa_root/members"; },
    (input) => { input.pages[0].scope = "roomMembers"; },
    (input) => { input.pages[0].scope = "members/foreign"; },
  ]) { const input = inventory(); mutate(input); invalid(input); }
});

test("independent inventory: page sequence cannot omit, duplicate or continue after a terminal page", () => {
  for (const mutate of [
    (pages) => { pages[0].pageIndex = 1; },
    (pages) => { pages[1].pageIndex = 2; },
    (pages) => { pages[1].pageIndex = 0; },
    (pages) => { pages[0].exhausted = true; pages[0].nextCursor = null; },
    (pages) => { pages[0].pageIndex = -1; },
    (pages) => { pages[0].pageIndex = 0.5; },
    (pages) => { pages[0].pageIndex = "0"; },
    (pages) => { pages[1].startAfter = "foreign"; },
    (pages) => { pages[0].startAfter = "a"; },
  ]) {
    const input = pageChain(inventory(), "members", [["a"], ["b"]]);
    mutate(input.pages.filter((page) => page.scope === "members"));
    invalid(input);
  }
});

test("independent inventory: cursor terminality and progress are explicit, not truthy or guessed", () => {
  for (const mutate of [
    (page) => { page.nextCursor = "a"; },
    (page) => { page.exhausted = false; page.nextCursor = null; },
    (page) => { page.exhausted = false; page.nextCursor = "b"; },
    (page) => { page.exhausted = false; page.nextCursor = "a"; page.records = []; },
    (page) => { page.exhausted = "true"; },
    (page) => { delete page.nextCursor; },
    (page) => { page.startAfter = undefined; },
  ]) {
    const input = pageChain(inventory(), "members", [["a"]]);
    mutate(input.pages.find((page) => page.scope === "members"));
    invalid(input);
  }
});

test("independent inventory: all timestamps enforce exact seconds and nanoseconds boundaries", () => {
  for (const timestamp of [stamp(0, 0), stamp(253402300799, 999999999)]) {
    const input = pageChain(inventory(), "members", [["a"]]);
    input.source.expectedUpdateTime = { ...timestamp };
    input.observedRoot.updateTime = { ...timestamp };
    input.observedRoot.readTime = { ...timestamp };
    input.readTime = { ...timestamp };
    for (const page of input.pages) {
      page.readTime = { ...timestamp };
      for (const value of page.records) value.updateTime = { ...timestamp };
    }
    assert.equal(inspect(input).sourceVersionMatches, true);
  }
  const slots = [
    (input) => input.source.expectedUpdateTime,
    (input) => input.observedRoot.updateTime,
    (input) => input.observedRoot.readTime,
    (input) => input.readTime,
    (input) => input.pages[0].readTime,
    (input) => input.pages.find((page) => page.scope === "members").records[0].updateTime,
  ];
  const malformed = [stamp(-1, 0), stamp(253402300800, 0), stamp(-0, 0), stamp(1, -0),
    stamp(1.5, 0), stamp("1", 0), stamp(Infinity, 0), stamp(NaN, 0), stamp(Number.MAX_SAFE_INTEGER + 1, 0),
    stamp(1, -1), stamp(1, 1000000000), stamp(1, 0.5), stamp(1, "1"), stamp(1, NaN)];
  for (const slot of slots) for (const value of malformed) {
    const input = pageChain(inventory(), "members", [["a"]]);
    Object.assign(slot(input), value);
    invalid(input);
  }
});

test("independent inventory: mismatched snapshot times and future observed updates reject at nanosecond precision", () => {
  for (const mutate of [
    (input) => { input.observedRoot.readTime.nanoseconds -= 1; },
    (input) => { input.pages[0].readTime.nanoseconds += 1; },
    (input) => { input.observedRoot.updateTime = { ...input.readTime, nanoseconds: input.readTime.nanoseconds + 1 }; },
    (input) => { input.pages.find((page) => page.scope === "members").records[0].updateTime = { ...input.readTime, nanoseconds: input.readTime.nanoseconds + 1 }; },
  ]) {
    const input = pageChain(inventory(), "members", [["a"]]);
    mutate(input); invalid(input);
  }
  const input = pageChain(inventory(), "members", [["a"]]);
  input.pages.find((page) => page.scope === "members").records[0].updateTime = stamp(input.readTime.seconds - 1, 999999999);
  assert.equal(inspect(input).evidenceStatus, "structurally-consistent-claims");
});

test("independent inventory: malformed envelopes and undeclared content never become accepted metadata", () => {
  for (const input of [null, undefined, true, [], new Date(), "SECRET_ENVELOPE"]) invalid(input);
  const changes = [
    (input) => { input.inventoryVersion = 2; },
    (input) => { input.inventoryVersion = "1"; },
    (input) => { input.db = "SECRET_DB"; },
    (input) => { input.source.roles = ["owner"]; },
    (input) => { input.observedRoot.data = { private: "SECRET_DATA" }; },
    (input) => { input.pages[0].token = "SECRET_TOKEN"; },
    (input) => { input.pages.find((page) => page.scope === "members").records[0].data = { body: "SECRET_BODY" }; },
    (input) => { delete input.observedRoot; },
    (input) => { input.source = null; },
    (input) => { input.pages = {}; },
  ];
  for (const change of changes) {
    const input = pageChain(inventory(), "members", [["a"]]);
    change(input); invalid(input);
  }
});

test("independent inventory: only plain data objects are accepted; null prototypes retain identical semantics", () => {
  const input = pageChain(inventory(), "members", [["a"], ["b"]]);
  assert.deepEqual(inspect(nullPrototype(input)), inspect(input));
  for (const slot of [(value) => value, (value) => value.source, (value) => value.observedRoot,
    (value) => value.readTime, (value) => value.pages[0],
    (value) => value.pages.find((page) => page.scope === "members").records[0]]) {
    const hostile = structuredClone(input);
    Object.setPrototypeOf(slot(hostile), { inherited: "SECRET_PROTOTYPE" });
    invalid(hostile);
  }
});

test("independent inventory: accessors are rejected without invoking attacker-controlled getters", () => {
  const slots = [
    [(input) => input, "source"], [(input) => input.source, "path"],
    [(input) => input.observedRoot, "updateTime"], [(input) => input.readTime, "seconds"],
    [(input) => input.pages[0], "records"],
    [(input) => input.pages.find((page) => page.scope === "members").records[0], "id"],
  ];
  let invoked = 0;
  for (const [slot, key] of slots) {
    const input = pageChain(inventory(), "members", [["a"]]);
    Object.defineProperty(slot(input), key, { enumerable: true, get() { invoked += 1; throw new Error("SECRET_ACCESSOR"); } });
    invalid(input);
  }
  assert.equal(invoked, 0);
});

test("independent inventory: non-enumerable and symbol properties cannot hide unvalidated payloads", () => {
  for (const slot of [(input) => input, (input) => input.source, (input) => input.pages[0], (input) => input.readTime]) {
    for (const key of ["hiddenToken", Symbol("SECRET_SYMBOL")]) {
      const input = inventory();
      Object.defineProperty(slot(input), key, { value: "SECRET_PAYLOAD", enumerable: false });
      invalid(input);
    }
  }
  const input = inventory();
  Object.defineProperty(input.source, "path", { value: input.source.path, enumerable: false });
  invalid(input);
});

test("independent inventory: sparse, accessor-backed and decorated arrays fail before consuming records", () => {
  for (const target of ["pages", "records"]) for (const mode of ["hole", "extra", "symbol", "getter"]) {
    const input = pageChain(inventory(), "members", [["a"]]);
    const array = target === "pages" ? input.pages : input.pages.find((page) => page.scope === "members").records;
    let invoked = 0;
    if (mode === "hole") delete array[0];
    if (mode === "extra") array.secret = "SECRET_ARRAY";
    if (mode === "symbol") array[Symbol("SECRET_ARRAY")] = true;
    if (mode === "getter") Object.defineProperty(array, "0", { enumerable: true, get() { invoked += 1; throw new Error("SECRET_ARRAY"); } });
    invalid(input);
    assert.equal(invoked, 0);
  }
});

test("independent inventory: per-page bound accepts 500 records and rejects 501", () => {
  const input = limitedInput(1, 500);
  assert.equal(coverage(inspect(input), "members").recordCount, 500);
  invalid(limitedInput(1, 501));
});

test("independent inventory: total page bound accepts 1000 pages and rejects 1001", () => {
  assert.equal(coverage(inspect(limitedInput(1000, 1)), "members").pageCount, 1000);
  invalid(limitedInput(1001, 1));
});

test("independent inventory: total record bound accepts 10000 and counts records across scopes", () => {
  const input = limitedInput(20, 500);
  assert.equal(coverage(inspect(input), "members").recordCount, 10000);
  pageChain(input, "invites", [["extra"]]);
  invalid(input);
});

test("independent inventory: deep-frozen input stays unchanged and reports do not retain mutable input metadata", () => {
  const input = pageChain(inventory(), "members", [["a"], ["b"]]);
  const before = structuredClone(input);
  const report = inspect(freeze(input));
  assert.deepEqual(input, before);
  assert.deepEqual(inspect(input), report);
  const mutable = structuredClone(before);
  const snapshot = inspect(mutable);
  const serialized = JSON.stringify(snapshot);
  mutable.source.expectedUpdateTime.nanoseconds += 1;
  mutable.observedRoot.updateTime.nanoseconds += 1;
  mutable.readTime.nanoseconds += 1;
  mutable.pages[0].records.push(record("changed"));
  assert.equal(JSON.stringify(snapshot), serialized);
});

test("independent inventory: digest binds record identity, versions, read time and pagination, not only counts", () => {
  const original = pageChain(inventory(), "members", [["private-a", "private-b"]]);
  const base = inspect(original).reportDigest;
  const inputs = [];
  const renamed = structuredClone(original);
  renamed.pages.find((page) => page.scope === "members").records[0].id = "private-A";
  inputs.push(renamed);
  const updated = structuredClone(original);
  updated.pages.find((page) => page.scope === "members").records[0].updateTime.nanoseconds += 1;
  inputs.push(updated);
  const rootChanged = structuredClone(original);
  rootChanged.source.expectedUpdateTime.nanoseconds += 1;
  inputs.push(rootChanged);
  const observedChanged = structuredClone(original);
  observedChanged.observedRoot.updateTime.nanoseconds += 1;
  inputs.push(observedChanged);
  const snapshotChanged = structuredClone(original);
  snapshotChanged.readTime.nanoseconds += 1;
  snapshotChanged.observedRoot.readTime.nanoseconds += 1;
  for (const page of snapshotChanged.pages) page.readTime.nanoseconds += 1;
  inputs.push(snapshotChanged);
  inputs.push(pageChain(inventory(), "members", [["private-a"], ["private-b"]]));
  const digests = inputs.map((input) => inspect(input).reportDigest);
  assert.ok(digests.every((digest) => digest !== base));
  assert.equal(new Set(digests).size, digests.length);
});

test("independent inventory: supplied private record identities never appear in reports or validation errors", () => {
  const secret = "PRIVATE_OPAQUE_ID_73cc3c";
  const input = pageChain(inventory("room"), "participants", [[secret]]);
  const report = inspect(input);
  assert.equal(JSON.stringify(report).includes(secret), false);
  assert.deepEqual(report.source, { ...input.source, observedUpdateTime: input.observedRoot.updateTime });
  input.pages.find((page) => page.scope === "participants").records[0].body = secret;
  assert.throws(() => inspect(input), (error) => {
    assert.equal(error.constructor, TypeError);
    assert.equal(error.message, "Invalid server migration inventory evidence.");
    assert.equal(String(error).includes(secret), false);
    assert.deepEqual(Object.keys(error), []);
    return true;
  });
});

test("independent inventory: invocation is synchronous and performs no filesystem, network or console work", async (t) => {
  const input = freeze(pageChain(inventory(), "members", [["a"], ["b"]]));
  const calls = [];
  const forbidden = (label) => () => { calls.push(label); throw new Error("Unexpected inventory inspector I/O"); };
  for (const [moduleName, methods] of [
    ["node:fs", ["readFileSync", "writeFileSync", "writeFile", "appendFileSync"]],
    ["node:http", ["request", "get"]], ["node:https", ["request", "get"]],
    ["node:net", ["connect", "createConnection"]],
  ]) {
    const module = require(moduleName);
    for (const method of methods) t.mock.method(module, method, forbidden(`${moduleName}.${method}`));
  }
  t.mock.method(globalThis, "fetch", forbidden("fetch"));
  for (const method of ["log", "warn", "error"]) t.mock.method(console, method, forbidden(`console.${method}`));
  const output = inspect(input);
  assert.equal(typeof output.then, "undefined");
  await Promise.resolve();
  assert.deepEqual(calls, []);
  assert.equal(output.writeCount, 0);
});
