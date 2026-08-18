const test = require("node:test");
const assert = require("node:assert/strict");
const { getApps, initializeApp } = require("firebase-admin/app");
const { Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  PLAN_CONFIGURATION,
  buildPlanCatalog,
  validateConfiguredPrice,
  makeStripeBillingHandlers,
  parseCheckoutRequest,
  parsePortalRequest,
  createStripeClient,
  cancelStripeBillingForDeletedUser,
} = require("../premium/stripe_billing");

const NOW_MS = Date.UTC(2026, 7, 18, 12, 0, 0);

function clone(value) {
  if (value instanceof Timestamp) return value;
  if (Array.isArray(value)) return value.map(clone);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, clone(item)]));
  }
  return value;
}

class FakeSnapshot {
  constructor(ref, value) {
    this.ref = ref;
    this.id = ref.id;
    this.exists = value !== undefined;
    this._value = value;
  }
  data() {
    return this._value === undefined ? undefined : clone(this._value);
  }
}

class FakeDocumentReference {
  constructor(store, collectionName, id) {
    this.store = store;
    this.collectionName = collectionName;
    this.id = id;
    this.path = `${collectionName}/${id}`;
  }
  async get() {
    return new FakeSnapshot(this, this.store.documents.get(this.path));
  }
  async set(value, options) {
    if (
      this.store.failNextPendingSessionWrite &&
      typeof value.pendingCheckoutSessionId === "string"
    ) {
      this.store.failNextPendingSessionWrite = false;
      throw new Error("injected crash before session id persistence");
    }
    this.store.write(this, value, options);
  }
}

class FakeQuery {
  constructor(store, collectionName, field = null, expected = null, max = Infinity) {
    this.store = store;
    this.collectionName = collectionName;
    this.field = field;
    this.expected = expected;
    this.max = max;
  }
  where(field, operator, expected) {
    assert.equal(operator, "==");
    return new FakeQuery(this.store, this.collectionName, field, expected, this.max);
  }
  limit(max) {
    return new FakeQuery(
      this.store,
      this.collectionName,
      this.field,
      this.expected,
      max,
    );
  }
  async get() {
    const docs = [];
    for (const [path, value] of this.store.documents) {
      const [collectionName, id] = path.split("/");
      if (collectionName !== this.collectionName) continue;
      if (this.field && value[this.field] !== this.expected) continue;
      docs.push(
        new FakeSnapshot(
          new FakeDocumentReference(this.store, collectionName, id),
          value,
        ),
      );
      if (docs.length >= this.max) break;
    }
    return { docs, size: docs.length, empty: docs.length === 0 };
  }
}

class FakeFirestore {
  constructor(seed = {}) {
    this.documents = new Map(Object.entries(seed).map(([path, value]) => [path, clone(value)]));
    this.transactionCount = 0;
  }
  collection(name) {
    const query = new FakeQuery(this, name);
    query.doc = (id) => new FakeDocumentReference(this, name, id);
    return query;
  }
  write(reference, value, options = {}) {
    const previous = this.documents.get(reference.path) ?? {};
    this.documents.set(reference.path, options.merge ? { ...previous, ...clone(value) } : clone(value));
  }
  async runTransaction(callback) {
    this.transactionCount += 1;
    const writes = [];
    const transaction = {
      get: (reference) => reference.get(),
      set: (reference, value, options) => writes.push(["set", reference, value, options]),
      create: (reference, value) => {
        if (this.documents.has(reference.path)) throw new Error("already exists");
        writes.push(["set", reference, value]);
      },
      delete: (reference) => writes.push(["delete", reference]),
    };
    const result = await callback(transaction);
    for (const [operation, reference, value, options] of writes) {
      if (operation === "delete") this.documents.delete(reference.path);
      else this.write(reference, value, options);
    }
    return result;
  }
}

