// Test double around InMemoryFirestore (or any db with doc/getAll/
// runTransaction) that records every document path read, split into plain
// reads and transaction reads, so a test can prove WHAT a code path read and
// that no read-write transaction touched content.
function tracked(db) {
  const reads = [];
  const transactionReads = [];
  let transactions = 0;
  let batched = false;
  const wrapped = Object.create(db);
  wrapped.doc = (path) => {
    const reference = db.doc(path);
    const get = reference.get.bind(reference);
    reference.get = async () => {
      if (!batched) reads.push(reference.path);
      return get();
    };
    return reference;
  };
  wrapped.getAll = async (...references) => {
    reads.push(...references.map((reference) => reference.path));
    batched = true;
    try {
      return await db.getAll(...references);
    } finally {
      batched = false;
    }
  };
  wrapped.runTransaction = async (callback) => {
    transactions += 1;
    return db.runTransaction(async (transaction) => callback({
      ...transaction,
      get: async (reference) => {
        transactionReads.push(reference.path);
        return transaction.get(reference);
      },
      getAll: async (...references) => {
        transactionReads.push(...references.map((reference) => reference.path));
        return transaction.getAll(...references);
      },
    }));
  };
  return {
    db: wrapped,
    reads,
    transactionReads,
    transactionCount: () => transactions,
  };
}

module.exports = { tracked };
