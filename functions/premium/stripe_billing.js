const Stripe = require("stripe");
const { randomUUID } = require("node:crypto");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { defineSecret, defineString } = require("firebase-functions/params");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions/v2");
const functionsV1 = require("firebase-functions/v1");

const { db } = require("../utils/firestore");
const {
  buildEntitlements,
  applyEntitlementsInTransaction,
} = require("./entitlements");

const REGION = "europe-west1";
const BILLING_RETURN_URL = "https://yovoice.app/premium";
const CHECKOUT_SUCCESS_URL =
  "https://yovoice.app/premium?checkout=success&session_id={CHECKOUT_SESSION_ID}";
const CHECKOUT_CANCEL_URL = "https://yovoice.app/premium?checkout=cancelled";

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");
const STRIPE_MONTHLY_PRICE_ID = defineString("STRIPE_MONTHLY_PRICE_ID");
const STRIPE_YEARLY_PRICE_ID = defineString("STRIPE_YEARLY_PRICE_ID");
const STRIPE_PORTAL_CONFIGURATION_ID = defineString(
  "STRIPE_PORTAL_CONFIGURATION_ID",
  { default: "" },
);
const STRIPE_EXPECTED_MODE = defineString("STRIPE_EXPECTED_MODE");

const PLAN_CONFIGURATION = Object.freeze({
  monthly: Object.freeze({ interval: "month", plnAmount: 1999 }),
  yearly: Object.freeze({ interval: "year", plnAmount: 19999 }),
});
const ACTIVE_SUBSCRIPTION_STATUSES = new Set(["active", "trialing"]);
const GRACE_SUBSCRIPTION_STATUSES = new Set(["past_due"]);
const ZERO_DECIMAL_CURRENCIES = new Set([
  "bif",
  "clp",
  "djf",
  "gnf",
  "jpy",
  "kmf",
  "krw",
  "mga",
  "pyg",
  "rwf",
  "ugx",
  "vnd",
  "vuv",
  "xaf",
  "xof",
  "xpf",
]);

function exactKeys(value, allowed) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.keys(value).every((key) => allowed.includes(key))
  );
}

function normalizeCountryCode(value) {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string" || !/^[A-Za-z]{2}$/.test(value)) {
    throw new HttpsError(
      "invalid-argument",
      "countryCode must be a two-letter ISO country code.",
    );
  }
  return value.toUpperCase();
}

function parseBillingContextRequest(data) {
  const input = data ?? {};
  if (!exactKeys(input, ["countryCode"])) {
    throw new HttpsError("invalid-argument", "Unexpected billing context fields.");
  }
  return { countryCode: normalizeCountryCode(input.countryCode) };
}

function parseCheckoutRequest(data) {
  const input = data ?? {};
  if (!exactKeys(input, ["plan"]) || !(input.plan in PLAN_CONFIGURATION)) {
    throw new HttpsError(
      "invalid-argument",
      "plan must be monthly or yearly.",
    );
  }
  return { plan: input.plan };
}

function parsePortalRequest(data) {
  const input = data ?? {};
  if (!exactKeys(input, []) || Object.keys(input).length !== 0) {
    throw new HttpsError("invalid-argument", "This request takes no fields.");
  }
}

function formatMinorAmount(amount, currency, countryCode) {
  const divisor = ZERO_DECIMAL_CURRENCIES.has(currency) ? 1 : 100;
  const locale = countryCode ? `und-${countryCode}` : "en";
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency: currency.toUpperCase(),
  }).format(amount / divisor);
}

function validateConfiguredPrice(price, plan, expectedLiveMode) {
  const configuration = PLAN_CONFIGURATION[plan];
  if (
    !price ||
    price.object !== "price" ||
    price.active !== true ||
    price.type !== "recurring" ||
    price.recurring?.interval !== configuration.interval ||
    price.recurring?.interval_count !== 1 ||
    price.livemode !== expectedLiveMode
  ) {
    throw new Error(`Stripe ${plan} Price is not an active one-${configuration.interval} recurring Price.`);
  }
  if (
    price.currency !== "pln" ||
    price.unit_amount !== configuration.plnAmount ||
    price.tax_behavior !== "inclusive"
  ) {
    throw new Error(
      `Stripe ${plan} Price must be PLN ${configuration.plnAmount} with inclusive tax.`,
    );
  }
  if (Object.keys(price.currency_options ?? {}).length > 0) {
    throw new Error(
      `Stripe ${plan} Price has manual currency options; YO Voice uses Adaptive Pricing instead.`,
    );
  }
}

function buildPlanCatalog(countryCode) {
  const monthlyAmount = PLAN_CONFIGURATION.monthly.plnAmount;
  const plans = ["monthly", "yearly"].map((id) => {
    const amount = PLAN_CONFIGURATION[id].plnAmount;
    const yearly = id === "yearly";
    const equivalentAmount = yearly ? Math.round(amount / 12) : null;
    const savingsPercent = yearly
      ? Math.max(0, Math.round((1 - amount / (monthlyAmount * 12)) * 100))
      : 0;
    return {
      id,
      interval: PLAN_CONFIGURATION[id].interval,
      currency: "PLN",
      unitAmount: amount,
      formattedPrice: formatMinorAmount(amount, "pln", countryCode),
      formattedEquivalent: yearly
        ? formatMinorAmount(equivalentAmount, "pln", countryCode)
        : null,
      savingsPercent,
    };
  });

  return {
    countryCode,
    currency: "PLN",
    priceDisplaySource: "base",
    localizedAtCheckout: true,
    taxDisplay: "included",
    taxNotice:
      "The PLN base price includes applicable tax. Stripe shows the final local currency and tax before payment.",
    plans,
  };
}