function price({
  id,
  interval,
  amount,
  product = "prod_premium",
  livemode = false,
  currencyOptions = {},
}) {
  return {
    id,
    object: "price",
    active: true,
    livemode,
    type: "recurring",
    currency: "pln",
    unit_amount: amount,
    tax_behavior: "inclusive",
    product,
    currency_options: currencyOptions,
    recurring: { interval, interval_count: 1 },
  };
}

function subscription({
  id = "sub_current",
  customer = "cus_current",
  status = "active",
  priceId = "price_monthly",
  cancelAtPeriodEnd = false,
  latestInvoice = { paid: true, status: "paid" },
}) {
  return {
    id,
    object: "subscription",
    customer,
    status,
    cancel_at_period_end: cancelAtPeriodEnd,
    latest_invoice: latestInvoice,
    current_period_end: Math.floor((NOW_MS + 30 * 86400000) / 1000),
    items: { data: [{ price: { id: priceId } }] },
  };
}

function responseRecorder() {
  return {
    statusCode: null,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(value) {
      this.body = value;
      return this;
    },
    send(value) {
      this.body = value;
      return this;
    },
  };
}

function stripeFake(overrides = {}) {
  const prices = {
    monthly: price({
      id: "price_monthly",
      interval: "month",
      amount: PLAN_CONFIGURATION.monthly.plnAmount,
    }),
    yearly: price({
      id: "price_yearly",
      interval: "year",
      amount: PLAN_CONFIGURATION.yearly.plnAmount,
    }),
  };
  return {
    prices: {
      retrieve: async (id) => (id === "price_monthly" ? prices.monthly : prices.yearly),
    },
    customers: { create: async () => ({ id: "cus_current" }) },
    subscriptions: {
      retrieve: async () => subscription({}),
      list: async () => ({ data: [] }),
      cancel: async () => subscription({ status: "canceled" }),
    },
    checkout: {
      sessions: {
        create: async () => ({ id: "cs_current", url: "https://checkout.stripe.test/session" }),
        retrieve: async () => ({ status: "expired", url: null }),
        expire: async () => ({}),
      },
    },
    billingPortal: {
      configurations: {
        retrieve: async () => ({
          id: "bpc_test",
          active: true,
          features: {
            subscription_cancel: { enabled: true },
            subscription_update: {
              enabled: true,
              default_allowed_updates: ["price"],
              products: [
                {
                  product: "prod_premium",
                  prices: ["price_monthly", "price_yearly"],
                },
              ],
            },
          },
        }),
      },
      sessions: {
        create: async () => ({ url: "https://billing.stripe.test/session" }),
      },
    },
    charges: {
      retrieve: async () => ({
        id: "ch_current",
        customer: "cus_current",
        invoice: "in_current",
      }),
    },
    invoices: {
      retrieve: async () => ({ id: "in_current", customer: "cus_current" }),
    },
    webhooks: { constructEvent: () => overrides.event },
    ...overrides,
  };
}

function handlers({ firestore, stripe, portalConfigurationId = "bpc_test" }) {
  return makeStripeBillingHandlers({
    firestore,
    stripe,
    priceIds: { monthly: "price_monthly", yearly: "price_yearly" },
    portalConfigurationId,
    expectedLiveMode: false,
    now: () => Timestamp.fromMillis(NOW_MS),
  });
}

test("base catalog is exact PLN 19.99 monthly and 199.99 yearly", () => {
  const catalog = buildPlanCatalog("PL");
  assert.equal(catalog.currency, "PLN");
  assert.equal(catalog.priceDisplaySource, "base");
  assert.equal(catalog.localizedAtCheckout, true);
  assert.deepEqual(
    catalog.plans.map(({ id, unitAmount }) => ({ id, unitAmount })),
    [
      { id: "monthly", unitAmount: 1999 },
      { id: "yearly", unitAmount: 19999 },
    ],
  );
});

