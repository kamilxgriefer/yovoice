const test = require("node:test");
const assert = require("node:assert/strict");
const { getApps, initializeApp } = require("firebase-admin/app");
const { Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  BLIK_PLAN_CONFIGURATION,
  PLAN_CONFIGURATION,
  validateConfiguredPrice,
  validateConfiguredBlikPrice,
  makeStripeBillingHandlers,
  parseCheckoutRequest,
  parsePortalRequest,
  createStripeClient,
  cancelStripeBillingForDeletedUser,
  isAllowedStripeHostedUrl,
  STRIPE_CHECKOUT_HOST,
  STRIPE_BILLING_PORTAL_HOST,
  MAX_STRIPE_WEBHOOK_BODY_BYTES,
  MAX_STRIPE_WEBHOOK_INSTANCES,
  stripePremiumWebhook,
  mapStripeSubscription,
} = require("../premium/stripe_billing");
const {
  buildPlanCatalog,
  getPremiumBillingContextWithoutStripe,
} = require("../premium/billing_context");

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
      set: (reference, value, options) => {
        if (
          this.failNextPendingSessionWrite &&
          typeof value.pendingCheckoutSessionId === "string"
        ) {
          this.failNextPendingSessionWrite = false;
          throw new Error("injected crash before session id persistence");
        }
        if (
          this.failNextOverlapCompletionWrite &&
          reference.collectionName === "stripeWebhookEvents" &&
          value.processingState === "completed" &&
          value.entitlementOverlap === true
        ) {
          this.failNextOverlapCompletionWrite = false;
          throw new Error("injected crash after duplicate cancellation");
        }
        writes.push(["set", reference, value, options]);
      },
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
  currency = "eur",
  type = "recurring",
}) {
  return {
    id,
    object: "price",
    active: true,
    livemode,
    type,
    currency,
    unit_amount: amount,
    tax_behavior: "inclusive",
    billing_scheme: "per_unit",
    transform_quantity: null,
    product,
    currency_options: currencyOptions,
    recurring:
      type === "recurring"
        ? {
            interval,
            interval_count: 1,
            usage_type: "licensed",
            aggregate_usage: null,
          }
        : null,
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
  const invoiceSuffix = id.startsWith("sub_") ? id.slice(4) : id;
  const canonicalInvoiceId = `in_${invoiceSuffix}`;
  const canonicalPaymentIntentId =
    canonicalInvoiceId === "in_current" ? "pi_invoice" : `pi_${invoiceSuffix}`;
  const normalizedLatestInvoice =
    latestInvoice && typeof latestInvoice === "object"
      ? {
          id: latestInvoice.id ?? canonicalInvoiceId,
          object: "invoice",
          customer,
          parent: {
            type: "subscription_details",
            subscription_details: { subscription: id },
          },
          ...latestInvoice,
          _testPaymentIntentId:
            latestInvoice._testPaymentIntentId ?? canonicalPaymentIntentId,
        }
      : latestInvoice;
  return {
    id,
    object: "subscription",
    customer,
    status,
    cancel_at_period_end: cancelAtPeriodEnd,
    latest_invoice: normalizedLatestInvoice,
    current_period_end: Math.floor((NOW_MS + 30 * 86400000) / 1000),
    items: { data: [{ price: { id: priceId }, quantity: 1 }] },
  };
}

function responseRecorder() {
  return {
    statusCode: null,
    body: null,
    headers: {},
    set(name, value) {
      this.headers[name] = value;
      return this;
    },
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

test("public Stripe webhook rejects cheap invalid traffic before Stripe SDK work", async () => {
  let constructCalls = 0;
  const fake = stripeFake();
  fake.webhooks.constructEvent = () => {
    constructCalls += 1;
    throw new Error("invalid signature");
  };
  const service = handlers({ firestore: new FakeFirestore(), stripe: fake });

  let response = responseRecorder();
  await service.stripeWebhookHandler(
    { method: "GET", rawBody: Buffer.from("x"), headers: {} },
    response,
    "whsec_test",
  );
  assert.equal(response.statusCode, 405);
  assert.equal(response.headers.Allow, "POST");

  response = responseRecorder();
  await service.stripeWebhookHandler(
    {
      method: "POST",
      rawBody: Buffer.alloc(MAX_STRIPE_WEBHOOK_BODY_BYTES + 1),
      headers: { "stripe-signature": "sig" },
    },
    response,
    "whsec_test",
  );
  assert.equal(response.statusCode, 413);

  response = responseRecorder();
  await service.stripeWebhookHandler(
    {
      method: "POST",
      rawBody: Buffer.from("x"),
      headers: { "stripe-signature": ["sig"] },
    },
    response,
    "whsec_test",
  );
  assert.equal(response.statusCode, 400);
  assert.equal(constructCalls, 0);

  response = responseRecorder();
  await service.stripeWebhookHandler(
    {
      method: "POST",
      rawBody: Buffer.from("signed"),
      headers: { "stripe-signature": "sig" },
    },
    response,
    "whsec_test",
  );
  assert.equal(response.statusCode, 400);
  assert.equal(response.body, "Invalid signature");
  assert.equal(constructCalls, 1);
});

test("public Stripe webhook has a bounded runtime envelope", () => {
  assert.equal(stripePremiumWebhook.__endpoint.maxInstances, MAX_STRIPE_WEBHOOK_INSTANCES);
  assert.equal(stripePremiumWebhook.__endpoint.timeoutSeconds, 60);
  assert.equal(stripePremiumWebhook.__endpoint.platform, "gcfv2");
});

function stripeFake(overrides = {}) {
  const prices = {
    monthly: price({
      id: "price_monthly",
      interval: "month",
      amount: PLAN_CONFIGURATION.monthly.unitAmount,
    }),
    yearly: price({
      id: "price_yearly",
      interval: "year",
      amount: PLAN_CONFIGURATION.yearly.unitAmount,
    }),
    blikMonthly: price({
      id: "price_blik_monthly",
      amount: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
      currency: "pln",
      type: "one_time",
    }),
    blikYearly: price({
      id: "price_blik_yearly",
      amount: BLIK_PLAN_CONFIGURATION.yearly.unitAmount,
      currency: "pln",
      type: "one_time",
    }),
  };
  const prepaidSession = {
    id: "cs_prepaid",
    mode: "payment",
    status: "complete",
    payment_status: "paid",
    customer: "cus_current",
    payment_intent: "pi_prepaid",
    currency: "pln",
    amount_total: BLIK_PLAN_CONFIGURATION.yearly.unitAmount,
  };
  return {
    prices: {
      retrieve: async (id) => ({
        price_monthly: prices.monthly,
        price_yearly: prices.yearly,
        price_blik_monthly: prices.blikMonthly,
        price_blik_yearly: prices.blikYearly,
      })[id],
    },
    customers: {
      create: async () => ({ id: "cus_current" }),
      del: async (id) => ({ id, object: "customer", deleted: true }),
      update: async (id) => ({ id, object: "customer" }),
    },
    subscriptions: {
      retrieve: async () => subscription({}),
      list: async () => ({ data: [] }),
      cancel: async () => subscription({ status: "canceled" }),
    },
    checkout: {
      sessions: {
        create: async () => ({
          id: "cs_current",
          status: "open",
          url: "https://checkout.stripe.com/c/pay/session",
        }),
        retrieve: async (id) =>
          id === "cs_prepaid" ? prepaidSession : { status: "expired", url: null },
        list: async () => ({ data: [], has_more: false }),
        listLineItems: async () => ({
          data: [{ price: { id: "price_blik_yearly" }, quantity: 1 }],
        }),
        expire: async () => ({}),
      },
    },
    paymentIntents: {
      retrieve: async (id) =>
        id !== "pi_prepaid"
          ? {
              id,
              status: "succeeded",
              customer: "cus_current",
            }
          : {
              id: "pi_prepaid",
              status: "succeeded",
              customer: "cus_current",
              currency: "pln",
              amount_received: BLIK_PLAN_CONFIGURATION.yearly.unitAmount,
              payment_method: "pm_blik",
            },
    },
    invoicePayments: {
      list: async (request) => {
        let invoiceId = request.invoice;
        let paymentIntentId = request.payment?.payment_intent;
        if (invoiceId && !paymentIntentId) {
          paymentIntentId =
            invoiceId === "in_current"
              ? "pi_invoice"
              : `pi_${invoiceId.slice(3)}`;
        } else if (paymentIntentId === "pi_invoice") {
          invoiceId = "in_current";
        }
        if (!invoiceId || !paymentIntentId) return { data: [], has_more: false };
        return {
          data: [
            {
              id: `inpay_${invoiceId.slice(3)}`,
              object: "invoice_payment",
              invoice: invoiceId,
              status: "paid",
              payment: {
                type: "payment_intent",
                payment_intent: paymentIntentId,
              },
            },
          ],
          has_more: false,
        };
      },
    },
    paymentMethods: {
      retrieve: async () => ({ id: "pm_blik", type: "blik" }),
    },
    billingPortal: {
      configurations: {
        retrieve: async () => ({
          id: "bpc_test",
          active: true,
          features: {
            subscription_cancel: { enabled: true, mode: "at_period_end" },
            subscription_update: {
              enabled: true,
              default_allowed_updates: ["price"],
              products: [
                {
                  product: "prod_premium",
                  prices: ["price_monthly", "price_yearly"],
                  adjustable_quantity: {
                    enabled: false,
                    minimum: 1,
                    maximum: null,
                  },
                },
              ],
            },
          },
        }),
      },
      sessions: {
        create: async () => ({ url: "https://billing.stripe.com/p/session" }),
      },
    },
    charges: {
      retrieve: async () => ({
        id: "ch_current",
        customer: "cus_current",
        payment_intent: "pi_invoice",
        amount: 600,
        amount_refunded: 600,
      }),
    },
    invoices: {
      retrieve: async (id) => ({
        id,
        customer: "cus_current",
        parent: {
          type: "subscription_details",
          subscription_details: {
            subscription:
              id === "in_current" ? "sub_current" : `sub_${id.slice(3)}`,
          },
        },
      }),
    },
    webhooks: { constructEvent: () => overrides.event },
    ...overrides,
  };
}

function handlers({ firestore, stripe, portalConfigurationId = "bpc_test" }) {
  return makeStripeBillingHandlers({
    firestore,
    stripe,
    priceIds: {
      monthly: "price_monthly",
      yearly: "price_yearly",
      blikMonthly: "price_blik_monthly",
      blikYearly: "price_blik_yearly",
    },
    portalConfigurationId,
    expectedLiveMode: false,
    now: () => Timestamp.fromMillis(NOW_MS),
  });
}

test("base catalog is exact EUR 6 monthly and EUR 60 yearly", () => {
  const catalog = buildPlanCatalog("PL");
  assert.equal(catalog.currency, "EUR");
  assert.equal(catalog.priceDisplaySource, "base");
  assert.equal(catalog.localizedAtCheckout, true);
  assert.deepEqual(
    catalog.plans.map(({ id, unitAmount }) => ({ id, unitAmount })),
    [
      { id: "monthly", unitAmount: 600 },
      { id: "yearly", unitAmount: 6000 },
    ],
  );
  assert.equal(catalog.plans[1].savingsPercent, 17);
  assert.match(catalog.plans[1].formattedEquivalent, /5/);
});

test("secret-free billing context renders the catalog but disables checkout", async () => {
  const result = await getPremiumBillingContextWithoutStripe(
    { data: { countryCode: "DE" } },
    new FakeFirestore(),
    NOW_MS,
  );
  assert.equal(result.currency, "EUR");
  assert.equal(result.checkoutAvailable, false);
  assert.equal(result.portalAvailable, false);
  assert.deepEqual(Object.keys(result).sort(), [
    "billingManagedBy",
    "checkoutAvailable",
    "countryCode",
    "currency",
    "currentPeriodEndMs",
    "currentPlan",
    "localizedAtCheckout",
    "plans",
    "portalAvailable",
    "priceDisplaySource",
    "renewalBehavior",
    "taxDisplay",
    "taxNotice",
  ]);
});

test("secret-free context never advertises a portal for an existing Stripe subscription", async () => {
  const firestore = new FakeFirestore({
    "entitlements/user": {
      source: "stripe",
      plan: "monthly",
      status: "active",
      isPremium: true,
      currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 86400000),
    },
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_current",
    },
  });
  const result = await getPremiumBillingContextWithoutStripe(
    { auth: { uid: "user" }, data: {} },
    firestore,
    NOW_MS,
  );
  assert.equal(result.checkoutAvailable, false);
  assert.equal(result.portalAvailable, false);
});

test("configured Prices fail closed on mode, tax, amount or manual currency options", () => {
  const valid = price({ id: "p", interval: "month", amount: 600 });
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
  assert.throws(() =>
    validateConfiguredPrice(
      { ...valid, billing_scheme: "tiered" },
      "monthly",
      false,
    ),
  );
  assert.throws(() =>
    validateConfiguredPrice(
      { ...valid, transform_quantity: { divide_by: 2, round: "up" } },
      "monthly",
      false,
    ),
  );
  assert.throws(() =>
    validateConfiguredPrice(
      { ...valid, recurring: { ...valid.recurring, usage_type: "metered" } },
      "monthly",
      false,
    ),
  );
});

test("configured BLIK Prices are exact one-time PLN passes", () => {
  const valid = price({
    id: "p_blik",
    amount: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
    currency: "pln",
    type: "one_time",
  });
  assert.doesNotThrow(() =>
    validateConfiguredBlikPrice(valid, "monthly", false),
  );
  assert.throws(() =>
    validateConfiguredBlikPrice({ ...valid, type: "recurring" }, "monthly", false),
  );
  assert.throws(() =>
    validateConfiguredBlikPrice({ ...valid, unit_amount: 1 }, "monthly", false),
  );
  assert.throws(() =>
    validateConfiguredBlikPrice({ ...valid, currency: "eur" }, "monthly", false),
  );
  assert.throws(() =>
    validateConfiguredBlikPrice(
      { ...valid, transform_quantity: { divide_by: 2, round: "up" } },
      "monthly",
      false,
    ),
  );
  assert.throws(() =>
    validateConfiguredBlikPrice(
      { ...valid, billing_scheme: "tiered" },
      "monthly",
      false,
    ),
  );
});

test("subscription projection requires one configured item with quantity one", () => {
  const configured = { monthly: "price_monthly", yearly: "price_yearly" };
  assert.doesNotThrow(() =>
    mapStripeSubscription(subscription({}), configured, { nowMs: NOW_MS }),
  );
  const quantityTwo = subscription({});
  quantityTwo.items.data[0].quantity = 2;
  assert.throws(
    () => mapStripeSubscription(quantityTwo, configured, { nowMs: NOW_MS }),
    /one configured Premium Price/,
  );
  const extraItem = subscription({});
  extraItem.items.data.push({ price: { id: "price_yearly" }, quantity: 1 });
  assert.throws(
    () => mapStripeSubscription(extraItem, configured, { nowMs: NOW_MS }),
    /one configured Premium Price/,
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
  assert.deepEqual(parseCheckoutRequest({ plan: "monthly" }), {
    plan: "monthly",
    paymentMethod: "recurring",
  });
  assert.deepEqual(
    parseCheckoutRequest({ plan: "yearly", paymentMethod: "blik" }),
    { plan: "yearly", paymentMethod: "blik" },
  );
  assert.deepEqual(
    parseCheckoutRequest({ plan: "monthly", paymentMethod: "blik" }),
    { plan: "monthly", paymentMethod: "blik" },
  );
  assert.throws(() =>
    parseCheckoutRequest({ plan: "monthly", paymentMethod: "paypal" }),
  );
  assert.throws(() => parseCheckoutRequest({ plan: "monthly", amount: 1 }));
  assert.doesNotThrow(() => parsePortalRequest({}));
  assert.throws(() => parsePortalRequest({ returnUrl: "https://evil.test" }));
});

test("Stripe hosted URL validation rejects lookalike and credential-smuggling URLs", () => {
  assert.equal(
    isAllowedStripeHostedUrl(
      "https://checkout.stripe.com/c/pay/session?prefilled_email=user%40example.test",
      STRIPE_CHECKOUT_HOST,
    ),
    true,
  );
  assert.equal(
    isAllowedStripeHostedUrl(
      "https://billing.stripe.com/p/session#manage",
      STRIPE_BILLING_PORTAL_HOST,
    ),
    true,
  );
  for (const value of [
    "http://checkout.stripe.com/c/pay/session",
    "https://checkout.stripe.com.evil.test/c/pay/session",
    "https://checkout.stripe.com@evil.test/c/pay/session",
    "https://user:password@checkout.stripe.com/c/pay/session",
    "https://checkout.stripe.com:444/c/pay/session",
    "javascript:alert(1)",
    "not a URL",
    null,
  ]) {
    assert.equal(
      isAllowedStripeHostedUrl(value, STRIPE_CHECKOUT_HOST),
      false,
      String(value),
    );
  }
});

test("checkout parsing rejects prototype-chain plan names", () => {
  for (const plan of ["toString", "constructor", "__proto__"]) {
    assert.throws(() => parseCheckoutRequest({ plan }), /monthly or yearly/);
  }
  const nullPrototype = Object.create(null);
  nullPrototype.plan = "constructor";
  assert.throws(() => parseCheckoutRequest(nullPrototype), /monthly or yearly/);
  const inherited = Object.create({ plan: "monthly", paymentMethod: "blik" });
  assert.throws(() => parseCheckoutRequest(inherited), /monthly or yearly/);
  const inheritedPaymentMethod = Object.create({ paymentMethod: "blik" });
  inheritedPaymentMethod.plan = "monthly";
  assert.throws(
    () => parseCheckoutRequest(inheritedPaymentMethod),
    /monthly or yearly/,
  );
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
  assert.equal(calls, 4);

  const wrongProduct = stripeFake();
  const originalWrongProduct = wrongProduct.prices.retrieve;
  wrongProduct.prices.retrieve = async (id) => {
    const configured = await originalWrongProduct(id);
    return id === "price_yearly"
      ? { ...configured, product: "prod_b" }
      : { ...configured, product: "prod_a" };
  };
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

test("billing context rejects active-looking state without canonical isPremium", async () => {
  for (const value of [undefined, false]) {
    const firestore = new FakeFirestore({
      "entitlements/user": {
        source: "stripe",
        plan: "monthly",
        status: "active",
        ...(value === undefined ? {} : { isPremium: value }),
        currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 86400000),
        renewalBehavior: "renews",
      },
      "billingAccounts/user": {
        stripeCustomerId: "cus_current",
        stripeSubscriptionId: "sub_current",
      },
    });
    const result = await handlers({ firestore, stripe: stripeFake() })
      .getPremiumBillingContextHandler({ auth: { uid: "user" }, data: {} });
    assert.equal(result.currentPlan, "none", String(value));
    assert.equal(result.currentPeriodEndMs, null, String(value));
    assert.equal(result.renewalBehavior, "none", String(value));
    // A malformed access projection must not trap a still-canonical Stripe
    // subscription outside its cancellation/management surface.
    assert.equal(result.portalAvailable, true, String(value));
    assert.equal(result.checkoutAvailable, true, String(value));
  }
});

test("suspended or unverified payer can still open their canonical Stripe portal", async () => {
  const firestore = new FakeFirestore({
    "entitlements/suspended": { source: "stripe", status: "active" },
    "billingAccounts/suspended": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_current",
    },
    "users/suspended": { banned: true, disabled: true },
  });
  const result = await handlers({ firestore, stripe: stripeFake() })
    .createPremiumPortalSessionHandler({
      auth: { uid: "suspended", token: { email_verified: false } },
      data: {},
    });
  assert.equal(result.url, "https://billing.stripe.com/p/session");
});

test("portal configuration retrieval expands subscription update products", async () => {
  const fake = stripeFake();
  const originalRetrieve = fake.billingPortal.configurations.retrieve;
  let retrieveArguments;
  fake.billingPortal.configurations.retrieve = async (...args) => {
    retrieveArguments = args;
    return originalRetrieve(...args);
  };
  await handlers({ firestore: new FakeFirestore(), stripe: fake })
    .loadPortalConfiguration();
  assert.deepEqual(retrieveArguments, [
    "bpc_test",
    { expand: ["features.subscription_update.products"] },
  ]);
});

test("portal fails closed unless cancellation and both plan switches are enabled", async () => {
  const firestore = new FakeFirestore({
    "entitlements/user": { source: "stripe", status: "active" },
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_current",
    },
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

test("portal accepts only at-period-end cancellation and the exact two Price allowlist", async () => {
  const seed = {
    "entitlements/user": { source: "stripe", status: "active" },
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_current",
    },
  };
  const validFeatures = {
    subscription_cancel: { enabled: true, mode: "at_period_end" },
    subscription_update: {
      enabled: true,
      default_allowed_updates: ["price"],
      products: [
        {
          product: "prod_premium",
          prices: ["price_monthly", "price_yearly"],
          adjustable_quantity: {
            enabled: false,
            minimum: 1,
            maximum: null,
          },
        },
      ],
    },
  };
  const invalidFeatures = [
    {
      ...validFeatures,
      subscription_cancel: { enabled: true, mode: "immediately" },
    },
    {
      ...validFeatures,
      subscription_update: {
        ...validFeatures.subscription_update,
        default_allowed_updates: ["price", "quantity"],
      },
    },
    {
      ...validFeatures,
      subscription_update: {
        ...validFeatures.subscription_update,
        products: [
          ...validFeatures.subscription_update.products,
          { product: "prod_other", prices: ["price_other"] },
        ],
      },
    },
    {
      ...validFeatures,
      subscription_update: {
        ...validFeatures.subscription_update,
        products: [
          {
            product: "prod_premium",
            prices: ["price_monthly", "price_yearly", "price_extra"],
          },
        ],
      },
    },
    {
      ...validFeatures,
      subscription_update: {
        ...validFeatures.subscription_update,
        products: [
          {
            ...validFeatures.subscription_update.products[0],
            adjustable_quantity: {
              enabled: true,
              minimum: 1,
              maximum: 10,
            },
          },
        ],
      },
    },
  ];
  for (const features of invalidFeatures) {
    const fake = stripeFake();
    fake.billingPortal.configurations.retrieve = async () => ({
      active: true,
      features,
    });
    await assert.rejects(
      handlers({ firestore: new FakeFirestore(seed), stripe: fake })
        .createPremiumPortalSessionHandler({
          auth: { uid: "user" },
          data: {},
        }),
      /must allow cancellation and switching between both configured Premium Prices/,
    );
  }
});

test("portal configuration is revalidated after a Dashboard mutation", async () => {
  const firestore = new FakeFirestore({
    "entitlements/user": { source: "stripe", status: "active" },
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_current",
    },
  });
  const fake = stripeFake();
  const originalRetrieve = fake.billingPortal.configurations.retrieve;
  let quantityEnabled = false;
  fake.billingPortal.configurations.retrieve = async () => {
    const configuration = await originalRetrieve();
    if (quantityEnabled) {
      configuration.features.subscription_update.default_allowed_updates = [
        "price",
        "quantity",
      ];
    }
    return configuration;
  };
  const service = handlers({ firestore, stripe: fake });
  assert.equal(
    (
      await service.createPremiumPortalSessionHandler({
        auth: { uid: "user" },
        data: {},
      })
    ).url,
    "https://billing.stripe.com/p/session",
  );
  quantityEnabled = true;
  await assert.rejects(
    service.createPremiumPortalSessionHandler({
      auth: { uid: "user" },
      data: {},
    }),
    /must allow cancellation and switching between both configured Premium Prices/,
  );
});

test("portal verifies that the canonical subscription belongs to the customer", async () => {
  const firestore = new FakeFirestore({
    "entitlements/user": { source: "stripe", status: "active" },
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_current",
    },
  });
  const fake = stripeFake();
  fake.subscriptions.retrieve = async () =>
    subscription({ customer: "cus_another_customer" });
  await assert.rejects(
    handlers({ firestore, stripe: fake }).createPremiumPortalSessionHandler({
      auth: { uid: "user" },
      data: {},
    }),
    /does not belong to this billing account/,
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
  const original = fake.prices.retrieve;
  fake.prices.retrieve = async (id) =>
    id === "price_monthly"
      ? price({ id, interval: "month", amount: 1 })
      : original(id);
  await assert.rejects(
    handlers({ firestore, stripe: fake }).applySubscription("sub_current", {
      id: "evt_wrong_price",
      type: "customer.subscription.updated",
      created: 1,
    }),
    /must be EUR 600/,
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
    { method: "POST", rawBody: Buffer.from("x"), headers: { "stripe-signature": "sig" } },
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

test("Dahlia invoice.paid resolves its subscription through Invoice.parent", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "personal" },
  });
  const event = {
    id: "evt_dahlia_invoice_paid",
    livemode: false,
    type: "invoice.paid",
    created: 8,
    data: {
      object: {
        id: "in_current",
        customer: "cus_current",
        parent: {
          type: "subscription_details",
          subscription_details: { subscription: "sub_current" },
        },
      },
    },
  };
  const response = responseRecorder();
  await handlers({ firestore, stripe: stripeFake({ event }) }).stripeWebhookHandler(
    { method: "POST", rawBody: Buffer.from("signed"), headers: { "stripe-signature": "sig" } },
    response,
    "whsec_test",
  );
  assert.equal(response.statusCode, 200);
  assert.equal(firestore.documents.get("entitlements/user").isPremium, true);
  assert.equal(
    firestore.documents.get("billingAccounts/user").currentInvoiceId,
    "in_current",
  );
  assert.equal(
    firestore.documents.get("billingAccounts/user").currentPaymentIntentId,
    "pi_invoice",
  );
});

test("unpaid renewal never extends access beyond the paid entitlement", async () => {
  const paidUntil = Timestamp.fromMillis(NOW_MS + 5 * 86400000);
  const firestore = new FakeFirestore({
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_current",
      stripeSubscriptionStatus: "active",
      currentInvoiceId: "in_current",
      currentPaymentIntentId: "pi_invoice",
    },
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
    { method: "POST", rawBody: Buffer.from("x"), headers: { "stripe-signature": "sig" } },
    response,
    "whsec_test",
  );
  assert.equal(response.statusCode, 200);
  assert.equal(firestore.documents.get("entitlements/user").isPremium, false);
});

test("signed BLIK Checkout grants a non-renewing yearly prepaid entitlement", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "personal", premiumIdentity: false },
  });
  const event = {
    id: "evt_blik_paid",
    livemode: false,
    type: "checkout.session.completed",
    created: 10,
    data: {
      object: {
        id: "cs_prepaid",
        mode: "payment",
        payment_status: "paid",
        metadata: { firebaseUid: "attacker-selected" },
      },
    },
  };
  const service = handlers({ firestore, stripe: stripeFake({ event }) });
  const response = responseRecorder();
  await service.stripeWebhookHandler(
    { method: "POST", rawBody: Buffer.from("signed"), headers: { "stripe-signature": "sig" } },
    response,
    "whsec_test",
  );
  assert.equal(response.statusCode, 200);
  const entitlement = firestore.documents.get("entitlements/user");
  assert.equal(entitlement.isPremium, true);
  assert.equal(entitlement.plan, "yearly");
  assert.equal(entitlement.source, "stripe_prepaid");
  assert.equal(entitlement.renewalBehavior, "none");
  assert.equal(
    entitlement.currentPeriodEnd.toMillis(),
    NOW_MS + 365 * 86400000,
  );
  assert.equal(firestore.documents.get("users/user").premiumIdentity, true);
  assert.ok(firestore.documents.has("stripeWebhookEvents/evt_blik_paid"));
  assert.ok(firestore.documents.has("stripeWebhookEvents/prepaid_cs_prepaid"));
  assert.equal(firestore.documents.has("entitlements/attacker-selected"), false);
});

