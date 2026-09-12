"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");
const { INVENTORY_VERSION, MAX_INVENTORY_RECORDS, MAX_INVENTORY_PAGES,
  MAX_PAGE_RECORDS, REQUIRED_SCOPES, inspectLegacyMigrationInventory: inspect } = require("../servers/migration_inventory");

const ERROR_MESSAGE = "Invalid server migration inventory evidence.";
const stamp = (seconds = 100, nanoseconds = 123456789) => ({ seconds, nanoseconds });
const row = (id, updateTime = stamp()) => ({ id, updateTime });
function page(scope = "members", patch = {}) {
  return { scope, parentPath: "clubs/club_a", readTime: stamp(200), pageIndex: 0,
    startAfter: null, nextCursor: null, exhausted: true, records: [], ...patch };
}
function evidence(kind = "club") {
  const path = kind === "club" ? "clubs/club_a" : "rooms/room_a";
  return { inventoryVersion: INVENTORY_VERSION,
    source: { kind, id: kind === "club" ? "club_a" : "room_a", path, expectedUpdateTime: stamp() },
    observedRoot: { path, updateTime: stamp(), readTime: stamp(200) }, readTime: stamp(200),
    pages: REQUIRED_SCOPES[kind].map((scope) => page(scope, { parentPath: path })) };
}
function rejects(input) {
  assert.throws(() => inspect(input), (error) => error instanceof TypeError && error.message === ERROR_MESSAGE);
}
function held(report) {
  assert.equal(report.dryRun, true);
  assert.equal(report.scope, "inventory-page-chain-only");
  assert.equal(report.fullInventoryComplete, false);
  assert.equal(report.applyReady, false);
  assert.equal(report.writeCount, 0);
  assert.ok(report.unverifiedGates.includes("operator-evidence-not-independently-verified"));
  assert.ok(report.unverifiedGates.includes("complete-related-record-and-media-generation-inventory"));
  assert.match(report.reportDigest, /^[a-f0-9]{64}$/u);
}

test("both closed registries report only claimed empty coverage and never permit apply", () => {
  for (const kind of ["club", "room"]) {
    const result = inspect(evidence(kind));
    held(result);
    assert.equal(result.evidenceStatus, "structurally-consistent-claims");
    assert.deepEqual(result.requiredScopes, REQUIRED_SCOPES[kind]);
    assert.ok(result.claimedCollectionCoverage.every((scope) => scope.status === "claimed-exhausted" && scope.recordCount === 0));
  }
});

test("omitted scopes are unresolved, not silently empty or caller-selected completeness", () => {
  const input = evidence(); input.pages = [];
  const result = inspect(input); held(result);
  assert.equal(result.evidenceStatus, "unresolved");
  assert.equal(result.unresolvedReasons.length, 3);
  assert.ok(result.claimedCollectionCoverage.every((scope) => scope.status === "missing" && scope.pageCount === 0));
});

test("a well-formed unfinished chain remains unresolved; empty nonfinal pages reject", () => {
  const input = evidence();
  input.pages[0] = page("members", { records: [row("a")], exhausted: false, nextCursor: "a" });
  const result = inspect(input); held(result);
  assert.ok(result.unresolvedReasons.includes("unclosed-scope:members"));
  assert.equal(result.claimedCollectionCoverage[0].status, "unclosed");
  input.pages[0].records = []; rejects(input);
});

test("multi-page chains canonicalize outer order but never reorder records", () => {
  const input = evidence();
  input.pages[0] = page("members", { records: [row("a"), row("b")], exhausted: false, nextCursor: "b" });
  input.pages.push(page("members", { pageIndex: 1, startAfter: "b", records: [row("c")] }));
  const first = inspect(input);
  input.pages.reverse();
  assert.deepEqual(inspect(input), first);
  held(first);
  assert.deepEqual(first.claimedCollectionCoverage[0], { scope: "members", status: "claimed-exhausted", pageCount: 2, recordCount: 3 });
  input.pages.find((value) => value.scope === "members" && value.pageIndex === 0).records.reverse();
  rejects(input);
});

test("terminal empty page is valid after a nonempty page and exact cursor", () => {
  const input = evidence();
  input.pages[0] = page("members", { records: [row("a")], exhausted: false, nextCursor: "a" });
  input.pages.push(page("members", { pageIndex: 1, startAfter: "a" }));
  assert.equal(inspect(input).evidenceStatus, "structurally-consistent-claims");
});