test("configured Prices fail closed on mode, tax, amount or manual currency options", () => {
  const valid = price({ id: "p", interval: "month", amount: 1999 });
  assert.doesNotThrow(() => validateConfiguredPrice(valid, "monthly", false));
  assert.throws(() => validateConfiguredPrice({ ...valid, livemode: true }, "monthly", false));
  assert.throws(() => validateConfiguredPrice({ ...valid, tax_behavior: "exclusive" }, "monthly", false));
  assert.throws(() => validateConfiguredPrice({ ...valid, unit_amount: 999 }, "monthly", false));
  assert.throws(() =>
    validateConfiguredPrice(
      { ...valid, currency_options: { eur: { unit_amount: 499 } } },
      "monthly",
      false,
    ),
  );
});

test("Stripe client fails closed when configured key mode does not match", () => {
  assert.doesNotThrow(() => createStripeClient("sk_test_example", "test"));
  assert.throws(() => createStripeClient("sk_test_example", "live"));
  assert.throws(() => createStripeClient("sk_live_example", "test"));
  assert.throws(() => createStripeClient("sk_live_example", "unknown"));
  assert.throws(() =>
    createStripeClient("sk_test_example", "test", {
      projectId: "yovoice-ec54a",
      functionsEmulator: false,
    }),
  );
  assert.doesNotThrow(() =>
    createStripeClient("sk_live_example", "live", {
      projectId: "yovoice-ec54a",
      functionsEmulator: false,
    }),
  );
});

test("checkout and portal reject unexpected client-controlled fields", () => {
  assert.deepEqual(parseCheckoutRequest({ plan: "monthly" }), { plan: "monthly" });
  assert.throws(() => parseCheckoutRequest({ plan: "monthly", amount: 1 }));
  assert.doesNotThrow(() => parsePortalRequest({}));
  assert.throws(() => parsePortalRequest({ returnUrl: "https://evil.test" }));
});

test("price loader is single-flight and enforces one shared Product", async () => {
  let calls = 0;
  const fake = stripeFake();
  const original = fake.prices.retrieve;
  fake.prices.retrieve = async (...args) => {
    calls += 1;
    await new Promise((resolve) => setTimeout(resolve, 5));
    return original(...args);
  };
  const service = handlers({ firestore: new FakeFirestore(), stripe: fake });
  await Promise.all([service.loadPrices(), service.loadPrices(), service.loadPrices()]);
  assert.equal(calls, 2);

  const wrongProduct = stripeFake();
  wrongProduct.prices.retrieve = async (id) =>
    id === "price_monthly"
      ? price({ id, interval: "month", amount: 1999, product: "prod_a" })
      : price({ id, interval: "year", amount: 19999, product: "prod_b" });
  await assert.rejects(handlers({ firestore: new FakeFirestore(), stripe: wrongProduct }).loadPrices());
});

test("admin grant is complimentary, has no portal and no renewal claim", async () => {
  const firestore = new FakeFirestore({
    "entitlements/user": {
      source: "admin",
      plan: "monthly",
      status: "active",
      isPremium: true,
      currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 86400000),
      renewalBehavior: "none",
    },
    "billingAccounts/user": { stripeCustomerId: "cus_old" },
  });
  const result = await handlers({ firestore, stripe: stripeFake() })
    .getPremiumBillingContextHandler({ auth: { uid: "user" }, data: {} });
  assert.equal(result.billingManagedBy, "admin");
  assert.equal(result.portalAvailable, false);
  assert.equal(result.checkoutAvailable, false);
  assert.equal(result.renewalBehavior, "none");
});

test("expired entitlement has no current plan and can resubscribe", async () => {
  const firestore = new FakeFirestore({
    "entitlements/user": {
      source: "stripe",
      plan: "monthly",
      status: "expired",
      isPremium: false,
      currentPeriodEnd: Timestamp.fromMillis(NOW_MS - 1000),
    },
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
  });
  const result = await handlers({ firestore, stripe: stripeFake() })
    .getPremiumBillingContextHandler({ auth: { uid: "user" }, data: {} });
  assert.equal(result.currentPlan, "none");
  assert.equal(result.checkoutAvailable, true);
});