test("monthly BLIK grants exactly 30 days and a second event cannot stack time", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "personal" },
  });
  const fake = stripeFake();
  fake.checkout.sessions.retrieve = async () => ({
    id: "cs_monthly_blik",
    mode: "payment",
    status: "complete",
    payment_status: "paid",
    customer: "cus_current",
    payment_intent: "pi_monthly_blik",
    currency: "pln",
    amount_total: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
  });
  fake.checkout.sessions.listLineItems = async () => ({
    data: [{ price: { id: "price_blik_monthly" }, quantity: 1 }],
  });
  fake.paymentIntents.retrieve = async () => ({
    id: "pi_monthly_blik",
    status: "succeeded",
    customer: "cus_current",
    currency: "pln",
    amount_received: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
    payment_method: "pm_blik",
    payment_method_types: ["blik"],
  });
  const service = handlers({ firestore, stripe: fake });
  const first = await service.applyPrepaidPurchase("cs_monthly_blik", {
    id: "evt_monthly_blik_1",
    type: "checkout.session.completed",
    created: 11,
  });
  assert.deepEqual(first, { applied: true, uid: "user", plan: "monthly" });
  const end = firestore.documents
    .get("entitlements/user")
    .currentPeriodEnd.toMillis();
  assert.equal(end, NOW_MS + 30 * 86400000);

  const duplicate = await service.applyPrepaidPurchase("cs_monthly_blik", {
    id: "evt_monthly_blik_2",
    type: "checkout.session.async_payment_succeeded",
    created: 12,
  });
  assert.deepEqual(duplicate, { ignored: true });
  assert.equal(
    firestore.documents.get("entitlements/user").currentPeriodEnd.toMillis(),
    end,
  );
  assert.equal(
    firestore.documents.get("stripeWebhookEvents/evt_monthly_blik_2")
      .duplicatePrepaidPurchase,
    true,
  );
});