test("contradictory page indices, cursor gaps, duplicates and post-end pages reject", () => {
  for (const patch of [
    { pageIndex: 1 }, { pageIndex: -1 }, { pageIndex: -0 }, { pageIndex: 0.5 },
    { startAfter: "a" }, { nextCursor: "a" }, { exhausted: "true" },
    { records: [row("b"), row("a")] }, { records: [row("a"), row("a")] },
  ]) { const input = evidence(); Object.assign(input.pages[0], patch); rejects(input); }
  for (const second of [
    page("members"), page("members", { pageIndex: 2, startAfter: "a" }),
    page("members", { pageIndex: 1, startAfter: "b" }),
    page("members", { pageIndex: 1, startAfter: "a", records: [row("a")] }),
  ]) {
    const input = evidence(); input.pages[0] = page("members", { records: [row("a")], exhausted: false, nextCursor: "a" });
    input.pages.push(second); rejects(input);
  }
  const postEnd = evidence(); postEnd.pages.push(page("members", { pageIndex: 1 })); rejects(postEnd);
});

test("source identity and every scope are closed to foreign roots and paths", () => {
  for (const mutate of [
    (input) => { input.source.kind = "server"; },
    (input) => { input.source.id = "foreign"; },
    (input) => { input.source.path = "rooms/club_a"; },
    (input) => { input.observedRoot.path = "clubs/foreign"; },
    (input) => { input.pages[0].parentPath = "clubs/foreign"; },
    (input) => { input.pages[0].scope = "roomMembers"; },
    (input) => { input.pages[0].scope = "channels/c/messages"; },
    (input) => { input.pages[0].scope = "media"; },
  ]) { const input = evidence(); mutate(input); rejects(input); }
});

test("expected and observed source generations compare seconds AND nanoseconds", () => {
  for (const version of [stamp(101), stamp(100, 123456790), stamp(500)]) {
    const input = evidence(); input.source.expectedUpdateTime = version;
    const result = inspect(input); held(result);
    assert.equal(result.sourceVersionMatches, false);
    assert.equal(result.evidenceStatus, "unresolved");
    assert.deepEqual(result.unresolvedReasons, ["source-version-changed"]);
    assert.ok(result.claimedCollectionCoverage.every((scope) => scope.status === "unresolved-source-change"));
  }
});

test("all read times agree and observed updates cannot exceed their claimed read time", () => {
  for (const mutate of [
    (input) => { input.pages[0].readTime.nanoseconds += 1; },
    (input) => { input.observedRoot.readTime.nanoseconds += 1; },
    (input) => { input.observedRoot.updateTime = stamp(201); },
    (input) => { input.pages[0].records = [row("a", stamp(200, 123456790))]; },
  ]) { const input = evidence(); mutate(input); rejects(input); }
  const equal = evidence(); equal.pages[0].records = [row("a", stamp(200))];
  assert.equal(inspect(equal).sourceVersionMatches, true);
});

test("timestamps preserve nanos and reject malformed values uniformly", () => {
  for (const timestamp of [null, {}, { seconds: 0 }, stamp(-1), stamp(-0), stamp(0, -0), stamp(1.5),
    stamp(NaN), stamp(Infinity), stamp(253402300800), stamp(0, -1), stamp(0, 1e9), stamp(0, 1.5),
    { ...stamp(), data: "private" }]) {
    const input = evidence(); input.source.expectedUpdateTime = timestamp; rejects(input);
  }
  const input = evidence(); input.source.expectedUpdateTime = stamp(0, 0);
  input.observedRoot.updateTime = stamp(0, 0); input.readTime = stamp(253402300799, 999999999);
  input.observedRoot.readTime = { ...input.readTime };
  input.pages.forEach((page) => { page.readTime = { ...input.readTime }; });
  assert.deepEqual(inspect(input).readTime, input.readTime);
});

test("UTF8 query order differs from UTF16 for BMP/astral IDs and matches installed SDK", () => {
  const { dirname, join } = require("node:path");
  // Test the installed implementation without importing an unexported package
  // subpath. The production inventory module never loads this SDK.
  const { compareUtf8Strings } = require(join(dirname(require.resolve("@google-cloud/firestore")), "order.js"));
  const ids = ["a", "a\u0301", "z", "é", "\ue000", "😀"];
  const input = evidence(); input.pages[0].records = ids.map((id) => row(id));
  assert.equal(inspect(input).claimedCollectionCoverage[0].recordCount, ids.length);
  for (let index = 1; index < ids.length; index += 1) {
    assert.ok(compareUtf8Strings(ids[index - 1], ids[index]) < 0);
    assert.ok(Buffer.compare(Buffer.from(ids[index - 1]), Buffer.from(ids[index])) < 0);
  }
  input.pages[0].records = [row("😀"), row("\ue000")]; rejects(input);
});

test("opaque equivalent Unicode, spaces and case remain distinct without normalization", () => {
  const input = evidence();
  const ids = [" A ", "A", "a", "e\u0301", "é"];
  input.pages[0].records = ids.map((id) => row(id));
  const result = inspect(input); assert.equal(result.claimedCollectionCoverage[0].recordCount, 5);
  input.pages[0].records[0].id = " B ";
  assert.notEqual(inspect(input).reportDigest, result.reportDigest);
});