function billingManager(source) {
  if (source === "stripe") return "stripe";
  if (["apple", "appStore", "ios"].includes(source)) return "apple";
  if (["google", "googlePlay", "play"].includes(source)) return "google";
  if (source === "admin") return "admin";
  return "none";
}

function entitlementIsActiveAt(entitlements, nowMs) {
  const periodEndMs = entitlements.currentPeriodEnd?.toMillis?.();
  return (
    ["active", "trialing", "grace"].includes(entitlements.status) &&
    Number.isFinite(periodEndMs) &&
    periodEndMs > nowMs
  );
}

function buildBillingContext(countryCode, state, nowMs) {
  const manager = billingManager(state.entitlements.source);
  const active = entitlementIsActiveAt(state.entitlements, nowMs);
  return {
    ...buildPlanCatalog(countryCode),
    billingManagedBy: manager,
    checkoutAvailable: !active,
    portalAvailable:
      manager === "stripe" &&
      typeof state.billing.stripeCustomerId === "string" &&
      state.billing.stripeCustomerId.startsWith("cus_"),
    currentPlan:
      active &&
      (state.entitlements.plan === "monthly" ||
        state.entitlements.plan === "yearly")
        ? state.entitlements.plan
        : "none",
    renewalBehavior:
      active &&
      (state.entitlements.renewalBehavior === "renews" ||
        state.entitlements.renewalBehavior === "ends")
        ? state.entitlements.renewalBehavior
        : "none",
    currentPeriodEndMs:
      active && Number.isFinite(state.entitlements.currentPeriodEnd?.toMillis?.())
        ? state.entitlements.currentPeriodEnd.toMillis()
        : null,
  };
}

async function readAccountState(firestore, uid) {
  if (!uid) return { entitlements: {}, billing: {} };
  const [entitlementSnapshot, billingSnapshot] = await Promise.all([
    firestore.collection("entitlements").doc(uid).get(),
    firestore.collection("billingAccounts").doc(uid).get(),
  ]);
  return {
    entitlements: entitlementSnapshot.data() ?? {},
    billing: billingSnapshot.data() ?? {},
  };
}

async function getPremiumBillingContextWithoutStripe(
  request,
  firestore = db,
  nowMs = Timestamp.now().toMillis(),
) {
  const { countryCode } = parseBillingContextRequest(request.data);
  const state = await readAccountState(firestore, request.auth?.uid);
  return buildBillingContext(countryCode, state, nowMs);
}

async function listStripeSubscriptionsForCustomer(stripe, customerId) {
  const subscriptions = [];
  let startingAfter;
  do {
    const result = await stripe.subscriptions.list({
      customer: customerId,
      status: "all",
      limit: 100,
      ...(startingAfter ? { starting_after: startingAfter } : {}),
    });
    subscriptions.push(...result.data);
    startingAfter = result.has_more
      ? result.data[result.data.length - 1]?.id
      : undefined;
    if (result.has_more && !startingAfter) {
      throw new Error("Stripe subscription pagination made no progress.");
    }
  } while (startingAfter);
  return subscriptions;
}

async function cancelStripeSubscriptionsForCustomer(
  stripe,
  customerId,
  idempotencyScope,
) {
  const subscriptions = await listStripeSubscriptionsForCustomer(
    stripe,
    customerId,
  );
  let canceledCount = 0;
  for (const subscription of subscriptions) {
    const canonicalCustomerId =
      typeof subscription.customer === "string"
        ? subscription.customer
        : subscription.customer?.id;
    if (canonicalCustomerId !== customerId) {
      throw new Error("Stripe returned a subscription for another customer.");
    }
    if (!["canceled", "incomplete_expired"].includes(subscription.status)) {
      await stripe.subscriptions.cancel(
        subscription.id,
        {},
        {
          idempotencyKey: `yovoice_cancel_${idempotencyScope}_${subscription.id}`,
        },
      );
      canceledCount += 1;
    }
  }
  return canceledCount;
}