test("BLIK fulfillment never overwrites access activated while Checkout was open", async () => {
  const currentPeriodEnd = Timestamp.fromMillis(NOW_MS + 45 * 86400000);
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "entitlements/user": {
      source: "stripe",
      plan: "monthly",
      status: "active",
      isPremium: true,
      currentPeriodEnd,
    },
    "users/user": { premiumIdentity: true },
  });
  const result = await handlers({ firestore, stripe: stripeFake() })
    .applyPrepaidPurchase("cs_prepaid", {
      id: "evt_blik_overlap",
      type: "checkout.session.completed",
      created: 13,
    });
  assert.deepEqual(result, { reviewRequired: true, uid: "user" });
  const entitlement = firestore.documents.get("entitlements/user");
  assert.equal(entitlement.source, "stripe");
  assert.equal(entitlement.currentPeriodEnd.toMillis(), currentPeriodEnd.toMillis());
  assert.equal(
    firestore.documents.get("stripeWebhookEvents/prepaid_cs_prepaid")
      .fulfillmentStatus,
    "manual-review",
  );
  assert.equal(
    firestore.documents.get("billingAccounts/user").billingReviewReason,
    "prepaid-active-entitlement-overlap",
  );
});

test("BLIK webhook fails closed on an unconfigured total or PaymentIntent", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "personal" },
  });
  const fake = stripeFake();
  fake.paymentIntents.retrieve = async () => ({
    id: "pi_prepaid",
    status: "succeeded",
    customer: "cus_other",
    currency: "pln",
    amount_received: BLIK_PLAN_CONFIGURATION.yearly.unitAmount,
    payment_method: "pm_blik",
    payment_method_types: ["blik"],
  });
  await assert.rejects(
    handlers({ firestore, stripe: fake }).applyPrepaidPurchase("cs_prepaid", {
      id: "evt_bad_blik",
      type: "checkout.session.completed",
      created: 13,
    }),
    /not a settled configured BLIK payment/,
  );
  assert.equal(firestore.documents.has("entitlements/user"), false);
  assert.equal(firestore.documents.has("stripeWebhookEvents/evt_bad_blik"), false);
});