test("unsupported record and cursor IDs fail instead of being skipped or aliased", () => {
  for (const id of ["", "x".repeat(129), "/", "a/b", ".", "..", "__id123__", "__reserved__",
    "\ud800", "\udc00", "ok\ud800bad", "a\u0000", "a\u007f", 123, null]) {
    const input = evidence(); input.pages[0].records = [row(id)]; rejects(input);
    const cursor = evidence(); cursor.pages[0].startAfter = id;
    if (id !== null) rejects(cursor);
  }
  const input = evidence(); input.pages[0].records = [row("x".repeat(128))];
  assert.equal(inspect(input).claimedCollectionCoverage[0].recordCount, 1);
});

test("private payload keys, accessors, symbols, class instances and sparse arrays reject without evaluation", () => {
  for (const key of ["body", "data", "token", "url", "role", "collectionPath"]) {
    const input = evidence(); input.pages[0][key] = "DO_NOT_ECHO_SECRET"; rejects(input);
  }
  let evaluated = false;
  const input = evidence(); Object.defineProperty(input, "readTime", { enumerable: true, get() { evaluated = true; throw new Error("secret"); } });
  rejects(input); assert.equal(evaluated, false);
  const symbol = evidence(); symbol[Symbol("secret")] = true; rejects(symbol);
  const sparse = evidence(); sparse.pages = new Array(1); rejects(sparse);
  const extra = evidence(); extra.pages.extra = "secret"; rejects(extra);
  const hidden = evidence(); Object.defineProperty(hidden, "secret", { value: true }); rejects(hidden);
  rejects(new (class Evidence {})());
  for (const version of [undefined, null, "1", 0, 2]) { const input = evidence(); input.inventoryVersion = version; rejects(input); }
});

test("global page and per-page record boundaries are enforced, not truncated", () => {
  const input = evidence();
  input.pages[0].records = Array.from({ length: MAX_PAGE_RECORDS }, (_, index) => row(`r_${String(index).padStart(6, "0")}`));
  assert.equal(inspect(input).claimedCollectionCoverage[0].recordCount, MAX_PAGE_RECORDS);
  input.pages[0].records.push(row("z")); rejects(input);
  const many = evidence();
  many.pages = Array.from({ length: MAX_INVENTORY_PAGES }, (_, index) => page("members", {
    pageIndex: index, startAfter: index ? `r_${String(index - 1).padStart(6, "0")}` : null,
    records: [row(`r_${String(index).padStart(6, "0")}`)], exhausted: index === MAX_INVENTORY_PAGES - 1,
    nextCursor: index === MAX_INVENTORY_PAGES - 1 ? null : `r_${String(index).padStart(6, "0")}`,
  }));
  assert.equal(inspect(many).claimedCollectionCoverage[0].pageCount, MAX_INVENTORY_PAGES);
  many.pages.push(page("invites")); rejects(many);
});

test("global record boundary accepts 10000 and rejects 10001 across scopes", () => {
  const input = evidence(); input.pages = input.pages.slice(1);
  const pages = MAX_INVENTORY_RECORDS / MAX_PAGE_RECORDS;
  const id = (index) => `r_${String(index).padStart(6, "0")}`;
  for (let index = 0; index < pages; index += 1) {
    input.pages.push(page("members", { pageIndex: index, startAfter: index ? id(index * MAX_PAGE_RECORDS - 1) : null,
      exhausted: index === pages - 1, nextCursor: index === pages - 1 ? null : id((index + 1) * MAX_PAGE_RECORDS - 1),
      records: Array.from({ length: MAX_PAGE_RECORDS }, (_, offset) => row(id(index * MAX_PAGE_RECORDS + offset))) }));
  }
  assert.equal(inspect(input).claimedCollectionCoverage[0].recordCount, MAX_INVENTORY_RECORDS);
  input.pages[0].records = [row("one_extra")]; rejects(input);
});

test("aggregate contains no record IDs and digest binds hidden IDs and exact record generations", () => {
  const input = evidence(); input.pages[0].records = [row("private_record_identity")];
  const initial = inspect(input); held(initial);
  assert.equal(JSON.stringify(initial).includes("private_record_identity"), false);
  input.pages[0].records[0].updateTime.nanoseconds += 1;
  assert.notEqual(inspect(input).reportDigest, initial.reportDigest);
  input.pages[0].records[0].id = "other_private_identity";
  assert.notEqual(inspect(input).reportDigest, initial.reportDigest);
});

test("input is deeply immutable and output is detached from operator evidence", () => {
  const input = evidence(); input.pages[0].records = [row("a")];
  function freeze(value) { if (value && typeof value === "object") { Object.values(value).forEach(freeze); Object.freeze(value); } return value; }
  const before = JSON.stringify(input); freeze(input);
  const first = inspect(input); const second = inspect(input);
  assert.deepEqual(first, second); assert.equal(JSON.stringify(input), before);
  first.source.expectedUpdateTime.nanoseconds = 0;
  first.requiredScopes.pop();
  assert.deepEqual(inspect(input), second);
});