async function cancelStripeBillingForDeletedUser(
  uid,
  { firestore, stripe, now = () => Timestamp.now() },
) {
  const billingRef = firestore.collection("billingAccounts").doc(uid);
  const snapshot = await billingRef.get();
  const billing = snapshot.data() ?? {};
  const customerId = billing.stripeCustomerId;
  if (
    !snapshot.exists ||
    typeof customerId !== "string" ||
    !customerId.startsWith("cus_")
  ) {
    return { outcome: "no-stripe-subscription" };
  }

  const pendingSessionId = billing.pendingCheckoutSessionId;
  if (typeof pendingSessionId === "string" && pendingSessionId.startsWith("cs_")) {
    const pending = await stripe.checkout.sessions.retrieve(pendingSessionId);
    if (pending.status === "open") {
      await stripe.checkout.sessions.expire(pendingSessionId);
    }
  }

  const canceledCount = await cancelStripeSubscriptionsForCustomer(
    stripe,
    customerId,
    `auth_delete_${uid}`,
  );
  await billingRef.set(
    {
      accountDeletedAt: now(),
      accountDeletionCancellationStatus:
        canceledCount > 0 ? "canceled" : "no-active-subscription",
      pendingCheckoutSessionId: null,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  // Keep the private customer/subscription binding: late cancellation,
  // dispute, refund and replay webhooks still need canonical ownership.
  return {
    outcome: canceledCount > 0 ? "canceled" : "no-active-subscription",
  };
}

function mapStripeSubscription(
  subscription,
  priceIds,
  { previousEntitlement = {}, nowMs = Date.now() } = {},
) {
  const priceId = subscription.items?.data?.[0]?.price?.id;
  const plan =
    priceId === priceIds.monthly
      ? "monthly"
      : priceId === priceIds.yearly
        ? "yearly"
        : null;
  if (!plan || subscription.items?.data?.length !== 1) {
    throw new Error("Stripe subscription does not contain one configured Premium Price.");
  }

  const periodEndSeconds =
    subscription.current_period_end ??
    subscription.items?.data?.[0]?.current_period_end;
  if (!Number.isSafeInteger(periodEndSeconds) || periodEndSeconds <= 0) {
    throw new Error("Stripe subscription is missing its current period end.");
  }

  const latestInvoice = subscription.latest_invoice;
  const paymentSettled =
    latestInvoice &&
    typeof latestInvoice === "object" &&
    (latestInvoice.paid === true || latestInvoice.status === "paid");
  const previousPeriodEndMs = previousEntitlement.currentPeriodEnd?.toMillis?.();
  const previouslyPaidAndActive =
    previousEntitlement.source === "stripe" &&
    previousEntitlement.isPremium === true &&
    Number.isFinite(previousPeriodEndMs) &&
    previousPeriodEndMs > nowMs;

  let status = "expired";
  let effectivePeriodEndSeconds = periodEndSeconds;
  if (ACTIVE_SUBSCRIPTION_STATUSES.has(subscription.status) && paymentSettled) {
    status = subscription.status;
  } else if (
    (ACTIVE_SUBSCRIPTION_STATUSES.has(subscription.status) ||
      GRACE_SUBSCRIPTION_STATUSES.has(subscription.status)) &&
    previouslyPaidAndActive
  ) {
    status = "grace";
    // Never advance access into an unpaid renewal period. Keep only the
    // already-paid entitlement window while Stripe settles the new invoice.
    effectivePeriodEndSeconds = Math.floor(previousPeriodEndMs / 1000);
  }

  return {
    plan,
    status,
    currentPeriodEnd: Timestamp.fromMillis(effectivePeriodEndSeconds * 1000),
    priceId,
    cancelAtPeriodEnd: subscription.cancel_at_period_end === true,
    paymentSettled,
  };
}

function createStripeClient(
  secretKey,
  expectedMode,
  {
    projectId =
      process.env.GCLOUD_PROJECT ??
      process.env.GOOGLE_CLOUD_PROJECT ??
      process.env.FIREBASE_CONFIG_PROJECT_ID,
    functionsEmulator = process.env.FUNCTIONS_EMULATOR === "true",
  } = {},
) {
  if (
    projectId === "yovoice-ec54a" &&
    !functionsEmulator &&
    expectedMode !== "live"
  ) {
    throw new HttpsError(
      "failed-precondition",
      "The production Firebase project requires live Stripe mode.",
      { reason: "billing-not-configured" },
    );
  }
  if (!["live", "test"].includes(expectedMode)) {
    throw new HttpsError(
      "failed-precondition",
      "Premium billing mode is not configured.",
      { reason: "billing-not-configured" },
    );
  }
  const expectedPrefix = expectedMode === "live" ? "sk_live_" : "sk_test_";
  if (typeof secretKey !== "string" || !secretKey.startsWith(expectedPrefix)) {
    throw new HttpsError(
      "failed-precondition",
      "Premium billing is not configured.",
      { reason: "billing-not-configured" },
    );
  }
  return new Stripe(secretKey, {
    maxNetworkRetries: 2,
    timeout: 20_000,
    appInfo: { name: "YO Voice Firebase Functions" },
  });
}

async function requireActiveBillingUser(request, firestore) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  if (request.auth.token?.email_verified !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Verify your email before managing Premium.",
      { reason: "email-verification-required" },
    );
  }
  const profileSnapshot = await firestore.collection("users").doc(request.auth.uid).get();
  const profile = profileSnapshot.data() ?? {};
  if (
    !profileSnapshot.exists ||
    profile.banned === true ||
    profile.disabled === true ||
    profile.deleted === true ||
    profile.status === "deleted"
  ) {
    throw new HttpsError("permission-denied", "This account cannot manage Premium.");
  }
  return { uid: request.auth.uid };
}

function requireAuthenticatedBillingOwner(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  // Billing ownership follows the signed Firebase uid and its server-only
  // customer mapping. A suspension may remove product access, but must never
  // prevent the payer from cancelling future charges.
  return { uid: request.auth.uid };
}