test("suspended or unverified payer can still open their canonical Stripe portal", async () => {
  const firestore = new FakeFirestore({
    "entitlements/suspended": { source: "stripe", status: "active" },
    "billingAccounts/suspended": { stripeCustomerId: "cus_current" },
    "users/suspended": { banned: true, disabled: true },
  });
  const result = await handlers({ firestore, stripe: stripeFake() })
    .createPremiumPortalSessionHandler({
      auth: { uid: "suspended", token: { email_verified: false } },
      data: {},
    });
  assert.equal(result.url, "https://billing.stripe.test/session");
});

test("portal fails closed unless cancellation and both plan switches are enabled", async () => {
  const firestore = new FakeFirestore({
    "entitlements/user": { source: "stripe", status: "active" },
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
  });
  const fake = stripeFake();
  fake.billingPortal.configurations.retrieve = async () => ({
    active: true,
    features: {
      subscription_cancel: { enabled: false },
      subscription_update: { enabled: true, default_allowed_updates: ["price"] },
    },
  });
  await assert.rejects(
    handlers({ firestore, stripe: fake }).createPremiumPortalSessionHandler({
      auth: { uid: "user" },
      data: {},
    }),
    /must allow cancellation/,
  );
});

test("webhook refuses metadata-only TOFU binding", async () => {
  const service = handlers({ firestore: new FakeFirestore(), stripe: stripeFake() });
  await assert.rejects(
    service.applySubscription("sub_current", {
      id: "evt_tofu",
      type: "customer.subscription.updated",
      created: 1,
    }),
    /no unique canonical Firebase billing binding/,
  );
});

test("webhook fails closed when a configured Price has the wrong amount", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "personal" },
  });
  const fake = stripeFake();
  fake.prices.retrieve = async (id) =>
    id === "price_monthly"
      ? price({ id, interval: "month", amount: 1 })
      : price({ id, interval: "year", amount: 19999 });
  await assert.rejects(
    handlers({ firestore, stripe: fake }).applySubscription("sub_current", {
      id: "evt_wrong_price",
      type: "customer.subscription.updated",
      created: 1,
    }),
    /must be PLN 1999/,
  );
  assert.equal(firestore.documents.has("entitlements/user"), false);
  assert.equal(firestore.documents.has("stripeWebhookEvents/evt_wrong_price"), false);
});

test("webhook preserves an opaque Unicode Firebase uid from canonical reverse binding", async () => {
  const uid = " użytkownik Ω ";
  const firestore = new FakeFirestore({
    [`billingAccounts/${uid}`]: { stripeCustomerId: "cus_current" },
    [`users/${uid}`]: { accountType: "personal" },
  });
  const result = await handlers({ firestore, stripe: stripeFake() }).applySubscription(
    "sub_current",
    { id: "evt_unicode", type: "customer.subscription.updated", created: 2 },
  );
  assert.deepEqual(result, { applied: true, uid });
  assert.equal(firestore.documents.get(`entitlements/${uid}`).isPremium, true);
  assert.equal(firestore.documents.get("stripeWebhookEvents/evt_unicode").type, "customer.subscription.updated");
});

test("webhook replay is idempotent and entitlement + ledger commit together", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "creator" },
  });
  const service = handlers({ firestore, stripe: stripeFake() });
  const event = { id: "evt_once", type: "customer.subscription.updated", created: 3 };
  assert.deepEqual(await service.applySubscription("sub_current", event), {
    applied: true,
    uid: "user",
  });
  assert.deepEqual(await service.applySubscription("sub_current", event), { ignored: true });
  assert.equal(firestore.documents.get("billingAccounts/user").stripeSubscriptionId, "sub_current");
  assert.equal(firestore.documents.get("entitlements/user").isPremium, true);
  assert.ok(firestore.documents.has("stripeWebhookEvents/evt_once"));
});

