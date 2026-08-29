const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const {
  parseArgs,
  runBackfill,
  writeFatalError,
} = require("../scripts/backfill_profile_identity");

class FakeQuery {
  constructor(database, { limit = 500, after = null } = {}) {
    this.database = database;
    this.pageLimit = limit;
    this.after = after;
  }

  orderBy() {
    return this;
  }

  limit(value) {
    return new FakeQuery(this.database, { limit: value, after: this.after });
  }

  startAfter(value) {
    return new FakeQuery(this.database, {
      limit: this.pageLimit,
      after: value,
    });
  }

  async get() {
    const ids = this.database.userIds
      .filter((id) => this.after === null || id > this.after)
      .slice(0, this.pageLimit);
    const docs = ids.map((id) => ({ id }));
    return { docs, size: docs.length };
  }
}

class FakeStateReference {
  constructor(database) {
    this.database = database;
  }

  async get() {
    const data = this.database.state;
    return {
      exists: data !== null,
      data: () => data,
    };
  }

  async set(data) {
    this.database.state = { ...data };
  }

  async delete() {
    this.database.state = null;
  }
}

class FakeDatabase {
  constructor(userIds) {
    this.userIds = [...userIds].sort();
    this.state = null;
  }

  collection(name) {
    assert.equal(name, "users");
    return new FakeQuery(this);
  }

  doc(path) {
    assert.equal(path, "privateMigrationState/profileIdentityBackfill");
    return new FakeStateReference(this);
  }
}

const emptyResult = {
  writes: 0,
  conversations: 0,
  clubMirrorsScanned: 0,
  moments: 0,
  sourceUnavailable: false,
};

describe("profile identity backfill", () => {
  test("arguments default to dry-run and require explicit apply", () => {
    assert.deepEqual(parseArgs(["--project", "yovoice-ec54a"]), {
      apply: false,
      restart: false,
      project: "yovoice-ec54a",
      maxUsers: 500,
    });
    assert.equal(
      parseArgs(["--project", "yovoice-ec54a", "--apply"]).apply,
      true,
    );
  });

  test("apply resumes privately, reaches the end and reruns as a no-op", async () => {
    const database = new FakeDatabase(["uid-a", "uid-b", "uid-c"]);
    const calls = [];
    const syncIdentity = async (uid, { apply }) => {
      calls.push({ uid, apply });
      return {
        ...emptyResult,
        writes: uid === "uid-a" && calls.length === 1 ? 1 : 0,
      };
    };
    const args = {
      apply: true,
      restart: false,
      project: "yovoice-ec54a",
      maxUsers: 2,
    };

    const first = await runBackfill({ database, syncIdentity, args });
    assert.equal(first.scannedUsers, 2);
    assert.equal(first.affectedUsers, 1);
    assert.equal(first.continuationStored, true);
    assert.equal(database.state.lastUid, "uid-b");

    const second = await runBackfill({ database, syncIdentity, args });
    assert.equal(second.scannedUsers, 1);
    assert.equal(second.reachedEnd, true);
    assert.equal(second.continuationStored, false);
    assert.equal(database.state, null);

    const third = await runBackfill({
      database,
      syncIdentity: async () => emptyResult,
      args: { ...args, maxUsers: 4 },
    });
    assert.equal(third.scannedUsers, 3);
    assert.equal(third.plannedWrites, 0);
    assert.equal(database.state, null);
  });

  test("dry-run never stores a cursor or applies writes", async () => {
    const database = new FakeDatabase(["uid-a", "uid-b"]);
    const applyValues = [];
    const report = await runBackfill({
      database,
      syncIdentity: async (_uid, { apply }) => {
        applyValues.push(apply);
        return { ...emptyResult, writes: 2 };
      },
      args: {
        apply: false,
        restart: false,
        project: "yovoice-ec54a",
        maxUsers: 1,
      },
    });
    assert.deepEqual(applyValues, [false]);
    assert.equal(report.plannedWrites, 2);
    assert.equal(report.continuationStored, false);
    assert.equal(database.state, null);
  });

  test("fatal CLI output never discloses an SDK resource path", () => {
    let output = "";
    writeFatalError(
      new Error(
        "permission denied at projects/p/databases/d/documents/users/private-uid",
      ),
      { write: (value) => (output += value) },
    );
    assert.equal(output, "Profile identity backfill failed.\n");
    assert.equal(output.includes("private-uid"), false);
    assert.equal(output.includes("documents/users"), false);
  });
});