async function consumeBillingRateLimit(
  firestore,
  uid,
  action,
  { now = Timestamp.now(), limit = 8, windowSeconds = 60 } = {},
) {
  const reference = firestore.collection("billingRateLimits").doc(`${uid}_${action}`);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const value = snapshot.data() ?? {};
    const startMs = value.windowStartedAt?.toMillis?.();
    const insideWindow =
      Number.isFinite(startMs) && now.toMillis() - startMs < windowSeconds * 1000;
    const count = insideWindow && Number.isSafeInteger(value.count) ? value.count : 0;
    if (insideWindow && count >= limit) {
      throw new HttpsError("resource-exhausted", "Try again in a moment.");
    }
    transaction.set(reference, {
      windowStartedAt: insideWindow ? value.windowStartedAt : now,
      count: count + 1,
      updatedAt: now,
    });
  });
}

async function acquireCheckoutLease(
  firestore,
  uid,
  { now = Timestamp.now(), leaseSeconds = 45 } = {},
) {
  const reference = firestore.collection("billingCheckoutLocks").doc(uid);
  const token = randomUUID();
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const leaseUntilMs = snapshot.data()?.leaseUntil?.toMillis?.();
    if (Number.isFinite(leaseUntilMs) && leaseUntilMs > now.toMillis()) {
      throw new HttpsError(
        "aborted",
        "A checkout is already being prepared. Try again in a moment.",
        { reason: "checkout-in-progress" },
      );
    }
    transaction.set(reference, {
      token,
      leaseUntil: Timestamp.fromMillis(now.toMillis() + leaseSeconds * 1000),
      updatedAt: now,
    });
  });
  return { reference, token };
}

async function releaseCheckoutLease(firestore, lease) {
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(lease.reference);
    if (snapshot.data()?.token === lease.token) transaction.delete(lease.reference);
  });
}