test("old subscription event cannot overwrite a newer active subscription", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_new",
      stripeSubscriptionStatus: "active",
    },
    "users/user": { accountType: "personal" },
  });
  const fake = stripeFake();
  fake.subscriptions.retrieve = async (id) =>
    id === "sub_old"
      ? subscription({ id, status: "canceled" })
      : subscription({ id, status: "active" });
  const result = await handlers({ firestore, stripe: fake }).applySubscription(
    "sub_old",
    { id: "evt_old", type: "customer.subscription.deleted", created: 4 },
  );
  assert.deepEqual(result, { ignored: true });
  assert.equal(firestore.documents.get("billingAccounts/user").stripeSubscriptionId, "sub_new");
  assert.equal(firestore.documents.get("stripeWebhookEvents/evt_old").ignoredAsSuperseded, true);
});

test("unpaid Checkout completion never provisions Premium", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "personal" },
  });
  const fake = stripeFake({
    event: {
      id: "evt_unpaid",
      livemode: false,
      type: "checkout.session.completed",
      created: 5,
      data: { object: { payment_status: "unpaid", subscription: "sub_current" } },
    },
  });
  const response = responseRecorder();
  await handlers({ firestore, stripe: fake }).stripeWebhookHandler(
    { rawBody: Buffer.from("x"), headers: { "stripe-signature": "sig" } },
    response,
    "whsec_test",
  );
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.awaitingPayment, true);
  assert.equal(firestore.documents.has("entitlements/user"), false);
});

test("active subscription with an unpaid first invoice cannot grant Premium", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "personal" },
  });
  const fake = stripeFake();
  fake.subscriptions.retrieve = async () =>
    subscription({ latestInvoice: { paid: false, status: "open" } });
  await handlers({ firestore, stripe: fake }).applySubscription("sub_current", {
    id: "evt_unsettled_subscription",
    type: "customer.subscription.created",
    created: 6,
  });
  assert.equal(firestore.documents.get("entitlements/user").isPremium, false);
  assert.equal(firestore.documents.get("entitlements/user").status, "expired");
});

test("invoice paid grants Premium after an unsettled subscription event", async () => {
  let paid = false;
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "personal" },
  });
  const fake = stripeFake();
  fake.subscriptions.retrieve = async () =>
    subscription({
      latestInvoice: paid
        ? { paid: true, status: "paid" }
        : { paid: false, status: "open" },
    });
  const service = handlers({ firestore, stripe: fake });
  await service.applySubscription("sub_current", {
    id: "evt_before_payment",
    type: "customer.subscription.created",
    created: 7,
  });
  assert.equal(firestore.documents.get("entitlements/user").isPremium, false);
  paid = true;
  await service.applySubscription("sub_current", {
    id: "evt_invoice_paid",
    type: "invoice.paid",
    created: 8,
  });
  assert.equal(firestore.documents.get("entitlements/user").isPremium, true);
});

test("unpaid renewal never extends access beyond the paid entitlement", async () => {
  const paidUntil = Timestamp.fromMillis(NOW_MS + 5 * 86400000);
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "entitlements/user": {
      source: "stripe",
      plan: "monthly",
      status: "active",
      isPremium: true,
      currentPeriodEnd: paidUntil,
    },
    "users/user": { accountType: "personal" },
  });
  const fake = stripeFake();
  fake.subscriptions.retrieve = async () =>
    subscription({ latestInvoice: { paid: false, status: "open" } });
  await handlers({ firestore, stripe: fake }).applySubscription("sub_current", {
    id: "evt_unpaid_renewal",
    type: "customer.subscription.updated",
    created: 9,
  });
  const entitlement = firestore.documents.get("entitlements/user");
  assert.equal(entitlement.status, "grace");
  assert.equal(entitlement.currentPeriodEnd.toMillis(), paidUntil.toMillis());
});

