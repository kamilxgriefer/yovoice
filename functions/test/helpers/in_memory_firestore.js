function clone(value) {
  return value === undefined ? undefined : structuredClone(value);
}

function directChild(path, collectionPath) {
  const prefix = `${collectionPath}/`;
  if (!path.startsWith(prefix)) return false;
  return !path.slice(prefix.length).includes("/");
}

class MemorySnapshot {
  constructor(reference, record) {
    this.ref = reference;
    this.id = reference.id;
    this.exists = record !== undefined;
    this._record = record;
    this.createTime = record?.createTime ?? null;
    this.updateTime = record?.updateTime ?? null;
  }

  data() {
    return this.exists ? clone(this._record.data) : undefined;
  }
}

class MemoryDocumentReference {
  constructor(database, path) {
    this.database = database;
    this.path = path.replace(/^\/+|\/+$/gu, "");
    this.id = this.path.split("/").at(-1);
  }

  collection(name) {
    return new MemoryCollectionReference(this.database, `${this.path}/${name}`);
  }

  async get() {
    return this.database._snapshot(this, this.database._documents);
  }

  async set(data, options = undefined) {
    this.database._set(this.database._documents, this, data, options);
  }

  async update(data) {
    if (!this.database._documents.has(this.path)) {
      throw new Error(`document missing: ${this.path}`);
    }
    this.database._set(this.database._documents, this, data, { merge: true });
  }
}

class MemoryQuery {
  constructor(database, collectionPath, config = {}) {
    this.database = database;
    this.collectionPath = collectionPath;
    this.config = {
      filters: config.filters ?? [],
      limit: config.limit ?? null,
      orderBys: config.orderBys ?? [],
      startAfter: config.startAfter ?? null,
    };
  }

  _copy(changes) {
    return new MemoryQuery(this.database, this.collectionPath, {
      ...this.config,
      ...changes,
    });
  }

  where(field, operator, value) {
    if (operator !== "==" && operator !== "<=") {
      throw new Error(`unsupported operator: ${operator}`);
    }
    return this._copy({
      filters: [...this.config.filters, { field, operator, value }],
    });
  }

  orderBy(field, direction = "asc") {
    if (direction !== "asc" && direction !== "desc") {
      throw new Error(`unsupported order direction: ${direction}`);
    }
    return this._copy({
      orderBys: [...this.config.orderBys, { field, direction }],
    });
  }

  limit(value) {
    return this._copy({ limit: value });
  }

  // Firestore takes one boundary value per orderBy clause. A paged
  // subcollection read (`orderBy(createdAt).orderBy(documentId())`) passes
  // two, so a single-scalar boundary silently skipped or repeated documents
  // that share a timestamp. Rest args keep every existing single-value caller
  // byte-identical.
  startAfter(...values) {
    return this._copy({ startAfter: values });
  }

  async get() {
    let entries = [...this.database._documents.entries()]
      .filter(([path]) => directChild(path, this.collectionPath));
    for (const filter of this.config.filters) {
      entries = entries.filter(([, record]) => {
        const left = record.data?.[filter.field];
        if (left === undefined) return false;
        if (filter.operator === "==") return left === filter.value;
        const normalizedLeft = left instanceof Date ? left.getTime() : left;
        const normalizedRight = filter.value instanceof Date
          ? filter.value.getTime()
          : filter.value;
        return normalizedLeft <= normalizedRight;
      });
    }
    const orderBys = this.config.orderBys.length === 0
      ? [{ field: "__name__", direction: "asc" }]
      : this.config.orderBys;
    const orderedValue = ([path, record], field) =>
      field === "__name__" ? path.split("/").at(-1) : record.data?.[field];
    entries = entries
      .filter((entry) => orderBys.every(
        ({ field }) => orderedValue(entry, field) !== undefined,
      ))
      .sort((left, right) => {
        for (const { field, direction } of orderBys) {
          const leftValue = orderedValue(left, field);
          const rightValue = orderedValue(right, field);
          const normalizedLeft = leftValue instanceof Date
            ? leftValue.getTime()
            : leftValue;
          const normalizedRight = rightValue instanceof Date
            ? rightValue.getTime()
            : rightValue;
          const comparison = normalizedLeft < normalizedRight
            ? -1
            : normalizedLeft > normalizedRight ? 1 : 0;
          if (comparison !== 0) {
            return direction === "desc" ? -comparison : comparison;
          }
        }
        return left[0].localeCompare(right[0]);
      });
    if (this.config.startAfter !== null) {
      const normalize = (value) =>
        value instanceof Date ? value.getTime() : value;
      const boundary = this.config.startAfter;
      entries = entries.filter((entry) => {
        for (let index = 0; index < boundary.length; index += 1) {
          const order = orderBys[index];
          if (order === undefined) return true;
          const left = normalize(orderedValue(entry, order.field));
          const right = normalize(boundary[index]);
          if (left === right) continue;
          return order.direction === "desc" ? left < right : left > right;
        }
        // Equal on every ordered field: this IS the boundary document.
        return false;
      });
    }
    if (this.config.limit !== null) entries = entries.slice(0, this.config.limit);
    const docs = entries.map(([path, record]) => this.database._snapshot(
      new MemoryDocumentReference(this.database, path),
      new Map([[path, record]]),
    ));
    this.database.metrics.queryDocumentReads += docs.length;
    this.database.metrics.queryCalls += 1;
    return { docs, size: docs.length, empty: docs.length === 0 };
  }
}