test("BLIK fulfillment verifies the PaymentIntent's actually used PaymentMethod", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "personal" },
  });
  const fake = stripeFake();
  fake.paymentIntents.retrieve = async () => ({
    id: "pi_prepaid",
    status: "succeeded",
    customer: "cus_current",
    currency: "pln",
    amount_received: BLIK_PLAN_CONFIGURATION.yearly.unitAmount,
    payment_method: "pm_card",
    payment_method_types: ["blik"],
  });
  fake.paymentMethods.retrieve = async () => ({ id: "pm_card", type: "card" });
  await assert.rejects(
    handlers({ firestore, stripe: fake }).applyPrepaidPurchase("cs_prepaid", {
      id: "evt_card_not_blik",
      type: "checkout.session.completed",
      created: 13,
    }),
    /not a settled configured BLIK payment/,
  );
  assert.equal(firestore.documents.has("entitlements/user"), false);
});

test("a second paid BLIK checkout cannot replace the current prepaid receipt", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "personal" },
  });
  const fake = stripeFake();
  const sessions = {
    cs_first: {
      id: "cs_first",
      mode: "payment",
      status: "complete",
      payment_status: "paid",
      customer: "cus_current",
      payment_intent: "pi_first",
      currency: "pln",
      amount_total: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
    },
    cs_second: {
      id: "cs_second",
      mode: "payment",
      status: "complete",
      payment_status: "paid",
      customer: "cus_current",
      payment_intent: "pi_second",
      currency: "pln",
      amount_total: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
    },
  };
  fake.checkout.sessions.retrieve = async (id) => sessions[id];
  fake.checkout.sessions.listLineItems = async () => ({
    data: [{ price: { id: "price_blik_monthly" }, quantity: 1 }],
  });
  fake.paymentIntents.retrieve = async (id) => ({
    id,
    status: "succeeded",
    customer: "cus_current",
    currency: "pln",
    amount_received: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
    payment_method: "pm_blik",
  });
  const service = handlers({ firestore, stripe: fake });
  assert.deepEqual(
    await service.applyPrepaidPurchase("cs_first", {
      id: "evt_first_blik",
      type: "checkout.session.completed",
      created: 14,
    }),
    { applied: true, uid: "user", plan: "monthly" },
  );
  assert.deepEqual(
    await service.applyPrepaidPurchase("cs_second", {
      id: "evt_second_blik",
      type: "checkout.session.completed",
      created: 15,
    }),
    { reviewRequired: true, uid: "user" },
  );
  const billing = firestore.documents.get("billingAccounts/user");
  assert.equal(billing.currentPrepaidCheckoutSessionId, "cs_first");
  assert.equal(billing.currentPrepaidPaymentIntentId, "pi_first");
  assert.equal(billing.lastPrepaidCheckoutSessionId, "cs_first");
  assert.equal(billing.lastPrepaidPaymentIntentId, "pi_first");
  assert.equal(
    firestore.documents.get("stripeWebhookEvents/prepaid_cs_second")
      .fulfillmentStatus,
    "manual-review",
  );

  fake.charges.retrieve = async () => ({
    id: "ch_second",
    customer: "cus_current",
    payment_intent: "pi_second",
    invoice: null,
    amount: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
    amount_refunded: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
  });
  assert.deepEqual(
    await service.applyFinancialRiskEvent({
      id: "evt_second_blik_refund",
      type: "charge.refunded",
      created: 16,
      data: { object: { id: "ch_second" } },
    }),
    { reviewRequired: true },
  );
  assert.equal(firestore.documents.get("entitlements/user").isPremium, true);
  assert.equal(
    firestore.documents.get("billingAccounts/user").currentPrepaidPaymentIntentId,
    "pi_first",
  );
});

test("a BLIK refund delivered before Checkout fulfillment permanently blocks the grant", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "personal" },
  });
  const fake = stripeFake();
  fake.charges.retrieve = async () => ({
    id: "ch_prepaid_before_fulfillment",
    customer: "cus_current",
    payment_intent: "pi_prepaid",
    amount: BLIK_PLAN_CONFIGURATION.yearly.unitAmount,
    amount_refunded: BLIK_PLAN_CONFIGURATION.yearly.unitAmount,
  });
  const service = handlers({ firestore, stripe: fake });
  assert.deepEqual(
    await service.applyFinancialRiskEvent({
      id: "evt_refund_before_blik_fulfillment",
      type: "charge.refunded",
      created: 16,
      data: { object: { id: "ch_prepaid_before_fulfillment" } },
    }),
    { reviewRequired: true },
  );
  assert.equal(
    firestore.documents.get("stripeFinancialRisks/pi_prepaid").accessBlocked,
    true,
  );
  assert.deepEqual(
    await service.applyPrepaidPurchase("cs_prepaid", {
      id: "evt_blik_after_refund",
      type: "checkout.session.completed",
      created: 17,
    }),
    { reviewRequired: true, uid: "user" },
  );
  assert.equal(firestore.documents.has("entitlements/user"), false);
  assert.equal(
    firestore.documents.get("stripeWebhookEvents/prepaid_cs_prepaid")
      .fulfillmentStatus,
    "financial-risk",
  );
});

test("prepaid access has no Stripe subscription portal", async () => {
  const firestore = new FakeFirestore({
    "entitlements/user": {
      source: "stripe_prepaid",
      plan: "yearly",
      status: "active",
      currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 86400000),
      renewalBehavior: "none",
    },
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_stale",
    },
  });
  const context = await handlers({ firestore, stripe: stripeFake() })
    .getPremiumBillingContextHandler({ auth: { uid: "user" }, data: {} });
  assert.equal(context.billingManagedBy, "stripe");
  assert.equal(context.portalAvailable, false);
  assert.equal(context.renewalBehavior, "none");
  await assert.rejects(
    handlers({ firestore, stripe: stripeFake() })
      .createPremiumPortalSessionHandler({ auth: { uid: "user" }, data: {} }),
    /prepaid and has no subscription portal/,
  );
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

test("late Stripe events never recreate access for missing or deleted users", async () => {
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
    assert.equal(firestore.documents.has(`entitlements/${scenario.uid}`), false);
    assert.ok(firestore.documents.has(`stripeWebhookEvents/${scenario.eventId}`));
  }
});

test("Auth deletion creates a durable tombstone even without an existing billing document", async () => {
  const firestore = new FakeFirestore();
  const result = await cancelStripeBillingForDeletedUser("deleted", {
    firestore,
    stripe: stripeFake(),
    now: () => Timestamp.fromMillis(NOW_MS),
  });
  assert.deepEqual(result, { outcome: "no-stripe-subscription" });
  const billing = firestore.documents.get("billingAccounts/deleted");
  assert.equal(billing.accountDeletionTombstone, true);
  assert.equal(billing.accountDeletedAt.toMillis(), NOW_MS);
  assert.equal(billing.accountDeletionCancellationStatus, "no-stripe-subscription");
});