test("async payment failure reprojects the canonical unpaid subscription", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "personal" },
  });
  const fake = stripeFake({
    event: {
      id: "evt_async_failed",
      livemode: false,
      type: "checkout.session.async_payment_failed",
      created: 10,
      data: { object: { subscription: "sub_current" } },
    },
  });
  fake.subscriptions.retrieve = async () =>
    subscription({ latestInvoice: { paid: false, status: "void" } });
  const response = responseRecorder();
  await handlers({ firestore, stripe: fake }).stripeWebhookHandler(
    { rawBody: Buffer.from("x"), headers: { "stripe-signature": "sig" } },
    response,
    "whsec_test",
  );
  assert.equal(response.statusCode, 200);
  assert.equal(firestore.documents.get("entitlements/user").isPremium, false);
});

test("transaction refresh uses canonical canceled state, not the stale event state", async () => {
  let retrieval = 0;
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "personal" },
  });
  const fake = stripeFake();
  fake.subscriptions.retrieve = async () => {
    retrieval += 1;
    return subscription({ status: retrieval === 1 ? "active" : "canceled" });
  };
  await handlers({ firestore, stripe: fake }).applySubscription("sub_current", {
    id: "evt_stale_active",
    type: "customer.subscription.updated",
    created: 11,
  });
  assert.equal(firestore.documents.get("entitlements/user").status, "expired");
  assert.equal(firestore.documents.get("entitlements/user").isPremium, false);
});

test("late Stripe events never recreate missing or deleted user profiles", async () => {
  for (const scenario of [
    { uid: "missing", user: undefined, status: "active", eventId: "evt_late_paid" },
    {
      uid: "deleted",
      user: { deleted: true, status: "deleted", premiumIdentity: false },
      status: "canceled",
      eventId: "evt_late_cancel",
    },
    {
      uid: "auth-tombstone",
      user: {
        disabled: true,
        authDeletedAt: Timestamp.fromMillis(NOW_MS),
        premiumIdentity: false,
      },
      status: "active",
      eventId: "evt_after_auth_delete",
    },
  ]) {
    const seed = {
      [`billingAccounts/${scenario.uid}`]: { stripeCustomerId: "cus_current" },
    };
    if (scenario.user) seed[`users/${scenario.uid}`] = scenario.user;
    const firestore = new FakeFirestore(seed);
    const fake = stripeFake();
    fake.subscriptions.retrieve = async () =>
      subscription({ status: scenario.status });
    await handlers({ firestore, stripe: fake }).applySubscription("sub_current", {
      id: scenario.eventId,
      type:
        scenario.status === "canceled"
          ? "customer.subscription.deleted"
          : "invoice.paid",
      created: 12,
    });
    if (scenario.user) {
      assert.deepEqual(firestore.documents.get(`users/${scenario.uid}`), scenario.user);
    } else {
      assert.equal(firestore.documents.has(`users/${scenario.uid}`), false);
    }
    assert.ok(firestore.documents.has(`entitlements/${scenario.uid}`));
    assert.ok(firestore.documents.has(`stripeWebhookEvents/${scenario.eventId}`));
  }
});

test("Auth deletion cancels canonical Stripe billing and retains the private binding", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/deleted": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_current",
    },
  });
  let cancellation;
  const fake = stripeFake();
  fake.subscriptions.list = async () => ({ data: [subscription({})], has_more: false });
  fake.subscriptions.cancel = async (subscriptionId, payload, options) => {
    cancellation = { subscriptionId, payload, options };
    return subscription({ status: "canceled" });
  };
  const result = await cancelStripeBillingForDeletedUser("deleted", {
    firestore,
    stripe: fake,
    now: () => Timestamp.fromMillis(NOW_MS),
  });
  assert.deepEqual(result, { outcome: "canceled" });
  assert.equal(cancellation.subscriptionId, "sub_current");
  assert.match(cancellation.options.idempotencyKey, /deleted_sub_current$/);
  const billing = firestore.documents.get("billingAccounts/deleted");
  assert.equal(billing.stripeCustomerId, "cus_current");
  assert.equal(billing.stripeSubscriptionId, "sub_current");
  assert.equal(billing.accountDeletionCancellationStatus, "canceled");
});