function makeStripeBillingHandlers({
  firestore,
  stripe,
  priceIds,
  portalConfigurationId = "",
  expectedLiveMode,
  now = () => Timestamp.now(),
}) {
  let priceCache = null;
  let portalConfigurationCache = null;

  async function loadPrices() {
    const nowMs = now().toMillis();
    if (priceCache && priceCache.expiresAtMs > nowMs) return priceCache.value;
    if (priceCache?.promise) return priceCache.promise;
    const promise = Promise.all([
      stripe.prices.retrieve(priceIds.monthly, { expand: ["currency_options"] }),
      stripe.prices.retrieve(priceIds.yearly, { expand: ["currency_options"] }),
    ]).then(([monthly, yearly]) => {
      validateConfiguredPrice(monthly, "monthly", expectedLiveMode);
      validateConfiguredPrice(yearly, "yearly", expectedLiveMode);
      const monthlyProduct =
        typeof monthly.product === "string" ? monthly.product : monthly.product?.id;
      const yearlyProduct =
        typeof yearly.product === "string" ? yearly.product : yearly.product?.id;
      if (!monthlyProduct || monthlyProduct !== yearlyProduct) {
        throw new Error("Stripe Premium Prices must belong to the same Product.");
      }
      const value = { monthly, yearly };
      priceCache = { value, expiresAtMs: nowMs + 5 * 60 * 1000 };
      return value;
    });
    priceCache = { promise, expiresAtMs: 0 };
    try {
      return await promise;
    } catch (error) {
      priceCache = null;
      throw error;
    }
  }

  async function loadPortalConfiguration() {
    if (
      typeof portalConfigurationId !== "string" ||
      !portalConfigurationId.startsWith("bpc_")
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Premium subscription management is not configured.",
        { reason: "billing-not-configured" },
      );
    }
    const nowMs = now().toMillis();
    if (
      portalConfigurationCache?.value &&
      portalConfigurationCache.expiresAtMs > nowMs
    ) {
      return portalConfigurationCache.value;
    }
    if (portalConfigurationCache?.promise) {
      return portalConfigurationCache.promise;
    }
    const promise = Promise.all([
      loadPrices(),
      stripe.billingPortal.configurations.retrieve(portalConfigurationId),
    ]).then(([prices, configuration]) => {
      const cancelEnabled =
        configuration.active === true &&
        configuration.features?.subscription_cancel?.enabled === true;
      const update = configuration.features?.subscription_update;
      const priceUpdateEnabled =
        update?.enabled === true &&
        update.default_allowed_updates?.includes("price");
      const expectedProduct =
        typeof prices.monthly.product === "string"
          ? prices.monthly.product
          : prices.monthly.product?.id;
      const matchingProduct = update?.products?.find(
        (entry) =>
          (typeof entry.product === "string"
            ? entry.product
            : entry.product?.id) === expectedProduct,
      );
      const allowedPrices = new Set(
        (matchingProduct?.prices ?? []).map((entry) =>
          typeof entry === "string" ? entry : entry?.id,
        ),
      );
      if (
        !cancelEnabled ||
        !priceUpdateEnabled ||
        !allowedPrices.has(prices.monthly.id) ||
        !allowedPrices.has(prices.yearly.id)
      ) {
        throw new Error(
          "Stripe Portal must allow cancellation and switching between both configured Premium Prices.",
        );
      }
      portalConfigurationCache = {
        value: configuration,
        expiresAtMs: nowMs + 5 * 60 * 1000,
      };
      return configuration;
    });
    portalConfigurationCache = { promise, expiresAtMs: 0 };
    try {
      return await promise;
    } catch (error) {
      portalConfigurationCache = null;
      throw error;
    }
  }

  async function accountState(uid) {
    return readAccountState(firestore, uid);
  }

  function entitlementIsActive(entitlements) {
    return entitlementIsActiveAt(entitlements, now().toMillis());
  }

  async function getPremiumBillingContextHandler(request) {
    return getPremiumBillingContextWithoutStripe(
      request,
      firestore,
      now().toMillis(),
    );
  }

  async function createPremiumCheckoutSessionHandler(request) {
    const { plan } = parseCheckoutRequest(request.data);
    const user = await requireActiveBillingUser(request, firestore);
    await consumeBillingRateLimit(firestore, user.uid, "checkout", { now: now() });
    const prices = await loadPrices();
    const lease = await acquireCheckoutLease(firestore, user.uid, { now: now() });
    try {
      const state = await accountState(user.uid);
      const manager = billingManager(state.entitlements.source);
      if (entitlementIsActive(state.entitlements)) {
        throw new HttpsError(
          "failed-precondition",
          manager === "stripe"
            ? "Manage your existing subscription instead."
            : "This subscription is managed by another provider.",
          { reason: "billing-managed-elsewhere", billingManagedBy: manager },
        );
      }

      let customerId = state.billing.stripeCustomerId;
      if (typeof customerId !== "string" || !customerId.startsWith("cus_")) {
        const customer = await stripe.customers.create(
          { metadata: { firebaseUid: user.uid } },
          { idempotencyKey: `yovoice_customer_${user.uid}_v1` },
        );
        customerId = customer.id;
        await firestore.collection("billingAccounts").doc(user.uid).set(
          {
            stripeCustomerId: customerId,
            provider: "stripe",
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      const pendingSessionId = state.billing.pendingCheckoutSessionId;
      if (
        typeof pendingSessionId === "string" &&
        pendingSessionId.startsWith("cs_")
      ) {
        const pending = await stripe.checkout.sessions.retrieve(pendingSessionId);
        if (
          state.billing.pendingCheckoutPlan === plan &&
          pending.status === "open" &&
          typeof pending.url === "string" &&
          pending.url.startsWith("https://")
        ) {
          return { url: pending.url };
        }
        if (pending.status === "open") {
          await stripe.checkout.sessions.expire(pendingSessionId);
        }
      }

      // A stale/missing entitlement must never allow a second paid
      // subscription. Stripe is authoritative for its own customer here.
      const subscriptions = await stripe.subscriptions.list({
        customer: customerId,
        status: "all",
        limit: 10,
      });
      const existing = subscriptions.data.find(
        (subscription) =>
          !["canceled", "incomplete_expired"].includes(subscription.status),
      );
      if (existing) {
        throw new HttpsError(
          "failed-precondition",
          "A Stripe subscription already exists. Manage it instead.",
          { reason: "stripe-subscription-exists", billingManagedBy: "stripe" },
        );
      }

      const savedAttemptToken = state.billing.pendingCheckoutAttemptToken;
      const attemptToken =
        !pendingSessionId &&
        state.billing.pendingCheckoutPlan === plan &&
        typeof savedAttemptToken === "string" &&
        /^[0-9a-f-]{36}$/.test(savedAttemptToken)
          ? savedAttemptToken
          : lease.token;
      await firestore.collection("billingAccounts").doc(user.uid).set(
        {
          pendingCheckoutAttemptToken: attemptToken,
          // Clear a stale provider id before the external create. If this
          // invocation crashes after Stripe succeeds, the retry reuses the
          // persisted attempt token and therefore Stripe's idempotency key.
          pendingCheckoutSessionId: null,
          pendingCheckoutPlan: plan,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      const session = await stripe.checkout.sessions.create(
        {
          mode: "subscription",
          customer: customerId,
          payment_method_types: ["card"],
          client_reference_id: user.uid,
          line_items: [{ price: prices[plan].id, quantity: 1 }],
          adaptive_pricing: { enabled: true },
          automatic_tax: { enabled: true },
          billing_address_collection: "required",
          customer_update: { address: "auto", name: "auto" },
          success_url: CHECKOUT_SUCCESS_URL,
          cancel_url: CHECKOUT_CANCEL_URL,
          metadata: { firebaseUid: user.uid, plan },
          subscription_data: { metadata: { firebaseUid: user.uid, plan } },
        },
        { idempotencyKey: `yovoice_checkout_${user.uid}_${attemptToken}` },
      );
      if (typeof session.url !== "string" || !session.url.startsWith("https://")) {
        throw new Error("Stripe Checkout did not return a hosted URL.");
      }
      await firestore.collection("billingAccounts").doc(user.uid).set(
        {
          pendingCheckoutSessionId: session.id,
          pendingCheckoutPlan: plan,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return { url: session.url };
    } finally {
      try {
        await releaseCheckoutLease(firestore, lease);
      } catch (error) {
        // The lease expires automatically. Never hide a valid Checkout URL
        // (or the original Stripe error) behind cleanup-only Firestore noise.
        logger.warn("Stripe checkout lease cleanup failed", {
          uid: user.uid,
          message: error.message,
        });
      }
    }
  }

  async function createPremiumPortalSessionHandler(request) {
    parsePortalRequest(request.data);
    const user = requireAuthenticatedBillingOwner(request);
    await consumeBillingRateLimit(firestore, user.uid, "portal", { now: now() });
    const state = await accountState(user.uid);
    const manager = billingManager(state.entitlements.source);
    if (manager !== "stripe") {
      throw new HttpsError(
        "failed-precondition",
        "This subscription is managed by another provider.",
        { reason: "billing-managed-elsewhere", billingManagedBy: manager },
      );
    }
    const customerId = state.billing.stripeCustomerId;
    if (typeof customerId !== "string" || !customerId.startsWith("cus_")) {
      throw new HttpsError(
        "failed-precondition",
        "No Stripe billing account was found.",
        { reason: "stripe-customer-missing" },
      );
    }
    await loadPortalConfiguration();
    const session = await stripe.billingPortal.sessions.create({
      customer: customerId,
      return_url: BILLING_RETURN_URL,
      configuration: portalConfigurationId,
    });
    if (typeof session.url !== "string" || !session.url.startsWith("https://")) {
      throw new Error("Stripe Billing Portal did not return a hosted URL.");
    }
    return { url: session.url };
  }

  async function canonicalBillingBinding(customerId) {
    if (typeof customerId !== "string" || !customerId.startsWith("cus_")) {
      throw new Error("Stripe event is missing its customer.");
    }
    const bindings = await firestore
      .collection("billingAccounts")
      .where("stripeCustomerId", "==", customerId)
      .limit(2)
      .get();
    if (bindings.size !== 1) {
      throw new Error(
        "Stripe customer has no unique canonical Firebase billing binding.",
      );
    }
    return { uid: bindings.docs[0].id, billingRef: bindings.docs[0].ref };
  }

  async function chargeForFinancialEvent(event) {
    if (event.type === "charge.refunded") return event.data.object;
    const dispute = event.data.object;
    const chargeId =
      typeof dispute.charge === "string" ? dispute.charge : dispute.charge?.id;
    if (typeof chargeId !== "string" || !chargeId.startsWith("ch_")) {
      throw new Error("Stripe dispute is missing its charge.");
    }
    return stripe.charges.retrieve(chargeId);
  }

  async function applyFinancialRiskEvent(event) {
    const charge = await chargeForFinancialEvent(event);
    let customerId =
      typeof charge.customer === "string" ? charge.customer : charge.customer?.id;
    if ((!customerId || !customerId.startsWith("cus_")) && charge.invoice) {
      const invoiceId =
        typeof charge.invoice === "string" ? charge.invoice : charge.invoice?.id;
      const invoice = await stripe.invoices.retrieve(invoiceId);
      customerId =
        typeof invoice.customer === "string"
          ? invoice.customer
          : invoice.customer?.id;
    }
    const { uid, billingRef } = await canonicalBillingBinding(customerId);
    const eventRef = firestore.collection("stripeWebhookEvents").doc(event.id);
    const isPartialRefund =
      event.type === "charge.refunded" &&
      Number.isSafeInteger(charge.amount) &&
      Number.isSafeInteger(charge.amount_refunded) &&
      charge.amount_refunded < charge.amount;

    if (isPartialRefund) {
      await firestore.runTransaction(async (transaction) => {
        const eventSnapshot = await transaction.get(eventRef);
        if (eventSnapshot.exists) return;
        transaction.set(
          billingRef,
          {
            billingReviewRequired: true,
            billingReviewReason: "partial-refund",
            billingReviewEventId: event.id,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        transaction.create(eventRef, {
          type: event.type,
          created: event.created,
          supportReviewRequired: true,
          processedAt: FieldValue.serverTimestamp(),
        });
      });
      return { reviewRequired: true };
    }

    if (
      event.type === "charge.refunded" &&
      (!Number.isSafeInteger(charge.amount) ||
        !Number.isSafeInteger(charge.amount_refunded) ||
        charge.amount_refunded < charge.amount)
    ) {
      throw new Error("Stripe refund amounts are invalid.");
    }

    await cancelStripeSubscriptionsForCustomer(stripe, customerId, event.id);
    await firestore.runTransaction(async (transaction) => {
      const userRef = firestore.collection("users").doc(uid);
      const entitlementRef = firestore.collection("entitlements").doc(uid);
      const [eventSnapshot, billingSnapshot, userSnapshot, entitlementSnapshot] =
        await Promise.all([
          transaction.get(eventRef),
          transaction.get(billingRef),
          transaction.get(userRef),
          transaction.get(entitlementRef),
        ]);
      if (eventSnapshot.exists) return;
      if (billingSnapshot.data()?.stripeCustomerId !== customerId) {
        throw new Error("Financial event customer binding changed.");
      }
      const prior = entitlementSnapshot.data() ?? {};
      const entitlementData = buildEntitlements({
        plan: ["monthly", "yearly"].includes(prior.plan) ? prior.plan : "none",
        status: "expired",
        currentPeriodEnd: now(),
        source: "stripe",
      });
      transaction.set(
        billingRef,
        {
          financialAccessStatus: "revoked",
          financialAccessReason:
            event.type === "charge.refunded" ? "full-refund" : "dispute",
          lastFinancialEventId: event.id,
          renewalBehavior: "none",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      const user = userSnapshot.data() ?? {};
      applyEntitlementsInTransaction(transaction, uid, entitlementData, {
        user,
        firestore,
        writeUserProjection:
          userSnapshot.exists &&
          user.banned !== true &&
          user.disabled !== true &&
          user.deleted !== true &&
          user.status !== "deleted" &&
          !user.authDeletedAt,
      });
      transaction.create(eventRef, {
        type: event.type,
        created: event.created,
        accessRevoked: true,
        processedAt: FieldValue.serverTimestamp(),
      });
    });
    return { revoked: true };
  }

  async function applySubscription(subscriptionId, event) {
    if (typeof subscriptionId !== "string" || !subscriptionId.startsWith("sub_")) {
      throw new Error("Stripe webhook has no valid subscription id.");
    }
    // The webhook must enforce the same commercial configuration as Checkout;
    // matching an id alone is not pricing authority.
    await loadPrices();
    const initialSubscription = await stripe.subscriptions.retrieve(subscriptionId);
    const customerId =
      typeof initialSubscription.customer === "string"
        ? initialSubscription.customer
        : initialSubscription.customer?.id;
    if (typeof customerId !== "string" || !customerId.startsWith("cus_")) {
      throw new Error("Stripe subscription is missing its customer.");
    }
    const { uid, billingRef } = await canonicalBillingBinding(customerId);
    const eventRef = firestore.collection("stripeWebhookEvents").doc(event.id);
    let alreadyProcessed = false;
    let ignoredAsSuperseded = false;
    await firestore.runTransaction(async (transaction) => {
      // Refresh on every Firestore transaction retry. This closes the race in
      // which an older active event pauses here, a cancellation commits, and
      // the older handler resumes with a stale object and resurrects access.
      const subscription = await stripe.subscriptions.retrieve(subscriptionId, {
        expand: ["latest_invoice"],
      });
      const currentCustomerId =
        typeof subscription.customer === "string"
          ? subscription.customer
          : subscription.customer?.id;
      if (currentCustomerId !== customerId) {
        throw new Error("Stripe subscription customer changed during processing.");
      }
      const userRef = firestore.collection("users").doc(uid);
      const entitlementRef = firestore.collection("entitlements").doc(uid);
      const [
        eventSnapshot,
        billingSnapshot,
        userSnapshot,
        entitlementSnapshot,
      ] = await Promise.all([
        transaction.get(eventRef),
        transaction.get(billingRef),
        transaction.get(userRef),
        transaction.get(entitlementRef),
      ]);
      if (eventSnapshot.exists) {
        alreadyProcessed = true;
        return;
      }
      const billing = billingSnapshot.data() ?? {};
      if (!billingSnapshot.exists || billing.stripeCustomerId !== customerId) {
        throw new Error("Stripe customer does not match the canonical billing account.");
      }
      const mapped = mapStripeSubscription(subscription, priceIds, {
        previousEntitlement: entitlementSnapshot.data() ?? {},
        nowMs: now().toMillis(),
      });
      const priorSubscriptionId = billing.stripeSubscriptionId;
      const priorStatus = billing.stripeSubscriptionStatus;
      if (
        typeof priorSubscriptionId === "string" &&
        priorSubscriptionId !== subscriptionId &&
        ["active", "trialing", "grace"].includes(priorStatus)
      ) {
        ignoredAsSuperseded = true;
        transaction.create(eventRef, {
          type: event.type,
          created: event.created,
          ignoredAsSuperseded: true,
          processedAt: FieldValue.serverTimestamp(),
        });
        return;
      }

      const entitlementData = buildEntitlements({
        plan: mapped.plan,
        status: mapped.status,
        currentPeriodEnd: mapped.currentPeriodEnd,
        source: "stripe",
        cancelAtPeriodEnd: mapped.cancelAtPeriodEnd,
      });
      transaction.set(
        billingRef,
        {
          provider: "stripe",
          stripeCustomerId: customerId,
          stripeSubscriptionId: subscriptionId,
          stripeSubscriptionStatus: mapped.status,
          currentPriceId: mapped.priceId,
          currentPeriodEnd: mapped.currentPeriodEnd,
          cancelAtPeriodEnd: mapped.cancelAtPeriodEnd,
          renewalBehavior: ["active", "trialing", "grace"].includes(mapped.status)
            ? mapped.cancelAtPeriodEnd
              ? "ends"
              : "renews"
            : "none",
          lastStripeEventCreated: event.created,
          lastStripeEventId: event.id,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      applyEntitlementsInTransaction(transaction, uid, entitlementData, {
        user: userSnapshot.data() ?? {},
        firestore,
        writeUserProjection:
          userSnapshot.exists &&
          userSnapshot.data()?.banned !== true &&
          userSnapshot.data()?.disabled !== true &&
          userSnapshot.data()?.deleted !== true &&
          userSnapshot.data()?.status !== "deleted" &&
          !userSnapshot.data()?.authDeletedAt,
      });
      transaction.create(eventRef, {
        type: event.type,
        created: event.created,
        processedAt: FieldValue.serverTimestamp(),
      });
    });
    if (alreadyProcessed) return { ignored: true };
    if (ignoredAsSuperseded) return { ignored: true };
    return { applied: true, uid };
  }

  async function stripeWebhookHandler(request, response, webhookSecret) {
    let event;
    try {
      event = stripe.webhooks.constructEvent(
        request.rawBody,
        request.headers["stripe-signature"],
        webhookSecret,
      );
      if (event.livemode !== expectedLiveMode) {
        throw new Error("Stripe webhook mode does not match this deployment.");
      }
    } catch (error) {
      logger.warn("Stripe webhook signature rejected", { message: error.message });
      response.status(400).send("Invalid signature");
      return;
    }

    try {
      let subscriptionId = null;
      if (
        event.type === "charge.refunded" ||
        event.type === "charge.dispute.created"
      ) {
        await applyFinancialRiskEvent(event);
      } else if (event.type.startsWith("customer.subscription.")) {
        subscriptionId = event.data.object.id;
      } else if (
        event.type === "checkout.session.completed" ||
        event.type === "checkout.session.async_payment_succeeded"
      ) {
        const session = event.data.object;
        if (!["paid", "no_payment_required"].includes(session.payment_status)) {
          response.status(200).json({ received: true, awaitingPayment: true });
          return;
        }
        subscriptionId =
          typeof session.subscription === "string"
            ? session.subscription
            : session.subscription?.id;
      } else if (event.type === "checkout.session.async_payment_failed") {
        const session = event.data.object;
        subscriptionId =
          typeof session.subscription === "string"
            ? session.subscription
            : session.subscription?.id;
      } else if (["invoice.paid", "invoice.payment_failed"].includes(event.type)) {
        const invoice = event.data.object;
        subscriptionId =
          typeof invoice.subscription === "string"
            ? invoice.subscription
            : invoice.subscription?.id;
      }
      if (subscriptionId) await applySubscription(subscriptionId, event);
      response.status(200).json({ received: true });
    } catch (error) {
      logger.error("Stripe webhook processing failed", {
        eventId: event.id,
        eventType: event.type,
        message: error.message,
      });
      response.status(500).send("Webhook processing failed");
    }
  }

  return {
    getPremiumBillingContextHandler,
    createPremiumCheckoutSessionHandler,
    createPremiumPortalSessionHandler,
    stripeWebhookHandler,
    applySubscription,
    applyFinancialRiskEvent,
    loadPrices,
    loadPortalConfiguration,
  };
}

function runtimeHandlers() {
  const secretKey = STRIPE_SECRET_KEY.value();
  const expectedMode = STRIPE_EXPECTED_MODE.value();
  const stripe = createStripeClient(secretKey, expectedMode);
  return makeStripeBillingHandlers({
    firestore: db,
    stripe,
    priceIds: {
      monthly: STRIPE_MONTHLY_PRICE_ID.value(),
      yearly: STRIPE_YEARLY_PRICE_ID.value(),
    },
    portalConfigurationId: STRIPE_PORTAL_CONFIGURATION_ID.value(),
    expectedLiveMode: expectedMode === "live",
  });
}

const billingCallableOptions = {
  region: REGION,
  secrets: [STRIPE_SECRET_KEY],
};

const getPremiumBillingContext = onCall(
  { region: REGION, maxInstances: 20, concurrency: 80 },
  (request) => getPremiumBillingContextWithoutStripe(request),
);
const createPremiumCheckoutSession = onCall(billingCallableOptions, (request) =>
  runtimeHandlers().createPremiumCheckoutSessionHandler(request),
);
const createPremiumPortalSession = onCall(billingCallableOptions, (request) =>
  runtimeHandlers().createPremiumPortalSessionHandler(request),
);
const stripePremiumWebhook = onRequest(
  {
    region: REGION,
    secrets: [STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET],
    invoker: "public",
  },
  (request, response) =>
    runtimeHandlers().stripeWebhookHandler(
      request,
      response,
      STRIPE_WEBHOOK_SECRET.value(),
    ),
);

const onAuthUserDeletedCancelStripe = functionsV1
  .runWith({ failurePolicy: true, secrets: ["STRIPE_SECRET_KEY"] })
  .region(REGION)
  .auth.user()
  .onDelete(async (user) => {
    const expectedMode = STRIPE_EXPECTED_MODE.value();
    const stripe = createStripeClient(process.env.STRIPE_SECRET_KEY, expectedMode);
    await cancelStripeBillingForDeletedUser(user.uid, {
      firestore: db,
      stripe,
    });
  });

module.exports = {
  getPremiumBillingContext,
  createPremiumCheckoutSession,
  createPremiumPortalSession,
  stripePremiumWebhook,
  onAuthUserDeletedCancelStripe,
  makeStripeBillingHandlers,
  buildPlanCatalog,
  buildBillingContext,
  getPremiumBillingContextWithoutStripe,
  cancelStripeBillingForDeletedUser,
  mapStripeSubscription,
  createStripeClient,
  validateConfiguredPrice,
  parseBillingContextRequest,
  parseCheckoutRequest,
  parsePortalRequest,
  billingManager,
  acquireCheckoutLease,
  releaseCheckoutLease,
  requireAuthenticatedBillingOwner,
  PLAN_CONFIGURATION,
};