class MemoryCollectionReference extends MemoryQuery {
  doc(id) {
    return new MemoryDocumentReference(this.database, `${this.collectionPath}/${id}`);
  }
}

class InMemoryFirestore {
  constructor() {
    this._documents = new Map();
    this._tail = Promise.resolve();
    this.metrics = {
      getAllDocumentReads: 0,
      queryCalls: 0,
      queryDocumentReads: 0,
    };
  }

  doc(path) {
    return new MemoryDocumentReference(this, path);
  }

  collection(path) {
    return new MemoryCollectionReference(this, path);
  }

  async getAll(...references) {
    this.metrics.getAllDocumentReads += references.length;
    return Promise.all(references.map((reference) => reference.get()));
  }

  seed(path, data, {
    createTime = new Date("2026-08-16T00:00:00.000Z"),
    updateTime = createTime,
  } = {}) {
    this._documents.set(path, {
      data: clone(data),
      createTime: clone(createTime),
      updateTime: clone(updateTime),
    });
  }

  data(path) {
    return clone(this._documents.get(path)?.data);
  }

  paths(prefix = "") {
    return [...this._documents.keys()].filter((path) => path.startsWith(prefix));
  }

  _snapshot(reference, documents) {
    return new MemorySnapshot(reference, documents.get(reference.path));
  }

  _set(documents, reference, data, options = undefined) {
    const previous = documents.get(reference.path);
    const nextData = options?.merge && previous
      ? { ...clone(previous.data), ...clone(data) }
      : clone(data);
    const now = new Date("2026-08-16T12:00:00.000Z");
    documents.set(reference.path, {
      data: nextData,
      createTime: previous?.createTime ?? now,
      updateTime: now,
    });
  }

  async runTransaction(callback) {
    let release;
    const previous = this._tail;
    this._tail = new Promise((resolve) => {
      release = resolve;
    });
    await previous;
    const documents = new Map([...this._documents.entries()].map(
      ([path, record]) => [path, clone(record)],
    ));
    const transaction = {
      get: async (reference) => this._snapshot(reference, documents),
      getAll: async (...references) => references.map((reference) =>
        this._snapshot(reference, documents)),
      set: (reference, data, options) =>
        this._set(documents, reference, data, options),
      create: (reference, data) => {
        if (documents.has(reference.path)) {
          throw new Error(`document exists: ${reference.path}`);
        }
        this._set(documents, reference, data);
      },
      update: (reference, data) => {
        if (!documents.has(reference.path)) {
          throw new Error(`document missing: ${reference.path}`);
        }
        this._set(documents, reference, data, { merge: true });
      },
      delete: (reference) => documents.delete(reference.path),
    };
    try {
      const result = await callback(transaction);
      this._documents = documents;
      return result;
    } finally {
      release();
    }
  }

  batch() {
    const operations = [];
    return {
      set: (reference, data, options) =>
        operations.push({ kind: "set", reference, data, options }),
      create: (reference, data) =>
        operations.push({ kind: "create", reference, data }),
      delete: (reference) => operations.push({ kind: "delete", reference }),
      commit: async () => {
        await this.runTransaction(async (transaction) => {
          for (const operation of operations) {
            transaction[operation.kind](
              operation.reference,
              operation.data,
              operation.options,
            );
          }
        });
      },
    };
  }
}

module.exports = { InMemoryFirestore };