test("Auth deletion refuses a mismatched subscription customer", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/deleted": {
      stripeCustomerId: "cus_expected",
      stripeSubscriptionId: "sub_current",
    },
  });
  const fake = stripeFake();
  fake.subscriptions.list = async () => ({
    data: [subscription({ customer: "cus_current" })],
    has_more: false,
  });
  await assert.rejects(
    cancelStripeBillingForDeletedUser("deleted", { firestore, stripe: fake }),
    /returned a subscription for another customer/,
  );
  assert.notEqual(
    firestore.documents.get("billingAccounts/deleted").accountDeletionCancellationStatus,
    "canceled",
  );
});

test("Auth deletion expires Checkout and finds a subscription missing from Firestore", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/deleted": {
      stripeCustomerId: "cus_current",
      pendingCheckoutSessionId: "cs_pending",
    },
  });
  let expired = false;
  let canceled = false;
  const fake = stripeFake();
  fake.checkout.sessions.retrieve = async () => ({ status: "open" });
  fake.checkout.sessions.expire = async () => {
    expired = true;
  };
  fake.subscriptions.list = async () => ({
    data: [subscription({ id: "sub_discovered" })],
  });
  fake.subscriptions.cancel = async () => {
    canceled = true;
  };
  const result = await cancelStripeBillingForDeletedUser("deleted", {
    firestore,
    stripe: fake,
  });
  assert.deepEqual(result, { outcome: "canceled" });
  assert.equal(expired, true);
  assert.equal(canceled, true);
  assert.equal(
    firestore.documents.get("billingAccounts/deleted").pendingCheckoutSessionId,
    null,
  );
});

test("signed full-refund webhook revokes access, cancels all subscriptions and replays safely", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "entitlements/user": {
      source: "stripe",
      plan: "monthly",
      status: "active",
      isPremium: true,
      currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 86400000),
    },
    "users/user": { accountType: "creator", premiumIdentity: true },
  });
  const keys = [];
  const event = {
    id: "evt_full_refund",
    livemode: false,
    type: "charge.refunded",
    created: 13,
    data: {
      object: {
        id: "ch_current",
        customer: "cus_current",
        amount: 1999,
        amount_refunded: 1999,
      },
    },
  };
  const fake = stripeFake({ event });
  fake.subscriptions.list = async () => ({
    data: [subscription({ id: "sub_a" }), subscription({ id: "sub_b" })],
    has_more: false,
  });
  fake.subscriptions.cancel = async (_id, _payload, options) => {
    keys.push(options.idempotencyKey);
  };
  const service = handlers({ firestore, stripe: fake });
  for (let index = 0; index < 2; index += 1) {
    const response = responseRecorder();
    await service.stripeWebhookHandler(
      { rawBody: Buffer.from("signed"), headers: { "stripe-signature": "sig" } },
      response,
      "whsec_test",
    );
    assert.equal(response.statusCode, 200);
  }
  assert.equal(firestore.documents.get("entitlements/user").isPremium, false);
  assert.equal(firestore.documents.get("users/user").premiumIdentity, false);
  assert.equal(firestore.documents.get("users/user").accountType, "personal");
  assert.equal(
    firestore.documents.get("billingAccounts/user").financialAccessReason,
    "full-refund",
  );
  assert.deepEqual(keys.slice(0, 2), keys.slice(2));
});