test("Auth deletion expires Premium that won the race before the tombstone", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/deleted": { stripeCustomerId: "cus_current" },
    "entitlements/deleted": {
      source: "stripe",
      plan: "monthly",
      status: "active",
      isPremium: true,
      currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 30 * 86400000),
    },
  });
  const result = await cancelStripeBillingForDeletedUser("deleted", {
    firestore,
    stripe: stripeFake(),
    now: () => Timestamp.fromMillis(NOW_MS),
  });
  assert.deepEqual(result, { outcome: "no-active-subscription" });
  const entitlement = firestore.documents.get("entitlements/deleted");
  assert.equal(entitlement.isPremium, false);
  assert.equal(entitlement.status, "expired");
  assert.equal(entitlement.currentPeriodEnd.toMillis(), NOW_MS);
  assert.equal(
    firestore.documents.get("billingAccounts/deleted").accountDeletionTombstone,
    true,
  );
});

test("Checkout cannot create a customer or session after an Auth deletion tombstone", async () => {
  const firestore = new FakeFirestore({
    "users/deleted": { accountType: "personal" },
    "billingAccounts/deleted": {
      accountDeletionTombstone: true,
      accountDeletedAt: Timestamp.fromMillis(NOW_MS),
    },
  });
  let customerCreates = 0;
  let sessionCreates = 0;
  const fake = stripeFake();
  fake.customers.create = async () => {
    customerCreates += 1;
    return { id: "cus_should_not_exist" };
  };
  fake.checkout.sessions.create = async () => {
    sessionCreates += 1;
    return {
      id: "cs_should_not_exist",
      status: "open",
      url: "https://checkout.stripe.com/c/pay/session",
    };
  };
  await assert.rejects(
    handlers({ firestore, stripe: fake }).createPremiumCheckoutSessionHandler({
      auth: { uid: "deleted", token: { email_verified: true } },
      data: { plan: "monthly" },
    }),
    /cannot manage Premium/,
  );
  assert.equal(customerCreates, 0);
  assert.equal(sessionCreates, 0);
});

test("a lost Customer create response leaves a durable idempotent cleanup attempt", async () => {
  const firestore = new FakeFirestore({
    "users/user": { accountType: "personal" },
  });
  let sessionCreates = 0;
  const fake = stripeFake();
  fake.customers.create = async (_payload, options) => {
    const attempt = firestore.documents.get("stripeCustomerCleanup/create_user");
    assert.equal(attempt.uid, "user");
    assert.equal(attempt.status, "creating");
    assert.equal(attempt.requiresManualCleanup, true);
    assert.equal(
      attempt.createIdempotencyKey,
      "yovoice_customer_user_v1",
    );
    assert.equal(options.idempotencyKey, attempt.createIdempotencyKey);
    throw new Error("injected provider response loss after Customer create");
  };
  fake.checkout.sessions.create = async () => {
    sessionCreates += 1;
  };
  await assert.rejects(
    handlers({ firestore, stripe: fake }).createPremiumCheckoutSessionHandler({
      auth: { uid: "user", token: { email_verified: true } },
      data: { plan: "monthly" },
    }),
    /injected provider response loss/,
  );
  const attempt = firestore.documents.get("stripeCustomerCleanup/create_user");
  assert.equal(attempt.status, "creating");
  assert.equal(attempt.requiresManualCleanup, true);
  assert.equal(attempt.stripeCustomerId, undefined);
  assert.equal(sessionCreates, 0);
});

test("a Customer created during an Auth deletion race is deleted before Checkout", async () => {
  const firestore = new FakeFirestore({
    "users/user": { accountType: "personal" },
  });
  const deletedCustomers = [];
  let scrubCalls = 0;
  let sessionCreates = 0;
  const fake = stripeFake();
  fake.customers.create = async () => {
    firestore.documents.set("billingAccounts/user", {
      accountDeletionTombstone: true,
      accountDeletedAt: Timestamp.fromMillis(NOW_MS),
    });
    return { id: "cus_orphan" };
  };
  fake.customers.del = async (id, payload, options) => {
    deletedCustomers.push({ id, payload, options });
    return { id, object: "customer", deleted: true };
  };
  fake.customers.update = async () => {
    scrubCalls += 1;
  };
  fake.checkout.sessions.create = async () => {
    sessionCreates += 1;
  };
  await assert.rejects(
    handlers({ firestore, stripe: fake }).createPremiumCheckoutSessionHandler({
      auth: { uid: "user", token: { email_verified: true } },
      data: { plan: "monthly" },
    }),
    /cannot manage Premium/,
  );
  assert.deepEqual(
    deletedCustomers.map(({ id }) => id),
    ["cus_orphan"],
  );
  assert.deepEqual(deletedCustomers[0].payload, {});
  assert.match(
    deletedCustomers[0].options.idempotencyKey,
    /cus_orphan$/,
  );
  assert.equal(scrubCalls, 0);
  assert.equal(sessionCreates, 0);
  assert.equal(
    firestore.documents.get("billingAccounts/user").stripeCustomerId,
    undefined,
  );
  assert.equal(
    firestore.documents.get("stripeCustomerCleanup/cus_orphan").status,
    "deleted",
  );
  const attempt = firestore.documents.get("stripeCustomerCleanup/create_user");
  assert.equal(attempt.stripeCustomerId, "cus_orphan");
  assert.equal(attempt.status, "deleted");
  assert.equal(attempt.requiresManualCleanup, false);
});

test("subscription webhook after a billing tombstone cancels the incoming subscription without access", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/deleted": {
      stripeCustomerId: "cus_current",
      accountDeletionTombstone: true,
      accountDeletedAt: Timestamp.fromMillis(NOW_MS),
    },
    "users/deleted": { accountType: "personal" },
  });
  const canceled = [];
  const fake = stripeFake();
  fake.subscriptions.retrieve = async (id) => subscription({ id });
  fake.subscriptions.cancel = async (id) => {
    canceled.push(id);
    return subscription({ id, status: "canceled" });
  };
  assert.deepEqual(
    await handlers({ firestore, stripe: fake }).applySubscription(
      "sub_after_delete",
      {
        id: "evt_after_billing_tombstone",
        type: "customer.subscription.created",
        created: 13,
      },
    ),
    { ignored: true },
  );
  assert.deepEqual(canceled, ["sub_after_delete"]);
  assert.equal(firestore.documents.has("entitlements/deleted"), false);
  assert.equal(
    firestore.documents.get("stripeWebhookEvents/evt_after_billing_tombstone")
      .ignoredAfterAccountDeletion,
    true,
  );
});

test("recurring webhook never overwrites active Apple, admin or BLIK access", async () => {
  for (const source of ["apple", "admin", "stripe_prepaid"]) {
    const periodEnd = Timestamp.fromMillis(NOW_MS + 10 * 86400000);
    const firestore = new FakeFirestore({
      "billingAccounts/user": { stripeCustomerId: "cus_current" },
      "entitlements/user": {
        source,
        plan: "yearly",
        status: "active",
        isPremium: true,
        currentPeriodEnd: periodEnd,
      },
      "users/user": { accountType: "personal" },
    });
    const canceled = [];
    const fake = stripeFake();
    fake.subscriptions.retrieve = async (id) => subscription({ id });
    fake.subscriptions.cancel = async (id) => {
      canceled.push(id);
      return subscription({ id, status: "canceled" });
    };
    assert.deepEqual(
      await handlers({ firestore, stripe: fake }).applySubscription(
        `sub_overlap_${source}`,
        {
          id: `evt_overlap_${source}`,
          type: "customer.subscription.created",
          created: 14,
        },
      ),
      { reviewRequired: true, uid: "user" },
    );
    const entitlement = firestore.documents.get("entitlements/user");
    assert.equal(entitlement.source, source);
    assert.equal(entitlement.currentPeriodEnd.toMillis(), periodEnd.toMillis());
    assert.deepEqual(canceled, [`sub_overlap_${source}`]);
  }
});

test("a duplicate active Stripe subscription is canceled without replacing the canonical one", async () => {
  const periodEnd = Timestamp.fromMillis(NOW_MS + 10 * 86400000);
  const firestore = new FakeFirestore({
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_existing",
      stripeSubscriptionStatus: "active",
    },
    "entitlements/user": {
      source: "stripe",
      plan: "monthly",
      status: "active",
      isPremium: true,
      currentPeriodEnd: periodEnd,
    },
    "users/user": { accountType: "personal" },
  });
  const canceled = [];
  const fake = stripeFake();
  fake.subscriptions.retrieve = async (id) => subscription({ id });
  fake.subscriptions.cancel = async (id) => {
    canceled.push(id);
    return subscription({ id, status: "canceled" });
  };
  assert.deepEqual(
    await handlers({ firestore, stripe: fake }).applySubscription(
      "sub_duplicate",
      {
        id: "evt_duplicate_active",
        type: "customer.subscription.created",
        created: 15,
      },
    ),
    { reviewRequired: true, uid: "user" },
  );
  assert.deepEqual(canceled, ["sub_duplicate"]);
  assert.equal(
    firestore.documents.get("billingAccounts/user").stripeSubscriptionId,
    "sub_existing",
  );
  assert.equal(firestore.documents.get("entitlements/user").plan, "monthly");
  assert.equal(
    firestore.documents.get("stripeWebhookEvents/evt_duplicate_active")
      .incomingSubscriptionCanceled,
    true,
  );
});