test("partial refund preserves access and creates a support-review audit", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "entitlements/user": {
      source: "stripe",
      plan: "monthly",
      status: "active",
      isPremium: true,
      currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 86400000),
    },
    "users/user": { premiumIdentity: true },
  });
  let cancelCalls = 0;
  const fake = stripeFake();
  fake.subscriptions.cancel = async () => {
    cancelCalls += 1;
  };
  await handlers({ firestore, stripe: fake }).applyFinancialRiskEvent({
    id: "evt_partial_refund",
    type: "charge.refunded",
    created: 14,
    data: {
      object: {
        customer: "cus_current",
        amount: 1999,
        amount_refunded: 500,
      },
    },
  });
  assert.equal(cancelCalls, 0);
  assert.equal(firestore.documents.get("entitlements/user").isPremium, true);
  assert.equal(firestore.documents.get("billingAccounts/user").billingReviewRequired, true);
  assert.equal(
    firestore.documents.get("stripeWebhookEvents/evt_partial_refund")
      .supportReviewRequired,
    true,
  );
});

test("dispute revocation does not resurrect an Auth-deleted tombstone", async () => {
  const tombstone = {
    disabled: true,
    authDeletedAt: Timestamp.fromMillis(NOW_MS),
    premiumIdentity: false,
  };
  const firestore = new FakeFirestore({
    "billingAccounts/deleted": { stripeCustomerId: "cus_current" },
    "entitlements/deleted": {
      source: "stripe",
      plan: "yearly",
      status: "active",
      isPremium: true,
      currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 86400000),
    },
    "users/deleted": tombstone,
  });
  const fake = stripeFake();
  fake.subscriptions.list = async () => ({ data: [], has_more: false });
  await handlers({ firestore, stripe: fake }).applyFinancialRiskEvent({
    id: "evt_dispute",
    type: "charge.dispute.created",
    created: 15,
    data: { object: { charge: "ch_current" } },
  });
  assert.deepEqual(firestore.documents.get("users/deleted"), tombstone);
  assert.equal(firestore.documents.get("entitlements/deleted").isPremium, false);
});

test("Checkout payload contains only server prices and enables Adaptive Pricing + automatic tax", async () => {
  let payload;
  const firestore = new FakeFirestore({
    "users/user": { banned: false },
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
  });
  const fake = stripeFake();
  fake.checkout.sessions.create = async (value) => {
    payload = value;
    return { id: "cs_current", url: "https://checkout.stripe.test/session" };
  };
  await handlers({ firestore, stripe: fake }).createPremiumCheckoutSessionHandler({
    auth: { uid: "user", token: { email_verified: true } },
    data: { plan: "yearly" },
  });
  assert.deepEqual(payload.line_items, [{ price: "price_yearly", quantity: 1 }]);
  assert.deepEqual(payload.adaptive_pricing, { enabled: true });
  assert.deepEqual(payload.automatic_tax, { enabled: true });
  assert.deepEqual(payload.payment_method_types, ["card"]);
  assert.equal("currency" in payload, false);
  assert.equal("tax_id_collection" in payload, false);
});

test("checkout retry after crash reuses the same Stripe idempotency key", async () => {
  const firestore = new FakeFirestore({
    "users/user": { banned: false },
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      pendingCheckoutSessionId: "cs_old",
      pendingCheckoutPlan: "yearly",
    },
  });
  firestore.failNextPendingSessionWrite = true;
  const keys = [];
  const fake = stripeFake();
  fake.checkout.sessions.retrieve = async () => ({ status: "open", url: "https://old" });
  fake.checkout.sessions.create = async (_payload, options) => {
    keys.push(options.idempotencyKey);
    return { id: "cs_new", url: "https://checkout.stripe.test/new" };
  };
  const service = handlers({ firestore, stripe: fake });
  const request = {
    auth: { uid: "user", token: { email_verified: true } },
    data: { plan: "monthly" },
  };
  await assert.rejects(
    service.createPremiumCheckoutSessionHandler(request),
    /injected crash/,
  );
  const recovered = await service.createPremiumCheckoutSessionHandler(request);
  assert.equal(recovered.url, "https://checkout.stripe.test/new");
  assert.equal(keys.length, 2);
  assert.equal(keys[0], keys[1]);
});