test("duplicate detection refreshes the prior subscription even when its projected status is stale", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_old",
      stripeSubscriptionStatus: "expired",
    },
    "entitlements/user": {
      source: "stripe",
      plan: "monthly",
      status: "expired",
      isPremium: false,
      currentPeriodEnd: Timestamp.fromMillis(NOW_MS - 1000),
    },
    "users/user": { accountType: "personal" },
  });
  const canceled = [];
  const fake = stripeFake();
  fake.subscriptions.retrieve = async (id) => subscription({ id, status: "active" });
  fake.subscriptions.cancel = async (id) => {
    canceled.push(id);
    return subscription({ id, status: "canceled" });
  };
  assert.deepEqual(
    await handlers({ firestore, stripe: fake }).applySubscription("sub_new", {
      id: "evt_duplicate_stale_projection",
      type: "invoice.paid",
      created: 16,
    }),
    { reviewRequired: true, uid: "user" },
  );
  assert.deepEqual(canceled, ["sub_new"]);
  assert.equal(
    firestore.documents.get("billingAccounts/user").stripeSubscriptionId,
    "sub_old",
  );
  assert.equal(firestore.documents.get("entitlements/user").isPremium, false);
});

test("duplicate cancellation survives a crash before the manual-review audit", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_existing",
      stripeSubscriptionStatus: "active",
    },
    "entitlements/user": {
      source: "stripe",
      plan: "monthly",
      status: "active",
      isPremium: true,
      currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 86400000),
    },
    "users/user": { accountType: "personal" },
  });
  firestore.failNextOverlapCompletionWrite = true;
  let duplicateStatus = "active";
  let cancellationCalls = 0;
  const fake = stripeFake();
  fake.subscriptions.retrieve = async (id) =>
    subscription({
      id,
      status: id === "sub_duplicate" ? duplicateStatus : "active",
    });
  fake.subscriptions.cancel = async (id) => {
    assert.equal(id, "sub_duplicate");
    cancellationCalls += 1;
    duplicateStatus = "canceled";
    return subscription({ id, status: "canceled" });
  };
  const service = handlers({ firestore, stripe: fake });
  const event = {
    id: "evt_duplicate_crash",
    type: "customer.subscription.created",
    created: 17,
  };
  await assert.rejects(
    service.applySubscription("sub_duplicate", event),
    /injected crash after duplicate cancellation/,
  );
  assert.equal(
    firestore.documents.get("stripeWebhookEvents/evt_duplicate_crash")
      .processingState,
    "cancel-pending",
  );
  assert.deepEqual(
    await service.applySubscription("sub_duplicate", event),
    { reviewRequired: true, uid: "user" },
  );
  assert.equal(cancellationCalls, 1);
  const receipt = firestore.documents.get(
    "stripeWebhookEvents/evt_duplicate_crash",
  );
  assert.equal(receipt.processingState, "completed");
  assert.equal(receipt.incomingSubscriptionAlreadyTerminal, true);
  assert.equal(receipt.cancellationConverged, true);
  assert.equal(
    firestore.documents.get("billingAccounts/user").billingReviewReason,
    "duplicate-active-stripe-subscription",
  );
});

test("a paid incoming subscription can replace a stale Firestore projection after canonical refresh", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_old",
      stripeSubscriptionStatus: "active",
    },
    "entitlements/user": {
      source: "stripe",
      plan: "monthly",
      status: "active",
      isPremium: true,
      currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 86400000),
    },
    "users/user": { accountType: "personal" },
  });
  const fake = stripeFake();
  fake.subscriptions.retrieve = async (id) =>
    id === "sub_old"
      ? subscription({ id, status: "canceled" })
      : subscription({ id, priceId: "price_yearly", status: "active" });
  assert.deepEqual(
    await handlers({ firestore, stripe: fake }).applySubscription("sub_new", {
      id: "evt_new_after_old_terminal",
      type: "invoice.paid",
      created: 16,
    }),
    { applied: true, uid: "user" },
  );
  assert.equal(
    firestore.documents.get("billingAccounts/user").stripeSubscriptionId,
    "sub_new",
  );
  assert.equal(firestore.documents.get("entitlements/user").plan, "yearly");
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
  fake.checkout.sessions.retrieve = async () => ({
    id: "cs_pending",
    customer: "cus_current",
    status: "open",
  });
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

test("Auth deletion paginates and expires every open Checkout Session for the canonical Customer", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/deleted": {
      stripeCustomerId: "cus_current",
      pendingCheckoutSessionId: "cs_pending_gap",
    },
  });
  const listRequests = [];
  const expired = [];
  const fake = stripeFake();
  fake.checkout.sessions.list = async (request) => {
    listRequests.push(request);
    if (!request.starting_after) {
      return {
        data: [
          {
            id: "cs_page_one",
            customer: "cus_current",
            status: "open",
          },
        ],
        has_more: true,
      };
    }
    assert.equal(request.starting_after, "cs_page_one");
    return {
      data: [
        {
          id: "cs_page_two",
          customer: { id: "cus_current" },
          status: "open",
        },
      ],
      has_more: false,
    };
  };
  fake.checkout.sessions.retrieve = async (id) => ({
    id,
    customer: "cus_current",
    status: "open",
  });
  fake.checkout.sessions.expire = async (id, payload, options) => {
    expired.push({ id, payload, options });
  };
  const result = await cancelStripeBillingForDeletedUser("deleted", {
    firestore,
    stripe: fake,
    now: () => Timestamp.fromMillis(NOW_MS),
  });
  assert.deepEqual(result, { outcome: "no-active-subscription" });
  assert.equal(listRequests.length, 2);
  assert.deepEqual(listRequests[0], {
    customer: "cus_current",
    status: "open",
    limit: 100,
  });
  assert.deepEqual(listRequests[1], {
    customer: "cus_current",
    status: "open",
    limit: 100,
    starting_after: "cs_page_one",
  });
  assert.deepEqual(
    expired.map(({ id }) => id),
    ["cs_page_one", "cs_page_two", "cs_pending_gap"],
  );
  for (const { id, payload, options } of expired) {
    assert.deepEqual(payload, {});
    assert.match(options.idempotencyKey, new RegExp(`${id}$`));
  }
  assert.equal(
    firestore.documents.get("billingAccounts/deleted").pendingCheckoutSessionId,
    null,
  );
});

test("signed full-refund webhook revokes only its subscription and replay cannot touch a later purchase", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_current",
      stripeSubscriptionStatus: "active",
      currentInvoiceId: "in_current",
      currentPaymentIntentId: "pi_invoice",
    },
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
  fake.subscriptions.retrieve = async (id) => subscription({ id });
  fake.subscriptions.cancel = async (_id, _payload, options) => {
    keys.push(options.idempotencyKey);
  };
  const service = handlers({ firestore, stripe: fake });
  let response = responseRecorder();
  await service.stripeWebhookHandler(
    { method: "POST", rawBody: Buffer.from("signed"), headers: { "stripe-signature": "sig" } },
    response,
    "whsec_test",
  );
  assert.equal(response.statusCode, 200);
  assert.equal(firestore.documents.get("entitlements/user").isPremium, false);
  assert.equal(firestore.documents.get("users/user").premiumIdentity, false);
  assert.equal(firestore.documents.get("users/user").accountType, "personal");
  assert.equal(
    firestore.documents.get("billingAccounts/user").financialAccessReason,
    "full-refund",
  );
  assert.equal(keys.length, 1);
  assert.match(keys[0], /sub_current$/);

  const laterPeriodEnd = Timestamp.fromMillis(NOW_MS + 60 * 86400000);
  firestore.documents.set("billingAccounts/user", {
    ...firestore.documents.get("billingAccounts/user"),
    stripeSubscriptionId: "sub_later",
    stripeSubscriptionStatus: "active",
  });
  firestore.documents.set("entitlements/user", {
    source: "stripe",
    plan: "yearly",
    status: "active",
    isPremium: true,
    currentPeriodEnd: laterPeriodEnd,
  });
  firestore.documents.set("users/user", {
    accountType: "creator",
    premiumIdentity: true,
  });
  response = responseRecorder();
  await service.stripeWebhookHandler(
    {
      method: "POST",
      rawBody: Buffer.from("signed replay"),
      headers: { "stripe-signature": "sig" },
    },
    response,
    "whsec_test",
  );
  assert.equal(response.statusCode, 200);
  assert.equal(keys.length, 1);
  assert.equal(firestore.documents.get("entitlements/user").isPremium, true);
  assert.equal(firestore.documents.get("entitlements/user").plan, "yearly");
  assert.equal(
    firestore.documents.get("entitlements/user").currentPeriodEnd.toMillis(),
    laterPeriodEnd.toMillis(),
  );
  assert.equal(firestore.documents.get("users/user").premiumIdentity, true);
});

test("a concurrent recurring financial delivery cannot execute a second cancellation", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_current",
      stripeSubscriptionStatus: "active",
      currentInvoiceId: "in_current",
      currentPaymentIntentId: "pi_invoice",
    },
    "entitlements/user": {
      source: "stripe",
      plan: "monthly",
      status: "active",
      isPremium: true,
      currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 86400000),
    },
    "users/user": { accountType: "creator", premiumIdentity: true },
    "stripeWebhookEvents/evt_concurrent_refund": {
      type: "charge.refunded",
      subscriptionId: "sub_current",
      invoiceId: "in_current",
      paymentIntentId: "pi_invoice",
      processingState: "financial-cancel-pending",
      operationToken: "other-worker",
      operationLeaseUntil: Timestamp.fromMillis(NOW_MS + 60000),
    },
    "stripeFinancialRisks/pi_invoice": {
      accessBlocked: true,
      paymentIntentId: "pi_invoice",
    },
  });
  let cancellationCalls = 0;
  const fake = stripeFake();
  fake.subscriptions.cancel = async () => {
    cancellationCalls += 1;
  };
  assert.deepEqual(
    await handlers({ firestore, stripe: fake }).applyFinancialRiskEvent({
      id: "evt_concurrent_refund",
      type: "charge.refunded",
      created: 17,
      data: { object: { id: "ch_current" } },
    }),
    { inProgress: true },
  );
  assert.equal(cancellationCalls, 0);
  assert.equal(firestore.documents.get("entitlements/user").isPremium, true);
});

test("refund of an old recurring charge cannot cancel or revoke the current subscription", async () => {
  const currentPeriodEnd = Timestamp.fromMillis(NOW_MS + 45 * 86400000);
  const firestore = new FakeFirestore({
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_new",
      stripeSubscriptionStatus: "active",
      currentInvoiceId: "in_new",
      currentPaymentIntentId: "pi_new",
    },
    "entitlements/user": {
      source: "stripe",
      plan: "yearly",
      status: "active",
      isPremium: true,
      currentPeriodEnd,
    },
    "users/user": { accountType: "creator", premiumIdentity: true },
  });
  let cancellations = 0;
  const fake = stripeFake();
  fake.charges.retrieve = async () => ({
    id: "ch_old_recurring",
    customer: "cus_current",
    payment_intent: "pi_old",
    amount: 600,
    amount_refunded: 600,
  });
  fake.invoices.retrieve = async () => ({
    id: "in_old",
    customer: "cus_current",
    parent: {
      type: "subscription_details",
      subscription_details: { subscription: "sub_old" },
    },
  });
  fake.invoicePayments.list = async () => ({
    data: [
      {
        id: "inpay_old",
        invoice: "in_old",
        status: "paid",
        payment: { type: "payment_intent", payment_intent: "pi_old" },
      },
    ],
    has_more: false,
  });
  fake.paymentIntents.retrieve = async () => ({
    id: "pi_old",
    customer: "cus_current",
  });
  fake.subscriptions.retrieve = async (id) => subscription({ id });
  fake.subscriptions.cancel = async () => {
    cancellations += 1;
  };
  assert.deepEqual(
    await handlers({ firestore, stripe: fake }).applyFinancialRiskEvent({
      id: "evt_old_recurring_refund",
      type: "charge.refunded",
      created: 16,
      data: { object: { id: "ch_old_recurring" } },
    }),
    { reviewRequired: true },
  );
  assert.equal(cancellations, 0);
  assert.equal(
    firestore.documents.get("billingAccounts/user").stripeSubscriptionId,
    "sub_new",
  );
  assert.equal(firestore.documents.get("entitlements/user").isPremium, true);
  assert.equal(
    firestore.documents.get("entitlements/user").currentPeriodEnd.toMillis(),
    currentPeriodEnd.toMillis(),
  );
  assert.equal(
    firestore.documents.get("stripeWebhookEvents/evt_old_recurring_refund")
      .ignoredAsNonCurrentRecurring,
    true,
  );
});

test("a recurring financial event rejects an Invoice whose parent is not subscription_details", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_current",
      stripeSubscriptionStatus: "active",
      currentInvoiceId: "in_current",
      currentPaymentIntentId: "pi_invoice",
    },
    "entitlements/user": {
      source: "stripe",
      plan: "monthly",
      status: "active",
      isPremium: true,
      currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 86400000),
    },
    "users/user": { accountType: "personal" },
  });
  let cancellations = 0;
  const fake = stripeFake();
  fake.invoices.retrieve = async () => ({
    id: "in_current",
    customer: "cus_current",
    parent: {
      type: "quote_details",
      // A nested subscription-looking id must not be accepted unless the
      // discriminated union explicitly says this is a subscription Invoice.
      subscription_details: { subscription: "sub_current" },
    },
  });
  fake.subscriptions.cancel = async () => {
    cancellations += 1;
  };
  await assert.rejects(
    handlers({ firestore, stripe: fake }).applyFinancialRiskEvent({
      id: "evt_wrong_invoice_parent",
      type: "charge.refunded",
      created: 17,
      data: { object: { id: "ch_current" } },
    }),
    /Invoice does not match its canonical subscription/,
  );
  assert.equal(cancellations, 0);
  assert.equal(firestore.documents.get("entitlements/user").isPremium, true);
  assert.equal(
    firestore.documents.has("stripeWebhookEvents/evt_wrong_invoice_parent"),
    false,
  );
});

test("refund of an older Invoice on the same subscription cannot revoke its newer paid period", async () => {
  const currentPeriodEnd = Timestamp.fromMillis(NOW_MS + 45 * 86400000);
  const firestore = new FakeFirestore({
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_current",
      stripeSubscriptionStatus: "active",
      currentInvoiceId: "in_new_period",
      currentPaymentIntentId: "pi_new_period",
    },
    "entitlements/user": {
      source: "stripe",
      plan: "monthly",
      status: "active",
      isPremium: true,
      currentPeriodEnd,
    },
    "users/user": { accountType: "creator", premiumIdentity: true },
  });
  let cancellations = 0;
  const fake = stripeFake();
  fake.charges.retrieve = async () => ({
    id: "ch_old_period",
    customer: "cus_current",
    payment_intent: "pi_old_period",
    amount: 600,
    amount_refunded: 600,
  });
  fake.invoicePayments.list = async () => ({
    data: [
      {
        id: "inpay_old_period",
        invoice: "in_old_period",
        status: "paid",
        payment: {
          type: "payment_intent",
          payment_intent: "pi_old_period",
        },
      },
    ],
    has_more: false,
  });
  fake.invoices.retrieve = async () => ({
    id: "in_old_period",
    customer: "cus_current",
    parent: {
      type: "subscription_details",
      subscription_details: { subscription: "sub_current" },
    },
  });
  fake.paymentIntents.retrieve = async () => ({
    id: "pi_old_period",
    customer: "cus_current",
  });
  fake.subscriptions.cancel = async () => {
    cancellations += 1;
  };
  assert.deepEqual(
    await handlers({ firestore, stripe: fake }).applyFinancialRiskEvent({
      id: "evt_old_period_refund",
      type: "charge.refunded",
      created: 17,
      data: { object: { id: "ch_old_period" } },
    }),
    { reviewRequired: true },
  );
  assert.equal(cancellations, 0);
  assert.equal(firestore.documents.get("entitlements/user").isPremium, true);
  assert.equal(
    firestore.documents.get("entitlements/user").currentPeriodEnd.toMillis(),
    currentPeriodEnd.toMillis(),
  );
});

test("recurring refund delivered before subscription fulfillment blocks and cancels the later grant", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
    "users/user": { accountType: "personal" },
  });
  const canceled = [];
  const fake = stripeFake();
  fake.subscriptions.cancel = async (id) => {
    canceled.push(id);
    return subscription({ id, status: "canceled" });
  };
  const service = handlers({ firestore, stripe: fake });
  assert.deepEqual(
    await service.applyFinancialRiskEvent({
      id: "evt_refund_before_subscription",
      type: "charge.refunded",
      created: 18,
      data: { object: { id: "ch_current" } },
    }),
    { reviewRequired: true },
  );
  assert.equal(
    firestore.documents.get("stripeFinancialRisks/pi_invoice").accessBlocked,
    true,
  );
  assert.deepEqual(
    await service.applySubscription("sub_current", {
      id: "evt_subscription_after_refund",
      type: "invoice.paid",
      created: 19,
    }),
    { reviewRequired: true, uid: "user" },
  );
  assert.deepEqual(canceled, ["sub_current"]);
  assert.equal(firestore.documents.has("entitlements/user"), false);
  assert.equal(
    firestore.documents.get("billingAccounts/user").billingReviewReason,
    "subscription-payment-at-financial-risk",
  );
});

test("full BLIK refund revokes only the matching current prepaid access", async () => {
  const firestore = new FakeFirestore({
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      currentPrepaidCheckoutSessionId: "cs_prepaid",
      currentPrepaidPaymentIntentId: "pi_prepaid",
      lastPrepaidCheckoutSessionId: "cs_prepaid",
      lastPrepaidPaymentIntentId: "pi_prepaid",
      prepaidAccessStatus: "active",
    },
    "stripeWebhookEvents/prepaid_cs_prepaid": {
      fulfillmentStatus: "applied",
      checkoutSessionId: "cs_prepaid",
      paymentIntentId: "pi_prepaid",
    },
    "entitlements/user": {
      source: "stripe_prepaid",
      plan: "yearly",
      status: "active",
      isPremium: true,
      currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 86400000),
    },
    "users/user": { accountType: "creator", premiumIdentity: true },
  });
  let cancelCalls = 0;
  const fake = stripeFake();
  fake.charges.retrieve = async () => ({
    id: "ch_blik",
    customer: "cus_current",
    payment_intent: "pi_prepaid",
    invoice: null,
    amount: BLIK_PLAN_CONFIGURATION.yearly.unitAmount,
    amount_refunded: BLIK_PLAN_CONFIGURATION.yearly.unitAmount,
  });
  fake.subscriptions.cancel = async () => {
    cancelCalls += 1;
  };
  const result = await handlers({ firestore, stripe: fake })
    .applyFinancialRiskEvent({
      id: "evt_blik_refund",
      type: "charge.refunded",
      created: 14,
      data: {
        object: {
          id: "ch_blik",
          customer: "cus_current",
          payment_intent: "pi_prepaid",
          amount: BLIK_PLAN_CONFIGURATION.yearly.unitAmount,
          amount_refunded: BLIK_PLAN_CONFIGURATION.yearly.unitAmount,
        },
      },
    });
  assert.deepEqual(result, { revoked: true });
  assert.equal(cancelCalls, 0);
  assert.equal(firestore.documents.get("entitlements/user").isPremium, false);
  assert.equal(
    firestore.documents.get("entitlements/user").source,
    "stripe_prepaid",
  );
  assert.equal(
    firestore.documents.get("billingAccounts/user").prepaidAccessStatus,
    "revoked",
  );
});

test("old BLIK refund cannot cancel or revoke a newer subscription", async () => {
  const currentPeriodEnd = Timestamp.fromMillis(NOW_MS + 86400000);
  const firestore = new FakeFirestore({
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_new",
      stripeSubscriptionStatus: "active",
      lastPrepaidPaymentIntentId: "pi_old_blik",
      prepaidAccessStatus: "active",
    },
    "entitlements/user": {
      source: "stripe",
      plan: "monthly",
      status: "active",
      isPremium: true,
      currentPeriodEnd,
    },
    "users/user": { premiumIdentity: true },
  });
  let cancelCalls = 0;
  const fake = stripeFake();
  fake.charges.retrieve = async () => ({
    id: "ch_old_blik",
    customer: "cus_current",
    payment_intent: "pi_old_blik",
    invoice: null,
    amount: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
    amount_refunded: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
  });
  fake.subscriptions.cancel = async () => {
    cancelCalls += 1;
  };
  const service = handlers({ firestore, stripe: fake });
  const event = {
    id: "evt_old_blik_refund",
    type: "charge.refunded",
    created: 15,
    data: {
      object: {
        id: "ch_old_blik",
        customer: "cus_current",
        payment_intent: "pi_old_blik",
        amount: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
        amount_refunded: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
      },
    },
  };
  assert.deepEqual(await service.applyFinancialRiskEvent(event), {
    reviewRequired: true,
  });
  assert.deepEqual(await service.applyFinancialRiskEvent(event), {
    ignored: true,
  });
  assert.equal(cancelCalls, 0);
  const entitlement = firestore.documents.get("entitlements/user");
  assert.equal(entitlement.isPremium, true);
  assert.equal(entitlement.source, "stripe");
  assert.equal(entitlement.currentPeriodEnd.toMillis(), currentPeriodEnd.toMillis());
  assert.equal(
    firestore.documents.get("stripeWebhookEvents/evt_old_blik_refund")
      .ignoredAsNonCurrentPrepaid,
    true,
  );
  assert.equal(
    firestore.documents.get("billingAccounts/user").billingReviewRequired,
    true,
  );
});

test("historical lastPrepaid fields are never authority to revoke current prepaid access", async () => {
  const currentPeriodEnd = Timestamp.fromMillis(NOW_MS + 20 * 86400000);
  const firestore = new FakeFirestore({
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      currentPrepaidCheckoutSessionId: "cs_current_blik",
      currentPrepaidPaymentIntentId: "pi_current_blik",
      lastPrepaidCheckoutSessionId: "cs_old_blik",
      lastPrepaidPaymentIntentId: "pi_old_blik",
      prepaidAccessStatus: "active",
    },
    "stripeWebhookEvents/prepaid_cs_current_blik": {
      fulfillmentStatus: "applied",
      checkoutSessionId: "cs_current_blik",
      paymentIntentId: "pi_current_blik",
    },
    "entitlements/user": {
      source: "stripe_prepaid",
      plan: "yearly",
      status: "active",
      isPremium: true,
      currentPeriodEnd,
    },
    "users/user": { premiumIdentity: true },
  });
  const fake = stripeFake();
  fake.charges.retrieve = async () => ({
    id: "ch_old_blik_history",
    customer: "cus_current",
    payment_intent: "pi_old_blik",
    invoice: null,
    amount: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
    amount_refunded: BLIK_PLAN_CONFIGURATION.monthly.unitAmount,
  });
  assert.deepEqual(
    await handlers({ firestore, stripe: fake }).applyFinancialRiskEvent({
      id: "evt_old_blik_history",
      type: "charge.refunded",
      created: 17,
      data: { object: { id: "ch_old_blik_history" } },
    }),
    { reviewRequired: true },
  );
  assert.equal(firestore.documents.get("entitlements/user").isPremium, true);
  assert.equal(
    firestore.documents.get("entitlements/user").currentPeriodEnd.toMillis(),
    currentPeriodEnd.toMillis(),
  );
  assert.equal(
    firestore.documents.get("billingAccounts/user").currentPrepaidPaymentIntentId,
    "pi_current_blik",
  );
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
  fake.charges.retrieve = async () => ({
    id: "ch_partial",
    customer: "cus_current",
    invoice: null,
    payment_intent: "pi_partial",
    amount: 1999,
    amount_refunded: 500,
  });
  fake.subscriptions.cancel = async () => {
    cancelCalls += 1;
  };
  await handlers({ firestore, stripe: fake }).applyFinancialRiskEvent({
    id: "evt_partial_refund",
    type: "charge.refunded",
    created: 14,
    data: {
      object: {
        id: "ch_partial",
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

test("dispute handling does not mutate access behind an Auth-deleted tombstone", async () => {
  const tombstone = {
    disabled: true,
    authDeletedAt: Timestamp.fromMillis(NOW_MS),
    premiumIdentity: false,
  };
  const firestore = new FakeFirestore({
    "billingAccounts/deleted": {
      stripeCustomerId: "cus_current",
      stripeSubscriptionId: "sub_current",
      stripeSubscriptionStatus: "active",
      accountDeletionTombstone: true,
      accountDeletedAt: Timestamp.fromMillis(NOW_MS),
    },
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
  assert.equal(firestore.documents.get("entitlements/deleted").isPremium, true);
  assert.equal(
    firestore.documents.get("stripeWebhookEvents/evt_dispute")
      .ignoredAsNonCurrentRecurring,
    true,
  );
});

test("recurring Checkout allows only card and PayPal with server prices", async () => {
  let payload;
  const firestore = new FakeFirestore({
    "users/user": { banned: false },
    "billingAccounts/user": { stripeCustomerId: "cus_current" },
  });
  const fake = stripeFake();
  fake.checkout.sessions.create = async (value) => {
    payload = value;
    return {
      id: "cs_current",
      status: "open",
      url: "https://checkout.stripe.com/c/pay/session",
    };
  };
  await handlers({ firestore, stripe: fake }).createPremiumCheckoutSessionHandler({
    auth: { uid: "user", token: { email_verified: true } },
    data: { plan: "yearly" },
  });
  assert.deepEqual(payload.line_items, [{ price: "price_yearly", quantity: 1 }]);
  assert.deepEqual(payload.adaptive_pricing, { enabled: true });
  assert.deepEqual(payload.automatic_tax, { enabled: true });
  assert.deepEqual(payload.payment_method_types, ["card", "paypal"]);
  assert.equal(payload.mode, "subscription");
  assert.equal("currency" in payload, false);
  assert.equal("tax_id_collection" in payload, false);
});

test("BLIK Checkout is a non-renewing server-priced monthly or yearly pass", async () => {
  for (const [plan, expectedPrice] of [
    ["monthly", "price_blik_monthly"],
    ["yearly", "price_blik_yearly"],
  ]) {
    let payload;
    const firestore = new FakeFirestore({
      "users/user": { banned: false },
      "billingAccounts/user": { stripeCustomerId: "cus_current" },
    });
    const fake = stripeFake();
    fake.checkout.sessions.create = async (value) => {
      payload = value;
      return {
        id: `cs_${plan}`,
        status: "open",
        url: "https://checkout.stripe.com/c/pay/blik",
      };
    };
    await handlers({ firestore, stripe: fake }).createPremiumCheckoutSessionHandler({
      auth: { uid: "user", token: { email_verified: true } },
      data: { plan, paymentMethod: "blik" },
    });
    assert.equal(payload.mode, "payment");
    assert.deepEqual(payload.payment_method_types, ["blik"]);
    assert.deepEqual(payload.line_items, [{ price: expectedPrice, quantity: 1 }]);
    assert.equal("subscription_data" in payload, false);
    assert.equal("adaptive_pricing" in payload, false);
    assert.deepEqual(payload.automatic_tax, { enabled: true });
  }
});

test("Checkout scans every subscription page before reusing a pending URL", async () => {
  const firestore = new FakeFirestore({
    "users/user": { banned: false },
    "billingAccounts/user": {
      stripeCustomerId: "cus_current",
      pendingCheckoutSessionId: "cs_pending",
      pendingCheckoutPlan: "monthly",
      pendingCheckoutPaymentMethod: "recurring",
    },
  });
  const listCalls = [];
  let pendingRetrievals = 0;
  let sessionCreates = 0;
  const fake = stripeFake();
  fake.subscriptions.list = async (request) => {
    listCalls.push(request);
    if (!request.starting_after) {
      return {
        data: [subscription({ id: "sub_terminal_page", status: "canceled" })],
        has_more: true,
      };
    }
    return {
      data: [subscription({ id: "sub_active_page", status: "active" })],
      has_more: false,
    };
  };
  fake.checkout.sessions.retrieve = async () => {
    pendingRetrievals += 1;
    return { status: "open", url: "https://checkout.stripe.com/c/pay/pending" };
  };
  fake.checkout.sessions.create = async () => {
    sessionCreates += 1;
    return {
      id: "cs_new",
      status: "open",
      url: "https://checkout.stripe.com/c/pay/new",
    };
  };
  await assert.rejects(
    handlers({ firestore, stripe: fake }).createPremiumCheckoutSessionHandler({
      auth: { uid: "user", token: { email_verified: true } },
      data: { plan: "monthly" },
    }),
    /subscription already exists/,
  );
  assert.equal(listCalls.length, 2);
  assert.equal(listCalls[0].limit, 100);
  assert.equal(listCalls[0].status, "all");
  assert.equal(listCalls[1].starting_after, "sub_terminal_page");
  assert.equal(pendingRetrievals, 0);
  assert.equal(sessionCreates, 0);
});

test("checkout retry rotates idempotency after deliberately expiring an unpersisted Session", async () => {
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
    return {
      id: "cs_new",
      status: "open",
      url: "https://checkout.stripe.com/c/pay/new",
    };
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
  assert.equal(recovered.url, "https://checkout.stripe.com/c/pay/new");
  assert.equal(keys.length, 2);
  assert.notEqual(keys[0], keys[1]);
});
